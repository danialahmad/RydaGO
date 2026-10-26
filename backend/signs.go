package main

import "strings"

// laneOut is one lane at a maneuver: which ways it leads, and whether to use it.
type laneOut struct {
	Dirs   []string `json:"dirs"`   // left, slight_left, straight, slight_right, right, ...
	Valid  bool     `json:"valid"`  // this lane can make the maneuver
	Active bool     `json:"active"` // the best lane to be in
}

// signElement is one line of text on a road sign, as Valhalla reports it.
type signElement struct {
	Text string `json:"text"`
}

// valhallaLane is a lane as Valhalla reports it (directions joined with "|").
type valhallaLane struct {
	Directions string `json:"directions"`
	Valid      bool   `json:"valid"`
	Active     bool   `json:"active"`
}

func firstText(els []signElement) string {
	if len(els) == 0 {
		return ""
	}
	return strings.TrimSpace(els[0].Text)
}

// joinText joins up to max sign lines: "Gombak / Batu Caves".
func joinText(els []signElement, max int) string {
	var parts []string
	for _, e := range els {
		if t := strings.TrimSpace(e.Text); t != "" {
			parts = append(parts, t)
		}
		if len(parts) == max {
			break
		}
	}
	return strings.Join(parts, " / ")
}

// lanesOut converts Valhalla lanes, or returns nil when the road has none mapped.
func lanesOut(in []valhallaLane) []laneOut {
	if len(in) == 0 {
		return nil
	}
	out := make([]laneOut, 0, len(in))
	for _, l := range in {
		out = append(out, laneOut{Dirs: strings.Split(l.Directions, "|"), Valid: l.Valid, Active: l.Active})
	}
	return out
}
