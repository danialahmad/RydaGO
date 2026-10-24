package main

import (
	"math"
	"os"
	"strconv"
)

// tollOut describes the toll roads on a route. Valhalla knows *where* tolls are
// (OpenStreetMap toll tags) but not what they cost, so the price is an estimate.
type tollOut struct {
	Km       float64 `json:"km"`       // length driven on toll roads
	Rm       float64 `json:"rm"`       // estimated total for a class 1 car (RM)
	Estimate bool    `json:"estimate"` // always true until we have real plaza-to-plaza rates
}

// Rough class 1 (car) cost per km on closed-system expressways such as PLUS.
// Calibrated on one published fare, Damansara to Juru RM35.26 over about 320 km
// (Motorist.my 2026 table, not verified against PLUS), giving ~11 sen/km; another
// source quotes 13.6 sen/km. Urban expressways charge flat amounts per plaza
// instead, so tollMinRm keeps short toll stretches realistic. Override with
// TOLL_RM_PER_KM / TOLL_MIN_RM when real rates are known.
var (
	tollRmPerKm = envFloat("TOLL_RM_PER_KM", 0.11)
	tollMinRm   = envFloat("TOLL_MIN_RM", 1.0)
)

func envFloat(name string, def float64) float64 {
	if v, err := strconv.ParseFloat(os.Getenv(name), 64); err == nil && v >= 0 {
		return v
	}
	return def
}

// tollFor returns nil when the route uses no toll road (under 100 m is noise).
func tollFor(km float64) *tollOut {
	if km < 0.1 {
		return nil
	}
	rm := math.Max(tollMinRm, km*tollRmPerKm)
	return &tollOut{
		Km:       math.Round(km*10) / 10,
		Rm:       math.Round(rm*10) / 10, // nearest 10 sen
		Estimate: true,
	}
}
