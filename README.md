# Waze Revamp

App navigasi komuniti untuk Malaysia: laluan sebenar, arahan belok demi belok dalam Bahasa Melayu,
dan laporan jalan raya oleh pemandu (polis, kesesakan, kemalangan, bahaya, kamera, jalan tutup).

Semua dijalankan sendiri dengan data [OpenStreetMap](https://www.openstreetmap.org): tiada kunci API
atau akaun perkhidmatan pihak ketiga. *"Waze Revamp" ialah nama kerja; lihat `docs/DESIGN.md` tentang penjenamaan.*

## Mula dalam 3 langkah (hanya Docker diperlukan)

Anda **tak perlu** pasang Flutter, Go atau pangkalan data. Perlu: [Docker Desktop](https://www.docker.com/products/docker-desktop/)
dengan **8 GB RAM** diberi kepada Docker dan ~10 GB ruang kosong.

```bash
git clone <url-repo-ini>
cd waze-revamp
docker compose up -d --build
```

Kemudian buka **http://localhost:8080**.

### Apa yang berlaku kali pertama (sabar, ia perlukan masa)

`--build` membina app web dan API (~5 minit). Selepas itu dua perkhidmatan memuat turun dan membina data
peta Malaysia di belakang tabir:

| Perkhidmatan | Fungsi | Masa kali pertama |
|---|---|---|
| `valhalla` | laluan dan arahan belokan | ~25 minit |
| `nominatim` | carian alamat | ~70 minit |

**App boleh dibuka dari awal** (peta, daftar akaun, laporan berfungsi). Cuma carian dan laluan memberi
mesej "pelayan mungkin masih bersedia" sehingga kedua-duanya `healthy`:

```bash
docker compose ps          # tunggu valhalla dan nominatim jadi (healthy)
docker compose logs -f valhalla nominatim    # kemajuan
```

Mula kedua dan seterusnya ambil beberapa saat sahaja. Data kekal dalam `./data` dan volum Docker.

## Cuba app

1. Tekan **menu** (kiri atas) > Tetapan > **Mod demo pemanduan**: lokasi palsu supaya anda boleh cuba
   navigasi tanpa memandu atau memerlukan GPS.
2. Tekan **Mau ke mana?**, cari contohnya "Batu Caves", pilih laluan, tekan **Mula**.
3. Tekan butang oren untuk **lapor** (perlu akaun: Tetapan > Log masuk > Daftar).
4. Kembangkan bar bawah semasa memandu untuk Kongsi ETA, Senyap, Tamat. Dalam mod demo ada butang **Lencong**
   yang menunjukkan kira semula laluan.

Tekan lama pada peta (di web: klik dua kali) untuk meletak pin: "Pergi" atau "Lapor" di situ.

### Dari telefon (Wi-Fi yang sama)

Lihat `docs/DEVELOPMENT.md` (bahagian "Akses dari telefon"): tetapkan `BIND_ADDR=0.0.0.0` dalam `.env`, buka port
dalam firewall, dan buka `http://<ip-pc>:8080`. GPS sebenar perlu HTTPS; gunakan mod demo pada telefon.

## Dokumen

| Fail | Baca bila |
|---|---|
| [`docs/FEATURES.md`](docs/FEATURES.md) | Apa yang Waze ada dan apa yang kita sudah/belum buat |
| [`docs/ROADMAP.md`](docs/ROADMAP.md) | Apa nak buat seterusnya, mengikut keutamaan |
| [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) | Bagaimana ia disusun; di mana kod untuk apa |
| [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) | Cara kerja harian, resipi, perangkap |
| [`docs/API.md`](docs/API.md) | Rujukan endpoint API |
| [`docs/DESIGN.md`](docs/DESIGN.md) | Prinsip UI, warna, penjenamaan |
| [`CLAUDE.md`](CLAUDE.md) | Arahan ringkas untuk pembantu AI (Claude Code) |

## Struktur repo

```
lib/            app Flutter (models, services, state, ui)
test/           ujian Flutter
backend/        API Go + migrasi pangkalan data + ujian
docker/         Dockerfile web dan konfigurasi nginx
docker-compose.yml    semua perkhidmatan
docs/           dokumentasi
data/           (diabaikan git) data OSM dan jubin Valhalla
.env.example    pilihan konfigurasi (semua ada nilai lalai)
```

## Ujian

```bash
flutter test                          # perlu Flutter dipasang (lihat docs/DEVELOPMENT.md)
cd backend && docker run --rm -v "$PWD:/src" -w /src golang:1.26-alpine go test ./...
```

## Masalah biasa

| Gejala | Sebab dan penyelesaian |
|---|---|
| "port is already allocated" pada 8080/8081 | Ada program lain guna port itu. Tukar `WEB_PORT` dalam `.env`, atau hentikan program itu |
| Carian/laluan: "mungkin masih bersedia" | Data belum siap. `docker compose ps`, tunggu `healthy` |
| Build gagal kehabisan memori | Beri Docker 8 GB RAM (Docker Desktop > Settings > Resources) |
| Nominatim berhenti sendiri semasa import | Biasanya kekurangan RAM. Lihat `docker compose logs nominatim` |
| Mahu mula dari kosong | `docker compose down -v` dan `rm -rf data` (import semula ~1.5 jam) |
| Telefon tak boleh buka | Firewall atau `BIND_ADDR`. Lihat `docs/DEVELOPMENT.md` |

## Lesen dan kredit

Peta © penyumbang OpenStreetMap (ODbL), dihidangkan oleh OpenFreeMap. Laluan oleh
[Valhalla](https://github.com/valhalla/valhalla), carian oleh [Nominatim](https://nominatim.org).
Projek bebas; tiada kaitan dengan Waze atau Google. *(Belum ada fail LICENSE: putuskan sebelum dikongsi.)*
