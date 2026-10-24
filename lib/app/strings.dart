import 'package:flutter/widgets.dart';

/// Languages the app can show. English is the default.
enum AppLang {
  en('English', 'en', 'en-US'),
  ms('Bahasa Melayu', 'ms', 'ms-MY');

  const AppLang(this.nativeName, this.code, this.ttsLocale);
  final String nativeName;
  final String code; // sent to the API as ?lang=
  final String ttsLocale; // spoken-instruction voice
}

/// Every piece of text the user sees or hears, in both languages side by side so
/// a missing translation is obvious in review. Plain Dart (no code generation).
///
/// Widgets use `S.of(context)`; code without a context (voice, tests) builds one
/// with `S(AppLang.en)`.
class S {
  const S(this.lang);
  final AppLang lang;

  bool get ms => lang == AppLang.ms;
  String _t(String en, String ms) => this.ms ? ms : en;

  /// The nearest [StringsScope]'s strings, and rebuilds when the language changes.
  static S of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StringsScope>()?.strings ??
      const S(AppLang.en);

  // ---- general ----
  String get appName => 'Waze Revamp';
  String get cancel => _t('Cancel', 'Batal');
  String get close => _t('Close', 'Tutup');
  String get back => _t('Back', 'Kembali');
  String get retry => _t('Try again', 'Cuba lagi');
  String get done => _t('Done', 'Selesai');
  String get remove => _t('Remove', 'Buang');
  String get change => _t('Change', 'Tukar');
  String get set => _t('Set', 'Tetapkan');
  String get home => _t('Home', 'Rumah');
  String get work => _t('Work', 'Kerja');

  // ---- formatting ----
  String get hourAbbr => _t('h', 'j');
  String get minAbbr => 'min';
  String get kmh => _t('km/h', 'km/j');
  String get am => _t('AM', 'PG');
  String get pm => _t('PM', 'PTG');

  // ---- home / search ----
  String get favoritesHeader => _t('FAVOURITES', 'KEGEMARAN');
  String get recentHeader => _t('RECENT', 'TERBARU');
  String get whereTo => _t('Where to?', 'Mau ke mana?');
  String get setHomeSub => set;
  String get searchHint =>
      _t('Search address or place', 'Cari alamat atau tempat');
  String get searchEmpty => _t(
    'Type a place, street or address to start.',
    'Taip nama tempat, jalan atau alamat untuk bermula.',
  );
  String get noResults => _t('No results found', 'Tiada hasil dijumpai');
  String get searchFailed => _t(
    'Search is unreachable. The search server may still be starting, try again shortly.',
    'Carian tak dapat dihubungi. Pelayan carian mungkin masih bersedia, cuba lagi sebentar.',
  );
  String get tapToSet => _t('Tap to set', 'Tekan untuk tetapkan');
  String get setHomeTitle => _t('Set home', 'Tetapkan rumah');
  String get setWorkTitle => _t('Set work', 'Tetapkan tempat kerja');
  String homeSet(String name) =>
      _t('Home set: $name', 'Rumah ditetapkan: $name');
  String workSet(String name) =>
      _t('Work set: $name', 'Tempat kerja ditetapkan: $name');
  String get removeFavorite =>
      _t('Remove from favourites', 'Buang daripada kegemaran');
  String get addFavorite => _t('Add to favourites', 'Tambah ke kegemaran');
  String removedFavorite(String name) =>
      _t('$name removed from favourites', '$name dibuang daripada kegemaran');
  String get undo => _t('Undo', 'Asal semula');
  String get myLocation => _t('My location', 'Lokasi saya');
  String get menuTooltip => _t('Menu and settings', 'Menu dan tetapan');

  // ---- map status ----
  String get demoBanner => _t(
    'Demo mode: fake location and driving',
    'Mod demo: lokasi dan pemanduan palsu',
  );
  String get locating =>
      _t('Finding your location...', 'Mencari lokasi anda...');
  String get locDenied => _t(
    'Location not allowed. Using a sample location (KLCC)',
    'Lokasi tak dibenarkan. Guna lokasi contoh (KLCC)',
  );
  String get locUnavailable => _t(
    'GPS unavailable. Using a sample location (KLCC)',
    'GPS tak tersedia. Guna lokasi contoh (KLCC)',
  );
  String get waitingGps =>
      _t('Waiting for GPS signal...', 'Menunggu isyarat GPS...');

