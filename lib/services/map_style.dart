import 'dart:convert';

import 'package:http/http.dart' as http;

/// Roads are drawn this many times thicker than the stock style at close zoom, so
/// lanes and junctions stay readable at a glance while driving. The extra width
/// fades in between zoom 13 and 16: the city overview keeps its normal weight.
const kRoadWidthScale = 1.7;

final _roadLayer = RegExp(r'^(road|tunnel|bridge)_');

bool _isRoad(Map<String, dynamic> l) {
  final id = l['id'] as String? ?? '';
  return l['type'] == 'line' &&
      l['source-layer'] == 'transportation' &&
      _roadLayer.hasMatch(id) &&
      !id.contains('rail') &&
      !id.contains('path');
}

/// Turns an OpenFreeMap style into a flat, road-first one for driving: no 3D
/// building extrusions (they tower over the road) and thicker roads.
/// Works on the decoded style JSON and returns a changed copy.
Map<String, dynamic> flattenStyle(Map<String, dynamic> style,
    {double roadScale = kRoadWidthScale}) {
  final out = jsonDecode(jsonEncode(style)) as Map<String, dynamic>;
  final layers = (out['layers'] as List).cast<Map<String, dynamic>>();
  layers.removeWhere((l) => l['type'] == 'fill-extrusion');
  for (final l in layers) {
    if (!_isRoad(l)) continue;
    final paint = l['paint'] as Map<String, dynamic>?;
    if (paint == null || paint['line-width'] == null) continue;
    paint['line-width'] = scaleWidth(paint['line-width'], roadScale);
  }
  return out;
}

/// The factor applied at [zoom]: 1 up to zoom 13, [k] from zoom 16, linear between.
double zoomFactor(double k, num zoom) =>
    1 + (k - 1) * ((zoom - 13) / 3).clamp(0.0, 1.0);

/// Multiplies a MapLibre `line-width` value by [k] (fading in with zoom, see
/// [zoomFactor]): a plain number, or the outputs of an `interpolate` / `step`
/// expression (the zoom input and the stop positions are left alone). Anything
/// else is returned unchanged.
Object? scaleWidth(Object? v, double k) {
  Object? scale(Object? o, num zoom) {
    final f = zoomFactor(k, zoom);
    return o is num ? _round(o * f) : ['*', _round(f), o];
  }

  if (v is num) return scale(v, 20); // no zoom dependence: full factor
  if (v is List && v.isNotEmpty) {
    if (v[0] == 'interpolate' && v.length >= 5) {
      return [
        for (var i = 0; i < v.length; i++)
          // ["interpolate", type, input, stop, out, stop, out ...]
          i >= 4 && i.isEven && v[i - 1] is num ? scale(v[i], v[i - 1] as num) : v[i],
      ];
    }
    if (v[0] == 'step' && v.length >= 3) {
      return [
        for (var i = 0; i < v.length; i++)
          // ["step", input, out0, stop1, out1 ...]
          i >= 2 && i.isEven ? scale(v[i], i == 2 ? 0 : (v[i - 1] as num)) : v[i],
      ];
    }
  }
  return v;
}

double _round(double x) => (x * 100).round() / 100;

/// Downloads the style at [url] and flattens it. Returns the style as a JSON
/// string, or null if it could not be fetched (the caller falls back to the URL).
Future<String?> loadFlatStyle(String url) async {
  try {
    final res = await http.get(Uri.parse(url)).timeout(const Duration(seconds: 15));
    if (res.statusCode != 200) return null;
    final style = jsonDecode(res.body) as Map<String, dynamic>;
    return jsonEncode(flattenStyle(style));
  } catch (_) {
    return null;
  }
}
