# Senarai ciri: apa yang Waze ada, dan di mana kita berada

Dokumen ini ialah rujukan utama untuk "apa yang patut kita bina seterusnya". Ia disusun daripada
kajian ciri Waze (sumber di hujung), dan setiap ciri ada status dalam app kita.

**Legenda:** ✅ siap · 🟡 separa / ada had · ⬜ belum · ❌ sengaja tak buat

**Keutamaan** (lajur P): **1** = patut buat dahulu · **2** = bagus ada · **3** = nanti / tak penting.
Lajur "Perlu" menyebut apa yang perlu disediakan (backend, data, atau platform).

> Soal skop: Waze ialah produk dengan jutaan pengguna. Kita tak cuba menyalin semuanya. Ciri
> yang bergantung pada **data berskala besar** (trafik masa nyata, harga minyak, kelajuan
> had seluruh negara) ditanda jelas supaya tak dianggap mudah.

## 1. Peta dan lokasi

| Ciri | Status | P | Nota / Perlu |
|---|---|---|---|
| Titik lokasi bergerak dengan halo | ✅ | | `lib/ui/map/map_view.dart` |
| Kamera ikut dan berputar ikut arah perjalanan, condong 3D | ✅ | | Putar hanya bila laju > 5 km/j (arah GPS tak boleh dipercayai bila berhenti) |
| Butang "lokasi saya" | ✅ | | |
| Peta cerah dan gelap (tukar terus) | ✅ | | Tetapan: Auto / Cerah / Gelap. Auto ikut sistem, **bukan** matahari terbenam |
| Letak pin dengan tekan lama (web: klik dua kali), lalu "Pergi" atau "Lapor" | ✅ | | |
| Warna trafik pada jalan (merah, oren) | ⬜ | 1 | Perlu agregat kelajuan pemandu per segmen jalan. Kerja backend yang besar |
| Pemandu lain kelihatan di peta | ⬜ | 3 | Isu privasi. Fikir dahulu |
| Peta offline | ⬜ | 3 | |

## 2. Carian dan destinasi

| Ciri | Status | P | Nota / Perlu |
|---|---|---|---|
| "Mau ke mana?" dengan carian langsung (debounce 350 ms) | ✅ | | `search_screen.dart` |
| Rumah dan Kerja (pintasan di skrin utama) | ✅ | | Disimpan **pada peranti** sahaja |
| Kegemaran (bintang) dan Terbaru | ✅ | | Pada peranti. Segerak antara peranti belum ada |
| Cari tempat (kedai, masjid, pusat beli-belah) | 🟡 | 1 | Nominatim diimport gaya `address`: **tiada POI**. Tukar `NOMINATIM_IMPORT_STYLE=full` (3x masa dan disk), atau tambah sumber POI |
| Kategori pantas (minyak, makan, parkir) | ⬜ | 2 | Perlu POI dahulu |
| Carian suara | ⬜ | 3 | `speech_to_text` |
| Tambah perhentian di tengah jalan | ⬜ | 2 | Valhalla menyokong multi-lokasi. API `/route` perlu terima `via` |
| Kongsi lokasi / destinasi | ⬜ | 3 | |
| "Pergi nanti" (plan a drive, ingatan bila patut bertolak) | ⬜ | 3 | Perlu data trafik ramalan |

## 3. Pratonton laluan

| Ciri | Status | P | Nota / Perlu |
|---|---|---|---|
| Beberapa laluan dengan masa, waktu tiba, "+N min" berbanding terpantas | ✅ | | Tiga jenis: Terpantas, Tanpa tol, Jarak terpendek (satu panggilan Valhalla setiap satu) |
| "Melalui <jalan>" untuk setiap laluan | ✅ | | Jalan terpanjang dalam laluan |
| Pilihan "Elak tol" | ✅ | | Tetapan memilih laluan Tanpa tol dahulu |
| Elak lebuh raya | ✅ | | Tetapan > Avoid highways (`use_highways: 0`). Feri tersedia dalam API (`avoid=ferries`) tetapi belum ada dalam UI |
| Harga tol | ⬜ | 2 | Valhalla tak beri harga. Perlu jadual tol Malaysia |
| Masalah di laluan (kerja jalan, sesak) | ⬜ | 2 | Perlu data trafik/report di sepanjang laluan |
| Jenis kenderaan (motosikal, teksi, EV) | ⬜ | 2 | Valhalla ada costing `motorcycle`. Mudah untuk motosikal |
| Beberapa laluan alternatif sebenar (bukan sekadar 3 keutamaan) | ⬜ | 2 | Valhalla `alternates` |

