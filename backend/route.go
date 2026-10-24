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

type routeOut struct {
	Label     string        `json:"label"`
	Note      string        `json:"note"`
	Via       string        `json:"via,omitempty"` // the street the route follows for longest
	Minutes   int           `json:"minutes"`
	Km        float64       `json:"km"`
	Points    [][2]float64  `json:"points"` // [lat, lng]
	Maneuvers []maneuverOut `json:"maneuvers"`
}

// maneuverPhrases are Malay phrases for Valhalla's maneuver types
// (https://valhalla.github.io/valhalla/api/turn-by-turn/api-reference/).
var maneuverPhrases = map[int]string{
	1: "Mulakan perjalanan", 2: "Mulakan perjalanan", 3: "Mulakan perjalanan",
	4: "Anda telah sampai", 5: "Anda telah sampai, di sebelah kanan",
	6: "Anda telah sampai, di sebelah kiri",
	7: "Teruskan", 8: "Teruskan",
	9: "Belok sedikit ke kanan", 10: "Belok kanan", 11: "Belok tajam ke kanan",
	12: "Pusing U ke kanan", 13: "Pusing U ke kiri",
	14: "Belok tajam ke kiri", 15: "Belok kiri", 16: "Belok sedikit ke kiri",
	17: "Teruskan ke ramp", 18: "Ambil ramp di kanan", 19: "Ambil ramp di kiri",
	20: "Ambil jalan keluar di kanan", 21: "Ambil jalan keluar di kiri",
	22: "Kekal lurus", 23: "Kekal di lorong kanan", 24: "Kekal di lorong kiri",
	25: "Bergabung ke lebuh raya",
	26: "Masuk bulatan", 27: "Keluar dari bulatan",
}

// maneuverText builds the instruction shown in the app, e.g. "Belok kanan ke Jalan Ampang".
func maneuverText(typ int, streets []string, roundaboutExit int) string {
	phrase, ok := maneuverPhrases[typ]
	if !ok {
		phrase = "Teruskan"
	}
	if typ == 26 && roundaboutExit > 0 {
		phrase += ", ambil simpang ke-" + strconv.Itoa(roundaboutExit)
	}
	if typ >= 4 && typ <= 6 || len(streets) == 0 {
		return phrase
	}
	switch typ {
	case 1, 2, 3, 7, 8:
		return phrase + " di " + streets[0]
	}
	return phrase + " menuju " + streets[0]
}

// Each variant maps one of the app's route choices to a Valhalla costing.
var routeVariants = []struct {
	label, note string
	opts        map[string]any
}{
	{"Terpantas", "Laluan terpantas", map[string]any{}},
	{"Tanpa tol", "Elak tol", map[string]any{"use_tolls": 0.0}},
	{"Jarak terpendek", "Jarak paling dekat", map[string]any{"shortest": true}},
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
			out, err := askValhalla(r.Context(), fromLat, fromLng, toLat, toLng, v.opts)
			if err != nil {
				log.Printf("valhalla %s: %v", v.label, err)
				return
			}
			out.Label, out.Note = v.label, v.note
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
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "routing tidak tersedia"})
		return
	}
	writeJSON(w, http.StatusOK, routes)
}

func askValhalla(ctx context.Context, fromLat, fromLng, toLat, toLng float64, autoOpts map[string]any) (*routeOut, error) {
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
				} `json:"maneuvers"`
			} `json:"legs"`
		} `json:"trip"`
	}
	if err := json.NewDecoder(res.Body).Decode(&v); err != nil {
		return nil, err
	}
	var pts [][2]float64
	maneuvers := []maneuverOut{}
	via, viaKm := "", 0.0
	for _, leg := range v.Trip.Legs {
		offset := len(pts) // maneuver indexes are relative to their own leg's shape
		pts = append(pts, decodePolyline6(leg.Shape)...)
		for _, m := range leg.Maneuvers {
			street := ""
			if len(m.StreetNames) > 0 {
				street = m.StreetNames[0]
			}
			if street != "" && m.Length > viaKm {
				via, viaKm = street, m.Length
			}
			maneuvers = append(maneuvers, maneuverOut{
				Text:   maneuverText(m.Type, m.StreetNames, m.RoundaboutExitCount),
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
	}, nil
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
