package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

var valhallaURL = func() string {
	if v := os.Getenv("VALHALLA_URL"); v != "" {
		return strings.TrimRight(v, "/")
	}
	return "http://valhalla:8002"
}()

var valhallaClient = &http.Client{Timeout: 20 * time.Second}

type maneuverOut struct {
	Text   string    `json:"text"`
	Street string    `json:"street,omitempty"` // first street name of the step, shown in the banner
	Type   int       `json:"type"`             // Valhalla maneuver type, used by the app to pick an icon
	Km     float64   `json:"km"`               // length of this step
	Index  int       `json:"index"`            // index into Points where the step begins
	Exit   string    `json:"exit,omitempty"`   // highway exit number from the road sign, e.g. "3310A"
	Toward string    `json:"toward,omitempty"` // destinations on the sign, e.g. "Gombak / Batu Caves"
	Lanes  []laneOut `json:"lanes,omitempty"`  // only where OpenStreetMap has lane data
}

// limitRange says the posted speed limit is Kmh for route points From..To.
// Only stretches where OpenStreetMap knows the limit are listed (coverage in
// Malaysia is partial), so gaps mean "unknown", not "no limit".
type limitRange struct {
	From int `json:"from"`
	To   int `json:"to"`
	Kmh  int `json:"kmh"`
}

type routeOut struct {
	ID        string        `json:"id"` // stable: "fastest", "notoll", "shortest" (Label is translated)
	Label     string        `json:"label"`
	Note      string        `json:"note"`
	Via       string        `json:"via,omitempty"` // the street the route follows for longest
	Minutes   int           `json:"minutes"`
	Km        float64       `json:"km"`
	Points    [][2]float64  `json:"points"` // [lat, lng]
	Maneuvers []maneuverOut `json:"maneuvers"`
	Limits    []limitRange  `json:"limits"`
	Toll      *tollOut      `json:"toll,omitempty"` // absent when the route has no toll road
}

// Each variant maps one of the app's route choices to a Valhalla costing.
var routeVariants = []struct {
	id          string
	label, note map[string]string // by language
	opts        map[string]any
	alternates  int // extra routes to ask Valhalla for with this variant
}{
	{"fastest", map[string]string{langEN: "Fastest", langMS: "Terpantas"},
		map[string]string{langEN: "Fastest route", langMS: "Laluan terpantas"}, map[string]any{}, 2},
	{"notoll", map[string]string{langEN: "No tolls", langMS: "Tanpa tol"},
		map[string]string{langEN: "Avoids tolls", langMS: "Elak tol"}, map[string]any{"use_tolls": 0.0}, 0},
	{"shortest", map[string]string{langEN: "Shortest", langMS: "Jarak terpendek"},
		map[string]string{langEN: "Shortest distance", langMS: "Jarak paling dekat"}, map[string]any{"shortest": true}, 0},
}

func parseLatLng(s string) (lat, lng float64, ok bool) {
	parts := strings.Split(s, ",")
	if len(parts) != 2 {
		return 0, 0, false
	}
	lat, err1 := strconv.ParseFloat(strings.TrimSpace(parts[0]), 64)
	lng, err2 := strconv.ParseFloat(strings.TrimSpace(parts[1]), 64)
	if err1 != nil || err2 != nil || lat < -90 || lat > 90 || lng < -180 || lng > 180 {
		return 0, 0, false
	}
	return lat, lng, true
}

func (s *server) route(w http.ResponseWriter, r *http.Request) {
	lang := langFrom(r)
	avoid := avoidOpts(r.URL.Query().Get("avoid"))
	fromLat, fromLng, ok1 := parseLatLng(r.URL.Query().Get("from"))
	toLat, toLng, ok2 := parseLatLng(r.URL.Query().Get("to"))
	if !ok1 || !ok2 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "from and to must be lat,lng"})
		return
	}

	results := make([][]*routeOut, len(routeVariants))
	var wg sync.WaitGroup
	for i, v := range routeVariants {
		wg.Add(1)
		go func() {
			defer wg.Done()
			out, err := askValhalla(r.Context(), lang, fromLat, fromLng, toLat, toLng, withOpts(v.opts, avoid), v.alternates)
			if err != nil {
				log.Printf("valhalla %s: %v", v.id, err)
				return
			}
			out[0].ID, out[0].Label, out[0].Note = v.id, v.label[lang], v.note[lang]
			for n, alt := range out[1:] {
				alt.ID = "alt" + strconv.Itoa(n+1)
				alt.Label, alt.Note = altLabel[lang], altNote[lang]
			}
			results[i] = out
		}()
	}
	wg.Wait()

	var base, alts []routeOut
	for _, res := range results {
		if len(res) == 0 {
			continue
		}
		base = append(base, *res[0])
		for _, a := range res[1:] {
			alts = append(alts, *a)
		}
	}
	routes := pickRoutes(base, alts, maxRoutes)
	if len(routes) == 0 {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "routing unavailable"})
		return
	}
	writeJSON(w, http.StatusOK, routes)
}