## 4. Navigasi

| Ciri | Status | P | Nota / Perlu |
|---|---|---|---|
| Banner belokan: ikon, jarak, nama jalan | ✅ | | `nav_overlay.dart` |
| "Kemudian" (belokan kedua yang dekat) | ✅ | | Hanya bila dalam 500 m |
| Papan tanda keluar (nombor keluar dan "ke") | ✅ | | Dalam banner belokan, dari data Valhalla |
| Panduan lorong | 🟡 | | UI dan API siap, tetapi OSM jarang ada tag lorong di Malaysia jadi biasanya tiada |
| Zum ikut kelajuan dan jarak ke belokan | ✅ | | `navZoom` dalam `models/geo.dart` |
| Peta rata, jalan tebal, tiada bangunan 3D | ✅ | | `services/map_style.dart` |
| Ringkasan sebelum Start (laporan di laluan) | ✅ | | Kad laluan: kamera, polis, kemalangan di sepanjang laluan |
| Laluan alternatif sebenar | ✅ | | Sehingga 3 laluan berbeza; pendua digugurkan |
| Arahan suara (English dan Melayu) | 🟡 | | `flutter_tts`, ikut bahasa dipilih. Bergantung suara yang ada pada peranti/pelayar (mungkin tiada suara Melayu). Belum diuji pada telefon sebenar |
| Bar bawah: waktu tiba, baki masa dan jarak, "Melalui", kemajuan | ✅ | | Ketuk untuk kembangkan |
| Speedometer | ✅ | | Dari GPS |
| Tanda had laju | 🟡 | | Dari OSM `maxspeed` melalui Valhalla. Hanya ~1/3 jalan ada data; tanda hilang bila tak diketahui |
| Amaran memandu laju | 🟡 | | Meter jadi merah + amaran suara sekali. Tetapan: Mati / Tepat had / +5 / +10. Hanya di mana had diketahui |
| Kira semula laluan bila tersasar | ✅ | | `navigation.dart`: >120 m serta-merta, atau 3 fix >50 m; jeda 8 saat |
| Senyap / hidupkan suara | ✅ | | |
| Kongsi ETA | ✅ | | Pautan langsung (`/s/<token>`) yang dikemas kini setiap 10 s; tanpa log masuk jatuh balik ke salin teks |
| Skrin kekal hidup semasa navigasi | ⬜ | 1 | `wakelock_plus` |
| Navigasi di latar belakang + notifikasi | ⬜ | 1 | Perkhidmatan latar (native). Penting untuk telefon |
| Skrin tiba | ✅ | | "Anda telah sampai" + Selesai |
| Mod demo (tanpa memandu) | ✅ | | Bukan ciri Waze. Alat pembangun: Tetapan > Pembangun |

## 5. Komuniti: laporan

Waze ialah app komuniti; inilah ciri yang membezakannya.

| Ciri | Status | P | Nota / Perlu |
|---|---|---|---|
| Menu laporan dengan jenis besar | ✅ | | `report_sheet.dart`. 6 jenis |
| Subjenis (polis tersembunyi, trafik terhenti, lubang...) | ✅ | | Jadual penuh dalam `docs/API.md` |
| Laporan dipaparkan di peta dengan ikon | ✅ | | Muat semula setiap 15 saat |
| Amaran laporan berdekatan semasa memandu (visual) | ✅ | | Dalam 800 m |
| Amaran **suara** untuk laporan di hadapan | 🟡 | | Sekali setiap laporan, dalam 600 m, hanya di jalan laluan. Belum didengar pada telefon sebenar |
| "Masih ada?" (Ya / Tiada) untuk sahkan atau buang laporan | ✅ | | Kad muncul selepas melepasi laporan. 3 undi turun bersih menyembunyikan; undi naik melanjutkan hayat. Belum boleh undi dengan ketuk ikon di peta |
| Laporan tamat sendiri | 🟡 | | 2 jam untuk semua jenis (dilanjutkan undi naik). Waze beza ikut jenis |
| Cegah penyalahgunaan (spam, laporan palsu) | ⬜ | 1 | Had kadar per pengguna, undi, reputasi. **Wajib sebelum dibuka kepada orang ramai** |
| Laporan kemalangan dengan gambar, "chat peta", laporan isu peta | ⬜ | 3 | |
| Mata dan pangkat (gamifikasi) | ⬜ | 3 | |
| Laporan tak perlu log masuk | ❌ | | Sengaja: akaun diperlukan untuk kurangkan spam |

