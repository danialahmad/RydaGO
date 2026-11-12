# Architecture

**English** · [Bahasa Melayu](../ms/ARCHITECTURE.md)

An overview, so you know **where** to change something before you open the code.

## The big picture

```
   Phone / Chrome
        |
        |  http://<PC>:8080            (web: Flutter served by nginx)
        v
   +---------+      http://<PC>:8081      +-----------+
   |  Flutter | ------------------------> |  API (Go) |
   |  app     |   /auth /reports          |  chi      |
   +---------+   /route  /places          +-----+-----+
        |                                    |   |   |
        | map tiles (straight to internet)   |   |   +--> Nominatim :8080  (address search)
        v                                    |   +------> Valhalla  :8002  (routes, turns)
   tiles.openfreemap.org                     +----------> PostgreSQL + PostGIS (users, reports)
```

All services are run by **one** `docker-compose.yml` at the repo root.
The only things the app reaches directly on the internet are the **map tiles** (OpenFreeMap) and the
MapLibre GL JS script (loaded from `unpkg.com` by the web plugin).

| Service | Image / code | Port (host) | Purpose |
|---|---|---|---|
| `web` | `docker/web.Dockerfile` (Flutter build, nginx) | 8080 | Web app |
| `api` | `backend/` (Go 1.26) | 8081 | The app's only way in to data |
| `db` | `postgis/postgis:16-3.5` | 5432 (loopback) | Users and reports |
| `valhalla` | `gis-ops/docker-valhalla:3.5.1` | 8002 (loopback) | Routes and turn-by-turn directions |
| `nominatim` | `mediagis/nominatim:5.1` | 8088 (loopback) | Address search |

The app does **not** talk to Valhalla or Nominatim directly. Everything goes through the API, so the
response format is our own and stable (and we can swap engines later without touching the app).

## Backend (`backend/`)

One Go package (`package main`), with no extra layers because it is still small.

| File | Contents |
|---|---|
| `main.go` | chi router, goose migrations at startup, `/health`, `/reports`, report type and subtype table, CORS |
| `auth.go` | Register, log in (bcrypt), 7-day HS256 JWT, `requireAuth` middleware |
| `route.go` | `/route`: three parallel Valhalla calls, polyline6 decoding, speed limits (`traceLimits`), dropping duplicates |
| `lang.go` | Turn instructions in English or Malay (`maneuverText`) |
| `signs.go` | Exit signs (`exit`, `toward`) and lanes from Valhalla |
| `toll.go` | Toll price estimate (`TOLL_RM_PER_KM`, `TOLL_MIN_RM`) |
| `votes.go` | `/reports/{id}/vote`: "Still there?" |
| `accounts.go` | Delete your own report, delete account (`DELETE /me`) |
| `shares.go` | Live trip sharing: `/shares` and the `/s/{token}` page |
| `ratelimit.go` | Token-bucket rate limits, in memory |
| `places.go` | `/places`: proxy to Nominatim, trims the response |
| `migrations/` | goose SQL, embedded in the binary (`//go:embed`). Runs automatically when the API starts |
| `*_test.go` | Unit tests. Valhalla and Nominatim are replaced by fake `httptest` servers |
| `integration_test.go` | Tests against a real PostgreSQL; skipped without `TEST_DATABASE_URL` |

Database schema (result of `migrations/`):

```
users   (id, email UNIQUE, password_hash, created_at)
reports (id, type, subtype NULL, geom GEOGRAPHY(Point,4326), user_id -> users, created_at)
         GIST index on geom, index on created_at
report_votes (report_id, user_id, vote +1/-1, PRIMARY KEY (report_id, user_id))
shares (token PK, user_id, dest_*, lat/lng, eta_at, updated_at, ended_at)  -- live trip sharing
```

Reports are read with `ST_DWithin`. A report is valid while its age (since it was created or last upvoted) is
< 2 hours, and is hidden when `downvotes - upvotes >= 3`. Vote totals are computed with a `CROSS JOIN LATERAL` in
`nearbyReports`. Speed limits come from `traceLimits` in `route.go` (Valhalla `/trace_attributes`, `edge_walk`).
There is no cleanup job: old rows stay in the table, they are just not returned.

Key decisions:

- **Turn instructions are built in the API** (`maneuverText` in `lang.go`) in English or Malay according to `?lang=`,
  because Valhalla does not support Malay. Voice and banner use the same text. All other app text lives in `lib/app/strings.dart`.
- **Three routes = three Valhalla calls** (`routeVariants`): default (with 2 `alternates`), `use_tolls: 0`,
  `shortest: true`. Duplicates are dropped, and Valhalla's alternates fill empty slots up to 3 routes.
  If one call fails, the others are still returned.
- **JWT**: `JWT_SECRET` is required and must be 32+ characters, otherwise the API refuses to start.
  Login returns the same message for "email does not exist" and "wrong password", and runs a dummy bcrypt
  so the response time does not leak which emails exist.

## Flutter app (`lib/`)

