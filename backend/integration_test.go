package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"os"
	"strings"
	"testing"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"golang.org/x/crypto/bcrypt"
)

// These tests run the real router against a real PostGIS database. They are skipped
// unless TEST_DATABASE_URL points at a Postgres server where the user may create
// databases (use the maintenance database, e.g. .../postgres). Each run creates a
// throwaway database, applies the migrations, and drops it afterwards.
//
// With the compose stack running, from the repo root (PowerShell):
//
//	docker run --rm --network waze-revamp_default -v "${PWD}/backend:/src" -w /src `
//	  -e TEST_DATABASE_URL="postgres://waze:wazedev@db:5432/postgres?sslmode=disable" `
//	  golang:1.26-alpine go test ./...

func integrationServer(t *testing.T) (*httptest.Server, *pgxpool.Pool) {
	t.Helper()
	adminDSN := os.Getenv("TEST_DATABASE_URL")
	if adminDSN == "" {
		t.Skip("TEST_DATABASE_URL not set; skipping database tests")
	}
	ctx := context.Background()
	admin, err := pgx.Connect(ctx, adminDSN)
	if err != nil {
		t.Fatalf("connect admin: %v", err)
	}
	name := fmt.Sprintf("waze_test_%d", time.Now().UnixNano())
	if _, err := admin.Exec(ctx, "CREATE DATABASE "+name); err != nil {
		t.Fatalf("create database: %v", err)
	}
	t.Cleanup(func() {
		admin.Exec(context.Background(), "DROP DATABASE IF EXISTS "+name+" WITH (FORCE)")
		admin.Close(context.Background())
	})

	u, err := url.Parse(adminDSN)
	if err != nil {
		t.Fatal(err)
	}
	u.Path = "/" + name
	dsn := u.String()
	migrate(dsn) // the same embedded migrations the API runs at startup

	pool, err := pgxpool.New(ctx, dsn)
	if err != nil {
		t.Fatalf("connect: %v", err)
	}
	t.Cleanup(pool.Close)

	hash, _ := bcrypt.GenerateFromPassword([]byte("x"), bcrypt.MinCost)
	s := &server{db: pool, jwtSecret: []byte(strings.Repeat("k", 32)), dummyHash: hash}
	ts := httptest.NewServer(s.routes())
	t.Cleanup(ts.Close)
	return ts, pool
}

type apiClient struct {
	t    *testing.T
	base string
}

func (c apiClient) do(method, path, token string, body any) (int, []byte) {
	c.t.Helper()
	var rdr io.Reader
	if body != nil {
		b, _ := json.Marshal(body)
		rdr = bytes.NewReader(b)
	}
	req, _ := http.NewRequest(method, c.base+path, rdr)
	req.Header.Set("Content-Type", "application/json")
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	res, err := http.DefaultClient.Do(req)
	if err != nil {
		c.t.Fatal(err)
	}
	defer res.Body.Close()
	out, _ := io.ReadAll(res.Body)
	return res.StatusCode, out
}

func (c apiClient) register(email string) string {
	c.t.Helper()
	code, out := c.do("POST", "/auth/register", "", map[string]string{"email": email, "password": "password123"})
	if code != http.StatusCreated {
		c.t.Fatalf("register %s: %d %s", email, code, out)
	}
	var v struct {
		Token string `json:"token"`
	}
	if err := json.Unmarshal(out, &v); err != nil || v.Token == "" {
		c.t.Fatalf("register %s: no token in %s", email, out)
	}
	return v.Token
}

// newReport files a report at a fixed spot in KL and returns its id.
func (c apiClient) newReport(token, typ, subtype string) int64 {
	c.t.Helper()
	code, out := c.do("POST", "/reports", token,
		map[string]any{"type": typ, "subtype": subtype, "lat": 3.1579, "lng": 101.7116})
	if code != http.StatusCreated {
		c.t.Fatalf("create report: %d %s", code, out)
	}
	var r report
	json.Unmarshal(out, &r)
	return r.ID
}

func (c apiClient) vote(token string, id int64, v string) (int, map[string]int) {
	c.t.Helper()
	code, out := c.do("POST", fmt.Sprintf("/reports/%d/vote", id), token, map[string]string{"vote": v})
	var counts map[string]int
	json.Unmarshal(out, &counts)
	return code, counts
}

// nearby returns the reports visible around KLCC, as seen by token ("" = anonymous).
func (c apiClient) nearby(token string) map[int64]report {
	c.t.Helper()
	code, out := c.do("GET", "/reports?lat=3.1579&lng=101.7116&radius=2000", token, nil)
	if code != http.StatusOK {
		c.t.Fatalf("nearby: %d %s", code, out)
	}
	var list []report
	if err := json.Unmarshal(out, &list); err != nil {
		c.t.Fatal(err)
	}
	m := map[int64]report{}
	for _, r := range list {
		m[r.ID] = r
	}
	return m
}

