package main

import (
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"
	"github.com/jackc/pgx/v5"
	"golang.org/x/crypto/bcrypt"
)

// deleteReport lets a reporter take their own report down (a mistake, or it is gone).
func (s *server) deleteReport(w http.ResponseWriter, r *http.Request) {
	id, err := strconv.ParseInt(chi.URLParam(r, "id"), 10, 64)
	if err != nil || id <= 0 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid report id"})
		return
	}
	uid, _ := r.Context().Value(userCtxKey{}).(int64)
	var owner *int64
	err = s.db.QueryRow(r.Context(), `SELECT user_id FROM reports WHERE id = $1`, id).Scan(&owner)
	if errors.Is(err, pgx.ErrNoRows) {
		writeJSON(w, http.StatusNotFound, map[string]string{"error": "report not found"})
		return
	}
	if err != nil {
		log.Printf("delete report lookup: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}
	if owner == nil || *owner != uid {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "not your report"})
		return
	}
	if _, err := s.db.Exec(r.Context(), `DELETE FROM reports WHERE id = $1`, id); err != nil { // votes cascade
		log.Printf("delete report: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}
	w.WriteHeader(http.StatusNoContent)
}

// deleteAccount removes the signed-in user and everything tied to them: their
// reports (and the votes on those) and their own votes. The password is asked for
// again so a stolen token alone cannot wipe an account.
func (s *server) deleteAccount(w http.ResponseWriter, r *http.Request) {
	var in struct {
		Password string `json:"password"`
	}
	r.Body = http.MaxBytesReader(w, r.Body, 1<<10)
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid json"})
		return
	}
	uid, _ := r.Context().Value(userCtxKey{}).(int64)
	var hash string
	err := s.db.QueryRow(r.Context(), `SELECT password_hash FROM users WHERE id = $1`, uid).Scan(&hash)
	if errors.Is(err, pgx.ErrNoRows) {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "invalid or expired token"})
		return
	}
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}
	if bcrypt.CompareHashAndPassword([]byte(hash), []byte(in.Password)) != nil {
		writeJSON(w, http.StatusForbidden, map[string]string{"error": "wrong password"})
		return
	}
	tx, err := s.db.Begin(r.Context())
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}
	defer tx.Rollback(r.Context())
	// reports.user_id has no cascade, so reports go first (their votes cascade).
	for _, q := range []string{
		`DELETE FROM reports WHERE user_id = $1`,
		`DELETE FROM users WHERE id = $1`, // the user's own votes cascade
	} {
		if _, err := tx.Exec(r.Context(), q, uid); err != nil {
			log.Printf("delete account: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
			return
		}
	}
	if err := tx.Commit(r.Context()); err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}
	w.WriteHeader(http.StatusNoContent)
}
