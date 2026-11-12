# UI design

**English** · [Bahasa Melayu](../ms/DESIGN.md)

Goal: **easy to use while driving**, with a feel familiar to users of community navigation apps,
but with its own identity and icons.

## Principles

1. **One main screen.** The map is always full screen. Everything else is a panel sliding up from the bottom or
   a floating round button. Keep full-page changes to a minimum.
2. **Big fingers.** Touch targets at least 52 px; main buttons 56 px; report button 64 px.
   While driving, important text (distance to turn) is 38 px bold.
3. **One main action per stage**, and it is coloured:
   *green* = go (Start, Done), *orange* = report, *red* = stop (End).
4. **Show state, never stay silent.** Loading, errors and "nothing found" all have clear text (in both languages) and
   a next action (try again, turn on demo, allow location). No button that does nothing.
5. **Light and dark** are both first class. The map follows the theme.
6. **Language**: English by default, Malay optional. Relaxed but polite, short sentences. "Where to?" / "Mau ke mana?", "You have arrived" / "Anda telah sampai".

## Main screen stages (`ui/screens/map_screen.dart`)

| Stage | Bottom panel | Top | Bottom right |
|---|---|---|---|
| Browsing | `HomePanel`: "Where to?" bar + Home / Work / favourites | Menu button, location status chip | My location, Report |
| Pin dropped | `PinPanel`: "Dropped pin" + Go / Report | same | same |
| Preview | `RoutePreviewPanel`: route cards + **Start** | same | same |
| Driving | `NavBottomBar`: arrival time, remaining, progress, Share / Mute / End | dark `NavBanner`, nearby report pill, voice button | Speed bubble (left), Report |
| Arrived | "You have arrived" bar + **Done** | "You have arrived" banner | |

Other full screens: `SearchScreen` (search), `SettingsScreen`, `LoginScreen`.
Sheets: `ReportSheet` (grid of types, then subtypes).

## Tokens (`lib/app/theme.dart`)

| Name | Value | Use |
|---|---|---|
| `AppColors.brand` | `#2DB7F5` | Route line, location dot, active state |
| `AppColors.brandDeep` | `#1597D6` | Text and buttons on light backgrounds |
| `AppColors.go` | `#2FBF71` | Start, Done, "Fastest" |
| `AppColors.report` | `#FF7A1A` | Report button |
| `AppColors.danger` | `#E5484D` | End, destination, errors |
| `AppColors.banner` | `#0B1220` | Turn banner |
| `AppColors.ink` / `muted` | `#0E1A2B` / `#6B7A8C` | Primary / secondary text |

Shapes: bottom sheet radius 28, cards 20, buttons 18, search bar 30 (pill). Clear shadows
(`elevation` 5 to 16) so buttons stand out over a busy map.
Report type colours live on `ReportType` (`lib/models/report.dart`).

## Icons and branding

- **Material icons only.** No third-party logos, mascots or icons. Map marker icons are rendered
  at runtime from Material icons (`ui/map/marker_images.dart`).
- **"RydaGO"** is the project's working name. **Do not use "Waze"** in the app name, icon, or
  app store listing: it is a trademark. Pick a name before publishing (change `title` in
  `main.dart`, `web/manifest.json`, `web/index.html`, `AndroidManifest.xml`, `pubspec.yaml`).
- Settings > About already states that the project is independent. Keep it.
- **Map credits must be visible**: © OpenStreetMap contributors and OpenFreeMap. The MapLibre attribution control
  at the top right is how this is met. Do not hide it.

## Adding UI: checklist

1. Colours and radii from `AppColors` / the theme; do not write new values inside widgets.
2. Provide **loading**, **error** and **empty** states.
3. Test **dark** mode and small screens (360 px wide).
4. New text: add it to `lib/app/strings.dart` (English and Malay); times use `formatClock`, distances use `formatDistance`.
5. If a widget shows numbers that change while driving, do not rebuild the whole screen:
   use `ref.watch(navProvider.select(...))` or a small widget of its own.