  // ---- pin ----
  String get pinTitle => _t('Dropped pin', 'Lokasi dipilih');
  String get go => _t('Go', 'Pergi');
  String get reportShort => _t('Report', 'Lapor');

  // ---- route preview ----
  String get findingRoutes =>
      _t('Finding the best routes...', 'Mencari laluan terbaik...');
  String get routesFailed => _t(
    'Could not load routes. The routing server may still be starting (the first start takes a while).',
    'Laluan tak dapat dimuatkan. Pelayan laluan mungkin masih bersedia (kali pertama ambil masa).',
  );
  String get start => _t('Start', 'Mula');
  String get needGps => _t(
    'Navigation needs GPS. Allow location access or turn on demo mode in Settings.',
    'Navigasi perlukan GPS. Benarkan akses lokasi atau hidupkan mod demo dalam Tetapan.',
  );
  String arrive(String time) => _t('Arrive $time', 'Tiba $time');
  String via(String road) => _t('via $road', 'Melalui $road');
  String get tagFastest => _t('Fastest', 'Terpantas');
  String get tagSame => _t('Same speed', 'Sama laju');
  String tagSlower(int min) => '+$min min';
  String get noToll => _t('No toll', 'Tiada tol');
  String tollEstimate(String rm) => _t('Toll ≈ RM$rm', 'Tol ≈ RM$rm');
  String tollDetail(String km, String rm) => _t(
    '$km km of toll road · estimate ≈ RM$rm',
    '$km km jalan tol · anggaran ≈ RM$rm',
  );
  String get tollDisclaimer => _t(
    'Toll prices are estimates for a class 1 car, not official rates.',
    'Harga tol ialah anggaran untuk kereta kelas 1, bukan kadar rasmi.',
  );

  // ---- navigation ----
  String get recalculating =>
      _t('Recalculating...', 'Mengira semula laluan...');
  String get arrived => _t('You have arrived', 'Anda telah sampai');
  String get then => _t('Then', 'Kemudian');
  String get muteVoice => _t('Mute voice', 'Senyapkan suara');
  String get unmuteVoice => _t('Unmute voice', 'Hidupkan suara');
  String get shareEta => _t('Share ETA', 'Kongsi ETA');
  String get mute => _t('Mute', 'Senyap');
  String get voice => _t('Voice', 'Suara');
  String get end => _t('End', 'Tamat');
  String get detourDemo => _t('Detour (demo)', 'Lencong (demo)');
  String get destination => _t('destination', 'destinasi');
  String etaText(String dest, String time) => _t(
    "I'll arrive at $dest at $time.",
    'Saya akan sampai di $dest pada $time.',
  );
  String get etaCopied =>
      _t('ETA copied. Paste it to share.', 'ETA disalin. Tampal untuk kongsi.');

  // ---- reports ----
  String get reportWhat => _t('What do you see?', 'Apa yang anda nampak?');
  String get signInFirst => _t(
    'Sign in first to send a report.',
    'Log masuk dahulu untuk membuat laporan.',
  );
  String reported(String type, String sub) => _t(
    'Thanks! $type ($sub) reported.',
    'Terima kasih! $type ($sub) dilaporkan.',
  );
  String get sessionExpiredReport => _t(
    'Session expired. Please sign in again.',
    'Sesi tamat. Sila log masuk semula.',
  );
  String get reportFailed => _t(
    'Could not send the report. The server is unreachable.',
    'Gagal hantar laporan. Server tak dapat dihubungi.',
  );
  String stillThere(String name) =>
      _t('$name still there?', '$name masih ada?');
  String get yes => _t('Yes', 'Ya');
  String get no => _t('No', 'Tiada');
  String get voteOk => _t(
    'Thanks! Your answer helps other drivers.',
    'Terima kasih! Jawapan anda membantu pemandu lain.',
  );
  String get voteOwn =>
      _t('This is your own report.', 'Ini laporan anda sendiri.');
  String get voteSession => _t(
    'Session expired. Sign in again to answer.',
    'Sesi tamat. Log masuk semula untuk menjawab.',
  );
  String get voteFailed => _t(
    'Could not send your answer. Try again.',
    'Jawapan tak dapat dihantar. Cuba lagi.',
  );

