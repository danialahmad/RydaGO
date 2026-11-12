# Feature list: what Waze has, and where we are

**English** · [Bahasa Melayu](../ms/FEATURES.md)

This document is the main reference for "what should we build next". It is drawn from a
study of Waze's features (sources at the end), and every feature has a status in our app.

**Legend:** ✅ done · 🟡 partial / has limits · ⬜ not yet · ❌ deliberately not doing

**Priority** (column P): **1** = do first · **2** = nice to have · **3** = later / not important.
The "Needs" part of the notes column says what has to be in place (backend, data, or platform).

> On scope: Waze is a product with millions of users. We are not trying to copy all of it. Features
> that depend on **large-scale data** (live traffic, fuel prices, nationwide speed
> limits) are clearly marked so they are not mistaken for easy ones.

## 1. Map and location

| Feature | Status | P | Notes / Needs |
|---|---|---|---|
| Moving location dot with halo | ✅ | | `lib/ui/map/map_view.dart` |
| Camera follows and rotates with the direction of travel | ✅ | | Flat map (no tilt). Rotates only above 5 km/h (GPS heading is unreliable when stopped) |
| "My location" button | ✅ | | |
| Light and dark map (switches live) | ✅ | | Settings: Auto / Light / Dark. Auto follows the system, **not** sunset |
| Drop a pin with a long press (web: double-click), then "Go" or "Report" | ✅ | | |
| Traffic colours on roads (red, orange) | ⬜ | 1 | Needs aggregated driver speeds per road segment. Big backend job |
| Other drivers visible on the map | ⬜ | 3 | Privacy issue. Think first |
| Offline maps | ⬜ | 3 | |

## 2. Search and destinations

| Feature | Status | P | Notes / Needs |
|---|---|---|---|
| "Where to?" with live search (350 ms debounce) | ✅ | | `search_screen.dart` |
| Home and Work (shortcuts on the main screen) | ✅ | | Stored **on the device** only |
| Favourites (star) and Recents | ✅ | | On the device. No sync between devices yet |
| Search for places (shops, mosques, malls) | 🟡 | 1 | Nominatim imported with the `address` style: **no POIs**. Switch to `NOMINATIM_IMPORT_STYLE=full` (3x the time and disk), or add a POI source |
| Quick categories (fuel, food, parking) | ⬜ | 2 | Needs POIs first |
| Voice search | ⬜ | 3 | `speech_to_text` |
| Add a stop along the way | ⬜ | 2 | Valhalla supports multiple locations. The `/route` API needs to accept `via` |
| Share a location / destination | ⬜ | 3 | |
| "Leave later" (plan a drive, reminder when to leave) | ⬜ | 3 | Needs predictive traffic data |

## 3. Route preview

| Feature | Status | P | Notes / Needs |
|---|---|---|---|
| Several routes with time, arrival time, "+N min" compared to the fastest | ✅ | | Three kinds: Fastest, No tolls, Shortest (one Valhalla call each) |
| "Via <road>" for each route | ✅ | | Longest road on the route |
| "Avoid tolls" option | ✅ | | Settings selects the No tolls route first |
| Avoid highways | ✅ | | Settings > Avoid highways (`use_highways: 0`). Ferries are available in the API (`avoid=ferries`) but not yet in the UI |
| Toll prices | 🟡 | 2 | Estimate only (see "Toll detection" in section 6). Needs a Malaysian toll table for exact prices |
| Problems on the route (roadworks, jams) | 🟡 | 2 | Route cards show reports along the route (`models/route_summary.dart`). No real traffic data |
| Vehicle type (motorcycle, taxi, EV) | ⬜ | 2 | Valhalla has a `motorcycle` costing. Easy for motorcycles |
| Several real alternative routes (not just 3 preferences) | ✅ | | Valhalla `alternates` fill slots up to 3 routes; duplicates are dropped |

## 4. Navigation

| Feature | Status | P | Notes / Needs |
|---|---|---|---|
| Turn banner: icon, distance, street name | ✅ | | `nav_overlay.dart` |
| "Then" (a second turn close behind) | ✅ | | Only when within 500 m |
| Exit signs (exit number and "toward") | ✅ | | In the turn banner, from Valhalla data |
| Lane guidance | 🟡 | | UI and API done, but OSM rarely has lane tags in Malaysia so it is usually absent |
| Zoom by speed and distance to the turn | ✅ | | `navZoom` in `models/geo.dart` |
| Faster-route suggestion while driving (Yes / No) | 🟡 | | `state/alternatives.dart`. Checks every 45 s (30 s when stuck >1 min), suggests when it saves ≥3 min, "No" mutes it for 10 min. No live traffic: delay is estimated from jam/accident/closure reports on the route (`routeDelayMin`) and your own standstill (+5 min) |
| Tap the bottom bar: other routes from the current position | ✅ | | List with "saves X min" / "X min slower"; tap to switch. The arrow on the right opens actions (share, mute, end) |
| Flat map, thick roads, no 3D buildings | ✅ | | `services/map_style.dart` |
| Summary before Start (reports on the route) | ✅ | | Route card: cameras, police, accidents along the route |
| Voice guidance (English and Malay) | 🟡 | | `flutter_tts`, follows the chosen language. Depends on voices available on the device/browser (there may be no Malay voice). Not yet tested on a real phone |
| Bottom bar: arrival time, time and distance left, "Via", progress | ✅ | | Tap to expand |
| Speedometer | ✅ | | From GPS |
| Speed limit sign | 🟡 | | From OSM `maxspeed` via Valhalla. Only ~1/3 of roads have data; the sign disappears when unknown |
| Speeding alert | 🟡 | | Meter turns red + one voice warning. Settings: Off / At the limit / +5 / +10. Only where the limit is known |
| Re-route when off route | ✅ | | `navigation.dart`: >120 m immediately, or 3 fixes >50 m; 8-second pause |
| Mute / unmute voice | ✅ | | |
| Share ETA | ✅ | | Live link (`/s/<token>`) updated every 10 s; without login it falls back to copying text |
| Keep the screen on while navigating | ⬜ | 1 | `wakelock_plus` |
| Background navigation + notification | ⬜ | 1 | Native background service. Important for phones |
| Arrival screen | ✅ | | "You have arrived" + Done |
| Demo mode (no driving) | ✅ | | Not a Waze feature. Developer tool: Settings > Developer |