// askValhalla returns the requested route first, then up to [alternates] other
// routes Valhalla found between the same two points.
func askValhalla(ctx context.Context, lang string, fromLat, fromLng, toLat, toLng float64, autoOpts map[string]any, alternates int) ([]*routeOut, error) {
	payload := map[string]any{
		"locations": []map[string]float64{
			{"lat": fromLat, "lon": fromLng},
			{"lat": toLat, "lon": toLng},
		},
		"costing":         "auto",
		"costing_options": map[string]any{"auto": autoOpts},
		"units":           "kilometers",
	}
	if alternates > 0 {
		payload["alternates"] = alternates
	}
	body, _ := json.Marshal(payload)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, valhallaURL+"/route", bytes.NewReader(body))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	res, err := valhallaClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("status %d", res.StatusCode)
	}
	var v struct {
		Trip       valhallaTrip `json:"trip"`
		Alternates []struct {
			Trip valhallaTrip `json:"trip"`
		} `json:"alternates"`
	}
	if err := json.NewDecoder(res.Body).Decode(&v); err != nil {
		return nil, err
	}
	first, err := buildRoute(ctx, lang, v.Trip)
	if err != nil {
		return nil, err
	}
	out := []*routeOut{first}
	for _, a := range v.Alternates {
		if r, err := buildRoute(ctx, lang, a.Trip); err == nil {
			out = append(out, r)
		}
	}
	return out, nil
}

// valhallaTrip is the part of a Valhalla trip the API reads.
type valhallaTrip = struct {
	Summary struct {
		Time   float64 `json:"time"`
		Length float64 `json:"length"`
	} `json:"summary"`
	Legs []struct {
		Shape     string `json:"shape"`
		Maneuvers []struct {
			Type                int      `json:"type"`
			Length              float64  `json:"length"`
			BeginShapeIndex     int      `json:"begin_shape_index"`
			StreetNames         []string `json:"street_names"`
			RoundaboutExitCount int      `json:"roundabout_exit_count"`
			Toll                bool     `json:"toll"`
			Sign                struct {
				ExitNumber []signElement `json:"exit_number_elements"`
				Toward     []signElement `json:"exit_toward_elements"`
			} `json:"sign"`
			Lanes []valhallaLane `json:"lanes"`
		} `json:"maneuvers"`
	} `json:"legs"`
}

// buildRoute turns one Valhalla trip into the app's route format.
func buildRoute(ctx context.Context, lang string, trip valhallaTrip) (*routeOut, error) {
	var pts [][2]float64
	maneuvers := []maneuverOut{}
	limits := []limitRange{}
	via, viaKm := "", 0.0
	tollKm := 0.0
	for _, leg := range trip.Legs {
		offset := len(pts) // maneuver indexes are relative to their own leg's shape
		pts = append(pts, decodePolyline6(leg.Shape)...)
		for _, l := range traceLimits(ctx, leg.Shape) {
			limits = append(limits, limitRange{From: l.From + offset, To: l.To + offset, Kmh: l.Kmh})
		}
		for _, m := range leg.Maneuvers {
			street := ""
			if len(m.StreetNames) > 0 {
				street = m.StreetNames[0]
			}
			if m.Toll {
				tollKm += m.Length
			}
			if street != "" && m.Length > viaKm {
				via, viaKm = street, m.Length
			}
			maneuvers = append(maneuvers, maneuverOut{
				Text:   maneuverText(lang, m.Type, m.StreetNames, m.RoundaboutExitCount),
				Street: street,
				Type:   m.Type,
				Km:     m.Length,
				Index:  min(offset+m.BeginShapeIndex, len(pts)-1),
				Exit:   firstText(m.Sign.ExitNumber),
				Toward: joinText(m.Sign.Toward, 2),
				Lanes:  lanesOut(m.Lanes),
			})
		}
	}
	if len(pts) < 2 {
		return nil, fmt.Errorf("empty route")
	}
	return &routeOut{
		Minutes:   max(1, int(trip.Summary.Time/60+0.5)),
		Km:        float64(int(trip.Summary.Length*10+0.5)) / 10,
		Points:    pts,
		Maneuvers: maneuvers,
		Via:       via,
		Limits:    limits,
		Toll:      tollFor(tollKm),
	}, nil
}

