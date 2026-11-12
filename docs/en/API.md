# API reference

**English** · [Bahasa Melayu](../ms/API.md)

Base: `http://localhost:8081` (or `http://<pc-ip>:8081`). All responses are JSON.
Errors look like `{"error": "message"}`.

Source: `backend/main.go`, `auth.go`, `route.go`, `places.go`. Tests: `backend/*_test.go`.

## Summary

| Method | Path | Login? | Purpose |
|---|---|---|---|
| GET | `/health` | no | Check the API and database |
| POST | `/auth/register` | no | Create an account, get a token straight away |
| POST | `/auth/login` | no | Log in |
| GET | `/reports` | no (token optional) | Nearby reports that are still valid |
| POST | `/reports` | **yes** | Send a report |
| POST | `/reports/{id}/vote` | **yes** | "Still there?": vote up or down |
| DELETE | `/reports/{id}` | **yes** | Delete your own report |
| DELETE | `/me` | **yes** | Delete account (password required) |
| POST | `/shares` | **yes** | Start live trip sharing |
| PUT | `/shares/{token}` | **yes** | Update position and ETA |
| DELETE | `/shares/{token}` | **yes** | End sharing |
| GET | `/shares/{token}` | no | Read a shared trip (anyone with the link) |
| GET | `/s/{token}` | no | Web page for friends who open the link |
| GET | `/route` | no | Three route options with turn instructions, speed limits and tolls (`?lang=en|ms`) |
| GET | `/places` | no | Address or place search |

Authentication: `Authorization: Bearer <token>`. Tokens are valid for 7 days.

**Rate limits** (in memory, per API instance; `429` with `Retry-After`): `/auth/*` and `DELETE /me` 10 per minute per IP; `POST /reports` 6 per minute with a burst of 5 per user; votes 60 per minute; `/shares` 60 per minute per user; `GET /shares/{token}` 120 per minute per IP. `X-Forwarded-For` is deliberately ignored.

## `GET /health`

`200 {"status":"ok"}`. `503 {"status":"db down"}` if the database cannot be reached.

## `POST /auth/register`, `POST /auth/login`

Body: `{"email": "a@b.my", "password": "an-8-char-password"}`

- Email is normalised to lower case.
- Password: 8 to 72 characters (bcrypt limit).
- Success: `201` (register) or `200` (login) with `{"token": "...", "email": "a@b.my"}`.
- Errors: `400` (bad JSON, email or password), `409` (email already registered), `401` (wrong email or password. Same message for both).

## `GET /reports?lat=&lng=&radius=`

- `lat`, `lng`: required. `radius`: metres, default 5000, maximum 50000.
- A report stays valid for **2 hours** from creation, or from its latest upvote (an upvote extends its life).
- Hidden when downvotes exceed upvotes by at least **3** (`down - up >= 3`).
- Newest first, **at most 100**.
- If a valid `Authorization: Bearer` is sent, `mine` shows that user's own reports. An invalid token is ignored (not 401).

```json
[
  {"id": 16, "type": "jam", "subtype": "standstill", "lat": 3.2359, "lng": 101.6989,
   "created_at": "2026-10-24T02:25:11Z", "up": 2, "down": 0, "mine": false}
]
```

`subtype` is absent from the response if the reporter gave no detail. `400` if `lat`/`lng` is missing.

## `POST /reports/{id}/vote` (login)

Body: `{"vote": "up"}` (still there) or `{"vote": "down"}` (gone). One vote per user per report;
voting again replaces the existing vote. `200 {"up": 3, "down": 1}` (current totals).
`400` invalid id or vote value, `401` no token, `403` your own report, `404` report does not exist.

## `POST /reports` (login)

```json
{"type": "police", "subtype": "hidden", "lat": 3.1579, "lng": 101.7116}
```

`subtype` is optional. `201` with the stored report (same shape as above).
`400` if the type or subtype is invalid, the coordinates are out of range, or the body is over 16 KB. `401` if the token is missing or invalid.
`409` if the same user already reported the same type within 100 m in the last 10 minutes (duplicate). `429` if too fast.

## `DELETE /reports/{id}` (login)

Owner only. `204`; `403` not your report; `404` not found; `400` invalid id. Votes on that report are deleted too.

## `DELETE /me` (login)

Body: `{"password": "..."}` (checked again). Deletes the user, all their reports and their votes. `204`; `403` wrong password; `401` invalid token.

## Live trip sharing

`POST /shares` with body `{"dest_name", "dest_lat", "dest_lng", "lat", "lng", "eta_minutes"}` returns `201 {"token", "path": "/s/<token>"}`. The token is 128 random bits. The app sends `PUT /shares/{token}` (same body) every ~10 s while driving and `DELETE` on arrival or when stopping. `GET /shares/{token}` (no login) returns `{dest_name, dest_lat, dest_lng, lat, lng, eta_at, updated_at, ended, stale}`; `stale` means no update for 2 minutes. Links expire 8 hours after creation (`404`). A `PUT` after it ends gives `410`. The `/s/{token}` page refreshes itself every 10 s and loads nothing from other sites.

### Report types and subtypes

The first subtype is the default the app sends. **This table must match** `reportSubtypes` in
`backend/main.go`, `ReportType` in `lib/models/report.dart` and the table in `docs/ms/API.md`. Tests on both sides fail if the code differs.

