# Seni bina

[English](../en/ARCHITECTURE.md) · **Bahasa Melayu**

Gambaran keseluruhan, supaya anda tahu **di mana** nak ubah sesuatu sebelum membuka kod.

## Gambaran besar

```
   Telefon / Chrome
        |
        |  http://<PC>:8080            (web: Flutter dihidang nginx)
        v
   +---------+      http://<PC>:8081      +-----------+
   |  Flutter | ------------------------> |  API (Go) |
   |  app     |   /auth /reports          |  chi      |
   +---------+   /route  /places          +-----+-----+
        |                                    |   |   |
        | jubin peta (terus ke internet)     |   |   +--> Nominatim :8080  (carian alamat)
        v                                    |   +------> Valhalla  :8002  (laluan, belokan)
   tiles.openfreemap.org                     +----------> PostgreSQL + PostGIS (pengguna, laporan)
```

Semua perkhidmatan dijalankan oleh **satu** `docker-compose.yml` di akar repo.
Satu-satunya perkara yang disambung terus dari app ke luar ialah **jubin peta** (OpenFreeMap) dan skrip
MapLibre GL JS (dimuat dari `unpkg.com` oleh plugin web).

| Perkhidmatan | Imej / kod | Port (hos) | Fungsi |
|---|---|---|---|
| `web` | `docker/web.Dockerfile` (Flutter build, nginx) | 8080 | App web |
| `api` | `backend/` (Go 1.26) | 8081 | Satu-satunya pintu masuk data untuk app |
| `db` | `postgis/postgis:16-3.5` | 5432 (loopback) | Pengguna dan laporan |
| `valhalla` | `gis-ops/docker-valhalla:3.5.1` | 8002 (loopback) | Laluan dan arahan belok demi belok |
| `nominatim` | `mediagis/nominatim:5.1` | 8088 (loopback) | Carian alamat |

App **tidak** bercakap dengan Valhalla atau Nominatim terus. Semuanya melalui API, supaya format
respons kita sendiri yang stabil (dan kita boleh tukar enjin kemudian tanpa menyentuh app).

## Backend (`backend/`)

Satu pakej Go (`package main`), tanpa lapisan tambahan kerana ia masih kecil.

| Fail | Isi |
|---|---|
| `main.go` | Penghala chi, migrasi goose semasa mula, `/health`, `/reports`, jadual jenis dan subjenis laporan, CORS |
| `auth.go` | Daftar, log masuk (bcrypt), JWT HS256 7 hari, middleware `requireAuth` |
| `route.go` | `/route`: tiga panggilan selari ke Valhalla, nyahkod polyline6, had laju (`traceLimits`), gugurkan pendua |
| `lang.go` | Teks belokan dalam English atau Melayu (`maneuverText`) |
| `signs.go` | Papan tanda keluar (`exit`, `toward`) dan lorong daripada Valhalla |
| `toll.go` | Anggaran harga tol (`TOLL_RM_PER_KM`, `TOLL_MIN_RM`) |
| `votes.go` | `/reports/{id}/vote`: "Masih ada?" |
| `accounts.go` | Padam laporan sendiri, padam akaun (`DELETE /me`) |
| `shares.go` | Kongsi perjalanan langsung: `/shares` dan halaman `/s/{token}` |
| `ratelimit.go` | Had kadar baldi token, dalam ingatan |
| `places.go` | `/places`: proksi ke Nominatim, ringkaskan respons |
| `migrations/` | SQL goose, dibenamkan dalam binari (`//go:embed`). Berjalan automatik bila API bermula |
| `*_test.go` | Ujian unit. Valhalla dan Nominatim digantikan pelayan palsu `httptest` |
| `integration_test.go` | Ujian dengan PostgreSQL sebenar; dilangkau tanpa `TEST_DATABASE_URL` |

Skema pangkalan data (hasil `migrations/`):

```
users   (id, email UNIQUE, password_hash, created_at)
reports (id, type, subtype NULL, geom GEOGRAPHY(Point,4326), user_id -> users, created_at)
         indeks GIST pada geom, indeks pada created_at
report_votes (report_id, user_id, vote +1/-1, PRIMARY KEY (report_id, user_id))
shares (token PK, user_id, dest_*, lat/lng, eta_at, updated_at, ended_at)  -- kongsi perjalanan langsung
```

