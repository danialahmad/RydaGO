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
	"sync/atomic"
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
	return integrationServerWith(t, true)
}

// integrationServerWith starts the stack; relax lifts the per-user report limits.
func integrationServerWith(t *testing.T, relax bool) (*httptest.Server, *pgxpool.Pool) {
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
	s := &server{db: pool, jwtSecret: []byte(strings.Repeat("k", 32)), dummyHash: hash, relaxLimits: relax}
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

// reportSpot counts reports so each test report lands in a different place, more
// than the 100 m duplicate radius from the last (all stay inside the 2 km queries).
var reportSpot atomic.Int64

// newReport files a report near KLCC and returns its id.
func (c apiClient) newReport(token, typ, subtype string) int64 {
	c.t.Helper()
	lng := 101.7116 + float64(reportSpot.Add(1)%10)*0.0013
	code, out := c.do("POST", "/reports", token,
		map[string]any{"type": typ, "subtype": subtype, "lat": 3.1579, "lng": lng})
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

func TestDuplicatesDeletionAndAccountRemoval(t *testing.T) {
	ts, pool := integrationServer(t)
	c := apiClient{t: t, base: ts.URL}
	alice := c.register("alice@example.my")
	bob := c.register("bob@example.my")
	spot := map[string]any{"type": "police", "subtype": "hidden", "lat": 3.1579, "lng": 101.7116}

	t.Run("the same user reporting the same thing in the same place is a duplicate", func(t *testing.T) {
		if code, out := c.do("POST", "/reports", alice, spot); code != http.StatusCreated {
			t.Fatalf("first report: %d %s", code, out)
		}
		if code, _ := c.do("POST", "/reports", alice, spot); code != http.StatusConflict {
			t.Errorf("repeat: %d, want 409", code)
		}
		other := map[string]any{"type": "jam", "subtype": "heavy", "lat": 3.1579, "lng": 101.7116}
		if code, _ := c.do("POST", "/reports", alice, other); code != http.StatusCreated {
			t.Errorf("a different type at the same spot is fine: %d", code)
		}
		if code, _ := c.do("POST", "/reports", bob, spot); code != http.StatusCreated {
			t.Errorf("another user reporting the same thing is a confirmation: %d", code)
		}
		far := map[string]any{"type": "police", "subtype": "hidden", "lat": 3.1579, "lng": 101.7316}
		if code, _ := c.do("POST", "/reports", alice, far); code != http.StatusCreated {
			t.Errorf("the same type 2 km away is fine: %d", code)
		}
	})

	t.Run("only the owner can delete a report, and its votes go with it", func(t *testing.T) {
		id := c.newReport(alice, "hazard", "pothole")
		c.vote(bob, id, "up")
		path := fmt.Sprintf("/reports/%d", id)
		if code, _ := c.do("DELETE", path, "", nil); code != http.StatusUnauthorized {
			t.Errorf("no token: %d, want 401", code)
		}
		if code, _ := c.do("DELETE", path, bob, nil); code != http.StatusForbidden {
			t.Errorf("other user: %d, want 403", code)
		}
		if code, _ := c.do("DELETE", path, alice, nil); code != http.StatusNoContent {
			t.Errorf("owner: %d, want 204", code)
		}
		if code, _ := c.do("DELETE", path, alice, nil); code != http.StatusNotFound {
			t.Errorf("again: %d, want 404", code)
		}
		var votes int
		pool.QueryRow(context.Background(), `SELECT count(*) FROM report_votes WHERE report_id = $1`, id).Scan(&votes)
		if votes != 0 {
			t.Errorf("%d votes left behind", votes)
		}
		if code, _ := c.do("DELETE", "/reports/abc", alice, nil); code != http.StatusBadRequest {
			t.Errorf("bad id: %d, want 400", code)
		}
	})

	t.Run("deleting an account needs the password and removes the user's reports and votes", func(t *testing.T) {
		carol := c.register("carol@example.my")
		mine := c.newReport(carol, "camera", "speed")
		theirs := c.newReport(alice, "closed", "road")
		c.vote(carol, theirs, "up")

		if code, _ := c.do("DELETE", "/me", "", map[string]string{"password": "password123"}); code != http.StatusUnauthorized {
			t.Errorf("no token: %d, want 401", code)
		}
		if code, _ := c.do("DELETE", "/me", carol, map[string]string{"password": "wrong-password"}); code != http.StatusForbidden {
			t.Errorf("wrong password: %d, want 403", code)
		}
		if code, out := c.do("DELETE", "/me", carol, map[string]string{"password": "password123"}); code != http.StatusNoContent {
			t.Fatalf("delete: %d %s", code, out)
		}
		var users, reports, votes int
		ctx := context.Background()
		pool.QueryRow(ctx, `SELECT count(*) FROM users WHERE email = 'carol@example.my'`).Scan(&users)
		pool.QueryRow(ctx, `SELECT count(*) FROM reports WHERE id = $1`, mine).Scan(&reports)
		pool.QueryRow(ctx, `SELECT count(*) FROM report_votes WHERE report_id = $1`, theirs).Scan(&votes)
		if users != 0 || reports != 0 || votes != 0 {
			t.Errorf("left behind: users=%d reports=%d votes=%d", users, reports, votes)
		}
		if code, _ := c.do("POST", "/auth/login", "", map[string]string{"email": "carol@example.my", "password": "password123"}); code != http.StatusUnauthorized {
			t.Errorf("login after deletion: %d, want 401", code)
		}
	})
}

func TestRateLimitsOnTheRealRouter(t *testing.T) {
	ts, _ := integrationServerWith(t, false)
	c := apiClient{t: t, base: ts.URL}
	var last int
	for i := 0; i < 12; i++ {
		last, _ = c.do("POST", "/auth/login", "", map[string]string{"email": "nobody@example.my", "password": "password123"})
	}
	if last != http.StatusTooManyRequests {
		t.Errorf("12 logins in a row ended with %d, want 429", last)
	}
}

func TestReportRateLimitPerUser(t *testing.T) {
	ts, _ := integrationServerWith(t, false)
	c := apiClient{t: t, base: ts.URL}
	a := c.register("rl-a@example.my")
	b := c.register("rl-b@example.my")
	codes := make([]int, 0, 7)
	for i := 0; i < 7; i++ {
		code, _ := c.do("POST", "/reports", a,
			map[string]any{"type": "jam", "subtype": "heavy", "lat": 3.1 + float64(i)*0.01, "lng": 101.7})
		codes = append(codes, code)
	}
	for i, code := range codes {
		want := http.StatusCreated
		if i >= 5 {
			want = http.StatusTooManyRequests // burst of 5, then 6 per minute
		}
		if code != want {
			t.Errorf("report %d: %d, want %d (all: %v)", i+1, code, want, codes)
		}
	}
	if code, _ := c.do("POST", "/reports", b,
		map[string]any{"type": "jam", "subtype": "heavy", "lat": 3.5, "lng": 101.7}); code != http.StatusCreated {
		t.Errorf("another user has their own allowance: %d", code)
	}
}

func TestLiveShare(t *testing.T) {
	ts, pool := integrationServer(t)
	c := apiClient{t: t, base: ts.URL}
	owner := c.register("sharer@example.my")
	other := c.register("nosy@example.my")
	start := map[string]any{"dest_name": "Batu Caves", "dest_lat": 3.2369, "dest_lng": 101.6833,
		"lat": 3.1579, "lng": 101.7116, "eta_minutes": 25}

	if code, _ := c.do("POST", "/shares", "", start); code != http.StatusUnauthorized {
		t.Errorf("create without login: %d, want 401", code)
	}
	if code, _ := c.do("POST", "/shares", owner, map[string]any{"dest_name": "x", "dest_lat": 99, "dest_lng": 0, "lat": 0, "lng": 0}); code != http.StatusBadRequest {
		t.Errorf("bad coordinates: %d, want 400", code)
	}
	code, out := c.do("POST", "/shares", owner, start)
	if code != http.StatusCreated {
		t.Fatalf("create: %d %s", code, out)
	}
	var made struct{ Token, Path string }
	json.Unmarshal(out, &made)
	if len(made.Token) < 16 || made.Path != "/s/"+made.Token {
		t.Fatalf("token/path = %+v", made)
	}

	// Anyone with the link can read it, no login.
	code, out = c.do("GET", "/shares/"+made.Token, "", nil)
	var got shareOut
	json.Unmarshal(out, &got)
	if code != http.StatusOK || got.DestName != "Batu Caves" || got.Ended || got.Stale {
		t.Fatalf("public read: %d %+v", code, got)
	}
	if mins := time.Until(got.EtaAt).Minutes(); mins < 23 || mins > 26 {
		t.Errorf("eta is %.1f minutes away, want ~25", mins)
	}

	// Only the owner may update or end it.
	move := map[string]any{"dest_name": "Batu Caves", "dest_lat": 3.2369, "dest_lng": 101.6833,
		"lat": 3.2, "lng": 101.7, "eta_minutes": 10}
	if code, _ := c.do("PUT", "/shares/"+made.Token, other, move); code != http.StatusForbidden {
		t.Errorf("update by another user: %d, want 403", code)
	}
	if code, _ := c.do("PUT", "/shares/"+made.Token, owner, move); code != http.StatusNoContent {
		t.Fatalf("update by owner: %d, want 204", code)
	}
	_, out = c.do("GET", "/shares/"+made.Token, "", nil)
	json.Unmarshal(out, &got)
	if got.Lat != 3.2 || time.Until(got.EtaAt).Minutes() > 11 {
		t.Errorf("update not applied: %+v", got)
	}

	// An old signal is flagged as stale.
	pool.Exec(context.Background(), `UPDATE shares SET updated_at = now() - interval '5 minutes' WHERE token = $1`, made.Token)
	_, out = c.do("GET", "/shares/"+made.Token, "", nil)
	json.Unmarshal(out, &got)
	if !got.Stale {
		t.Error("a share not updated for 5 minutes should be stale")
	}

	if code, _ := c.do("DELETE", "/shares/"+made.Token, other, nil); code != http.StatusForbidden {
		t.Errorf("end by another user: %d, want 403", code)
	}
	if code, _ := c.do("DELETE", "/shares/"+made.Token, owner, nil); code != http.StatusNoContent {
		t.Fatalf("end by owner: %d, want 204", code)
	}
	_, out = c.do("GET", "/shares/"+made.Token, "", nil)
	json.Unmarshal(out, &got)
	if !got.Ended || got.Stale {
		t.Errorf("ended share: %+v", got)
	}
	if code, _ := c.do("PUT", "/shares/"+made.Token, owner, move); code != http.StatusGone {
		t.Errorf("update after end: %d, want 410", code)
	}

	// Unknown or malformed tokens are 404, and links expire after the max age.
	if code, _ := c.do("GET", "/shares/doesnotexistdoesnotexist", "", nil); code != http.StatusNotFound {
		t.Errorf("unknown token: %d, want 404", code)
	}
	if code, _ := c.do("GET", "/shares/short", "", nil); code != http.StatusNotFound {
		t.Errorf("malformed token: %d, want 404", code)
	}
	pool.Exec(context.Background(), `UPDATE shares SET created_at = now() - interval '9 hours' WHERE token = $1`, made.Token)
	if code, _ := c.do("GET", "/shares/"+made.Token, "", nil); code != http.StatusNotFound {
		t.Errorf("expired share: %d, want 404", code)
	}

	// The public page carries the token and loads nothing from other sites.
	code, page := c.do("GET", "/s/"+made.Token, "", nil)
	if code != http.StatusOK || !strings.Contains(string(page), made.Token) || strings.Contains(string(page), "src=\"http") {
		t.Errorf("share page: %d, token present=%v", code, strings.Contains(string(page), made.Token))
	}
	if code, _ := c.do("GET", "/s/bad%22%3E%3Cscript", "", nil); code != http.StatusNotFound {
		t.Errorf("a token with odd characters must be rejected: %d", code)
	}
}