## 6. Akaun dan tetapan

| Ciri | Status | P | Nota / Perlu |
|---|---|---|---|
| Daftar, log masuk, log keluar (JWT, 7 hari) | ✅ | | Tiada "lupa kata laluan" atau pengesahan email |
| Skrin Tetapan (akaun, tempat saya, navigasi, paparan, pembangun, tentang) | ✅ | | |
| Segerak tempat simpanan antara peranti | ⬜ | 2 | Jadual `saved_places` di backend |
| Tetapan amaran ikut jenis laporan | ⬜ | 2 | |
| Unit (km / batu) | ⬜ | 3 | |
| Bahasa: English (lalai) dan Melayu, tukar dalam Tetapan | ✅ | | `lib/app/strings.dart`. Tambah bahasa baru = tambah nilai `AppLang` dan terjemahan dalam `S` |
| Pengesanan tol dan anggaran harga | 🟡 | | Tol dikesan dari Valhalla (OSM). **Harga ialah anggaran** ~11 sen/km kelas 1, bukan kadar rasmi PLUS. Perlu jadual plaza-ke-plaza untuk harga tepat |
| Padam akaun dan data | ⬜ | 1 | Diperlukan oleh kedai app dan PDPA |

## 7. Platform

| Platform | Status | Nota |
|---|---|---|
| Web (Chrome, telefon melalui Wi-Fi) | ✅ | GPS sebenar perlu HTTPS atau `localhost`. Lihat `docs/DEVELOPMENT.md` |
| Android | 🟡 | Kebenaran lokasi dan internet ditambah. **Belum pernah dijalankan** pada peranti. Untuk emulator guna `API_URL=http://10.0.2.2:8081` |
| iOS | ⬜ | Platform tak dijana (`flutter create --platforms=ios`). Perlu Mac |
| Android Auto / CarPlay | ⬜ | Kerja besar, platform berasingan |
| Windows desktop | ❌ | Plugin MapLibre tak menyokongnya |

## Cadangan urutan kerja

Lihat `docs/ROADMAP.md`. Ringkasnya: **keselamatan data dahulu** (anti-spam, undi "masih ada?",
padam akaun), kemudian **pengalaman memandu sebenar** (latar belakang, skrin hidup, had laju),
kemudian **kandungan** (POI, trafik).

## Sumber kajian

- [Customize your alerts, Waze Help](https://support.google.com/waze/answer/13786535?hl=en): jenis amaran dan laporan
- [Report police sightings](https://support.google.com/waze/answer/13739289?hl=en), [Report a crash](https://support.google.com/waze/answer/13739612?hl=en), [Report traffic](https://support.google.com/waze/answer/13740207?hl=en), [Report road hazards](https://support.google.com/waze/answer/13739290?hl=en): subjenis laporan (polis: kamera mudah alih / tersembunyi / sebelah lain; kemalangan: bertindih / sebelah lain; trafik: teruk / terhenti; bahaya: kerja jalan, kenderaan di bahu, lampu isyarat rosak, lubang, objek)
- [Drive to a destination, Waze Help](https://support.google.com/waze/answer/6262563?hl=en): Home/Work di bawah bar carian, "Go now" dan "Leave later"
- [Speedometer, Waze Help](https://support.google.com/waze/answer/6386895?hl=en): speedometer jadi merah bila melebihi had, tanda had laju, ambang kelajuan
- [Waze trip preview (9to5Google)](https://9to5google.com/2021/07/28/waze-trip-preview-tolls-traffic/): pratonton laluan dengan masa, tol, kerja jalan dan trafik
- [5 Waze settings drivers should enable (BGR)](https://www.bgr.com/2273264/waze-settings-drivers-should-enable/): tetapan navigasi (elak feri, lebuh raya, jalan tak berturap), jenis kenderaan
- Halaman rujukan [AppShots: Waze](https://appshots.design/apps/gps-maps-traffic-alerts-live-navigation-app-shot-waze): hanya beberapa skrin awam boleh dilihat tanpa log masuk (banner belokan gelap dengan nama jalan biru muda; panel bawah dengan waktu tiba besar, "min · km", "Via ...", bar kemajuan dan baris tindakan; bubble kelajuan dan butang laporan bulat). Selebihnya terkunci

Ciri yang hanya diketahui daripada pengetahuan am tentang Waze (belum disahkan daripada sumber di atas)
ialah: warna trafik pada jalan, pemandu lain di peta, mata dan pangkat, "chat peta", dan Android Auto / CarPlay.