func TestDatabaseBackedAPI(t *testing.T) {
	ts, pool := integrationServer(t)
	c := apiClient{t: t, base: ts.URL}
	owner := c.register("owner@test.my")
	voterA, voterB, voterC := c.register("a@test.my"), c.register("b@test.my"), c.register("c@test.my")

	t.Run("accounts", func(t *testing.T) {
		if code, _ := c.do("POST", "/auth/register", "", map[string]string{"email": "OWNER@test.my", "password": "password123"}); code != http.StatusConflict {
			t.Errorf("duplicate email (different case): %d, want 409", code)
		}
		if code, _ := c.do("POST", "/auth/login", "", map[string]string{"email": "owner@test.my", "password": "password123"}); code != http.StatusOK {
			t.Errorf("login: %d, want 200", code)
		}
		if code, _ := c.do("POST", "/auth/login", "", map[string]string{"email": "owner@test.my", "password": "wrong-password"}); code != http.StatusUnauthorized {
			t.Errorf("wrong password: %d, want 401", code)
		}
		if code, _ := c.do("POST", "/auth/login", "", map[string]string{"email": "nobody@test.my", "password": "password123"}); code != http.StatusUnauthorized {
			t.Errorf("unknown email: %d, want 401", code)
		}
	})

	t.Run("reports are stored and read back with their subtype", func(t *testing.T) {
		id := c.newReport(owner, "police", "hidden")
		got, ok := c.nearby("")[id]
		if !ok {
			t.Fatal("new report not returned by /reports")
		}
		if got.Type != "police" || got.Subtype != "hidden" || got.Up != 0 || got.Down != 0 {
			t.Errorf("report = %+v", got)
		}
		if got.Mine {
			t.Error("anonymous caller must not get mine=true")
		}
		if !c.nearby(owner)[id].Mine {
			t.Error("the reporter should see mine=true")
		}
		if c.nearby(voterA)[id].Mine {
			t.Error("another user must not see mine=true")
		}
		if code, _ := c.do("POST", "/reports", owner, map[string]any{"type": "police", "subtype": "standstill", "lat": 3.1, "lng": 101.7}); code != http.StatusBadRequest {
			t.Errorf("wrong subtype for type: %d, want 400", code)
		}
		if code, _ := c.do("POST", "/reports", "", map[string]any{"type": "jam", "lat": 3.1, "lng": 101.7}); code != http.StatusUnauthorized {
			t.Errorf("no token: %d, want 401", code)
		}
	})

	t.Run("a report with no subtype is allowed", func(t *testing.T) {
		id := c.newReport(owner, "jam", "")
		if got := c.nearby("")[id]; got.Subtype != "" || got.Type != "jam" {
			t.Errorf("report = %+v", got)
		}
	})

	t.Run("reports far away are not returned", func(t *testing.T) {
		code, out := c.do("GET", "/reports?lat=5.4&lng=100.3&radius=2000", "", nil) // Penang
		if code != http.StatusOK || strings.Contains(string(out), `"type"`) {
			t.Errorf("status %d body %s", code, out)
		}
	})

	t.Run("voting", func(t *testing.T) {
		id := c.newReport(owner, "hazard", "pothole")
		if code, n := c.vote(voterA, id, "up"); code != http.StatusOK || n["up"] != 1 || n["down"] != 0 {
			t.Errorf("first vote: %d %v", code, n)
		}
		// Changing your mind replaces the vote instead of adding a second one.
		if code, n := c.vote(voterA, id, "down"); code != http.StatusOK || n["up"] != 0 || n["down"] != 1 {
			t.Errorf("changed vote: %d %v", code, n)
		}
		if code, _ := c.vote(owner, id, "up"); code != http.StatusForbidden {
			t.Errorf("own report: %d, want 403", code)
		}
		if code, _ := c.vote(voterA, 999999, "up"); code != http.StatusNotFound {
			t.Errorf("unknown report: %d, want 404", code)
		}
		if code, _ := c.vote(voterA, id, "maybe"); code != http.StatusBadRequest {
			t.Errorf("bad vote: %d, want 400", code)
		}
		if code, _ := c.vote("", id, "up"); code != http.StatusUnauthorized {
			t.Errorf("no token: %d, want 401", code)
		}
		if got := c.nearby("")[id]; got.Up != 0 || got.Down != 1 {
			t.Errorf("counts in /reports: up=%d down=%d", got.Up, got.Down)
		}
	})

	t.Run("three more 'gone' than 'still there' votes remove a report", func(t *testing.T) {
		id := c.newReport(owner, "police", "visible")
		c.vote(voterA, id, "down")
		c.vote(voterB, id, "down")
		if _, ok := c.nearby("")[id]; !ok {
			t.Fatal("two down votes should not hide it yet")
		}
		c.vote(voterC, id, "down")
		if _, ok := c.nearby("")[id]; ok {
			t.Error("three down votes should hide the report")
		}
		// One person changing their mind brings it back (net 2).
		c.vote(voterC, id, "up")
		if _, ok := c.nearby("")[id]; !ok {
			t.Error("net two down votes should show it again")
		}
	})

	t.Run("reports expire after two hours unless someone confirms them", func(t *testing.T) {
		old := c.newReport(owner, "closed", "road")
		confirmed := c.newReport(owner, "camera", "speed")
		for _, id := range []int64{old, confirmed} {
			if _, err := pool.Exec(context.Background(),
				`UPDATE reports SET created_at = now() - interval '3 hours' WHERE id = $1`, id); err != nil {
				t.Fatal(err)
			}
		}
		if _, ok := c.nearby("")[old]; ok {
			t.Error("a 3-hour-old report should be gone")
		}
		// A "still there" vote now makes the 3-hour-old report count as fresh again.
		if code, _ := c.vote(voterA, confirmed, "up"); code != http.StatusOK {
			t.Fatalf("vote: %d", code)
		}
		if _, ok := c.nearby("")[confirmed]; !ok {
			t.Error("a confirmed report should stay visible")
		}
		if _, ok := c.nearby("")[old]; ok {
			t.Error("the unconfirmed one must stay gone")
		}
	})
}
