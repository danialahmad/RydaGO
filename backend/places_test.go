package main

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"
)

func TestAreaOf(t *testing.T) {
	cases := []struct {
		name string
		addr map[string]string
		self string
		want string
	}{
		{"suburb and city", map[string]string{"suburb": "Bukit Bintang", "city": "Kuala Lumpur", "state": "WP"}, "Pavilion", "Bukit Bintang, Kuala Lumpur"},
		{"skips the place's own name", map[string]string{"suburb": "KLCC", "city": "Kuala Lumpur"}, "KLCC", "Kuala Lumpur"},
		{"falls back to state", map[string]string{"state": "Selangor"}, "X", "Selangor"},
		{"no duplicates", map[string]string{"city": "Penang", "state": "Penang"}, "X", "Penang"},
		{"empty", map[string]string{}, "X", ""},
	}
	for _, c := range cases {
		if got := areaOf(c.addr, c.self); got != c.want {
			t.Errorf("%s: got %q, want %q", c.name, got, c.want)
		}
	}
}

func fakeNominatim(t *testing.T, status int, body string) (*httptest.Server, *url.Values) {
	t.Helper()
	var got url.Values
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		got = r.URL.Query()
		w.WriteHeader(status)
		w.Write([]byte(body))
	}))
	t.Cleanup(srv.Close)
	old := nominatimURL
	nominatimURL = srv.URL
	t.Cleanup(func() { nominatimURL = old })
	return srv, &got
}

func getPlaces(query string) *httptest.ResponseRecorder {
	rec := httptest.NewRecorder()
	(&server{}).places(rec, httptest.NewRequest("GET", "/places?"+query, nil))
	return rec
}

func TestPlacesMapsNominatimResponse(t *testing.T) {
	_, got := fakeNominatim(t, 200, `[
	  {"lat":"3.1560","lon":"101.7146","name":"KLCC","display_name":"KLCC, Kuala Lumpur, Malaysia",
	   "category":"place","type":"quarter","address":{"suburb":"Bukit Bintang","city":"Kuala Lumpur"}},
	  {"lat":"oops","lon":"1","name":"Broken"},
	  {"lat":"3.1","lon":"101.6","name":"","display_name":"Jalan Tun Razak, Kuala Lumpur","category":"highway","type":"primary","address":{}}
	]`)

	rec := getPlaces("q=klcc&lat=3.15&lng=101.71")
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d: %s", rec.Code, rec.Body)
	}
	var out []placeOut
	if err := json.Unmarshal(rec.Body.Bytes(), &out); err != nil {
		t.Fatal(err)
	}
	if len(out) != 2 {
		t.Fatalf("got %d places, want 2 (unparsable coordinates are dropped): %+v", len(out), out)
	}
	if out[0].Name != "KLCC" || out[0].Area != "Bukit Bintang, Kuala Lumpur" || out[0].Lat != 3.156 {
		t.Errorf("first place: %+v", out[0])
	}
	if out[1].Name != "Jalan Tun Razak" {
		t.Errorf("name should fall back to the first part of display_name: %+v", out[1])
	}

	q := *got
	if q.Get("q") != "klcc" || q.Get("countrycodes") != "my,sg,bn" || q.Get("format") != "jsonv2" {
		t.Errorf("query sent to Nominatim: %v", q)
	}
	if !strings.HasPrefix(q.Get("viewbox"), "101.21") {
		t.Errorf("viewbox should be built around lng 101.71: %q", q.Get("viewbox"))
	}
}

func TestPlacesValidationAndErrors(t *testing.T) {
	for _, q := range []string{"", "q=a", "q=" + strings.Repeat("x", 201)} {
		if rec := getPlaces(q); rec.Code != http.StatusBadRequest {
			t.Errorf("%.20q: status %d, want 400", q, rec.Code)
		}
	}
	fakeNominatim(t, 500, "down")
	if rec := getPlaces("q=klcc"); rec.Code != http.StatusBadGateway {
		t.Errorf("upstream failure: status %d, want 502", rec.Code)
	}
}

func TestPlacesWithoutPositionSendsNoViewbox(t *testing.T) {
	_, got := fakeNominatim(t, 200, `[]`)
	if rec := getPlaces("q=klcc"); rec.Code != http.StatusOK || strings.TrimSpace(rec.Body.String()) != "[]" {
		t.Fatalf("status %d body %q", rec.Code, rec.Body)
	}
	if (*got).Has("viewbox") {
		t.Errorf("viewbox must only be sent when lat/lng are given: %v", *got)
	}
}