Laporan dibaca dengan `ST_DWithin`. Ia sah selagi umur (sejak dibuat atau undi naik terkini) < 2 jam, dan
disembunyikan bila `undi turun - undi naik >= 3`. Jumlah undi dikira dengan `CROSS JOIN LATERAL` dalam `nearbyReports`.
Had laju datang dari `traceLimits` dalam `route.go` (Valhalla `/trace_attributes`, `edge_walk`).
Tiada kerja pembersihan: baris lama kekal dalam jadual, cuma tak dipulangkan.

Keputusan penting:

- **Teks belokan dibina di API** (`maneuverText` dalam `lang.go`) dalam English atau Melayu ikut `?lang=`, kerana Valhalla
  tak menyokong bahasa Melayu. Suara dan banner menggunakan teks yang sama. Teks lain dalam app ada dalam `lib/app/strings.dart`.
- **Tiga laluan = tiga panggilan Valhalla** (`routeVariants`): biasa (dengan 2 `alternates`), `use_tolls: 0`,
  `shortest: true`. Pendua digugurkan, dan alternatif Valhalla mengisi tempat kosong sehingga 3 laluan.
  Kalau satu gagal, yang lain tetap dipulangkan.
- **JWT**: `JWT_SECRET` wajib dan mesti 32+ aksara, kalau tidak API enggan bermula.
  Log masuk memulangkan mesej sama untuk "email tak wujud" dan "kata laluan salah"
  dan menjalankan bcrypt palsu supaya masa respons tak membocorkan email mana yang wujud.

## App Flutter (`lib/`)

```
lib/
  main.dart                  titik masuk: ProviderScope + MaterialApp + tema
  app/
    config.dart              alamat API, gaya peta, lokasi sandaran (KLCC)
    strings.dart             S: semua teks UI, English dan Melayu
    theme.dart               warna (AppColors) dan ThemeData cerah/gelap
    format.dart              formatDistance / formatDuration / formatClock
  models/                    data tulen, tiada Flutter widget (kecuali IconData)
    geo.dart                 haversineM, routeCumulative, navZoom
    place.dart               Place, ikon ikut kategori Nominatim
    report.dart              ReportType (+ subjenis), Report
    route.dart               RouteOption, Maneuver
    route_summary.dart       laporan di sepanjang laluan (ringkasan sebelum Mula, kelewatan anggaran)
    user_loc.dart            UserLoc (fix, laju, arah, ketepatan)
  services/
    api.dart                 SEMUA panggilan HTTP ke API kita
    map_style.dart           ubah gaya OpenFreeMap: peta rata, jalan tebal, tiada bangunan 3D
    voice.dart               Speaker (TTS) dan VoicePlanner (bila nak bercakap)
  state/                     Riverpod: logik dan keadaan aplikasi
    user_loc.dart            GPS (geolocator) + suntikan fix untuk mod demo
    auth.dart                token disimpan dalam shared_preferences
    settings.dart            tema, suara, elak tol/lebuh raya, amaran laju
    saved_places.dart        Rumah, Kerja, kegemaran, terbaru
    trip.dart                destinasi, laluan, pilihan laluan, pin, "sedang navigasi"
    reports.dart             muat laporan berdekatan (setiap 15 s) dan hantar laporan
    navigation.dart          NavNotifier: fix GPS menjadi kemajuan, tiba, kira semula
    alternatives.dart        cadangan laluan lebih pantas semasa memandu, senarai laluan lain
    share.dart               kongsi perjalanan langsung (kemas kini setiap 10 s)
    demo.dart                mod demo: DemoDriver menghantar fix palsu
    voice.dart               sambung navigasi ke suara
  ui/
    screens/                 map_screen, search_screen, settings_screen, login_screen
    map/                     map_view (MapLibre + lapisan), marker_images (ikon penanda)
    widgets/                 panel bawah, pratonton laluan, banner, laporan, laluan alternatif, butang
```

Peraturan susunan: `models` tak import apa-apa daripada `state` atau `ui`; `state` tak import `ui`;
`ui` boleh import semua. Kalau anda terpaksa melanggarnya, ada sesuatu yang salah tempat.

### Aliran keadaan (Riverpod)

```
userLocProvider  (GPS atau demo)
      |
      +--> navProvider (NavNotifier) ----> navigatingProvider / banner / bar bawah / suara
      |         ^ mula dari startNavigation(): laluan terpilih dari routesProvider
      +--> reportsProvider (muat semula laluan sekitar)
      +--> routesProvider (laluan dari kedudukan semasa ke destinasi)

destinationProvider --> routesProvider --> routeIndexProvider --> RoutePreviewPanel
pinProvider (tekan lama) --> PinPanel; juga lokasi laporan seterusnya
MapView mendengar semuanya dan melukis semula lapisan peta.
```

