package main

import (
	"context"
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"net/url"
	"os"
	"strconv"
	"strings"
	"time"
)

var nominatimURL = func() string {
	if v := os.Getenv("NOMINATIM_URL"); v != "" {
		return strings.TrimRight(v, "/")
	}
	return "http://nominatim:8080"
}()

var nominatimClient = &http.Client{Timeout: 10 * time.Second}

type placeOut struct {
	Name     string  `json:"name"`
	Area     string  `json:"area"`
	Lat      float64 `json:"lat"`
	Lng      float64 `json:"lng"`
	Category string  `json:"category"`
	Type     string  `json:"type"`
}

// places proxies address search to Nominatim and trims the response to what
// the app needs. Optional lat/lng bias results towards the user.
func (s *server) places(w http.ResponseWriter, r *http.Request) {
	q := strings.TrimSpace(r.URL.Query().Get("q"))
	if n := len([]rune(q)); n < 2 || n > 200 {
		writeJSON(w, http.StatusBadRequest, map[string]string{"error": "q must be 2 to 200 characters"})
		return
	}
	params := url.Values{}
	params.Set("q", q)
	params.Set("format", "jsonv2")
	params.Set("addressdetails", "1")
	params.Set("limit", "8")
	params.Set("dedupe", "1")
	params.Set("countrycodes", "my,sg,bn")
	if langFrom(r) == langMS {
		params.Set("accept-language", "ms,en")
	} else {
		params.Set("accept-language", "en,ms")
	}
	if lat, err := strconv.ParseFloat(r.URL.Query().Get("lat"), 64); err == nil {
		if lng, err := strconv.ParseFloat(r.URL.Query().Get("lng"), 64); err == nil {
			// left,top,right,bottom: a soft preference (not bounded) around the user.
			params.Set("viewbox", fmt.Sprintf("%f,%f,%f,%f", lng-0.5, lat+0.5, lng+0.5, lat-0.5))
		}
	}

	out, err := searchNominatim(r.Context(), params)
	if err != nil {
		log.Printf("nominatim: %v", err)
		writeJSON(w, http.StatusBadGateway, map[string]string{"error": "search unavailable"})
		return
	}
	writeJSON(w, http.StatusOK, out)
}

func searchNominatim(ctx context.Context, params url.Values) ([]placeOut, error) {
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, nominatimURL+"/search?"+params.Encode(), nil)
	if err != nil {
		return nil, err
	}
	res, err := nominatimClient.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("status %d", res.StatusCode)
	}
	var raw []struct {
		Lat         string            `json:"lat"`
		Lon         string            `json:"lon"`
		Name        string            `json:"name"`
		DisplayName string            `json:"display_name"`
		Category    string            `json:"category"`
		Type        string            `json:"type"`
		Address     map[string]string `json:"address"`
	}
	if err := json.NewDecoder(res.Body).Decode(&raw); err != nil {
		return nil, err
	}
	out := make([]placeOut, 0, len(raw))
	for _, v := range raw {
		lat, err1 := strconv.ParseFloat(v.Lat, 64)
		lng, err2 := strconv.ParseFloat(v.Lon, 64)
		if err1 != nil || err2 != nil {
			continue
		}
		name := v.Name
		if name == "" {
			name, _, _ = strings.Cut(v.DisplayName, ",")
		}
		out = append(out, placeOut{
			Name: name, Area: areaOf(v.Address, name),
			Lat: lat, Lng: lng, Category: v.Category, Type: v.Type,
		})
	}
	return out, nil
}

// areaOf builds a short "suburb, city" style subtitle from Nominatim's address parts.
func areaOf(addr map[string]string, name string) string {
	pick := func(keys ...string) string {
		for _, k := range keys {
			if v := addr[k]; v != "" && v != name {
				return v
			}
		}
		return ""
	}
	var parts []string
	for _, p := range []string{
		pick("suburb", "neighbourhood", "city_district", "quarter"),
		pick("city", "town", "village", "municipality", "county"),
		pick("state"),
	} {
		if p != "" && (len(parts) == 0 || parts[len(parts)-1] != p) {
			parts = append(parts, p)
		}
		if len(parts) == 2 {
			break
		}
	}
	return strings.Join(parts, ", ")
}
