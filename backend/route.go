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
	Text   string  `json:"text"`
	Street string  `json:"street,omitempty"` // first street name of the step, shown in the banner
	Type   int     `json:"type"`             // Valhalla maneuver type, used by the app to pick an icon
	Km     float64 `json:"km"`               // length of this step
	Index  int     `json:"index"`            // index into Points where the step begins
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
}{
	{"fastest", map[string]string{langEN: "Fastest", langMS: "Terpantas"},
		map[string]string{langEN: "Fastest route", langMS: "Laluan terpantas"}, map[string]any{}},
	{"notoll", map[string]string{langEN: "No tolls", langMS: "Tanpa tol"},
		map[string]string{langEN: "Avoids tolls", langMS: "Elak tol"}, map[string]any{"use_tolls": 0.0}},
	{"shortest", map[string]string{langEN: "Shortest", langMS: "Jarak terpendek"},
		map[string]string{langEN: "Shortest distance", langMS: "Jarak paling dekat"}, map[string]any{"shortest": true}},
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
	fromLat, fromLng, ok1 := parseLatLng(r.URL.Query().Get("from"))
	toLat, toLng, ok2 := parseLatLng(r.URL.Query().Get("to"))
	if !ok1 || !ok2 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "from and to must be lat,lng"})
		return
	}

	results := make([]*routeOut, len(routeVariants))
	var wg sync.WaitGroup
	for i, v := range routeVariants {
		wg.Add(1)
		go func() {
			defer wg.Done()
			out, err := askValhalla(r.Context(), lang, fromLat, fromLng, toLat, toLng, v.opts)
			if err != nil {
				log.Printf("valhalla %s: %v", v.id, err)
				return
			}
			out.ID, out.Label, out.Note = v.id, v.label[lang], v.note[lang]
			results[i] = out
		}()
	}
	wg.Wait()

	routes := []routeOut{}
	for _, res := range results {
		if res != nil {
			routes = append(routes, *res)
		}
	}
	if len(routes) == 0 {
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "routing unavailable"})
		return
	}
	writeJSON(w, http.StatusOK, routes)
}

func askValhalla(ctx context.Context, lang string, fromLat, fromLng, toLat, toLng float64, autoOpts map[string]any) (*routeOut, error) {
	body, _ := json.Marshal(map[string]any{
		"locations": []map[string]float64{
			{"lat": fromLat, "lon": fromLng},
			{"lat": toLat, "lon": toLng},
		},
		"costing":         "auto",
		"costing_options": map[string]any{"auto": autoOpts},
		"units":           "kilometers",
	})
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
		Trip struct {
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
				} `json:"maneuvers"`
			} `json:"legs"`
		} `json:"trip"`
	}
	if err := json.NewDecoder(res.Body).Decode(&v); err != nil {
		return nil, err
	}
	var pts [][2]float64
	maneuvers := []maneuverOut{}
	limits := []limitRange{}
	via, viaKm := "", 0.0
	tollKm := 0.0
	for _, leg := range v.Trip.Legs {
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
			})
		}
	}
	if len(pts) < 2 {
		return nil, fmt.Errorf("empty route")
	}
	return &routeOut{
		Minutes:   max(1, int(v.Trip.Summary.Time/60+0.5)),
		Km:        float64(int(v.Trip.Summary.Length*10+0.5)) / 10,
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