  /// Name of a report type / subtype for display. [typeKey] is `ReportType.name`.
  String reportType(String typeKey, String english) =>
      ms ? (_msTypes[typeKey] ?? english) : english;
  String reportSubtype(String subKey, String english) =>
      ms ? (_msSubtypes[subKey] ?? english) : english;

  /// How the voice and pills say a report: "Hidden police" is awkward, so
  /// English reads "Police, hidden" and Malay "Polis tersembunyi".
  String reportSpoken(String type, String? sub) {
    if (sub == null) return type;
    if (sub.toLowerCase().contains(type.toLowerCase())) {
      return sub; // "Speed camera"
    }
    return ms ? '$type ${sub.toLowerCase()}' : '$type, ${sub.toLowerCase()}';
  }

  static const _msTypes = {
    'police': 'Polis',
    'jam': 'Kesesakan',
    'accident': 'Kemalangan',
    'hazard': 'Bahaya',
    'camera': 'Kamera',
    'closed': 'Jalan tutup',
  };
  static const _msSubtypes = {
    'visible': 'Kelihatan',
    'hidden': 'Tersembunyi',
    'other_side': 'Di sebelah lain',
    'moderate': 'Sederhana',
    'heavy': 'Teruk',
    'standstill': 'Terhenti',
    'minor': 'Kecil',
    'major': 'Besar',
    'object': 'Objek di jalan',
    'pothole': 'Lubang',
    'stopped_vehicle': 'Kenderaan rosak',
    'construction': 'Kerja jalan',
    'broken_light': 'Lampu isyarat rosak',
    'weather': 'Cuaca buruk',
    'speed': 'Kamera kelajuan',
    'red_light': 'Kamera lampu merah',
    'road': 'Jalan ditutup',
    'lane': 'Lorong ditutup',
  };

  // ---- voice ----
  String reportAhead(String name, int metres) =>
      _t('$name ahead, $metres meters', '$name di hadapan, $metres meter');
  String speedingVoice(int limit) => _t(
    'You are over the speed limit, $limit kilometers per hour',
    'Anda melebihi had laju, $limit kilometer sejam',
  );
  String get arrivedVoice => _t(
    'You have arrived at your destination',
    'Anda telah sampai di destinasi',
  );
  String get reroutingVoice =>
      _t('Recalculating route', 'Mengira semula laluan');
  String inDistance(int metres, String instruction) => _t(
    'In $metres meters, $instruction',
    'Dalam $metres meter, $instruction',
  );

  // ---- account ----
  String get notSignedIn => _t('Not signed in', 'Belum log masuk');
  String get signInToReport =>
      _t('Sign in to send reports', 'Log masuk untuk menghantar laporan');
  String get canReport =>
      _t('You can send reports', 'Boleh menghantar laporan');
  String get signIn => _t('Sign in', 'Log masuk');
  String get signOut => _t('Sign out', 'Log keluar');
  String get register => _t('Register', 'Daftar');
  String get createAccount => _t('Create account', 'Daftar akaun');
  String get accountNeeded => _t(
    'An account is needed to send road reports.',
    'Akaun diperlukan untuk menghantar laporan jalan raya.',
  );
  String get password => _t('Password', 'Kata laluan');
  String get passwordHelp =>
      _t('At least 8 characters', 'Sekurang-kurangnya 8 aksara');
  String get haveAccount =>
      _t('Already have an account? Sign in', 'Dah ada akaun? Log masuk');
  String get noAccount =>
      _t('No account yet? Register', 'Belum ada akaun? Daftar');
  String get serverUnreachable =>
      _t('Cannot reach the server', 'Server tak dapat dihubungi');
  String authError(int status, String? serverMessage) {
    if (status == 0) return serverUnreachable;
    switch (status) {
      case 401:
        return _t('Wrong email or password', 'Email atau kata laluan salah');
      case 409:
        return _t(
          'That email is already registered',
          'Email sudah didaftarkan',
        );
      case 400:
        return _t(
          'Check your email and password (8 to 72 characters)',
          'Semak email dan kata laluan anda (8 hingga 72 aksara)',
        );
    }
    return serverMessage ?? _t('Error ($status)', 'Ralat ($status)');
  }

