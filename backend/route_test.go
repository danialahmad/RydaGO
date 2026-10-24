package main

import (
	"encoding/json"
	"io"
	"math"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync"
	"testing"
)

// encodePolyline6 is the inverse of decodePolyline6, used to build fake Valhalla
// responses and to round-trip test the decoder.
func encodePolyline6(pts [][2]float64) string {
	var b strings.Builder
	var prevLat, prevLng int
	put := func(v int) {
		v <<= 1
		if v < 0 {
			v = ^v
		}
		for v >= 0x20 {
			b.WriteByte(byte((0x20 | (v & 0x1f)) + 63))
			v >>= 5
		}
		b.WriteByte(byte(v + 63))
	}
	for _, p := range pts {
		lat, lng := int(math.Round(p[0]*1e6)), int(math.Round(p[1]*1e6))
		put(lat - prevLat)
		put(lng - prevLng)
		prevLat, prevLng = lat, lng
	}
	return b.String()
}

func TestDecodePolyline6RoundTrip(t *testing.T) {
	in := [][2]float64{
		{3.157900, 101.711600},
		{3.158123, 101.712999},
		{-0.000001, -0.000001}, // sign flips and tiny values
		{-33.868820, 151.209290},
		{3.157900, 101.711600},
	}
	got := decodePolyline6(encodePolyline6(in))
	if len(got) != len(in) {
		t.Fatalf("got %d points, want %d", len(got), len(in))
	}
	for i := range in {
		if math.Abs(got[i][0]-in[i][0]) > 1e-6 || math.Abs(got[i][1]-in[i][1]) > 1e-6 {
			t.Errorf("point %d: got %v, want %v", i, got[i], in[i])
		}
	}
}

func TestDecodePolyline6Garbage(t *testing.T) {
	// Truncated and empty input must not panic or loop forever.
	if got := decodePolyline6(""); len(got) != 0 {
		t.Errorf("empty input: got %v", got)
	}
	full := encodePolyline6([][2]float64{{3.1, 101.7}, {3.2, 101.8}})
	_ = decodePolyline6(full[:len(full)-2])
}

func TestManeuverText(t *testing.T) {
	cases := []struct {
		name    string
		typ     int
		streets []string
		exit    int
		want    string
	}{
		{"start on street", 1, []string{"Jalan A"}, 0, "Mulakan perjalanan di Jalan A"},
		{"right turn", 10, []string{"Jalan B"}, 0, "Belok kanan menuju Jalan B"},
		{"left turn no street", 15, nil, 0, "Belok kiri"},
		{"roundabout exit", 26, []string{"Jalan C"}, 2, "Masuk bulatan, ambil simpang ke-2 menuju Jalan C"},
		{"arrive ignores street", 4, []string{"Jalan D"}, 0, "Anda telah sampai"},
		{"arrive right side", 5, nil, 0, "Anda telah sampai, di sebelah kanan"},
		{"continue", 8, []string{"Jalan E"}, 0, "Teruskan di Jalan E"},
		{"unknown type falls back", 99, nil, 0, "Teruskan"},
	}
	for _, c := range cases {
		if got := maneuverText(c.typ, c.streets, c.exit); got != c.want {
			t.Errorf("%s: got %q, want %q", c.name, got, c.want)
		}
	}
}

func TestParseLatLng(t *testing.T) {
	good := map[string][2]float64{
		"3.1579,101.7116":    {3.1579, 101.7116},
		" 3.1579 , 101.7116": {3.1579, 101.7116},
		"-90,180":            {-90, 180},
	}
	for in, want := range good {
		lat, lng, ok := parseLatLng(in)
		if !ok || lat != want[0] || lng != want[1] {
			t.Errorf("%q: got %v,%v ok=%v", in, lat, lng, ok)
		}
	}
	for _, in := range []string{"", "abc", "1,2,3", "91,0", "0,181", "x,y", "3.1579"} {
		if _, _, ok := parseLatLng(in); ok {
			t.Errorf("%q should be rejected", in)
		}
	}
}

// fakeValhalla answers /route with a 3-point trip and records the costing
// options each request asked for.
func fakeValhalla(t *testing.T, failWhen func(opts map[string]any) bool) (*httptest.Server, *[]map[string]any) {
	t.Helper()
	var mu sync.Mutex
	var seen []map[string]any
	shape := encodePolyline6([][2]float64{{3.1579, 101.7116}, {3.1600, 101.7200}, {3.1602, 101.7274}})
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		body, _ := io.ReadAll(r.Body)
		var req struct {
			Costing        string                    `json:"costing"`
			CostingOptions map[string]map[string]any `json:"costing_options"`
		}
		if err := json.Unmarshal(body, &req); err != nil || req.Costing != "auto" {
			http.Error(w, "bad request", http.StatusBadRequest)
			return
		}
		opts := req.CostingOptions["auto"]
		mu.Lock()
		seen = append(seen, opts)
		mu.Unlock()
		if failWhen != nil && failWhen(opts) {
			http.Error(w, "boom", http.StatusInternalServerError)
			return
		}
		json.NewEncoder(w).Encode(map[string]any{"trip": map[string]any{
			"summary": map[string]any{"time": 600.0, "length": 12.34},
			"legs": []map[string]any{{
				"shape": shape,
				"maneuvers": []map[string]any{
					{"type": 1, "length": 0.5, "begin_shape_index": 0, "street_names": []string{"Jalan A"}},
					{"type": 10, "length": 6.0, "begin_shape_index": 1, "street_names": []string{"Jalan B"}},
					{"type": 4, "length": 0.0, "begin_shape_index": 2},
				},
			}},
		}})
	}))
	t.Cleanup(srv.Close)
	return srv, &seen
}

