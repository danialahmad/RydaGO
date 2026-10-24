# Pelan kerja seterusnya

Disusun daripada `docs/FEATURES.md` (lihat di sana untuk senarai penuh dan alasan).
Susunan ialah cadangan; ubah ikut keperluan. Setiap item ada **bila dikira siap**.

## Peringkat 1: sebelum dibuka kepada orang lain

Tanpa ini data komuniti tak boleh dipercayai atau tak selamat.

1. **Anti-spam dan keselamatan asas**
   - Had kadar pada `/auth/*` dan `POST /reports` (per IP dan per pengguna).
   - Ketatkan CORS kepada asal app. Tukar semua nilai dev (kata laluan, JWT) dalam deploy.
   - Siap bila: satu pengguna tak boleh hantar >N laporan seminit; ujian membuktikannya.
2. **"Masih ada?" (sahkan/buang laporan)**
   - Endpoint `POST /reports/{id}/vote` (`up`/`down`), jadual `report_votes`, jangka hayat laporan
     dilanjutkan oleh undi naik dan dibuang oleh undi turun.
   - UI: pil amaran berdekatan ada 👍 / 👎 semasa memandu.
   - Siap bila: laporan dengan 3 undi turun hilang dari `GET /reports`.
3. **Padam akaun dan data** (`DELETE /me`) + skrin dalam Tetapan. Diperlukan kedai app dan PDPA.
4. **Ujian pangkalan data**: daftar, log masuk, simpan dan baca laporan, undi. Guna kontena `postgis` sementara.

## Peringkat 2: pengalaman memandu sebenar

5. **Uji pada Android sebenar** (dan pasang `flutter doctor` penuh). Betulkan apa yang pecah.
   Alamat API untuk emulator: `API_URL=http://10.0.2.2:8081`.
6. **Skrin kekal hidup** (`wakelock_plus`) dan **navigasi di latar belakang** dengan notifikasi
   (perkhidmatan latar Android). Tanpa ini navigasi berhenti bila skrin mati.
7. **Had laju dan amaran memandu laju**: ambil `maxspeed` (Valhalla `trace_attributes` pada laluan, atau
   lapisan OSM), tanda had laju di bubble kelajuan, bubble jadi merah melebihi had.
8. **Amaran suara untuk laporan di hadapan**: perluas `VoicePlanner` (sudah ada struktur "jauh/dekat").
9. **HTTPS** untuk web supaya GPS berfungsi di telefon tanpa helah. Caddy dalam compose dengan sijil
   dalaman atau domain sebenar.

## Peringkat 3: kandungan

10. **Tempat (POI)**: import Nominatim `full`, atau sumber POI lain, supaya "Masjid Negara" dijumpai.
    Kemudian kategori pantas (minyak, makan, parkir) dan "tambah perhentian".
11. **Segerak tempat simpanan** antara peranti (jadual `saved_places`, `/me/places`).
12. **Pilihan laluan lanjut**: elak lebuh raya/feri, motosikal, laluan alternatif sebenar, harga tol.

## Peringkat 4: lebih besar

13. **Trafik masa nyata**: kumpul kelajuan pemandu per segmen jalan (dengan persetujuan dan tanpa
    mengenal pasti individu), warnakan jalan, masukkan ke dalam anggaran masa. Kerja besar; reka dahulu.
14. iOS, Android Auto / CarPlay.
15. Peta offline; gamifikasi; lebih bahasa.

## Perkara yang perlu diputuskan oleh pemilik projek

- **Nama dan identiti sendiri** (bukan "Waze"; lihat `docs/DESIGN.md`).
- Siapa yang menjalankan pelayan, dan kos: Valhalla + Nominatim memerlukan beberapa GB RAM dan disk.
  Satu VPS 4 teras / 16 GB mencukupi untuk Malaysia.
- Polisi privasi dan berapa lama laporan/lokasi disimpan.
- Moderasi: siapa menimbang laporan palsu bila pengguna bertambah.
