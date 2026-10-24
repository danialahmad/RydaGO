package main

import (
	"net/http"
	"strconv"
)

// Languages the API can write instructions in. English is the default; the app
// sends lang=ms when the user picks Malay.
const (
	langEN = "en"
	langMS = "ms"
)

func langFrom(r *http.Request) string {
	if r.URL.Query().Get("lang") == langMS {
		return langMS
	}
	return langEN
}

// maneuverPhrases are the phrases for Valhalla's maneuver types
// (https://valhalla.github.io/valhalla/api/turn-by-turn/api-reference/).
var maneuverPhrases = map[string]map[int]string{
	langMS: {
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
	},
	langEN: {
		1: "Start your trip", 2: "Start your trip", 3: "Start your trip",
		4: "You have arrived", 5: "You have arrived, on the right",
		6: "You have arrived, on the left",
		7: "Continue", 8: "Continue",
		9: "Bear right", 10: "Turn right", 11: "Turn sharp right",
		12: "Make a U-turn to the right", 13: "Make a U-turn to the left",
		14: "Turn sharp left", 15: "Turn left", 16: "Bear left",
		17: "Continue onto the ramp", 18: "Take the ramp on the right", 19: "Take the ramp on the left",
		20: "Take the exit on the right", 21: "Take the exit on the left",
		22: "Keep straight", 23: "Keep right", 24: "Keep left",
		25: "Merge onto the highway",
		26: "Enter the roundabout", 27: "Exit the roundabout",
	},
}

// maneuverText builds the instruction shown in the app, e.g. "Turn right onto
// Jalan Ampang" / "Belok kanan menuju Jalan Ampang".
func maneuverText(lang string, typ int, streets []string, roundaboutExit int) string {
	if lang != langMS {
		lang = langEN
	}
	phrase, ok := maneuverPhrases[lang][typ]
	if !ok {
		phrase = maneuverPhrases[lang][7]
	}
	if typ == 26 && roundaboutExit > 0 {
		if lang == langMS {
			phrase += ", ambil simpang ke-" + strconv.Itoa(roundaboutExit)
		} else {
			phrase += ", take exit " + strconv.Itoa(roundaboutExit)
		}
	}
	if typ >= 4 && typ <= 6 || len(streets) == 0 {
		return phrase
	}
	switch typ {
	case 1, 2, 3, 7, 8:
		if lang == langMS {
			return phrase + " di " + streets[0]
		}
		return phrase + " on " + streets[0]
	}
	if lang == langMS {
		return phrase + " menuju " + streets[0]
	}
	if typ >= 17 && typ <= 25 { // ramps, exits, lane keeps, merges already say "onto/on the"
		return phrase + " toward " + streets[0]
	}
	return phrase + " onto " + streets[0]
}