func useValhalla(t *testing.T, url string) {
	t.Helper()
	old := valhallaURL
	valhallaURL = url
	t.Cleanup(func() { valhallaURL = old })
}

func getRoute(t *testing.T, query string) *httptest.ResponseRecorder {
	t.Helper()
	rec := httptest.NewRecorder()
	(&server{}).route(rec, httptest.NewRequest("GET", "/route?"+query, nil))
	return rec
}

func TestRouteReturnsThreeVariants(t *testing.T) {
	srv, seen := fakeValhalla(t, nil)
	useValhalla(t, srv.URL)

	rec := getRoute(t, "from=3.1579,101.7116&to=3.1602,101.7274")
	if rec.Code != http.StatusOK {
		t.Fatalf("status %d: %s", rec.Code, rec.Body)
	}
	var routes []routeOut
	if err := json.Unmarshal(rec.Body.Bytes(), &routes); err != nil {
		t.Fatal(err)
	}
	if len(routes) != 3 {
		t.Fatalf("got %d routes, want 3", len(routes))
	}
	labels := []string{routes[0].Label, routes[1].Label, routes[2].Label}
	if strings.Join(labels, "|") != "Terpantas|Tanpa tol|Jarak terpendek" {
		t.Errorf("labels out of order: %v", labels)
	}
	r := routes[0]
	if r.Minutes != 10 || r.Km != 12.3 {
		t.Errorf("minutes/km: got %d / %v, want 10 / 12.3", r.Minutes, r.Km)
	}
	if len(r.Points) != 3 || math.Abs(r.Points[2][1]-101.7274) > 1e-6 {
		t.Errorf("points not decoded: %v", r.Points)
	}
	wantText := []string{"Mulakan perjalanan di Jalan A", "Belok kanan menuju Jalan B", "Anda telah sampai"}
	if len(r.Maneuvers) != 3 {
		t.Fatalf("got %d maneuvers", len(r.Maneuvers))
	}
	if r.Maneuvers[1].Street != "Jalan B" || r.Maneuvers[2].Street != "" {
		t.Errorf("street names: %q / %q", r.Maneuvers[1].Street, r.Maneuvers[2].Street)
	}
	if r.Via != "Jalan B" { // the longest step (6 km) is on Jalan B
		t.Errorf("via = %q, want Jalan B", r.Via)
	}
	for i, m := range r.Maneuvers {
		if m.Text != wantText[i] || m.Index != i {
			t.Errorf("maneuver %d: got %q idx %d", i, m.Text, m.Index)
		}
	}

	// Each variant must ask Valhalla for different costing options.
	var plain, noToll, shortest int
	for _, opts := range *seen {
		switch {
		case len(opts) == 0:
			plain++
		case opts["use_tolls"] == 0.0:
			noToll++
		case opts["shortest"] == true:
			shortest++
		}
	}
	if plain != 1 || noToll != 1 || shortest != 1 {
		t.Errorf("costing options sent: %v", *seen)
	}
}

func TestRouteKeepsWorkingVariantsWhenOneFails(t *testing.T) {
	srv, _ := fakeValhalla(t, func(opts map[string]any) bool { return opts["use_tolls"] != nil })
	useValhalla(t, srv.URL)

	rec := getRoute(t, "from=3.1,101.7&to=3.2,101.8")
	var routes []routeOut
	json.Unmarshal(rec.Body.Bytes(), &routes)
	if rec.Code != http.StatusOK || len(routes) != 2 {
		t.Fatalf("status %d, %d routes: %s", rec.Code, len(routes), rec.Body)
	}
}

func TestRouteBadGatewayWhenValhallaDown(t *testing.T) {
	srv, _ := fakeValhalla(t, func(map[string]any) bool { return true })
	useValhalla(t, srv.URL)
	if rec := getRoute(t, "from=3.1,101.7&to=3.2,101.8"); rec.Code != http.StatusBadGateway {
		t.Errorf("status %d, want 502", rec.Code)
	}
}

func TestRouteRejectsBadInput(t *testing.T) {
	for _, q := range []string{"", "from=abc&to=1,2", "from=3.1,101.7", "to=3.1,101.7", "from=999,0&to=1,2"} {
		if rec := getRoute(t, q); rec.Code != http.StatusBadRequest {
			t.Errorf("%q: status %d, want 400", q, rec.Code)
		}
	}
}
