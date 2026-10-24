package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// These need no database: every case is rejected before the handler touches it.
func TestVoteRouteValidation(t *testing.T) {
	s := testServer()
	h := s.routes()
	token, err := s.issueToken(1)
	if err != nil {
		t.Fatal(err)
	}

	cases := []struct {
		name, path, body, auth string
		want                   int
	}{
		{"no token", "/reports/5/vote", `{"vote":"up"}`, "", http.StatusUnauthorized},
		{"bad token", "/reports/5/vote", `{"vote":"up"}`, "Bearer nonsense", http.StatusUnauthorized},
		{"id not a number", "/reports/abc/vote", `{"vote":"up"}`, "Bearer " + token, http.StatusBadRequest},
		{"id zero", "/reports/0/vote", `{"vote":"up"}`, "Bearer " + token, http.StatusBadRequest},
		{"vote missing", "/reports/5/vote", `{}`, "Bearer " + token, http.StatusBadRequest},
		{"vote not up or down", "/reports/5/vote", `{"vote":"UP"}`, "Bearer " + token, http.StatusBadRequest},
		{"body not json", "/reports/5/vote", `{`, "Bearer " + token, http.StatusBadRequest},
	}
	for _, c := range cases {
		req := httptest.NewRequest("POST", c.path, strings.NewReader(c.body))
		if c.auth != "" {
			req.Header.Set("Authorization", c.auth)
		}
		rec := httptest.NewRecorder()
		h.ServeHTTP(rec, req)
		if rec.Code != c.want {
			t.Errorf("%s: status %d, want %d (%s)", c.name, rec.Code, c.want, rec.Body)
		}
	}
}

func TestUserFromRequest(t *testing.T) {
	s := testServer()
	tok, _ := s.issueToken(9)

	req := httptest.NewRequest("GET", "/", nil)
	if _, present, _ := s.userFromRequest(req); present {
		t.Error("no header: present should be false")
	}
	req.Header.Set("Authorization", "Bearer "+tok)
	if uid, present, ok := s.userFromRequest(req); uid != 9 || !present || !ok {
		t.Errorf("valid token: %d %v %v", uid, present, ok)
	}
	req.Header.Set("Authorization", "Bearer garbage")
	if _, present, ok := s.userFromRequest(req); !present || ok {
		t.Errorf("bad token: present=%v ok=%v, want present but not ok", present, ok)
	}
}