```
lib/
  main.dart                  entry point: ProviderScope + MaterialApp + theme
  app/
    config.dart              API address, map style, fallback location (KLCC)
    strings.dart             S: all UI text, English and Malay
    theme.dart               colours (AppColors) and light/dark ThemeData
    format.dart              formatDistance / formatDuration / formatClock
  models/                    pure data, no Flutter widgets (except IconData)
    geo.dart                 haversineM, routeCumulative, navZoom
    place.dart               Place, icon by Nominatim category
    report.dart              ReportType (+ subtypes), Report
    route.dart               RouteOption, Maneuver
    route_summary.dart       reports along a route (summary before Start, estimated delay)
    user_loc.dart            UserLoc (fix, speed, heading, accuracy)
  services/
    api.dart                 ALL HTTP calls to our API
    map_style.dart           tweaks the OpenFreeMap style: flat map, thick roads, no 3D buildings
    voice.dart               Speaker (TTS) and VoicePlanner (when to speak)
  state/                     Riverpod: app logic and state
    user_loc.dart            GPS (geolocator) + fix injection for demo mode
    auth.dart                token stored in shared_preferences
    settings.dart            theme, voice, avoid tolls/highways, speed alert
    saved_places.dart        Home, Work, favourites, recents
    trip.dart                destination, routes, route choice, pin, "navigating"
    reports.dart             load nearby reports (every 15 s) and send reports
    navigation.dart          NavNotifier: GPS fixes into progress, arrival, re-routing
    alternatives.dart        faster-route suggestions while driving, list of other routes
    share.dart               live trip sharing (updated every 10 s)
    demo.dart                demo mode: DemoDriver sends fake fixes
    voice.dart               connects navigation to voice
  ui/
    screens/                 map_screen, search_screen, settings_screen, login_screen
    map/                     map_view (MapLibre + layers), marker_images (marker icons)
    widgets/                 bottom panels, route preview, banner, reports, alternatives, buttons
```

Layering rule: `models` imports nothing from `state` or `ui`; `state` does not import `ui`;
`ui` may import everything. If you find yourself breaking this, something is in the wrong place.

### State flow (Riverpod)

```
userLocProvider  (GPS or demo)
      |
      +--> navProvider (NavNotifier) ----> navigatingProvider / banner / bottom bar / voice
      |         ^ started by startNavigation(): the chosen route from routesProvider
      +--> reportsProvider (reloads the surrounding area)
      +--> routesProvider (routes from the current position to the destination)

destinationProvider --> routesProvider --> routeIndexProvider --> RoutePreviewPanel
pinProvider (long press) --> PinPanel; also the location of the next report
MapView listens to all of it and redraws the map layers.
```

The panel at the bottom of `MapScreen` is decided by state, with no `Navigator`:
navigating → `NavBottomBar`; has a destination → `RoutePreviewPanel`; has a pin → `PinPanel`; otherwise → `HomePanel`.
The Back button (Android) goes back one level (`PopScope` in `map_screen.dart`).

### Navigation (`state/navigation.dart`), the most delicate part

Navigation reacts **only** to GPS fixes (`userLocProvider`). There is no timer or simulation inside it.

1. Each fix is projected onto the route line (nearest segment, searching near the current segment first so that
   routes that cross themselves do not make progress jump). Result: `alongM` (metres from the start), distance from
   the line, snapped point.
2. Within 50 m of the line: the blue dot is snapped to the route. Further away: shown where it really is.
3. **Arrival**: ≤ 30 m remaining and on the route, or within 30 m of the destination.
4. **Off route**: distance > 120 m (immediately) or 3 fixes in a row > 50 m, and at least 8 seconds since
   navigation started or the last re-route → ask for a new route from the current position, re-selecting the **same kind**.
5. Fixes with accuracy > 100 m are ignored.
6. Next turn = the first maneuver with `cum[index] >= alongM`.

Demo mode (`state/demo.dart`) drives all of this by **injecting fake fixes** into `UserLocNotifier`
along the route, so the logic above is exercised without driving. `NavNotifier` does not know it is a demo.

### Map (`ui/map/map_view.dart`)

- One `MapLibreMap` widget. All layers (route line, report symbols, user dot) are drawn by `_draw`,
  which is called again when state changes. `_sync` serialises the calls so they do not overlap.
- Marker icons are rendered to PNG at app start (`marker_images.dart`) from Material icons, not image files.
  If that fails, it falls back to coloured circles.
- Switch light/dark with `controller.setStyle()`, **not** by changing the widget's `styleString`, because the
  plugin resets other options (attribution) when `styleString` changes.
- The camera fit for a route is computed by hand (`_fitDestination`), because `newLatLngBounds` + padding
  behaves differently on web.

## What is stored where

| Data | Location |
|---|---|
| Users, reports, votes, shares | PostgreSQL (Docker volume `pgdata`) |
| Valhalla OSM data and routing tiles | `./data/valhalla` (git-ignored) |
| Nominatim database | Docker volume `nominatim-data` |
| Login token, settings, Home/Work/favourites/recents | `shared_preferences` on the device (localStorage on web) |

## Known limits and technical debt

- **CORS is open to `*`** (`cors` in `main.go`). Tighten before deploying.
- The dev values in compose (`wazedev`, dev JWT) are **public**. Set real values in `.env`.
- Rate limiting is in memory (`ratelimit.go`): it resets when the API restarts and is not shared between instances.
- The real-database tests (`integration_test.go`) only run when `TEST_DATABASE_URL` is set, so a plain
  `go test` skips them (see `docs/en/DEVELOPMENT.md`).
- No Flutter widget/screen tests, only logic tests.
- `web/index.html` has a small script that collapses the map credits at startup. It depends on MapLibre CSS class
  names and may need updating when the plugin is upgraded.
- The map plugin loads MapLibre GL JS from `unpkg.com` at runtime: needs internet.
