# Panduan pembangunan

Cara kerja harian. Untuk cara **menjalankan** projek buat kali pertama, lihat `README.md`.

## Dua cara menjalankan app

| | Docker sahaja | Dev cepat (Flutter dipasang) |
|---|---|---|
| Apa perlu dipasang | Docker | Docker + Flutter 3.47.x |
| Perintah | `docker compose up -d --build` | `docker compose up -d db valhalla nominatim api` kemudian `flutter run -d chrome` |
| Ubah kod UI, lihat hasil | bina semula imej web (~3 min) | muat semula panas (saat) |
| Sesuai untuk | tengok dan guna | membangun |

Dalam cara dev, app (di `localhost:<port-rawak>`) memanggil API di `localhost:8081`: alamat API diambil
daripada host halaman (`lib/app/config.dart`). Untuk API di tempat lain: `--dart-define=API_URL=http://...`.

### Pasang Flutter

Ikut [docs.flutter.dev/get-started/install](https://docs.flutter.dev/get-started/install).
Versi yang digunakan projek: **3.47.7** (stable); sama dengan `FLUTTER_VERSION` dalam `docker/web.Dockerfile`.
Selepas itu `flutter pub get`. **Tidak perlu** Android Studio untuk web.

## Perintah biasa

```bash
flutter analyze                     # mesti "No issues found"
flutter test                        # ujian logik app
flutter run -d chrome               # app dengan muat semula panas

# Backend: Go tak perlu dipasang. Jalankan dalam Docker:
cd backend
docker run --rm -v "$PWD:/src" -w /src golang:1.26-alpine sh -c "gofmt -l . && go vet ./... && go test ./..."

# Ujian pangkalan data sebenar (undi, tamat tempoh). Mulakan `docker compose up -d db`, kemudian dari PowerShell:
docker run --rm --network waze-revamp_default -v "${PWD}:/src" -w /src -e TEST_DATABASE_URL="postgres://waze:wazedev@db:5432/postgres?sslmode=disable" golang:1.26-alpine go test ./...
# Tanpa TEST_DATABASE_URL, ujian ini dilangkau.

docker compose logs -f api          # log API
docker compose logs -f valhalla nominatim
docker compose ps                   # lihat "healthy"
docker compose up -d --build api    # selepas ubah kod Go
docker compose up -d --build web    # selepas ubah kod Flutter (dalam cara Docker sahaja)
docker compose down                 # henti (data kekal)
```

Pada Windows PowerShell gunakan `${PWD}` ganti `$PWD`. Dalam Git Bash, awasi penukaran laluan
(`-w /src` boleh jadi salah; jalankan perintah Docker dari PowerShell).

## Data dan kitaran hayatnya

Kali pertama `docker compose up`, **valhalla** dan **nominatim** masing-masing memuat turun fail OSM
Malaysia/Singapura/Brunei (~240 MB) dan membina data mereka. App berfungsi serta-merta (peta, log masuk,
laporan), tetapi `/route` dan `/places` memulangkan `502` sehingga `docker compose ps` menunjukkan `healthy`.

| | Masa kasar | Disk |
|---|---|---|
| Valhalla | ~25 minit | ~1.6 GB dalam `./data/valhalla` |
| Nominatim (`address`) | ~70 minit | ~3 GB dalam volum `nominatim-data` |

Keperluan: Docker diberi **8 GB RAM** dan ~10 GB ruang kosong.

Set semula sesuatu:

```bash
docker compose down -v      # BUANG semua volum: pengguna, laporan, data Nominatim. Import semula ~70 min
rm -rf data/valhalla        # buang jubin Valhalla (dibina semula di mula seterusnya, ~25 min)
```

Tukar kepada Nominatim `full` (ada POI): tetapkan `NOMINATIM_IMPORT_STYLE=full` dalam `.env`, lalu
`docker compose down` dan `docker volume rm waze-revamp_nominatim-data`, kemudian `up -d`. (Hanya terpakai pada volum baru.)

## Akses dari telefon pada Wi-Fi yang sama

1. Dalam `.env`: `BIND_ADDR=0.0.0.0` lalu `docker compose up -d`.
2. Buka port pada Windows Firewall (PowerShell **Administrator**), terhad kepada rangkaian rumah:
   ```powershell
   New-NetFirewallRule -DisplayName "RydaGO dev" -Direction Inbound -Protocol TCP -LocalPort 8080,8081 -RemoteAddress LocalSubnet -Profile Any -Action Allow
   ```
   (Buang selepas siap: `Remove-NetFirewallRule -DisplayName "RydaGO dev"`.)
3. Cari IP PC (`ipconfig`), buka `http://<ip>:8080` pada telefon. Semak `http://<ip>:8081/health` dahulu jika tak jadi.
4. **Tetapkan `JWT_SECRET` sebenar** dalam `.env` apabila membuka ke rangkaian; nilai lalai adalah awam.

**GPS sebenar tak berfungsi melalui `http://192.168.x.x`**: pelayar hanya benarkan lokasi pada HTTPS atau `localhost`.
Pada telefon gunakan **Mod demo** (Tetapan > Pembangun). Untuk GPS sebenar pada Android Chrome:
`chrome://flags/#unsafely-treat-insecure-origin-as-secure`, tambah `http://<ip>:8080`, hidupkan, mulakan semula Chrome.
Pada Chrome desktop, DevTools > Sensors membolehkan menetapkan lokasi sendiri.

## Mod demo

Tetapan > Pembangun > **Mod demo pemanduan**. Lokasi palsu bergerak di sepanjang laluan 10x lebih laju
dan melalui saluran GPS yang sama (lihat `docs/ARCHITECTURE.md`). Dalam navigasi, kembangkan bar bawah:
butang **Lencong (demo)** melompatkan kedudukan ~270 m dari laluan untuk menunjukkan re-route.
Berguna untuk demonstrasi dan untuk menguji UI navigasi tanpa memandu.

## Resipi: tambah sesuatu

### Jenis atau subjenis laporan baru

Sentuh **tiga** tempat (ujian di dua sisi akan gagal kalau terlupa satu):

1. `backend/main.go`: tambah dalam `reportSubtypes`.
2. `lib/models/report.dart`: tambah dalam enum `ReportType` (label, ikon, warna, subjenis).
3. `docs/API.md`: kemas kini jadual.
4. Kemas kini senarai jangkaan dalam `test/logic_test.dart` ("report types") dan `backend/main_test.go`.

Tiada migrasi diperlukan: `type` dan `subtype` ialah `TEXT` yang disahkan dalam kod Go.

### Endpoint API baru

1. Tulis pengendali dalam `backend/` dan daftar dalam `main()` (`r.Get(...)` atau `r.With(s.requireAuth).Post(...)`).
2. Tambah ujian `httptest`. Untuk pergantungan luar, ikut corak `fakeValhalla` / `fakeNominatim`.
3. Tambah kaedah dalam `lib/services/api.dart` (semua panggilan HTTP di sini sahaja).
4. Dokumenkan dalam `docs/API.md`.

### Perubahan pangkalan data

Fail baru `backend/migrations/0000N_nama.sql` dengan `-- +goose Up` dan `-- +goose Down`.
Ia berjalan automatik bila API dimulakan semula (`docker compose up -d --build api`). Jangan ubah migrasi
yang sudah dijalankan; tambah yang baru.

### Skrin atau panel UI baru

Ikut `docs/DESIGN.md`. Letak widget dalam `lib/ui/widgets/` (panel dalam peta) atau `lib/ui/screens/`
(halaman penuh). Keadaan baru → `lib/state/`; jangan letak logik dalam widget.

## Perangkap yang pernah memakan masa

- **`pg_isready` tanpa `-h 127.0.0.1`** lulus semasa Postgres masih memulakan diri lalu API bermula terlalu awal.
  Healthcheck dalam compose sudah betul; jangan "permudahkan".
- **Web: "tekan lama" ialah klik dua kali.** `onMapLongClick` dalam `maplibre_gl_web` dipasang pada `dblclick`.
  Pada telefon sebenar ia tekan lama.
- **Selepas widget hilang semasa tekan, klik pelayar tertunda jatuh ke peta di bawah** (web). Itulah sebabnya
  peta tak menggunakan `onMapClick` untuk apa-apa; hanya tekan lama/dua kali.
- **Tukar `styleString` widget peta** menetapkan semula pilihan plugin lain (atribusi). Guna `setStyle()`.
- **Plugin Flutter di Windows** (`geolocator`, `flutter_tts`, `shared_preferences`) mengeluarkan amaran
  tentang Developer Mode (symlink) bila `pub get`. Ia hanya penting untuk bina desktop Windows, yang memang
  tak disokong MapLibre. Abaikan untuk web.
- **Imej Flutter dalam Docker** dikunci kepada tag git `3.47.7`. Kalau anda naik taraf Flutter, ubah
  `FLUTTER_VERSION` dalam `docker/web.Dockerfile` juga, atau `pubspec.lock` tak serasi.
- **Pelayar dalam alat pratonton** (dalam app pembangun) kadang-kadang memotong paparan. Muat semula halaman.

## Konvensyen

- Dart: `flutter analyze` bersih. Fail kecil, satu tanggungjawab. `lib/models` tulen.
- Go: `gofmt`, `go vet`, ralat dikendalikan, tiada rahsia dalam kod.
- Komen menerangkan **kenapa**, bukan apa. Kod dan komen dalam bahasa yang sama dengan fail sedia ada
  (komen Inggeris di kebanyakan fail, teks UI dalam `strings.dart`: English dan Melayu).
- Commit kecil dan bermakna. Jangan commit `.env`, `data/`, `build/`.