## 5. Community: reports

Waze is a community app; this is the feature that sets it apart.

| Feature | Status | P | Notes / Needs |
|---|---|---|---|
| Report menu with large types | ✅ | | `report_sheet.dart`. 6 types |
| Subtypes (hidden police, standstill traffic, pothole...) | ✅ | | Full table in `docs/en/API.md` |
| Reports shown on the map with icons | ✅ | | Reloaded every 15 seconds |
| Nearby report alerts while driving (visual) | ✅ | | Within 800 m |
| **Voice** alert for reports ahead | 🟡 | | Once per report, within 600 m, only on the route's road. Not yet heard on a real phone |
| "Still there?" (Yes / Gone) to confirm or remove a report | ✅ | | Card appears after passing a report. 3 net downvotes hide it; an upvote extends its life. You cannot yet vote by tapping the icon on the map |
| Reports expire by themselves | 🟡 | | 2 hours for every type (extended by upvotes). Waze varies by type |
| Abuse prevention (spam, fake reports) | 🟡 | 1 | In place: rate limits (in memory), duplicate rejection (same type, 100 m, 10 min), votes. Not yet: reputation, rate limits shared between instances |
| Crash reports with photos, "map chat", map issue reports | ⬜ | 3 | |
| Points and ranks (gamification) | ⬜ | 3 | |
| Reporting without login | ❌ | | Deliberate: an account is required to cut spam |

## 6. Account and settings

| Feature | Status | P | Notes / Needs |
|---|---|---|---|
| Register, log in, log out (JWT, 7 days) | ✅ | | No "forgot password" or email verification |
| Settings screen (account, my places, navigation, display, developer, about) | ✅ | | |
| Sync saved places between devices | ⬜ | 2 | `saved_places` table in the backend |
| Alert settings per report type | ⬜ | 2 | |
| Units (km / miles) | ⬜ | 3 | |
| Language: English (default) and Malay, switch in Settings | ✅ | | `lib/app/strings.dart`. Adding a language = add an `AppLang` value and translations in `S` |
| Toll detection and price estimate | 🟡 | | Tolls detected from Valhalla (OSM). **The price is an estimate** of ~11 sen/km for class 1, not official PLUS rates. Needs a plaza-to-plaza table for exact prices |
| Delete account and data | ✅ | | Settings > Delete account (`DELETE /me`, password required). Required by app stores and the PDPA |

## 7. Platforms

| Platform | Status | Notes |
|---|---|---|
| Web (Chrome, phones over Wi-Fi) | ✅ | Real GPS needs HTTPS or `localhost`. See `docs/en/DEVELOPMENT.md` |
| Android | 🟡 | Location and internet permissions added. **Never run yet** on a device. For the emulator use `API_URL=http://10.0.2.2:8081` |
| iOS | ⬜ | Platform not generated (`flutter create --platforms=ios`). Needs a Mac |
| Android Auto / CarPlay | ⬜ | Big job, separate platform |
| Windows desktop | ❌ | The MapLibre plugin does not support it |

## Suggested order of work

See `docs/en/ROADMAP.md`. In short: **finish security** (CORS, real secrets, shared rate limits),
then **the real driving experience** (background, screen on, speed limits),
then **content** (POIs, traffic).

## Research sources

- [Customize your alerts, Waze Help](https://support.google.com/waze/answer/13786535?hl=en): alert and report types
- [Report police sightings](https://support.google.com/waze/answer/13739289?hl=en), [Report a crash](https://support.google.com/waze/answer/13739612?hl=en), [Report traffic](https://support.google.com/waze/answer/13740207?hl=en), [Report road hazards](https://support.google.com/waze/answer/13739290?hl=en): report subtypes (police: mobile camera / hidden / other side; crash: minor / other side; traffic: heavy / standstill; hazards: roadworks, vehicle on shoulder, broken traffic light, pothole, object)
- [Drive to a destination, Waze Help](https://support.google.com/waze/answer/6262563?hl=en): Home/Work under the search bar, "Go now" and "Leave later"
- [Speedometer, Waze Help](https://support.google.com/waze/answer/6386895?hl=en): speedometer turns red over the limit, speed limit sign, speed thresholds
- [Waze trip preview (9to5Google)](https://9to5google.com/2021/07/28/waze-trip-preview-tolls-traffic/): route preview with time, tolls, roadworks and traffic
- [5 Waze settings drivers should enable (BGR)](https://www.bgr.com/2273264/waze-settings-drivers-should-enable/): navigation settings (avoid ferries, highways, unpaved roads), vehicle type
- Reference page [AppShots: Waze](https://appshots.design/apps/gps-maps-traffic-alerts-live-navigation-app-shot-waze): only a few public screens are visible without login (dark turn banner with the street name in light blue; bottom panel with a large arrival time, "min · km", "Via ...", progress bar and action row; speed bubble and round report button). The rest is locked

Features known only from general knowledge of Waze (not yet confirmed from the sources above)
are: traffic colours on roads, other drivers on the map, points and ranks, "map chat", and Android Auto / CarPlay.
