package main

import (
	"context"
	"encoding/json"
	"errors"
	"net/http"
	"net/mail"
	"strconv"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"golang.org/x/crypto/bcrypt"
)

type userCtxKey struct{}

const tokenTTL = 7 * 24 * time.Hour

type credentials struct {
	Email    string `json:"email"`
	Password string `json:"password"`
}

func (s *server) issueToken(userID int64) (string, error) {
	now := time.Now()
	claims := jwt.RegisteredClaims{
		Subject:   strconv.FormatInt(userID, 10),
		IssuedAt:  jwt.NewNumericDate(now),
		ExpiresAt: jwt.NewNumericDate(now.Add(tokenTTL)),
	}
	return jwt.NewWithClaims(jwt.SigningMethodHS256, claims).SignedString(s.jwtSecret)
}

func readCredentials(w http.ResponseWriter, r *http.Request) (credentials, bool) {
	var c credentials
	r.Body = http.MaxBytesReader(w, r.Body, 1<<14)
	if err := json.NewDecoder(r.Body).Decode(&c); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid json"})
		return c, false
	}
	c.Email = strings.ToLower(strings.TrimSpace(c.Email))
	return c, true
}

func (s *server) register(w http.ResponseWriter, r *http.Request) {
	c, ok := readCredentials(w, r)
	if !ok {
		return
	}
	if _, err := mail.ParseAddress(c.Email); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "email tidak sah"})
		return
	}
	// bcrypt only uses the first 72 bytes, so reject longer passwords outright.
	if len(c.Password) < 8 || len(c.Password) > 72 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "kata laluan mesti 8 hingga 72 aksara"})
		return
	}
	hash, err := bcrypt.GenerateFromPassword([]byte(c.Password), bcrypt.DefaultCost)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}
	var id int64
	err = s.db.QueryRow(r.Context(),
		`INSERT INTO users (email, password_hash) VALUES ($1, $2) RETURNING id`,
		c.Email, string(hash)).Scan(&id)
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == "23505" {
		writeJSON(w, http.StatusConflict, map[string]string{"error": "email sudah didaftarkan"})
		return
	}
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}
	s.respondWithToken(w, http.StatusCreated, id, c.Email)
}

func (s *server) login(w http.ResponseWriter, r *http.Request) {
	c, ok := readCredentials(w, r)
	if !ok {
		return
	}
	var id int64
	var hash string
	err := s.db.QueryRow(r.Context(),
		`SELECT id, password_hash FROM users WHERE email = $1`, c.Email).Scan(&id, &hash)
	if errors.Is(err, pgx.ErrNoRows) {
		// Burn comparable time so unknown emails are not distinguishable by latency.
		bcrypt.CompareHashAndPassword(s.dummyHash, []byte(c.Password))
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "email atau kata laluan salah"})
		return
	}
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}
	if bcrypt.CompareHashAndPassword([]byte(hash), []byte(c.Password)) != nil {
		writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "email atau kata laluan salah"})
		return
	}
	s.respondWithToken(w, http.StatusOK, id, c.Email)
}

func (s *server) respondWithToken(w http.ResponseWriter, status int, id int64, email string) {
	tok, err := s.issueToken(id)
	if err != nil {
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}
	writeJSON(w, status, map[string]any{"token": tok, "email": email})
}

// userFromRequest returns the user id in a valid Bearer token. present is false
// when there is no Authorization header at all; ok is false when there is one
// but it is not a valid, unexpired token.
func (s *server) userFromRequest(r *http.Request) (uid int64, present, ok bool) {
	raw, found := strings.CutPrefix(r.Header.Get("Authorization"), "Bearer ")
	if !found {
		return 0, false, false
	}
	var claims jwt.RegisteredClaims
	_, err := jwt.ParseWithClaims(raw, &claims,
		func(*jwt.Token) (any, error) { return s.jwtSecret, nil },
		jwt.WithValidMethods([]string{"HS256"}), jwt.WithExpirationRequired())
	uid, perr := strconv.ParseInt(claims.Subject, 10, 64)
	if err != nil || perr != nil {
		return 0, true, false
	}
	return uid, true, true
}

func (s *server) requireAuth(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		uid, present, ok := s.userFromRequest(r)
		if !present {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "login diperlukan"})
			return
		}
		if !ok {
			writeJSON(w, http.StatusUnauthorized, map[string]string{"error": "token tidak sah atau tamat tempoh"})
			return
		}
		next.ServeHTTP(w, r.WithContext(context.WithValue(r.Context(), userCtxKey{}, uid)))
	})
}
