# Arahan untuk pembantu AI

Projek: app navigasi komuniti (Flutter web/mobile + API Go + Valhalla + Nominatim + PostGIS), Malaysia.
Mulakan dengan `README.md`, kemudian `docs/ARCHITECTURE.md` dan `docs/DEVELOPMENT.md`.
Senarai ciri dan keutamaan: `docs/FEATURES.md`, `docs/ROADMAP.md`.

## Perintah

```bash
docker compose up -d --build            # semua perkhidmatan (web di :8080, API di :8081)
flutter analyze && flutter test         # mesti bersih sebelum selesai
# Go tak dipasang pada mesin pembangun; jalankan dalam Docker (dari PowerShell, bukan Git Bash):
cd backend; docker run --rm -v "${PWD}:/src" -w /src golang:1.26-alpine sh -c "gofmt -l . ; go vet ./... ; go test ./..."
```

## Peraturan

- Teks yang pengguna nampak dalam **Bahasa Melayu**. Komen kod dalam bahasa fail sedia ada (kebanyakan Inggeris), jelaskan *kenapa*.
- **Kontrak jenis laporan** wujud di tiga tempat dan mesti sama: `backend/main.go` (`reportSubtypes`),
  `lib/models/report.dart` (`ReportType`), `docs/API.md`. Ujian kedua-dua sisi menjaganya.
- Semua panggilan HTTP dari app ada dalam `lib/services/api.dart`. Logik dalam `lib/state/`, bukan dalam widget.
  `lib/models` tulen (tiada import dari `state` atau `ui`).
- Navigasi hanya bertindak balas kepada `userLocProvider` (GPS). Mod demo menyuntik fix; jangan tambah laluan
  pintas dalam `NavNotifier` untuk demo.
- Hanya ikon Material. Jangan guna nama, logo atau maskot "Waze" dalam UI atau aset (lihat `docs/DESIGN.md`).
- Jangan commit `.env`, `data/`, `build/`. Nilai dalam `docker-compose.yml` ialah lalai dev yang awam.
- Tambah ujian bila menyentuh logik navigasi, API atau kontrak. Jalankan `flutter analyze` dan semua ujian sebelum melapor siap.
- Migrasi pangkalan data: fail baru dalam `backend/migrations/`; jangan ubah yang sedia ada.

## Perangkap (butiran dalam `docs/DEVELOPMENT.md`)

- Panggilan `/route` dan `/places` memulangkan 502 sebelum Valhalla/Nominatim `healthy` (data dibina kali pertama).
- Peta web: "tekan lama" = klik dua kali. Jangan guna `onMapClick` (klik hantu selepas widget hilang).
- Tukar tema peta dengan `controller.setStyle`, bukan tukar `styleString` widget.
- GPS sebenar tak jalan melalui `http://<ip>` (perlu HTTPS atau localhost); guna mod demo.
