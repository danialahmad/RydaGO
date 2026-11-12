# Development guide

**English** · [Bahasa Melayu](../ms/DEVELOPMENT.md)

Day-to-day workflow. For how to **run** the project the first time, see [`README.md`](../../README.md).

## Two ways to run the app

| | Docker only | Fast dev (Flutter installed) |
|---|---|---|
| What to install | Docker | Docker + Flutter 3.47.x |
| Command | `docker compose up -d --build` | `docker compose up -d db valhalla nominatim api` then `flutter run -d chrome` |
| Change UI code, see the result | rebuild the web image (~3 min) | hot reload (seconds) |
| Good for | looking and using | developing |

In dev mode, the app (at `localhost:<random-port>`) calls the API at `localhost:8081`: the API address is taken
from the page's host (`lib/app/config.dart`). For an API elsewhere: `--dart-define=API_URL=http://...`.

### Installing Flutter

Follow [docs.flutter.dev/get-started/install](https://docs.flutter.dev/get-started/install).
Version used by the project: **3.47.7** (stable); same as `FLUTTER_VERSION` in `docker/web.Dockerfile`.
Then `flutter pub get`. Android Studio is **not** needed for web.

## Common commands

```bash
flutter analyze                     # must say "No issues found"
flutter test                        # app logic tests
flutter run -d chrome               # app with hot reload

# Backend: Go does not need to be installed. Run it in Docker:
cd backend
docker run --rm -v "$PWD:/src" -w /src golang:1.26-alpine sh -c "gofmt -l . && go vet ./... && go test ./..."

# Real-database tests (votes, expiry). Start `docker compose up -d db`, then from PowerShell:
docker run --rm --network waze-revamp_default -v "${PWD}:/src" -w /src -e TEST_DATABASE_URL="postgres://waze:wazedev@db:5432/postgres?sslmode=disable" golang:1.26-alpine go test ./...
# Without TEST_DATABASE_URL these tests are skipped.

docker compose logs -f api          # API logs
docker compose logs -f valhalla nominatim
docker compose ps                   # look for "healthy"
docker compose up -d --build api    # after changing Go code
docker compose up -d --build web    # after changing Flutter code (Docker-only mode)
docker compose down                 # stop (data is kept)
```

On Windows PowerShell use `${PWD}` instead of `$PWD`. In Git Bash, watch out for path conversion
(`-w /src` can be mangled; run Docker commands from PowerShell).

## Data and its lifecycle

On the first `docker compose up`, **valhalla** and **nominatim** each download the Malaysia/Singapore/Brunei
OSM file (~240 MB) and build their data. The app works straight away (map, login, reports), but `/route` and
`/places` return `502` until `docker compose ps` shows `healthy`.

| | Rough time | Disk |
|---|---|---|
| Valhalla | ~25 minutes | ~1.6 GB in `./data/valhalla` |
| Nominatim (`address`) | ~70 minutes | ~3 GB in volume `nominatim-data` |

Requirements: Docker given **8 GB RAM** and ~10 GB free space.

Resetting things:

```bash
docker compose down -v      # DELETES all volumes: users, reports, Nominatim data. Re-import ~70 min
rm -rf data/valhalla        # delete Valhalla tiles (rebuilt on next start, ~25 min)
```

Switching to Nominatim `full` (with POIs): set `NOMINATIM_IMPORT_STYLE=full` in `.env`, then
`docker compose down` and `docker volume rm waze-revamp_nominatim-data`, then `up -d`. (Only applies to a new volume.)

## Access from a phone on the same Wi-Fi

1. In `.env`: `BIND_ADDR=0.0.0.0` then `docker compose up -d`.
2. Open the ports in Windows Firewall (PowerShell as **Administrator**), limited to the home network:
   ```powershell
   New-NetFirewallRule -DisplayName "RydaGO dev" -Direction Inbound -Protocol TCP -LocalPort 8080,8081 -RemoteAddress LocalSubnet -Profile Any -Action Allow
   ```
   (Remove it when done: `Remove-NetFirewallRule -DisplayName "RydaGO dev"`.)
3. Find the PC's IP (`ipconfig`), open `http://<ip>:8080` on the phone. Check `http://<ip>:8081/health` first if it does not work.
4. **Set a real `JWT_SECRET`** in `.env` when opening up to the network; the default value is public.

**Real GPS does not work over `http://192.168.x.x`**: browsers only allow location on HTTPS or `localhost`.
On the phone use **Demo mode** (Settings > Developer). For real GPS on Android Chrome:
`chrome://flags/#unsafely-treat-insecure-origin-as-secure`, add `http://<ip>:8080`, enable it, restart Chrome.
On desktop Chrome, DevTools > Sensors lets you set your own location.

## Demo mode

Settings > Developer > **Demo driving mode**. A fake location moves along the route at ~50 km/h in
real time (a sped-up speed makes the voice overlap and the camera jump) and through the same GPS channel (see
`docs/en/ARCHITECTURE.md`). While navigating, expand the bottom bar: the **Detour (demo)** button jumps the position
~270 m off the route to show re-routing. Useful for demos and for testing the navigation UI without driving.

## Recipes: adding things

### A new report type or subtype

Touch **three** places (the API doc exists in two languages; tests on both sides fail if you forget one):

1. `backend/main.go`: add to `reportSubtypes`.
2. `lib/models/report.dart`: add to the `ReportType` enum (label, icon, colour, subtypes).
3. `docs/en/API.md` and `docs/ms/API.md`: update the table in both languages.
4. Update the expected lists in `test/logic_test.dart` ("report types") and `backend/main_test.go`.

No migration needed: `type` and `subtype` are `TEXT`, validated in Go code.

### A new API endpoint

1. Write the handler in `backend/` and register it in `main()` (`r.Get(...)` or `r.With(s.requireAuth).Post(...)`).
2. Add an `httptest` test. For external dependencies, follow the `fakeValhalla` / `fakeNominatim` pattern.
3. Add a method to `lib/services/api.dart` (all HTTP calls live there and only there).
4. Document it in `docs/en/API.md` and `docs/ms/API.md`.

### Database changes

A new file `backend/migrations/0000N_name.sql` with `-- +goose Up` and `-- +goose Down`.
It runs automatically when the API restarts (`docker compose up -d --build api`). Do not edit migrations
that have already run; add a new one.

### A new UI screen or panel

Follow `docs/en/DESIGN.md`. Put widgets in `lib/ui/widgets/` (panels on the map) or `lib/ui/screens/`
(full pages). New state → `lib/state/`; do not put logic in widgets.

## Pitfalls that have cost time before

- **`pg_isready` without `-h 127.0.0.1`** passes while Postgres is still initialising, so the API starts too early.
  The healthcheck in compose is already correct; do not "simplify" it.
- **Web: "long press" is a double-click.** `onMapLongClick` in `maplibre_gl_web` is bound to `dblclick`.
  On a real phone it is a long press.
- **When a widget disappears during a tap, the browser's delayed click lands on the map underneath** (web). That is
  why the map does not use `onMapClick` for anything; only long press/double-click.
- **Changing the map widget's `styleString`** resets the plugin's other options (attribution). Use `setStyle()`.
- **Flutter plugins on Windows** (`geolocator`, `flutter_tts`, `shared_preferences`) warn about Developer Mode
  (symlinks) during `pub get`. It only matters for Windows desktop builds, which MapLibre does not support anyway.
  Ignore it for web.
- **The Flutter image in Docker** is pinned to git tag `3.47.7`. If you upgrade Flutter, also change
  `FLUTTER_VERSION` in `docker/web.Dockerfile`, or `pubspec.lock` will not be compatible.
- **The browser in the preview tool** (in the developer app) sometimes clips the view. Reload the page.

## Conventions

- Dart: `flutter analyze` clean. Small files, one responsibility each. `lib/models` stays pure.
- Go: `gofmt`, `go vet`, errors handled, no secrets in code.
- Comments explain **why**, not what. Code and comments in the same language as the existing file
  (English comments in most files; UI text in `strings.dart`: English and Malay).
- Docs exist in English (`docs/en/`) and Malay (`docs/ms/`). When you change one, update the other in the same commit.
- Small, meaningful commits. Do not commit `.env`, `data/`, `build/`.
