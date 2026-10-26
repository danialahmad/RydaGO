package main

import (
	"context"
	"database/sql"
	"embed"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strconv"
	"time"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/jackc/pgx/v5/pgxpool"
	_ "github.com/jackc/pgx/v5/stdlib"
	"github.com/pressly/goose/v3"
	"golang.org/x/crypto/bcrypt"
)

//go:embed migrations/*.sql
var migrations embed.FS

// reportSubtypes lists every report type and the subtypes it accepts. The first
// subtype is the default the app sends. Keep in sync with ReportType in the app
// (lib/models/report.dart); docs/API.md documents the same table.
var reportSubtypes = map[string][]string{
	"police":   {"visible", "hidden", "other_side"},
	"accident": {"minor", "major", "other_side"},
	"jam":      {"moderate", "heavy", "standstill"},
	"hazard":   {"object", "pothole", "stopped_vehicle", "construction", "broken_light", "weather"},
	"camera":   {"speed", "red_light"},
	"closed":   {"road", "lane"},
}

// validReport reports whether typ is a known type and subtype is empty or one
// of that type's subtypes.
func validReport(typ, subtype string) bool {
	subs, ok := reportSubtypes[typ]
	if !ok {
		return false
	}
	if subtype == "" {
		return true
	}
	for _, s := range subs {
		if s == subtype {
			return true
		}
	}
	return false
}

type server struct {
	db        *pgxpool.Pool
	jwtSecret []byte
	dummyHash []byte // compared against when the email is unknown, to even out login timing
	// relaxLimits lifts the per-user report and vote limits. Tests that file many
	// reports as one user set it; the auth limit always applies.
	relaxLimits bool
}

type report struct {
	ID        int64     `json:"id"`
	Type      string    `json:"type"`
	Subtype   string    `json:"subtype,omitempty"`
	Lat       float64   `json:"lat"`
	Lng       float64   `json:"lng"`
	CreatedAt time.Time `json:"created_at"`
	Up        int       `json:"up"`             // "still there" votes
	Down      int       `json:"down"`           // "gone" votes
	Mine      bool      `json:"mine,omitempty"` // only set when the caller sent a valid token
}

// How long a report stays on the map after it was made or last confirmed, and how
// many more "gone" than "still there" votes remove it early.
const (
	reportLifetime = "2 hours" // a Postgres interval literal
	hideNetDown    = 3

	// The same user reporting the same type within this distance and time is a duplicate.
	duplicateWindow  = "10 minutes" // a Postgres interval literal
	duplicateRadiusM = 100.0
)

func main() {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		log.Fatal("DATABASE_URL is required")
	}
	port := os.Getenv("PORT")
	if port == "" {
		port = "8081"
	}
	secret := os.Getenv("JWT_SECRET")
	if len(secret) < 32 {
		log.Fatal("JWT_SECRET is required and must be at least 32 characters")
	}
	dummy, err := bcrypt.GenerateFromPassword([]byte("dummy-password"), bcrypt.DefaultCost)
	if err != nil {
		log.Fatal(err)
	}

	migrate(dsn)

	pool, err := pgxpool.New(context.Background(), dsn)
	if err != nil {
		log.Fatalf("connect db: %v", err)
	}
	defer pool.Close()

	s := &server{db: pool, jwtSecret: []byte(secret), dummyHash: dummy}
	log.Printf("listening on :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, s.routes()))
}

// routes wires every endpoint. Kept separate from main so tests can serve the
// real router (see integration_test.go).
func (s *server) routes() http.Handler {
	r := chi.NewRouter()
	r.Use(middleware.RequestID, middleware.Logger, middleware.Recoverer, cors)
	r.Get("/health", s.health)
	// Limits are per client IP for the open auth endpoints, per user for the rest.
	authLimit := limit(newLimiter(10, 10), clientIP)
	reportLimit := limit(newLimiter(6, 5), userKey)
	voteLimit := limit(newLimiter(60, 30), userKey)
	if s.relaxLimits {
		reportLimit = limit(newLimiter(60000, 10000), userKey)
		voteLimit = reportLimit
	}
	r.With(authLimit).Post("/auth/register", s.register)
	r.With(authLimit).Post("/auth/login", s.login)
	r.With(s.requireAuth, reportLimit).Post("/reports", s.createReport)
	r.Get("/reports", s.nearbyReports)
	r.With(s.requireAuth, voteLimit).Post("/reports/{id}/vote", s.voteReport)
	r.With(s.requireAuth).Delete("/reports/{id}", s.deleteReport)
	r.With(s.requireAuth, authLimit).Delete("/me", s.deleteAccount)
	// Live trip sharing: the owner manages a share; anyone with the link may read it.
	shareLimit := limit(newLimiter(60, 20), userKey)
	r.With(s.requireAuth, shareLimit).Post("/shares", s.createShare)
	r.With(s.requireAuth, shareLimit).Put("/shares/{token}", s.updateShare)
	r.With(s.requireAuth, shareLimit).Delete("/shares/{token}", s.endShare)
	r.With(limit(newLimiter(120, 60), clientIP)).Get("/shares/{token}", s.getShare)
	r.Get("/s/{token}", s.sharePage)
	r.Get("/route", s.route)
	r.Get("/places", s.places)
	return r
}

