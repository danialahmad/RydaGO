# Reka bentuk UI

[English](../en/DESIGN.md) · **Bahasa Melayu**

Matlamat: **mudah dipakai semasa memandu**, dengan rasa yang biasa kepada pengguna app navigasi
komuniti, tetapi dengan identiti dan ikon sendiri.

## Prinsip

1. **Satu skrin utama.** Peta sentiasa penuh. Semua yang lain ialah panel yang meluncur dari bawah atau
   butang bulat yang terapung. Kurangkan pertukaran halaman penuh.
2. **Jari besar.** Sasaran sentuh sekurang-kurangnya 52 px; butang utama 56 px; butang lapor 64 px.
   Semasa memandu, teks penting (jarak belokan) 38 px tebal.
3. **Satu tindakan utama setiap peringkat**, dan ia berwarna:
   *hijau* = pergi (Mula, Selesai), *oren* = lapor, *merah* = hentikan (Tamat).
4. **Tunjuk keadaan, jangan diam.** Memuat, ralat dan "tiada" semuanya ada teks yang jelas (kedua-dua bahasa) dan
   tindakan seterusnya (cuba lagi, hidupkan demo, benarkan lokasi). Tiada butang yang tak berfungsi.
5. **Cerah dan gelap** sama-sama kelas pertama. Peta mengikut tema.
6. **Bahasa**: English lalai, Melayu pilihan. Santai tapi sopan, ayat pendek. "Where to?" / "Mau ke mana?", "You have arrived" / "Anda telah sampai".

## Peringkat skrin utama (`ui/screens/map_screen.dart`)

| Peringkat | Panel bawah | Atas | Kanan bawah |
|---|---|---|---|
| Menyemak | `HomePanel`: bar "Mau ke mana?" + Rumah / Kerja / kegemaran | Butang menu, cip status lokasi | Lokasi saya, Lapor |
| Pin diletak | `PinPanel`: "Lokasi dipilih" + Pergi / Lapor | sama | sama |
| Pratonton | `RoutePreviewPanel`: kad laluan + **Mula** | sama | sama |
| Memandu | `NavBottomBar`: waktu tiba, baki, kemajuan, Kongsi / Senyap / Tamat | `NavBanner` gelap, pil laporan berdekatan, butang suara | Bubble kelajuan (kiri), Lapor |
| Tiba | bar "Anda telah sampai" + **Selesai** | banner "Anda telah sampai" | |

Skrin penuh lain: `SearchScreen` (carian), `SettingsScreen`, `LoginScreen`.
Lembaran: `ReportSheet` (grid jenis, kemudian subjenis).

## Token (`lib/app/theme.dart`)

| Nama | Nilai | Kegunaan |
|---|---|---|
| `AppColors.brand` | `#2DB7F5` | Garis laluan, titik lokasi, keadaan aktif |
| `AppColors.brandDeep` | `#1597D6` | Teks dan butang pada latar cerah |
| `AppColors.go` | `#2FBF71` | Mula, Selesai, "Terpantas" |
| `AppColors.report` | `#FF7A1A` | Butang lapor |
| `AppColors.danger` | `#E5484D` | Tamat, destinasi, ralat |
| `AppColors.banner` | `#0B1220` | Banner belokan |
| `AppColors.ink` / `muted` | `#0E1A2B` / `#6B7A8C` | Teks utama / sekunder |

Bentuk: lembaran bawah jejari 28, kad 20, butang 18, bar carian 30 (penuh). Bayang jelas
(`elevation` 5 hingga 16) supaya butang kelihatan di atas peta yang sibuk.
Warna jenis laporan ada pada `ReportType` (`lib/models/report.dart`).

## Ikon dan penjenamaan

- **Hanya ikon Material.** Tiada logo, maskot atau ikon pihak ketiga. Ikon penanda peta dilukis
  semasa jalan daripada ikon Material (`ui/map/marker_images.dart`).
- Nama **"RydaGO"** ialah nama kerja projek. **Jangan guna "Waze"** pada nama app, ikon, atau
  kedai app: ia tanda dagangan. Pilih nama sendiri sebelum diterbitkan (ganti `title` dalam
  `main.dart`, `web/manifest.json`, `web/index.html`, `AndroidManifest.xml`, `pubspec.yaml`).
- Skrin Tetapan > Tentang sudah menyatakan projek ini bebas. Kekalkan.
- **Kredit peta wajib kelihatan**: © penyumbang OpenStreetMap dan OpenFreeMap. Kawalan atribusi MapLibre
  di kanan atas ialah cara ia dipatuhi. Jangan sembunyikannya.

## Menambah ciri UI: senarai semak

1. Warna dan jejari dari `AppColors` / tema, jangan tulis nilai baru di dalam widget.
2. Sediakan keadaan **memuat**, **ralat** dan **kosong**.
3. Uji mod **gelap** dan skrin kecil (360 px lebar).
4. Teks baru: tambah dalam `lib/app/strings.dart` (English dan Melayu); masa guna `formatClock`, jarak guna `formatDistance`.
5. Kalau widget menunjuk nombor yang berubah semasa memandu, jangan bina semula seluruh skrin:
   `ref.watch(navProvider.select(...))` atau widget kecil sendiri.
