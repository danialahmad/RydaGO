package main

import (
	"encoding/json"
	"reflect"
	"testing"
)

func TestSignHelpers(t *testing.T) {
	toward := []signElement{{"Gombak"}, {" "}, {"Batu Caves"}, {"Ulu Yam"}}
	if got := joinText(toward, 2); got != "Gombak / Batu Caves" {
		t.Errorf("joinText = %q", got)
	}
	if got := firstText([]signElement{{" 3310A "}}); got != "3310A" {
		t.Errorf("firstText = %q", got)
	}
	if firstText(nil) != "" || joinText(nil, 2) != "" {
		t.Error("empty sign should give empty text")
	}
}

func TestLanesOut(t *testing.T) {
	if lanesOut(nil) != nil {
		t.Error("no lane data should give nil, so the JSON field is omitted")
	}
	got := lanesOut([]valhallaLane{
		{Directions: "left|straight", Valid: true, Active: true},
		{Directions: "right"},
	})
	want := []laneOut{{Dirs: []string{"left", "straight"}, Valid: true, Active: true}, {Dirs: []string{"right"}}}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("lanes = %+v", got)
	}
}

func TestManeuverJSONOmitsEmptySignFields(t *testing.T) {
	b, _ := json.Marshal(maneuverOut{Text: "x", Type: 10})
	if s := string(b); s != `{"text":"x","type":10,"km":0,"index":0}` {
		t.Errorf("json = %s", s)
	}
}
