# Pelan kerja seterusnya

Disusun daripada `docs/FEATURES.md` (lihat di sana untuk senarai penuh dan alasan).
Susunan ialah cadangan; ubah ikut keperluan. Setiap item ada **bila dikira siap**.

## Peringkat 1: sebelum dibuka kepada orang lain

Tanpa ini data komuniti tak boleh dipercayai atau tak selamat.

1. **Anti-spam dan keselamatan asas**
   - Had kadar pada `/auth/*` dan `POST /reports` (per IP dan per pengguna).
   - Ketatkan CORS kepada asal app. Tukar semua nilai dev (kata laluan, JWT) dalam deploy.
   - Siap bila: satu pengguna tak boleh hantar >N laporan seminit; ujian membuktikannya.
2. **Padam akaun dan data** (`DELETE /me`) + skrin dalam Tetapan. Diperlukan kedai app dan PDPA.
3. **Padam laporan sendiri** dan undi dengan ketuk ikon di peta (undi kini hanya melalui kad "Masih ada?").

(Siap: "Masih ada?" dengan undi dan jangka hayat; ujian pangkalan data sebenar dalam `integration_test.go`.)

## Peringkat 2: pengalaman memandu sebenar

5. **Uji pada Android sebenar** (dan pasang `flutter doctor` penuh). Betulkan apa yang pecah.
   Alamat API untuk emulator: `API_URL=http://10.0.2.2:8081`.
6. **Skrin kekal hidup** (`wakelock_plus`) dan **navigasi di latar belakang** dengan notifikasi
   (perkhidmatan latar Android). Tanpa ini navigasi berhenti bila skrin mati.
7. **Tambah baik had laju**: liputan OSM `maxspeed` di Malaysia rendah (~1/3). Pertimbang tekaan ikut kelas
   jalan (dilabel "anggaran") atau sumbangan data ke OSM. Uji suara laporan/had laju pada telefon sebenar.
8. **HTTPS** untuk web supaya GPS berfungsi di telefon tanpa helah. Caddy dalam compose dengan sijil
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