  // ---- settings ----
  String get settings => _t('Settings', 'Tetapan');
  String get mySpots => _t('MY PLACES', 'TEMPAT SAYA');
  String get notSet => _t('Not set', 'Belum ditetapkan');
  String get noFavorites => _t('No favourites', 'Tiada kegemaran');
  String get favoritesHint => _t(
    'Tap the star on a search result to save it',
    'Tekan bintang pada hasil carian untuk simpan',
  );
  String get navigationSection => _t('NAVIGATION', 'NAVIGASI');
  String get voiceGuidance => _t('Voice guidance', 'Arahan suara');
  String get voiceGuidanceSub => _t(
    'Speak upcoming turns aloud, in the app language',
    'Sebut belokan seterusnya dalam bahasa aplikasi',
  );
  String get avoidTolls => _t('Avoid tolls', 'Elak tol');
  String get avoidTollsSub =>
      _t('Pick the toll-free route first', 'Pilih laluan tanpa tol dahulu');
  String get speedAlert => _t('Speeding alert', 'Amaran memandu laju');
  String get speedAlertSub => _t(
    'The speedometer turns red and a voice warns you when you go over the limit. '
        'The limit is only known on some roads.',
    'Meter jadi merah dan suara memberi amaran bila melebihi had laju. '
        'Had hanya diketahui pada sesetengah jalan.',
  );
  String get alertOff => _t('Off', 'Mati');
  String get alertAtLimit => _t('At limit', 'Tepat had');
  String alertPlus(int n) => '+$n $kmh';
  String get displaySection => _t('DISPLAY', 'PAPARAN');
  String get themeAuto => 'Auto';
  String get themeLight => _t('Light', 'Cerah');
  String get themeDark => _t('Dark', 'Gelap');
  String get languageSection => _t('LANGUAGE', 'BAHASA');
  String get languageSub => _t(
    'Used for the app, voice guidance and route directions.',
    'Digunakan untuk app, arahan suara dan arahan laluan.',
  );
  String get developerSection => _t('DEVELOPER', 'PEMBANGUN');
  String get demoMode => _t('Demo driving mode', 'Mod demo pemanduan');
  String get demoModeSub => _t(
    'A fake location moves along the route. Real GPS is ignored. Handy for previews without driving.',
    'Lokasi palsu bergerak di sepanjang laluan. GPS sebenar diabaikan. Berguna untuk pratonton tanpa memandu.',
  );
  String get aboutSection => _t('ABOUT', 'TENTANG');
  String get version =>
      _t('Version 0.1.0 · independent project', 'Versi 0.1.0 · projek bebas');
  String get credits => _t(
    'Map © OpenStreetMap contributors, served by OpenFreeMap. '
        'Routing by Valhalla and search by Nominatim, both self-hosted. '
        'This project is not affiliated with Waze or Google.',
    'Peta © penyumbang OpenStreetMap, dihidangkan oleh OpenFreeMap. '
        'Laluan oleh Valhalla, carian oleh Nominatim, kedua-duanya dijalankan sendiri. '
        'Projek ini tiada kaitan dengan Waze atau Google.',
  );
}

/// Makes [strings] available to the whole widget tree through `S.of(context)`.
class StringsScope extends InheritedWidget {
  const StringsScope({super.key, required this.strings, required super.child});
  final S strings;

  @override
  bool updateShouldNotify(StringsScope old) => old.strings.lang != strings.lang;
}
