# Rujukan API

Pangkalan: `http://localhost:8081` (atau `http://<ip-pc>:8081`). Semua respons JSON.
Ralat dalam bentuk `{"error": "mesej"}`.

Sumber kod: `backend/main.go`, `auth.go`, `route.go`, `places.go`. Ujian: `backend/*_test.go`.

## Ringkasan

| Kaedah | Laluan | Log masuk? | Fungsi |
|---|---|---|---|
| GET | `/health` | tidak | Semak API dan pangkalan data |
| POST | `/auth/register` | tidak | Daftar akaun, terus dapat token |
| POST | `/auth/login` | tidak | Log masuk |
| GET | `/reports` | tidak (token pilihan) | Laporan berdekatan yang masih sah |
| POST | `/reports` | **ya** | Hantar laporan |
| POST | `/reports/{id}/vote` | **ya** | "Masih ada?": undi naik atau turun |
| GET | `/route` | tidak | Tiga pilihan laluan dengan arahan belokan |
| GET | `/places` | tidak | Carian alamat atau tempat |

Pengesahan: `Authorization: Bearer <token>`. Token sah 7 hari.

## `GET /health`

`200 {"status":"ok"}`. `503 {"status":"db down"}` jika pangkalan data tak dapat dihubungi.

## `POST /auth/register`, `POST /auth/login`

Badan: `{"email": "a@b.my", "password": "kata-laluan-8-aksara"}`

- Email dinormalkan kepada huruf kecil.
- Kata laluan: 8 hingga 72 aksara (had bcrypt).
- Berjaya: `201` (daftar) atau `200` (log masuk) dengan `{"token": "...", "email": "a@b.my"}`.
- Ralat: `400` (JSON, email atau kata laluan tak sah), `409` (email sudah didaftarkan), `401` (email atau kata laluan salah. Mesej sama untuk kedua-duanya).

## `GET /reports?lat=&lng=&radius=`

- `lat`, `lng`: wajib. `radius`: meter, lalai 5000, maksimum 50000.
- Laporan kekal sah **2 jam** dari dibuat, atau dari undi naik terkini (undi naik melanjutkan hayatnya).
- Disembunyikan bila undi turun melebihi undi naik sekurang-kurangnya **3** (`down - up >= 3`).
- Terbaru dahulu, **maksimum 100**.
- Jika `Authorization: Bearer` yang sah dihantar, `mine` menunjukkan laporan milik pengguna itu. Token tak sah diabaikan (bukan 401).

```json
[
  {"id": 16, "type": "jam", "subtype": "standstill", "lat": 3.2359, "lng": 101.6989,
   "created_at": "2026-10-24T02:25:11Z", "up": 2, "down": 0, "mine": false}
]
```

`subtype` tiada dalam respons jika pelapor tak memberi butiran. `400` jika `lat`/`lng` tiada.

## `POST /reports/{id}/vote` (log masuk)

Badan: `{"vote": "up"}` (masih ada) atau `{"vote": "down"}` (sudah tiada). Satu undi bagi setiap pengguna
bagi setiap laporan; mengundi semula menukar undi sedia ada. `200 {"up": 3, "down": 1}` (jumlah terkini).
`400` id atau nilai undi tak sah, `401` tiada token, `403` laporan sendiri, `404` laporan tak wujud.

## `POST /reports` (log masuk)

```json
{"type": "police", "subtype": "hidden", "lat": 3.1579, "lng": 101.7116}
```

`subtype` pilihan. `201` dengan laporan yang disimpan (bentuk sama seperti di atas).
`400` jika jenis atau subjenis tak sah, koordinat di luar julat, atau badan lebih 16 KB. `401` jika token tiada atau tak sah.

### Jenis dan subjenis laporan

Subjenis pertama ialah lalai yang dihantar app. **Jadual ini mesti sama** dengan `reportSubtypes` dalam
`backend/main.go` dan `ReportType` dalam `lib/models/report.dart`. Ujian di kedua-dua sisi akan gagal jika berbeza.