Panel di bawah `MapScreen` ditentukan oleh keadaan, tanpa `Navigator`:
sedang navigasi → `NavBottomBar`; ada destinasi → `RoutePreviewPanel`; ada pin → `PinPanel`; kalau tak → `HomePanel`.
Butang Kembali (Android) mundur satu peringkat (`PopScope` dalam `map_screen.dart`).

### Navigasi (`state/navigation.dart`), bahagian paling halus

Navigasi **hanya** bertindak balas kepada fix GPS (`userLocProvider`). Tiada pemasa atau simulasi di dalamnya.

1. Setiap fix diunjurkan pada garis laluan (segmen terdekat, mula mencari berhampiran segmen semasa supaya laluan
   yang bersilang tak membuat kemajuan melompat). Hasilnya: `alongM` (meter dari mula), jarak dari garis, titik terlekat.
2. Dalam 50 m dari garis: titik biru dilekatkan pada laluan. Lebih jauh: ditunjuk di tempat sebenar.
3. **Tiba**: baki ≤ 30 m dan di atas laluan, atau dalam 30 m dari destinasi.
4. **Tersasar**: jarak > 120 m (serta-merta) atau 3 fix berturut-turut > 50 m, dan sudah 8 saat sejak
   navigasi bermula atau re-route terakhir → minta laluan baru dari kedudukan semasa, **jenis yang sama** dipilih semula.
5. Fix dengan ketepatan > 100 m diabaikan.
6. Belokan seterusnya = maneuver pertama yang `cum[index] >= alongM`.

Mod demo (`state/demo.dart`) memintas semua ini dengan **menyuntik fix palsu** ke `UserLocNotifier`
sepanjang laluan, supaya logik di atas diuji tanpa memandu. `NavNotifier` tak tahu ia demo.

### Peta (`ui/map/map_view.dart`)

- Satu widget `MapLibreMap`. Semua lapisan (garis laluan, simbol laporan, titik pengguna) dilukis oleh `_draw`,
  dan dipanggil semula bila keadaan berubah. `_sync` menyeragamkan panggilan supaya tak bertindih.
- Ikon penanda dilukis ke PNG semasa app bermula (`marker_images.dart`) daripada ikon Material, bukan fail gambar.
  Kalau gagal, jatuh balik kepada bulatan berwarna.
- Tukar cerah/gelap guna `controller.setStyle()`, **bukan** tukar `styleString` widget, sebab plugin
  menetapkan semula pilihan lain (atribusi) bila `styleString` berubah.
- Kamera dikira sendiri untuk muat laluan (`_fitDestination`), kerana `newLatLngBounds` + padding
  berkelakuan lain di web.

## Apa yang disimpan di mana

| Data | Tempat |
|---|---|
| Pengguna, laporan, undi, kongsi | PostgreSQL (volum Docker `pgdata`) |
| Data OSM Valhalla dan jubin laluan | `./data/valhalla` (diabaikan git) |
| Pangkalan data Nominatim | volum Docker `nominatim-data` |
| Token log masuk, tetapan, Rumah/Kerja/kegemaran/terbaru | `shared_preferences` pada peranti (localStorage di web) |

## Had dan hutang teknikal yang diketahui

- **CORS dibuka kepada `*`** (`cors` dalam `main.go`). Ketatkan sebelum deploy.
- Nilai dev dalam compose (`wazedev`, JWT dev) ialah **awam**. Tetapkan nilai sebenar dalam `.env`.
- Had kadar ialah dalam ingatan (`ratelimit.go`): ia ditetapkan semula bila API dimulakan semula dan tidak dikongsi antara instans.
- Ujian pangkalan data sebenar (`integration_test.go`) hanya berjalan bila `TEST_DATABASE_URL` ditetapkan, jadi
  `go test` biasa melangkaunya (lihat `docs/ms/DEVELOPMENT.md`).
- Tiada ujian widget/skrin Flutter, hanya ujian logik.
- `web/index.html` ada skrip kecil yang meruntuhkan kredit peta pada permulaan. Ia bergantung pada nama kelas CSS
  MapLibre dan mungkin perlu dikemas kini bila plugin dinaik taraf.
- Plugin peta memuat MapLibre GL JS dari `unpkg.com` semasa jalan: perlu internet.
