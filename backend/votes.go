package main

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
)

// voteReport records "still there" (up) or "gone" (down) for a report.
// One vote per user per report: voting again replaces the earlier vote, and a
// fresh "up" extends the report's lifetime. Reporters cannot vote on their own reports.
func (s *server) voteReport(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id <= 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "id laporan tak sah"})
		return
	}
	var in struct {
		Vote string `json:"vote"`
	}
	r.Body = http.MaxBytesReader(w, r.Body, 1<<10)
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil || (in.Vote != "up" && in.Vote != "down") {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": `vote mesti "up" atau "down"`})
		return
	}
	value := 1
	if in.Vote == "down" {
		value = -1
	}
	uid, _ := r.Context().Value(userCtxKey{}).(int64)

	var owner *int64
	err = s.db.QueryRow(r.Context(), `SELECT user_id FROM reports WHERE id = $1`, id).Scan(&owner)
	if errors.Is(err, pgx.ErrNoRows) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "laporan tak dijumpai"})
		return
	}
	if err != nil {
		log.Printf("vote lookup: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}
	if owner != nil && *owner == uid {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "tak boleh mengundi laporan sendiri"})
		return
	}

	_, err = s.db.Exec(r.Context(),
		`INSERT INTO report_votes (report_id, user_id, vote) VALUES ($1, $2, $3)
		 ON CONFLICT (report_id, user_id) DO UPDATE SET vote = EXCLUDED.vote, created_at = now()`,
		id, uid, value)
	if err != nil {
		log.Printf("vote insert: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}

	var up, down int
	err = s.db.QueryRow(r.Context(),
		`SELECT count(*) FILTER (WHERE vote = 1)::int, count(*) FILTER (WHERE vote = -1)::int
		 FROM report_votes WHERE report_id = $1`, id).Scan(&up, &down)
	if err != nil {
		log.Printf("vote count: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}
	writeJSON(w, http.StatusOK, map[string]int{"up": up, "down": down})
}
