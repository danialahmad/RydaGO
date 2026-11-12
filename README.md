# RydaGO

**English** · [Bahasa Melayu](README.ms.md)

A community navigation app for Malaysia, built on open data and fully self-hosted.

- **Navigation** with turn-by-turn directions, three route options, speed limits, speeding alerts and estimated toll prices
- **Community reports**: police, traffic jams, accidents, hazards, cameras and road closures, with "Still there?" confirmation
- **Two languages**: English (default) and Bahasa Melayu, including voice guidance
- **No API keys or third-party accounts**: maps from [OpenStreetMap](https://www.openstreetmap.org), routing by [Valhalla](https://github.com/valhalla/valhalla), search by [Nominatim](https://nominatim.org)

## Stack

| Layer | Technology |
|---|---|
| App (web and Android) | [Flutter](https://flutter.dev) 3.47 / Dart, [Riverpod](https://riverpod.dev) 3 (state), `maplibre_gl` (map), `geolocator` (GPS), `flutter_tts` (voice), `shared_preferences` |
| Map | [MapLibre](https://maplibre.org) with [OpenFreeMap](https://openfreemap.org) vector tiles (OpenStreetMap data) |
| API | [Go](https://go.dev) 1.26, `chi` router, `pgx`, `goose` migrations, JWT + bcrypt auth |
| Database | PostgreSQL 16 + [PostGIS](https://postgis.net) 3.5 (reports, votes, users) |
| Routing, directions, speed limits, tolls | [Valhalla](https://github.com/valhalla/valhalla) 3.5.1, with Malaysia/Singapore/Brunei OSM data from Geofabrik |
| Address search | [Nominatim](https://nominatim.org) 5.1 |
| Web server | nginx 1.27 (serves the web app) |
| Packaging | Docker Compose: `db`, `valhalla`, `nominatim`, `api`, `web` |

```
Flutter app --> nginx :8080 (web)
     |
     +--------> Go API :8081 --> PostGIS   (reports, votes, accounts)
                    |---------> Valhalla  (routes, speed limits, tolls)
                    '---------> Nominatim (address search)
```

## Getting started (Docker only)

You do **not** need Flutter, Go or a database installed. You need [Docker Desktop](https://www.docker.com/products/docker-desktop/)
with **8 GB of RAM** allocated to Docker and about 10 GB of free disk space.

```bash
git clone https://github.com/Shahrizwansohimi/RydaGO.git
cd RydaGO
docker compose up -d --build
```

Then open **http://localhost:8080**.

### First run

`--build` builds the web app and the API (~5 minutes). After that, the Malaysia map data is downloaded and
processed in the background:

| Service | Purpose | First-run time |
|---|---|---|
| `valhalla` | routes, directions, speed limits, tolls | ~25 minutes |
| `nominatim` | address search | ~70 minutes |

The app is usable straight away (map, accounts and reports work). Search and routing show a "server may still be
starting" message until both services are `healthy`:

```bash
docker compose ps                            # wait for valhalla and nominatim to be (healthy)
docker compose logs -f valhalla nominatim    # progress
```

Later starts take a few seconds. Data persists in `./data` and in Docker volumes.

## Trying it out

1. **Menu** (top left) > Settings > **Language** switches between English and Bahasa Melayu.
2. Settings > **Demo driving mode** uses a fake location, so you can try navigation without driving or GPS.
3. Tap **Where to?**, search for e.g. "Batu Caves", pick a route (each card shows its toll price), and tap **Start**.
4. Tap the orange button to **report** something (an account is required: Settings > Sign in > Register).
   When you pass someone else's report, the app asks whether it is still there.
5. While driving, expand the bottom bar for Share ETA, Mute and End. In demo mode a **Detour** button
   shows off re-routing.

Long-press the map (on web: double-click) to drop a pin, then choose Go or Report there.

> **Toll prices are estimates** (class 1 car, roughly 11 sen/km), not official rates. **Speed limits** only appear
> on roads where OpenStreetMap has the data (about a third of them).

### From a phone (same Wi-Fi)

See [`docs/en/DEVELOPMENT.md`](docs/en/DEVELOPMENT.md) ("Access from a phone on the same Wi-Fi"): set `BIND_ADDR=0.0.0.0` in `.env`, open the ports in your
firewall, and browse to `http://<pc-ip>:8080`. Real GPS needs HTTPS, so use demo mode on the phone.

## Documentation

Every doc exists in English (`docs/en/`) and Bahasa Melayu (`docs/ms/`) with the same content.

| File | Read it when |
|---|---|
| FEATURES ([en](docs/en/FEATURES.md) · [ms](docs/ms/FEATURES.md)) | You want the feature list and what is done or missing |
| ROADMAP ([en](docs/en/ROADMAP.md) · [ms](docs/ms/ROADMAP.md)) | You want to know what to build next, by priority |
| ARCHITECTURE ([en](docs/en/ARCHITECTURE.md) · [ms](docs/ms/ARCHITECTURE.md)) | You want to know how it fits together and where code lives |
| DEVELOPMENT ([en](docs/en/DEVELOPMENT.md) · [ms](docs/ms/DEVELOPMENT.md)) | Day-to-day workflow, recipes, pitfalls |
| API ([en](docs/en/API.md) · [ms](docs/ms/API.md)) | API endpoint reference |
| DESIGN ([en](docs/en/DESIGN.md) · [ms](docs/ms/DESIGN.md)) | UI principles, colours, branding |
| [`CLAUDE.md`](CLAUDE.md) | Short instructions for AI assistants (Claude Code) |

## Repository layout

```
lib/                  Flutter app (models, services, state, ui; UI text in lib/app/strings.dart)
test/                 Flutter tests
backend/              Go API, database migrations, tests
docker/               web Dockerfile and nginx config
docker-compose.yml    all services
docs/en/, docs/ms/    documentation in English and Bahasa Melayu
data/                 (git-ignored) OSM data and Valhalla tiles
.env.example          configuration options (all have defaults)
```

## Tests

```bash
flutter analyze && flutter test       # needs Flutter installed (see docs/en/DEVELOPMENT.md)
cd backend && docker run --rm -v "$PWD:/src" -w /src golang:1.26-alpine go test ./...
```

For the real-database tests, see [`docs/en/DEVELOPMENT.md`](docs/en/DEVELOPMENT.md).

## Troubleshooting

| Symptom | Cause and fix |
|---|---|
| "port is already allocated" on 8080/8081 | Another program uses that port. Change `WEB_PORT` in `.env`, or stop that program |
| Search/routing: "server may still be starting" | Data is not ready yet. Run `docker compose ps` and wait for `healthy` |
| Build fails with out-of-memory | Give Docker 8 GB of RAM (Docker Desktop > Settings > Resources) |
| Nominatim stops by itself during import | Usually not enough RAM. Check `docker compose logs nominatim` |
| Want to start from scratch | `docker compose down -v` and `rm -rf data` (re-import takes ~1.5 hours) |
| Phone cannot open the app | Firewall or `BIND_ADDR`. See `docs/en/DEVELOPMENT.md` |

The Docker project name stays `waze-revamp` (see `name:` in `docker-compose.yml`) so existing data volumes are
not lost. It is only an internal name.

## License and credits

Map data © OpenStreetMap contributors (ODbL), served by OpenFreeMap. Routing by Valhalla, search by Nominatim.
An independent project, not affiliated with Waze or Google. *(There is no LICENSE file yet: decide before sharing.)*
