package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

func TestCORSPreflightIsAnsweredWithoutCallingTheHandler(t *testing.T) {
	called := false
	h := cors(http.HandlerFunc(func(http.ResponseWriter, *http.Request) { called = true }))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("OPTIONS", "/reports", nil))
	if rec.Code != http.StatusNoContent || called {
		t.Errorf("status %d, handler called=%v", rec.Code, called)
	}
	hdr := rec.Header()
	if hdr.Get("Access-Control-Allow-Origin") == "" ||
		!strings.Contains(hdr.Get("Access-Control-Allow-Headers"), "Authorization") ||
		!strings.Contains(hdr.Get("Access-Control-Allow-Methods"), "POST") {
		t.Errorf("CORS headers missing: %v", hdr)
	}
}

func TestCORSAddsHeadersToNormalRequests(t *testing.T) {
	h := cors(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) { w.WriteHeader(http.StatusTeapot) }))
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest("GET", "/reports", nil))
	if rec.Code != http.StatusTeapot || rec.Header().Get("Access-Control-Allow-Origin") == "" {
		t.Errorf("status %d, headers %v", rec.Code, rec.Header())
	}
}

func TestReportTypesMatchTheApp(t *testing.T) {
	// The Flutter enum ReportType must use exactly these names.
	want := []string{"police", "accident", "jam", "hazard", "camera", "closed"}
	if len(validTypes) != len(want) {
		t.Errorf("validTypes has %d entries, want %d", len(validTypes), len(want))
	}
	for _, name := range want {
		if !validTypes[name] {
			t.Errorf("%q missing from validTypes", name)
		}
	}
}

func TestCreateReportValidation(t *testing.T) {
	s := &server{} // validation must reject these before any database call
	cases := []struct{ name, body string }{
		{"bad json", `{`},
		{"unknown type", `{"type":"ufo","lat":3.1,"lng":101.7}`},
		{"lat out of range", `{"type":"jam","lat":91,"lng":101.7}`},
		{"lng out of range", `{"type":"jam","lat":3.1,"lng":181}`},
		{"empty", `{}`},
	}
	for _, c := range cases {
		rec := httptest.NewRecorder()
		s.createReport(rec, httptest.NewRequest("POST", "/reports", strings.NewReader(c.body)))
		if rec.Code != http.StatusBadRequest {
			t.Errorf("%s: status %d, want 400", c.name, rec.Code)
		}
	}
}

func TestNearbyReportsRequiresPosition(t *testing.T) {
	s := &server{}
	for _, q := range []string{"", "lat=3.1", "lng=101.7", "lat=x&lng=y"} {
		rec := httptest.NewRecorder()
		s.nearbyReports(rec, httptest.NewRequest("GET", "/reports?"+q, nil))
		if rec.Code != http.StatusBadRequest {
			t.Errorf("%q: status %d, want 400", q, rec.Code)
		}
	}
}
