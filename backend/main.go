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

var validTypes = map[string]bool{
	"police": true, "accident": true, "jam": true,
	"hazard": true, "camera": true, "closed": true,
}

type server struct {
	db        *pgxpool.Pool
	jwtSecret []byte
	dummyHash []byte // compared against when the email is unknown, to even out login timing
}

type report struct {
	ID        int64     `json:"id"`
	Type      string    `json:"type"`
	Lat       float64   `json:"lat"`
	Lng       float64   `json:"lng"`
	CreatedAt time.Time `json:"created_at"`
}

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
	r := chi.NewRouter()
	r.Use(middleware.RequestID, middleware.Logger, middleware.Recoverer, cors)
	r.Get("/health", s.health)
	r.Post("/auth/register", s.register)
	r.Post("/auth/login", s.login)
	r.With(s.requireAuth).Post("/reports", s.createReport)
	r.Get("/reports", s.nearbyReports)
	r.Get("/route", s.route)
	r.Get("/places", s.places)

	log.Printf("listening on :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, r))
}

// cors allows the Flutter web build (served from another origin) to call the API.
// Dev only: tighten the origin list before deploying.
func cors(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Access-Control-Allow-Origin", "*")
		w.Header().Set("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
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
		Type string  `json:"type"`
		Lat  float64 `json:"lat"`
		Lng  float64 `json:"lng"`
	}
	if err := json.NewDecoder(r.Body).Decode(&in); err != nil {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid json"})
		return
	}
	if !validTypes[in.Type] || in.Lat < -90 || in.Lat > 90 || in.Lng < -180 || in.Lng > 180 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "invalid type or coordinates"})
		return
	}
	userID, _ := r.Context().Value(userCtxKey{}).(int64)
	rep := report{Type: in.Type, Lat: in.Lat, Lng: in.Lng}
	err := s.db.QueryRow(r.Context(),
		`INSERT INTO reports (type, geom, user_id)
		 VALUES ($1, ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography, $4)
		 RETURNING id, created_at`,
		in.Type, in.Lng, in.Lat, userID).Scan(&rep.ID, &rep.CreatedAt)
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

	rows, err := s.db.Query(r.Context(),
		`SELECT id, type, ST_Y(geom::geometry), ST_X(geom::geometry), created_at
		 FROM reports
		 WHERE ST_DWithin(geom, ST_SetSRID(ST_MakePoint($1, $2), 4326)::geography, $3)
		   AND created_at > now() - interval '2 hours'
		 ORDER BY created_at DESC
		 LIMIT 100`, lng, lat, radius)
	if err != nil {
		log.Printf("query reports: %v", err)
		writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
		return
	}
	defer rows.Close()

	out := []report{}
	for rows.Next() {
		var rep report
		if err := rows.Scan(&rep.ID, &rep.Type, &rep.Lat, &rep.Lng, &rep.CreatedAt); err != nil {
			log.Printf("scan report: %v", err)
			writeJSON(w, http.StatusInternalServerError, map[string]string{"error": "internal error"})
			return
		}
		out = append(out, rep)
	}
	writeJSON(w, http.StatusOK, out)
}