// cors allows the Flutter web build (served from another origin) to call the API.
// Dev only: tighten the origin list before deploying.
func cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
		w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")
		if r.Method == http.MethodOptions {
			w.WriteHeader(http.StatusNoContent)
			return
		}
		next.ServeHTTP(w, r)
	})
}

func migrate(dsn string) {
	db, err := sql.Open("pgx", dsn)
	if err != nil {
		log.Fatalf("open db for migrate: %v", err)
	}
	defer db.Close()
	goose.SetBaseFS(migrations)
	if err := goose.SetDialect("postgres"); err != nil {
		log.Fatal(err)
	}
	if err := goose.Up(db, "migrations"); err != nil {
		log.Fatalf("migrate: %v", err)
	}
}

func writeJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	json.NewEncoder(w).Encode(v)
}

func (s *server) health(w http.ResponseWriter, r *http.Request) {
	if err := s.db.Ping(r.Context()); err != nil {
		writeJSON(w, http.StatusServiceUnavailable, map[string]string{"status": "db down"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *server) createReport(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Type    string  `json:"type"`
		Subtype string  `json:"subtype"`
		Lat     float64 `json:"lat"`
		Lng     float64 `json:"lng"`
	}
	r.Body = http.MaxBytesReader(w, r.Body, 1<<14)
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid json"})
		return
	}
	if !validReport(in.Type, in.Subtype) || in.Lat < -90 || in.Lat > 90 || in.Lng < -180 || in.Lng > 180 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid type, subtype or coordinates"})
		return
	}
	userID, _ := r.Context().Value(userCtxKey{}).(int64)
	// The same person reporting the same thing in the same place again is a double
	// tap or a spammer, not new information.
	var dup bool
	if err := s.db.QueryRow(r.Context(),
		`SELECT EXISTS (SELECT 1 FROM reports
		   WHERE user_id = $1 AND type = $2
		     AND created_at > now() - interval '`+duplicateWindow+`'
		     AND ST_DWithin(geom, ST_SetSRID(ST_MakePoint($3, $4), 4326)::geography, $5))`,
		userID, in.Type, in.Lng, in.Lat, duplicateRadiusM).Scan(&dup); err != nil {
		log.Printf("duplicate check: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}
	if dup {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "you already reported this here"})
		return
	}
	rep := report{Type: in.Type, Subtype: in.Subtype, Lat: in.Lat, Lng: in.Lng}
	err := s.db.QueryRow(r.Context(),
		`INSERT INTO reports (type, subtype, geom, user_id)
		 VALUES ($1, NULLIF($2, ''), ST_SetSRID(ST_MakePoint($3, $4), 4326)::geography, $5)
		 RETURNING id, created_at`,
		in.Type, in.Subtype, in.Lng, in.Lat, userID).Scan(&rep.ID, &rep.CreatedAt)
	if err != nil {
		log.Printf("insert report: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}
	writeJSON(w, http.StatusCreated, rep)
}

func (s *server) nearbyReports(w http.ResponseWriter, r *http.Request) {
	q := r.URL.Query()
	lat, err1 := strconv.ParseFloat(q.Get("lat"), 64)
	lng, err2 := strconv.ParseFloat(q.Get("lng"), 64)
	if err1 != nil || err2 != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "lat and lng required"})
		return
	}
	radius := 5000.0
	if v, err := strconv.ParseFloat(q.Get("radius"), 64); err == nil && v > 0 && v <= 50000 {
		radius = v
	}

	// The caller may be anonymous; a valid token only adds "mine" to the answer.
	viewer, _, _ := s.userFromRequest(r)

	// A report is shown while it is younger than reportLifetime counted from its
	// creation or its latest "still there" vote, and until "gone" votes outnumber
	// "still there" votes by hideNetDown.
	rows, err := s.db.Query(r.Context(),
		`SELECT r.id, r.type, COALESCE(r.subtype, ''), ST_Y(r.geom::geometry), ST_X(r.geom::geometry),
		        r.created_at, v.up, v.down, COALESCE(r.user_id = $4, false)
		 FROM reports r
		 CROSS JOIN LATERAL (
		     SELECT count(*) FILTER (WHERE vote = 1)::int  AS up,
		            count(*) FILTER (WHERE vote = -1)::int AS down,
		            max(created_at) FILTER (WHERE vote = 1) AS last_up
		     FROM report_votes WHERE report_id = r.id) v
		 WHERE ST_DWithin(r.geom, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography, $3)
		   AND GREATEST(r.created_at, COALESCE(v.last_up, r.created_at)) > now() - interval '`+reportLifetime+`'
		   AND v.down - v.up < `+strconv.Itoa(hideNetDown)+`
		 ORDER BY r.created_at DESC
		 LIMIT 100`, lng, lat, radius, viewer)
	if err != nil {
		log.Printf("query reports: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}
	defer rows.Close()

	out := []report{}
	for rows.Next() {
		var rep report
		if err := rows.Scan(&rep.ID, &rep.Type, &rep.Subtype, &rep.Lat, &rep.Lng, &rep.CreatedAt,
			&rep.Up, &rep.Down, &rep.Mine); err != nil {
			log.Printf("scan report: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
			return
		}
		out = append(out, rep)
	}
	writeJSON(w, http.StatusOK, out)
}
