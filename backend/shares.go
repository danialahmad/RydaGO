package main

import (
	"crypto/rand"
	"encoding/base64"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"regexp"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
)

// A share is a live "I'm on my way" link. The driver's app creates it, keeps the
// position and ETA fresh while navigating, and ends it on arrival; anyone with the
// link sees where the driver is. The token is 128 random bits, so it cannot be guessed.

const (
	shareMaxAge   = 8 * time.Hour   // links stop working this long after they were made
	shareStaleAge = 2 * time.Minute // no update for this long: the viewer is told the signal is old
)

var shareToken = regexp.MustCompile(`^[A-Za-z0-9_-]{16,64}$`)

func newShareToken() (string, error) {
	b := make([]byte, 16)
	if _, err := rand.Read(b); err != nil {
		return "", err
	}
	return base64.RawURLEncoding.EncodeToString(b), nil
}

type shareIn struct {
	DestName   string  `json:"dest_name"`
	DestLat    float64 `json:"dest_lat"`
	DestLng    float64 `json:"dest_lng"`
	Lat        float64 `json:"lat"`
	Lng        float64 `json:"lng"`
	EtaMinutes int     `json:"eta_minutes"`
}

func (in shareIn) valid() bool {
	okLat := func(v float64) bool { return v >= -90 && v <= 90 }
	okLng := func(v float64) bool { return v >= -180 && v <= 180 }
	return len(in.DestName) <= 200 && okLat(in.DestLat) && okLat(in.Lat) && okLng(in.DestLng) && okLng(in.Lng) &&
		in.EtaMinutes >= 0 && in.EtaMinutes <= 24*60
}

func (s *server) createShare(w http.ResponseWriter, r *http.Request) {
	var in shareIn
	r.Body = http.MaxBytesReader(w, r.Body, 1<<12)
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil || !in.valid() {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid share"})
		return
	}
	token, err := newShareToken()
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}
	uid, _ := r.Context().Value(userCtxKey{}).(int64)
	_, err = s.db.Exec(r.Context(),
		`INSERT INTO shares (token, user_id, dest_name, dest_lat, dest_lng, lat, lng, eta_at)
		 VALUES ($1, $2, $3, $4, $5, $6, $7, now() + make_interval(mins => $8))`,
		token, uid, in.DestName, in.DestLat, in.DestLng, in.Lat, in.Lng, in.EtaMinutes)
	if err != nil {
		log.Printf("create share: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}
	writeJSON(w, http.StatusCreated, map[string]string{"token": token, "path": "/s/" + token})
}

// ownShare checks that the share exists and belongs to the caller, answering 404
// or 403 itself when it does not.
func (s *server) ownShare(w http.ResponseWriter, r *http.Request) (token string, ok bool) {
	token = chi.URLParam(r, "token")
	if !shareToken.MatchString(token) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "share not found"})
		return "", false
	}
	var owner int64
	err := s.db.QueryRow(r.Context(), `SELECT user_id FROM shares WHERE token = $1`, token).Scan(&owner)
	if errors.Is(err, pgx.ErrNoRows) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "share not found"})
		return "", false
	}
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return "", false
	}
	if uid, _ := r.Context().Value(userCtxKey{}).(int64); uid != owner {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "not your share"})
		return "", false
	}
	return token, true
}

func (s *server) updateShare(w http.ResponseWriter, r *http.Request) {
	token, ok := s.ownShare(w, r)
	if !ok {
		return
	}
	var in shareIn
	r.Body = http.MaxBytesReader(w, r.Body, 1<<12)
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil || !in.valid() {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid share"})
		return
	}
	tag, err := s.db.Exec(r.Context(),
		`UPDATE shares SET lat = $2, lng = $3, eta_at = now() + make_interval(mins => $4), updated_at = now()
		 WHERE token = $1 AND ended_at IS NULL`,
		token, in.Lat, in.Lng, in.EtaMinutes)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}
	if tag.RowsAffected() == 0 {
		writeJSON(w, http.StatusGone, map[string]string{"error": "share already ended"})
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

func (s *server) endShare(w http.ResponseWriter, r *http.Request) {
	token, ok := s.ownShare(w, r)
	if !ok {
		return
	}
	if _, err := s.db.Exec(r.Context(),
		`UPDATE shares SET ended_at = now() WHERE token = $1 AND ended_at IS NULL`, token); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

type shareOut struct {
	DestName  string    `json:"dest_name"`
	DestLat   float64   `json:"dest_lat"`
	DestLng   float64   `json:"dest_lng"`
	Lat       float64   `json:"lat"`
	Lng       float64   `json:"lng"`
	EtaAt     time.Time `json:"eta_at"`
	UpdatedAt time.Time `json:"updated_at"`
	Ended     bool      `json:"ended"` // the driver arrived or stopped sharing
	Stale     bool      `json:"stale"` // no recent update: the position may be old
}

// getShare is public: whoever has the link may read it. Expired links are 404.
func (s *server) getShare(w http.ResponseWriter, r *http.Request) {
	token := chi.URLParam(r, "token")
	if !shareToken.MatchString(token) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "share not found"})
		return
	}
	var out shareOut
	var endedAt *time.Time
	var createdAt time.Time
	err := s.db.QueryRow(r.Context(),
		`SELECT dest_name, dest_lat, dest_lng, lat, lng, eta_at, updated_at, ended_at, created_at
		 FROM shares WHERE token = $1`, token).
		Scan(&out.DestName, &out.DestLat, &out.DestLng, &out.Lat, &out.Lng, &out.EtaAt, &out.UpdatedAt, &endedAt, &createdAt)
	if errors.Is(err, pgx.ErrNoRows) || (err == nil && time.Since(createdAt) > shareMaxAge) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "share not found"})
		return
	}
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}
	out.Ended = endedAt != nil
	out.Stale = !out.Ended && time.Since(out.UpdatedAt) > shareStaleAge
	w.Header().Set("Cache-Control", "no-store")
	writeJSON(w, http.StatusOK, out)
}