// traceLimits asks Valhalla which posted speed limit applies along a route's shape.
// Failure is not an error for the route: the app just shows no limit.
func traceLimits(ctx context.Context, shape string) []limitRange {
	body, _ := json.Marshal(map[string]any{
		"encoded_polyline": shape,
		"costing":          "auto",
		"shape_match":      "edge_walk", // the shape came from Valhalla, so it walks its own edges exactly
		"filters": map[string]any{
			"attributes": []string{"edge.speed_limit", "edge.begin_shape_index", "edge.end_shape_index"},
			"action":     "include",
		},
	})
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, valhallaURL+"/trace_attributes", bytes.NewReader(body))
	if err != nil {
		return nil
	}
	req.Header.Set("Content-Type", "application/json")
	res, err := valhallaClient.Do(req)
	if err != nil {
		return nil
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return nil
	}
	var v struct {
		Edges []struct {
			SpeedLimit any `json:"speed_limit"` // a number, or absent when unknown
			Begin      int `json:"begin_shape_index"`
			End        int `json:"end_shape_index"`
		} `json:"edges"`
	}
	if json.NewDecoder(res.Body).Decode(&v) != nil {
		return nil
	}
	var out []limitRange
	for _, e := range v.Edges {
		if kmh, ok := e.SpeedLimit.(float64); ok && kmh > 0 && kmh < 200 {
			out = append(out, limitRange{From: e.Begin, To: e.End, Kmh: int(kmh)})
		}
	}
	return mergeLimits(out)
}

// mergeLimits joins neighbouring ranges that have the same limit.
func mergeLimits(in []limitRange) []limitRange {
	var out []limitRange
	for _, r := range in {
		if n := len(out); n > 0 && out[n-1].Kmh == r.Kmh && r.From <= out[n-1].To {
			if r.To > out[n-1].To {
				out[n-1].To = r.To
			}
			continue
		}
		out = append(out, r)
	}
	return out
}

// decodePolyline6 decodes Valhalla's encoded shape (polyline with 6 decimals).
func decodePolyline6(s string) [][2]float64 {
	var out [][2]float64
	idx, lat, lng := 0, 0, 0
	for idx < len(s) {
		for _, p := range []*int{&lat, &lng} {
			shift, result := 0, 0
			for {
				if idx >= len(s) {
					return out
				}
				b := int(s[idx]) - 63
				idx++
				result |= (b & 0x1f) << shift
				shift += 5
				if b < 0x20 {
					break
				}
			}
			if result&1 != 0 {
				*p += ^(result >> 1)
			} else {
				*p += result >> 1
			}
		}
		out = append(out, [2]float64{float64(lat) / 1e6, float64(lng) / 1e6})
	}
	return out
}

// maxRoutes is how many route cards the app shows at most.
const maxRoutes = 3

var (
	altLabel = map[string]string{langEN: "Alternative", langMS: "Alternatif"}
	altNote  = map[string]string{langEN: "Another way to go", langMS: "Jalan lain"}
)

// sameRoute says two routes are, for a driver, the same choice: equal length,
// time and main road.
func sameRoute(a, b routeOut) bool {
	return a.Km == b.Km && a.Minutes == b.Minutes && a.Via == b.Via
}

// pickRoutes returns at most [limit] distinct routes: the named choices first
// (fastest, no tolls, shortest), then real alternatives from Valhalla to fill the
// list. Choices that came out identical to an earlier one (no tolls on a road
// with none, say) are dropped, so every card on screen is a different decision.
func pickRoutes(base, alts []routeOut, limit int) []routeOut {
	out := []routeOut{}
	add := func(r routeOut) {
		if len(out) >= limit {
			return
		}
		for _, have := range out {
			if sameRoute(have, r) {
				return
			}
		}
		out = append(out, r)
	}
	for _, r := range base {
		add(r)
	}
	for _, r := range alts {
		add(r)
	}
	return out
}

// avoidOpts turns the app's ?avoid=highways,ferries into Valhalla costing options.
// Unknown words are ignored.
func avoidOpts(avoid string) map[string]any {
	opts := map[string]any{}
	for _, a := range strings.Split(avoid, ",") {
		switch strings.TrimSpace(a) {
		case "highways":
			opts["use_highways"] = 0.0
		case "ferries":
			opts["use_ferry"] = 0.0
		}
	}
	return opts
}

// withOpts is base plus extra (extra wins), as a new map.
func withOpts(base, extra map[string]any) map[string]any {
	out := make(map[string]any, len(base)+len(extra))
	for k, v := range base {
		out[k] = v
	}
	for k, v := range extra {
		out[k] = v
	}
	return out
}
