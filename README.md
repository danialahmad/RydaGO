# RydaGO

App navigasi komuniti untuk Malaysia, dibina dengan data terbuka dan dijalankan sendiri.

- **Navigasi** belok demi belok dengan tiga pilihan laluan, had laju, amaran memandu laju dan anggaran harga tol
- **Laporan komuniti**: polis, kesesakan, kemalangan, bahaya, kamera, jalan tutup, dengan pengesahan "Masih ada?"
- **Dua bahasa**: English (lalai) dan Bahasa Melayu, termasuk arahan suara
- **Tiada kunci API atau akaun pihak ketiga**: peta [OpenStreetMap](https://www.openstreetmap.org), laluan [Valhalla](https://github.com/valhalla/valhalla), carian [Nominatim](https://nominatim.org)

## Stack

| Lapisan | Teknologi |
|---|---|
| App (web dan Android) | [Flutter](https://flutter.dev) 3.47 / Dart, [Riverpod](https://riverpod.dev) 3 (state), `maplibre_gl` (peta), `geolocator` (GPS), `flutter_tts` (suara), `shared_preferences` |
| Peta | [MapLibre](https://maplibre.org) dengan jubin vektor [OpenFreeMap](https://openfreemap.org) (data OpenStreetMap) |
| API | [Go](https://go.dev) 1.26, router `chi`, `pgx`, migrasi `goose`, pengesahan JWT + bcrypt |
| Pangkalan data | PostgreSQL 16 + [PostGIS](https://postgis.net) 3.5 (laporan, undi, pengguna) |
| Laluan, arahan belokan, had laju, tol | [Valhalla](https://github.com/valhalla/valhalla) 3.5.1, data OSM Malaysia/Singapura/Brunei dari Geofabrik |
| Carian alamat | [Nominatim](https://nominatim.org) 5.1 |
| Web server | nginx 1.27 (menghidang app web) |
| Pakej dan jalankan | Docker Compose: `db`, `valhalla`, `nominatim`, `api`, `web` |

```
Flutter app --> nginx :8080 (web)
     |
     +--------> API Go :8081 --> PostGIS   (laporan, undi, akaun)
                    |-----------> Valhalla  (laluan, had laju, tol)
                    '-----------> Nominatim (carian alamat)
```

## Mula (hanya Docker diperlukan)

Anda **tak perlu** pasang Flutter, Go atau pangkalan data. Perlu: [Docker Desktop](https://www.docker.com/products/docker-desktop/)
dengan **8 GB RAM** diberi kepada Docker dan ~10 GB ruang kosong.

```bash
git clone https://github.com/Shahrizwansohimi/RydaGO.git
cd RydaGO
docker compose up -d --build
```

Kemudian buka **http://localhost:8080**.

### Kali pertama

`--build` membina app web dan API (~5 minit). Selepas itu data peta Malaysia dimuat turun dan dibina di belakang tabir:

| Perkhidmatan | Fungsi | Masa kali pertama |
|---|---|---|
| `valhalla` | laluan, arahan belokan, had laju, tol | ~25 minit |
| `nominatim` | carian alamat | ~70 minit |

App boleh dibuka dari awal (peta, akaun, laporan berfungsi). Carian dan laluan memberi mesej "pelayan mungkin
masih bersedia" sehingga kedua-duanya `healthy`:

```bash
docker compose ps                            # tunggu valhalla dan nominatim jadi (healthy)
docker compose logs -f valhalla nominatim    # kemajuan
```

Mula kedua dan seterusnya ambil beberapa saat. Data kekal dalam `./data` dan volum Docker.

## Cuba app

1. **Menu** (kiri atas) > Settings > **Language** untuk tukar English / Bahasa Melayu.
2. Settings > **Demo driving mode**: lokasi palsu supaya boleh cuba navigasi tanpa memandu atau GPS.
3. Tekan **Where to?**, cari contohnya "Batu Caves", pilih laluan (harga tol ditunjuk pada setiap kad), tekan **Start**.
4. Tekan butang oren untuk **lapor** (perlu akaun: Settings > Sign in > Register). Bila melepasi laporan orang lain,
   app tanya "masih ada?".
5. Kembangkan bar bawah semasa memandu untuk Share ETA, Mute dan End. Dalam mod demo ada butang **Detour**
   untuk lihat kira semula laluan.

Tekan lama pada peta (di web: klik dua kali) untuk meletak pin: Go atau Report di situ.

> **Harga tol ialah anggaran** (kereta kelas 1, ~11 sen/km), bukan kadar rasmi. **Had laju** hanya ada di jalan
> yang OpenStreetMap tahu (kira-kira satu pertiga).

### Dari telefon (Wi-Fi yang sama)

Lihat `docs/DEVELOPMENT.md` (bahagian "Akses dari telefon"): tetapkan `BIND_ADDR=0.0.0.0` dalam `.env`, buka port
dalam firewall, dan buka `http://<ip-pc>:8080`. GPS sebenar perlu HTTPS; guna mod demo pada telefon.

## Dokumen

| Fail | Baca bila |
|---|---|
| [`docs/FEATURES.md`](docs/FEATURES.md) | Senarai ciri, apa yang sudah dan belum dibuat |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | Apa nak buat seterusnya, mengikut keutamaan |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Bagaimana ia disusun; di mana kod untuk apa |
| [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) | Cara kerja harian, resipi, perangkap |
| [`docs/API.md`](docs/API.md) | Rujukan endpoint API |
| [`docs/DESIGN.md`](docs/DESIGN.md) | Prinsip UI, warna, penjenamaan |
| [`CLAUDE.md`](CLAUDE.md) | Arahan ringkas untuk pembantu AI (Claude Code) |

## Struktur repo

```
lib/                  app Flutter (models, services, state, ui; teks dalam lib/app/strings.dart)
test/                 ujian Flutter
backend/              API Go, migrasi pangkalan data, ujian
docker/               Dockerfile web dan konfigurasi nginx
docker-compose.yml    semua perkhidmatan
docs/                 dokumentasi
data/                 (diabaikan git) data OSM dan jubin Valhalla
.env.example          pilihan konfigurasi (semua ada nilai lalai)
```

## Ujian

```bash
flutter analyze && flutter test       # perlu Flutter dipasang (lihat docs/DEVELOPMENT.md)
cd backend && docker run --rm -v "$PWD:/src" -w /src golang:1.26-alpine go test ./...
```

Ujian pangkalan data sebenar: lihat `docs/DEVELOPMENT.md`.

## Masalah biasa

| Gejala | Sebab dan penyelesaian |
|---|---|
| "port is already allocated" pada 8080/8081 | Program lain guna port itu. Tukar `WEB_PORT` dalam `.env`, atau hentikan program itu |
| Carian/laluan: "mungkin masih bersedia" | Data belum siap. `docker compose ps`, tunggu `healthy` |
| Build gagal kehabisan memori | Beri Docker 8 GB RAM (Docker Desktop > Settings > Resources) |
| Nominatim berhenti sendiri semasa import | Biasanya kekurangan RAM. Lihat `docker compose logs nominatim` |
| Mahu mula dari kosong | `docker compose down -v` dan `rm -rf data` (import semula ~1.5 jam) |
| Telefon tak boleh buka | Firewall atau `BIND_ADDR`. Lihat `docs/DEVELOPMENT.md` |

Nama projek Docker kekal `waze-revamp` (lihat `name:` dalam `docker-compose.yml`) supaya volum data sedia ada
tak hilang. Ia hanya nama dalaman.

## Lesen dan kredit

Peta © penyumbang OpenStreetMap (ODbL), dihidangkan oleh OpenFreeMap. Laluan oleh Valhalla, carian oleh Nominatim.
Projek bebas; tiada kaitan dengan Waze atau Google. *(Belum ada fail LICENSE: putuskan sebelum dikongsi.)*