| `type` | Label in the app | Allowed `subtype` |
|---|---|---|
| `police` | Police | `visible`, `hidden`, `other_side` |
| `accident` | Accident | `minor`, `major`, `other_side` |
| `jam` | Traffic jam | `moderate`, `heavy`, `standstill` |
| `hazard` | Hazard | `object`, `pothole`, `stopped_vehicle`, `construction`, `broken_light`, `weather` |
| `camera` | Camera | `speed`, `red_light` |
| `closed` | Road closed | `road`, `lane` |

## `GET /route?from=lat,lng&to=lat,lng&lang=en&avoid=highways`

`avoid`: comma-separated list, `highways` and/or `ferries` (anything else is ignored). Up to **3** distinct routes are returned: the named options (`fastest`, `notoll`, `shortest`) first, then real alternative routes from Valhalla (`id` `alt1`, `alt2`, label "Alternative"/"Alternatif") to fill the slots. An option identical to an earlier one (same length, time and main road) is dropped.

`lang`: `en` (default) or `ms`. Sets the language of `label`, `note` and `text`. API error messages are always English; the app translates by status.

Asks Valhalla three times in parallel. Returns only the ones that succeed.

```jsonc
[
  {
    "id": "fastest",             // stable across languages: "fastest", "notoll", "shortest"
    "label": "Fastest",          // translated (ms: "Terpantas", "Tanpa tol", "Jarak terpendek")
    "note": "Fastest route",
    "via": "E12",                  // longest road on the route, may be absent
    "minutes": 6,
    "km": 4.9,
    "points": [[3.1579, 101.7116], [3.1580, 101.7120]],       // [lat, lng]
    "maneuvers": [
      {"text": "Start your trip on Lorong Kuda", "street": "Lorong Kuda",
       "type": 1, "km": 0.39, "index": 0},
      {"text": "You have arrived", "type": 4, "km": 0, "index": 164}
    ],
    "limits": [{"from": 0, "to": 40, "kmh": 60}]   // speed limits; only where OSM knows them
    ,"toll": {"km": 12.4, "rm": 1.4, "estimate": true}  // absent if the route uses no toll road
  }
]
```

- `maneuvers[]` may have `exit` (exit number on the sign, e.g. `"3310A"`), `toward` (destination on the sign, e.g. `"Gombak / Batu Caves"`) and `lanes[]` (`{dirs, valid, active}`; only where OSM has lane data, rare in Malaysia). All are absent when unknown.
- `limits[]`: speed limit in km/h for the segment `points[from]` to `points[to]`. Derived from Valhalla
  `trace_attributes`. Only about a third of roads in Malaysia have `maxspeed` in OSM, so the list
  may be short or empty. The app carries the last limit forward 400 m, then hides the sign.
- `toll`: length of toll road (Valhalla marks toll roads from OSM) and an **estimated** price for a class 1 car:
  `km × TOLL_RM_PER_KM` (default RM0.11, calibrated against one published PLUS rate, not official), minimum
  `TOLL_MIN_RM` (RM1.00). Both can be changed through API environment variables. The "No tolls" option only *avoids*
  tolls where it can, so it may still have tolls; `toll` shows the truth.
- `maneuvers[].index` is the index in `points` where the step starts.
- `type` is the [Valhalla maneuver type](https://valhalla.github.io/valhalla/api/turn-by-turn/api-reference/):
  1-3 start, 4-6 arrive, 9-16 turn, 17-24 ramp/exit/lane, 25 merge, 26-27 roundabout.
  The app maps them to icons in `maneuverIcon` (`lib/ui/widgets/nav_overlay.dart`).
- `text` is built in the API in the `lang` language (`maneuverText` in `lang.go`). `street` is the street name only.
- Errors: `400` if `from`/`to` is not a valid `lat,lng`; `502` if every Valhalla call fails (e.g. tiles still building).
- Times are Valhalla estimates **without live traffic**.

## `GET /places?q=&lat=&lng=`

- `q`: 2 to 200 characters. `lat`, `lng` optional; if given, nearby results are preferred (not restricted).
- Limited to Malaysia, Singapore and Brunei; Malay names preferred; at most 8 results.

```json
[{"name": "Batu Caves", "area": "Majlis Perbandaran Selayang, Selangor",
  "lat": 3.2369, "lng": 101.6833, "category": "place", "type": "town"}]
```

`category` and `type` are Nominatim values (used to pick an icon: `iconForCategory` in
`lib/models/place.dart`). `400` if `q` is too short or long; `502` if Nominatim is not ready.

> Nominatim is imported with the `address` style by default, so **places such as mosques and shopping malls
> are missing** (only roads, areas, addresses). See `docs/en/FEATURES.md`.

## curl examples

```bash
curl localhost:8081/health
curl "localhost:8081/route?from=3.1579,101.7116&to=3.1602,101.7274"
curl "localhost:8081/places?q=batu%20caves"
# register, keep the token, send a report
TOKEN=$(curl -s -X POST localhost:8081/auth/register -H 'Content-Type: application/json' \
  -d '{"email":"me@example.my","password":"password-8"}' | sed 's/.*"token":"\([^"]*\)".*/\1/')
curl -X POST localhost:8081/reports -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"type":"jam","subtype":"heavy","lat":3.1579,"lng":101.7116}'
```
