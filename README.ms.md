# RydaGO

[English](README.md) · **Bahasa Melayu**

App navigasi komuniti untuk Malaysia, dibina atas data terbuka dan dihoskan sendiri sepenuhnya.

- **Navigasi** dengan arahan belok demi belok, tiga pilihan laluan, had laju, amaran memandu laju dan anggaran harga tol
- **Laporan komuniti**: polis, kesesakan, kemalangan, bahaya, kamera dan jalan tutup, dengan pengesahan "Masih ada?"
- **Dua bahasa**: English (lalai) dan Bahasa Melayu, termasuk arahan suara
- **Tiada kunci API atau akaun pihak ketiga**: peta daripada [OpenStreetMap](https://www.openstreetmap.org), laluan oleh [Valhalla](https://github.com/valhalla/valhalla), carian oleh [Nominatim](https://nominatim.org)

## Teknologi

| Lapisan | Teknologi |
|---|---|
| App (web dan Android) | [Flutter](https://flutter.dev) 3.47 / Dart, [Riverpod](https://riverpod.dev) 3 (keadaan), `maplibre_gl` (peta), `geolocator` (GPS), `flutter_tts` (suara), `shared_preferences` |
| Peta | [MapLibre](https://maplibre.org) dengan jubin vektor [OpenFreeMap](https://openfreemap.org) (data OpenStreetMap) |
| API | [Go](https://go.dev) 1.26, penghala `chi`, `pgx`, migrasi `goose`, pengesahan JWT + bcrypt |
| Pangkalan data | PostgreSQL 16 + [PostGIS](https://postgis.net) 3.5 (laporan, undi, pengguna) |
| Laluan, arahan, had laju, tol | [Valhalla](https://github.com/valhalla/valhalla) 3.5.1, dengan data OSM Malaysia/Singapura/Brunei dari Geofabrik |
| Carian alamat | [Nominatim](https://nominatim.org) 5.1 |
| Pelayan web | nginx 1.27 (menghidang app web) |
| Pembungkusan | Docker Compose: `db`, `valhalla`, `nominatim`, `api`, `web` |

```
App Flutter --> nginx :8080 (web)
     |
     +--------> API Go :8081 --> PostGIS   (laporan, undi, akaun)
                    |---------> Valhalla  (laluan, had laju, tol)
                    '---------> Nominatim (carian alamat)
```

## Bermula (Docker sahaja)

Anda **tidak** perlu memasang Flutter, Go atau pangkalan data. Anda perlukan [Docker Desktop](https://www.docker.com/products/docker-desktop/)
dengan **8 GB RAM** diberi kepada Docker dan kira-kira 10 GB ruang cakera kosong.

```bash
git clone https://github.com/Shahrizwansohimi/RydaGO.git
cd RydaGO
docker compose up -d --build
```

Kemudian buka **http://localhost:8080**.

### Kali pertama

`--build` membina app web dan API (~5 minit). Selepas itu, data peta Malaysia dimuat turun dan
diproses di latar belakang:

| Perkhidmatan | Fungsi | Masa kali pertama |
|---|---|---|
| `valhalla` | laluan, arahan, had laju, tol | ~25 minit |
| `nominatim` | carian alamat | ~70 minit |

App boleh digunakan serta-merta (peta, akaun dan laporan berfungsi). Carian dan laluan menunjukkan mesej
"pelayan mungkin masih bersedia" sehingga kedua-dua perkhidmatan `healthy`:

```bash
docker compose ps                            # tunggu valhalla dan nominatim jadi (healthy)
docker compose logs -f valhalla nominatim    # kemajuan
```

Permulaan seterusnya ambil beberapa saat. Data kekal dalam `./data` dan dalam volum Docker.

## Mencuba

1. **Menu** (kiri atas) > Tetapan > **Bahasa** menukar antara English dan Bahasa Melayu.
2. Tetapan > **Mod demo pemanduan** menggunakan lokasi palsu, jadi anda boleh mencuba navigasi tanpa memandu atau GPS.
3. Ketuk **Mau ke mana?**, cari contohnya "Batu Caves", pilih laluan (setiap kad menunjuk harga tol), dan ketuk **Mula**.
4. Ketuk butang oren untuk **melapor** sesuatu (akaun diperlukan: Tetapan > Log masuk > Daftar).
   Bila anda melepasi laporan orang lain, app bertanya sama ada ia masih ada.
5. Semasa memandu, kembangkan bar bawah untuk Kongsi ETA, Senyap dan Tamat. Dalam mod demo, butang **Lencong**
   menunjukkan kira semula laluan.

Tekan lama pada peta (di web: klik dua kali) untuk meletak pin, kemudian pilih Pergi atau Lapor di situ.

> **Harga tol ialah anggaran** (kereta kelas 1, kira-kira 11 sen/km), bukan kadar rasmi. **Had laju** hanya muncul
> di jalan yang ada data dalam OpenStreetMap (kira-kira satu pertiga).

### Dari telefon (Wi-Fi yang sama)

Lihat [`docs/ms/DEVELOPMENT.md`](docs/ms/DEVELOPMENT.md) ("Akses dari telefon pada Wi-Fi yang sama"): tetapkan `BIND_ADDR=0.0.0.0`
dalam `.env`, buka port dalam firewall, dan layari `http://<ip-pc>:8080`. GPS sebenar perlu HTTPS, jadi guna mod demo pada telefon.

## Dokumentasi

Setiap dokumen ada dalam English (`docs/en/`) dan Bahasa Melayu (`docs/ms/`) dengan kandungan yang sama.

| Fail | Baca bila |
|---|---|
| FEATURES ([ms](docs/ms/FEATURES.md) · [en](docs/en/FEATURES.md)) | Anda mahu senarai ciri dan apa yang siap atau belum |
| ROADMAP ([ms](docs/ms/ROADMAP.md) · [en](docs/en/ROADMAP.md)) | Anda mahu tahu apa nak dibina seterusnya, ikut keutamaan |
| ARCHITECTURE ([ms](docs/ms/ARCHITECTURE.md) · [en](docs/en/ARCHITECTURE.md)) | Anda mahu tahu bagaimana semuanya bersambung dan di mana kod berada |
| DEVELOPMENT ([ms](docs/ms/DEVELOPMENT.md) · [en](docs/en/DEVELOPMENT.md)) | Cara kerja harian, resipi, perangkap |
| API ([ms](docs/ms/API.md) · [en](docs/en/API.md)) | Rujukan endpoint API |
| DESIGN ([ms](docs/ms/DESIGN.md) · [en](docs/en/DESIGN.md)) | Prinsip UI, warna, penjenamaan |
| [`CLAUDE.md`](CLAUDE.md) | Arahan ringkas untuk pembantu AI (Claude Code) |

## Susunan repositori

```
lib/                  app Flutter (models, services, state, ui; teks UI dalam lib/app/strings.dart)
test/                 ujian Flutter
backend/              API Go, migrasi pangkalan data, ujian
docker/               Dockerfile web dan konfigurasi nginx
docker-compose.yml    semua perkhidmatan
docs/en/, docs/ms/    dokumentasi dalam English dan Bahasa Melayu
data/                 (diabaikan git) data OSM dan jubin Valhalla
.env.example          pilihan konfigurasi (semuanya ada nilai lalai)
```

## Ujian

```bash
flutter analyze && flutter test       # perlu Flutter dipasang (lihat docs/ms/DEVELOPMENT.md)
cd backend && docker run --rm -v "$PWD:/src" -w /src golang:1.26-alpine go test ./...
```

Untuk ujian pangkalan data sebenar, lihat [`docs/ms/DEVELOPMENT.md`](docs/ms/DEVELOPMENT.md).

## Penyelesaian masalah

| Gejala | Punca dan penyelesaian |
|---|---|
| "port is already allocated" pada 8080/8081 | Program lain menggunakan port itu. Tukar `WEB_PORT` dalam `.env`, atau hentikan program itu |
| Carian/laluan: "pelayan mungkin masih bersedia" | Data belum sedia. Jalankan `docker compose ps` dan tunggu `healthy` |
| Bina gagal kerana kehabisan memori | Beri Docker 8 GB RAM (Docker Desktop > Settings > Resources) |
| Nominatim berhenti sendiri semasa import | Biasanya RAM tak cukup. Semak `docker compose logs nominatim` |
| Mahu mula dari kosong | `docker compose down -v` dan `rm -rf data` (import semula ambil ~1.5 jam) |
| Telefon tak dapat membuka app | Firewall atau `BIND_ADDR`. Lihat `docs/ms/DEVELOPMENT.md` |

Nama projek Docker kekal `waze-revamp` (lihat `name:` dalam `docker-compose.yml`) supaya volum data sedia ada
tak hilang. Ia hanya nama dalaman.

## Lesen dan kredit

Data peta © penyumbang OpenStreetMap (ODbL), dihidang oleh OpenFreeMap. Laluan oleh Valhalla, carian oleh Nominatim.
Projek bebas, tiada kaitan dengan Waze atau Google. *(Belum ada fail LICENSE: putuskan sebelum berkongsi.)*
