import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:maplibre_gl/maplibre_gl.dart';

const _apiUrlOverride = String.fromEnvironment('API_URL');

/// Where the API lives. `--dart-define=API_URL=...` wins. On web the API is
/// assumed to run on port 8081 of the same machine that served the page, so a
/// phone that opens http://192.168.1.100:8080 talks to http://192.168.1.100:8081
/// without a rebuild. Native builds default to localhost (Android emulator: 10.0.2.2).
String get kApiUrl {
  if (_apiUrlOverride.isNotEmpty) return _apiUrlOverride;
  if (kIsWeb && Uri.base.host.isNotEmpty) return 'http://${Uri.base.host}:8081';
  return 'http://localhost:8081';
}

/// OpenFreeMap vector styles (free, no API key, OpenStreetMap data).
const kMapStyleLight = 'https://tiles.openfreemap.org/styles/liberty';
const kMapStyleDark = 'https://tiles.openfreemap.org/styles/dark';

/// Fallback position (KLCC) used until the first real GPS fix, or when location
/// is denied or unavailable, so the app stays usable.
const kCenter = LatLng(3.1579, 101.7116);
