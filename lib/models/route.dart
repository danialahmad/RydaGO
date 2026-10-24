import 'package:maplibre_gl/maplibre_gl.dart';

/// One step of a route: "turn right onto Jalan B".
class Maneuver {
  const Maneuver(this.text, this.type, this.km, this.index, {this.street = ''});

  final String text; // full Malay instruction, also what the voice says
  final String street; // street name only, shown large in the banner ('' if none)
  final int type; // Valhalla maneuver type, mapped to an icon in the UI
  final double km;
  final int index; // index into RouteOption.points where this step begins

  static Maneuver fromJson(Map<String, dynamic> j) => Maneuver(
        j['text'] as String,
        j['type'] as int,
        (j['km'] as num).toDouble(),
        j['index'] as int,
        street: (j['street'] as String?) ?? '',
      );
}

/// One way to get to the destination, as returned by `GET /route`.
class RouteOption {
  const RouteOption(
    this.label,
    this.minutes,
    this.km,
    this.note,
    this.points,
    this.maneuvers, {
    this.via = '',
  });

  final String label; // "Terpantas", "Tanpa tol", "Jarak terpendek"
  final int minutes;
  final double km;
  final String note;
  final String via; // street the route follows for longest ('' if unknown)
  final List<LatLng> points;
  final List<Maneuver> maneuvers;

  static RouteOption fromJson(Map<String, dynamic> j) => RouteOption(
        j['label'] as String,
        j['minutes'] as int,
        (j['km'] as num).toDouble(),
        j['note'] as String,
        [
          for (final p in j['points'] as List)
            LatLng((p[0] as num).toDouble(), (p[1] as num).toDouble()),
        ],
        [
          for (final m in j['maneuvers'] as List)
            Maneuver.fromJson(m as Map<String, dynamic>),
        ],
        via: (j['via'] as String?) ?? '',
      );
}
