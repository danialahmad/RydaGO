# What to build next

**English** · [Bahasa Melayu](../ms/ROADMAP.md)

Drawn from `docs/en/FEATURES.md` (see there for the full list and reasons).
The order is a suggestion; change it as needed.

## Stage 1: before opening it to other people

Without this, community data cannot be trusted or is not safe.

1. **Further security**
   - Now in place: rate limits (in memory, per instance), duplicate report detection, deleting reports and deleting accounts.
   - Not yet: restrict CORS to the app's origin, replace all dev values (passwords, JWT) in deployment, shared rate limits if there is more than one API instance, voting by tapping an icon on the map.

(Done: "Still there?" with votes and lifetimes; real-database tests in `integration_test.go`.)

## Stage 2: the real driving experience

2. **Test on a real Android device** (and set up a full `flutter doctor`). Fix whatever breaks.
   API address for the emulator: `API_URL=http://10.0.2.2:8081`.
3. **Keep the screen on** (`wakelock_plus`) and **background navigation** with a notification
   (Android foreground service). Without this, navigation stops when the screen turns off.
4. **Improve speed limits**: OSM `maxspeed` coverage in Malaysia is low (~1/3). Consider guessing by road
   class (labelled "estimate") or contributing data to OSM. Test report/speed-limit voice on a real phone.
5. **HTTPS** for web so GPS works on phones without tricks. Caddy in compose with an internal
   certificate or a real domain.

## Stage 3: content

6. **Places (POI)**: import Nominatim `full`, or another POI source, so "Masjid Negara" can be found.
   Then quick categories (fuel, food, parking) and "add a stop".
7. **Sync saved places** across devices (`saved_places` table, `/me/places`).
8. **More route options**: avoid ferries in the UI (the API already supports it), motorcycles, exact toll prices (plaza table).

## Stage 4: bigger things

9. **Live traffic**: collect driver speeds per road segment (with consent and without
   identifying individuals), colour the roads, feed it into time estimates. Big job; design first.
10. iOS, Android Auto / CarPlay.
11. Offline maps; gamification; more languages.

## Decisions for the project owner

- **Its own name and identity** (not "Waze"; see `docs/en/DESIGN.md`).
- Who runs the servers, and the cost: Valhalla + Nominatim need several GB of RAM and disk.
  One 4-core / 16 GB VPS is enough for Malaysia.
- Privacy policy and how long reports/locations are kept.
- Moderation: who judges false reports as users grow.