// sharePage is the page a friend opens. It needs no app and no account: it polls
// the JSON above and shows the ETA, with a link to the position on OpenStreetMap.
func (s *server) sharePage(w http.ResponseWriter, r *http.Request) {
	token := chi.URLParam(r, "token")
	if !shareToken.MatchString(token) {
		http.NotFound(w, r)
		return
	}
	w.Header().Set("Content-Type", "text/html; charset=utf-8")
	w.Header().Set("Cache-Control", "no-store")
	w.Header().Set("Referrer-Policy", "no-referrer")
	w.Write([]byte(shareHTML(token)))
}

// shareHTML renders the page. The token is validated to URL-safe characters by
// shareToken before it gets here, and every other value reaches the page through
// textContent, never innerHTML, so a destination name cannot inject markup.
func shareHTML(token string) string {
	return `<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex">
<title>Live trip · RydaGO</title>
<style>
body{font-family:system-ui,sans-serif;margin:0;background:#f3f5f8;color:#101828}
main{max-width:30rem;margin:0 auto;padding:1.25rem}
.card{background:#fff;border-radius:1.25rem;padding:1.25rem;box-shadow:0 2px 10px #0001}
h1{font-size:1.1rem;margin:0 0 .25rem;color:#667085;font-weight:700}
#eta{font-size:2.6rem;font-weight:800;margin:.25rem 0}
#dest{font-size:1.2rem;font-weight:700}
#note{color:#667085;margin:.5rem 0 1rem}
a.btn{display:inline-block;background:#1e88e5;color:#fff;text-decoration:none;border-radius:2rem;padding:.7rem 1.2rem;font-weight:700}
.warn{color:#b54708}
</style></head><body><main><div class="card">
<h1>Live trip</h1><div id="dest">Loading…</div><div id="eta"></div><div id="note"></div>
<a class="btn" id="map" href="#" target="_blank" rel="noopener noreferrer">See on map</a>
</div></main>
<script>
const token = "` + token + `";
const $ = id => document.getElementById(id);
async function tick() {
  try {
    const res = await fetch('/shares/' + token, {cache: 'no-store'});
    if (!res.ok) { $('dest').textContent = 'This link is no longer available.'; $('eta').textContent = ''; $('note').textContent = ''; $('map').style.display = 'none'; return; }
    const s = await res.json();
    $('dest').textContent = 'Heading to ' + (s.dest_name || 'their destination');
    const eta = new Date(s.eta_at);
    if (s.ended) {
      $('eta').textContent = 'Trip ended';
      $('note').textContent = 'They have arrived or stopped sharing.';
      $('map').style.display = 'none';
      return;
    }
    const mins = Math.max(0, Math.round((eta - Date.now()) / 60000));
    $('eta').textContent = eta.toLocaleTimeString([], {hour: 'numeric', minute: '2-digit'});
    $('note').textContent = mins + ' min to go' + (s.stale ? ' · signal is old, they may be out of coverage' : '');
    $('note').className = s.stale ? 'warn' : '';
    $('map').href = 'https://www.openstreetmap.org/?mlat=' + s.lat + '&mlon=' + s.lng + '#map=16/' + s.lat + '/' + s.lng;
    $('map').style.display = '';
  } catch (e) { $('note').textContent = 'Reconnecting…'; }
  setTimeout(tick, 10000);
}
tick();
</script></body></html>`
}
