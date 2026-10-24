# Waze Revamp

Aplikasi navigasi komuniti untuk Malaysia: laluan sebenar, report jalan raya oleh pengguna, dan
navigasi belok demi belok. Semua perkhidmatan dijalankan sendiri (self-hosted) dengan data OpenStreetMap.

## Susunan

| Bahagian | Teknologi | Lokasi |
|---|---|---|
| App mudah alih / web | Flutter, Riverpod, MapLibre GL (peta OpenFreeMap) | `lib/` |
| API | Go, chi, pgx, goose, JWT | `backend/` |
| Pangkalan data | PostgreSQL 16 + PostGIS | `backend/docker-compose.yml` |
| Laluan | Valhalla | `backend/docker-compose.yml` |
| Carian alamat | Nominatim | `backend/docker-compose.yml` |

Aliran data: Flutter → API (`:8081`) → PostGIS, Valhalla (`:8002`), Nominatim (`:8088`).

## Mula

Keperluan: Flutter (stable), Docker. Go tak perlu dipasang; API dibina dalam Docker.

```bash
# 1. Backend (kali pertama ambil masa lama: muat turun OSM Malaysia, bina jubin Valhalla,
#    import ke Nominatim. Lihat kemajuan dengan `docker compose logs -f valhalla nominatim`)
cd backend
docker compose up -d --build

# 2. App di Chrome
cd ..
flutter run -d chrome
```

Untuk pratonton statik (bina web dan sajikan di `http://localhost:8080`):

```bash
flutter build web
node .claude/serve.js
```

Kata laluan dan rahsia dalam `docker-compose.yml` ialah nilai **dev sahaja**. Tetapkan
`POSTGRES_PASSWORD`, `NOMINATIM_PASSWORD` dan `JWT_SECRET` (sekurang-kurangnya 32 aksara) untuk apa-apa selain dev.
`GET /reports` dan `GET /route` awam; `POST /reports` perlukan log masuk.

## Mod demo

Tekan ikon akaun di peta, hidupkan **Mod demo pemanduan**. Lokasi palsu bergerak di sepanjang laluan
melalui saluran GPS yang sama, dan butang **Lencong** tunjuk re-route. Tanpa mod demo, navigasi
mengikut GPS peranti dan perlukan kebenaran lokasi.

## Ujian

```bash
# Flutter
flutter test

# Backend (dalam Docker, tak perlu Go)
cd backend
docker run --rm -v "$PWD:/src" -w /src golang:1.26-alpine go test ./...
```

Ujian backend guna pelayan palsu untuk Valhalla dan Nominatim, jadi tak perlukan data atau rangkaian.
Ujian yang menyentuh pangkalan data (daftar, log masuk, simpan report) belum ada.

## Nota

- API membenarkan CORS dari mana-mana asal (`*`) buat masa ini. Ketatkan sebelum deploy.
- Plugin MapLibre tak menyokong Windows desktop. Guna web, Android atau iOS.
- Navigasi tiada suara dan tiada data trafik.