| `type` | Label dalam app | `subtype` yang dibenarkan |
|---|---|---|
| `police` | Polis | `visible`, `hidden`, `other_side` |
| `accident` | Kemalangan | `minor`, `major`, `other_side` |
| `jam` | Kesesakan | `moderate`, `heavy`, `standstill` |
| `hazard` | Bahaya | `object`, `pothole`, `stopped_vehicle`, `construction`, `broken_light`, `weather` |
| `camera` | Kamera | `speed`, `red_light` |
| `closed` | Jalan tutup | `road`, `lane` |

## `GET /route?from=lat,lng&to=lat,lng`

Minta Valhalla tiga kali selari. Pulangkan hanya yang berjaya.

```jsonc
[
  {
    "label": "Terpantas",          // juga "Tanpa tol", "Jarak terpendek"
    "note": "Laluan terpantas",
    "via": "E12",                  // jalan paling panjang dalam laluan, boleh tiada
    "minutes": 6,
    "km": 4.9,
    "points": [[3.1579, 101.7116], [3.1580, 101.7120]],       // [lat, lng]
    "maneuvers": [
      {"text": "Mulakan perjalanan di Lorong Kuda", "street": "Lorong Kuda",
       "type": 1, "km": 0.39, "index": 0},
      {"text": "Anda telah sampai", "type": 4, "km": 0, "index": 164}
    ],
    "limits": [{"from": 0, "to": 40, "kmh": 60}]   // had laju; hanya di mana OSM tahu
  }
]
```

- `limits[]`: had laju dalam km/j untuk segmen `points[from]` hingga `points[to]`. Dianggar daripada Valhalla
  `trace_attributes`. Hanya kira-kira sepertiga jalan di Malaysia ada `maxspeed` dalam OSM, jadi senarai
  mungkin pendek atau kosong. App membawa had terakhir ke hadapan 400 m, selepas itu menyembunyikan tanda.
- `maneuvers[].index` ialah indeks dalam `points` di mana langkah bermula.
- `type` ialah [jenis belokan Valhalla](https://valhalla.github.io/valhalla/api/turn-by-turn/api-reference/):
  1-3 mula, 4-6 tiba, 9-16 belok, 17-24 ramp/jalan keluar/lorong, 25 bergabung, 26-27 bulatan.
  App memetakannya kepada ikon dalam `maneuverIcon` (`lib/ui/widgets/nav_overlay.dart`).
- `text` dibina di API dalam Bahasa Melayu (`maneuverText`). `street` ialah nama jalan sahaja.
- Ralat: `400` jika `from`/`to` bukan `lat,lng` yang sah; `502` jika semua panggilan Valhalla gagal (contohnya jubin masih dibina).
- Masa ialah anggaran Valhalla **tanpa trafik semasa**.

## `GET /places?q=&lat=&lng=`

- `q`: 2 hingga 200 aksara. `lat`, `lng` pilihan; jika ada, hasil berdekatan diutamakan (tidak terhad).
- Terhad kepada Malaysia, Singapura dan Brunei; nama Melayu diutamakan; maksimum 8 hasil.

```json
[{"name": "Batu Caves", "area": "Majlis Perbandaran Selayang, Selangor",
  "lat": 3.2369, "lng": 101.6833, "category": "place", "type": "town"}]
```

`category` dan `type` ialah nilai Nominatim (digunakan untuk memilih ikon: `iconForCategory` dalam
`lib/models/place.dart`). `400` jika `q` terlalu pendek atau panjang; `502` jika Nominatim tak sedia.

> Nominatim diimport dengan gaya `address` secara lalai, jadi **tempat seperti masjid dan pusat beli-belah
> tiada** (hanya jalan, kawasan, alamat). Lihat `docs/FEATURES.md`.

## Contoh dengan curl

```bash
curl localhost:8081/health
curl "localhost:8081/route?from=3.1579,101.7116&to=3.1602,101.7274"
curl "localhost:8081/places?q=batu%20caves"
# daftar, simpan token, hantar laporan
TOKEN=$(curl -s -X POST localhost:8081/auth/register -H 'Content-Type: application/json' \
  -d '{"email":"saya@contoh.my","password":"kata-laluan-8"}' | sed 's/.*"token":"\([^"]*\)".*/\1/')
curl -X POST localhost:8081/reports -H "Authorization: Bearer $TOKEN" -H 'Content-Type: application/json' \
  -d '{"type":"jam","subtype":"heavy","lat":3.1579,"lng":101.7116}'
```
