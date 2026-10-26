import 'package:maplibre_gl/maplibre_gl.dart';

/// One step of a route: "turn right onto Jalan B".
class Maneuver {
  const Maneuver(
    this.text,
    this.type,
    this.km,
    this.index, {
    this.street = '',
    this.exit = '',
    this.toward = '',
    this.lanes = const [],
  });

  final String
  text; // full instruction in the app language, also what the voice says
  final String
  street; // street name only, shown large in the banner ('' if none)
  final int type; // Valhalla maneuver type, mapped to an icon in the UI
  final double km;
  final int index; // index into RouteOption.points where this step begins
  final String exit; // exit number on the road sign, e.g. "3310A" ('' if none)
  final String toward; // destinations on the sign, e.g. "Gombak / Batu Caves"
  final List<Lane> lanes; // only where OpenStreetMap has lane data

  static Maneuver fromJson(Map<String, dynamic> j) => Maneuver(
    j['text'] as String,
    j['type'] as int,
    (j['km'] as num).toDouble(),
    j['index'] as int,
    street: (j['street'] as String?) ?? '',
    exit: (j['exit'] as String?) ?? '',
    toward: (j['toward'] as String?) ?? '',
    lanes: [
      for (final l in (j['lanes'] as List? ?? const []))
        Lane.fromJson(l as Map<String, dynamic>),
    ],
  );
}

/// One lane at a maneuver: where it leads, whether it can make the maneuver, and
/// whether it is the best one to be in.
class Lane {
  const Lane(this.dirs, {this.valid = false, this.active = false});

  final List<String> dirs; // left, slight_left, straight, slight_right, right ...
  final bool valid;
  final bool active;

  static Lane fromJson(Map<String, dynamic> j) => Lane(
    [for (final d in (j['dirs'] as List? ?? const [])) d as String],
    valid: (j['valid'] as bool?) ?? false,
    active: (j['active'] as bool?) ?? false,
  );
}

/// The posted speed limit along route points [from]..[to]. Only stretches where
/// OpenStreetMap knows the limit are listed, so a gap means "unknown".
class SpeedLimit {
  const SpeedLimit(this.from, this.to, this.kmh);

  final int from;
  final int to;
  final int kmh;

  static SpeedLimit fromJson(Map<String, dynamic> j) =>
      SpeedLimit(j['from'] as int, j['to'] as int, j['kmh'] as int);
}

/// Toll roads on a route. [rm] is an estimate for a class 1 car, not an official rate.
class Toll {
  const Toll(this.km, this.rm, {this.estimate = true});

  final double km; // length driven on toll roads
  final double rm; // estimated total price in ringgit
  final bool estimate;

  static Toll fromJson(Map<String, dynamic> j) => Toll(
    (j['km'] as num).toDouble(),
    (j['rm'] as num).toDouble(),
    estimate: (j['estimate'] as bool?) ?? true,
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
    this.limits = const [],
    this.id = '',
    this.toll,
  });

  final String id; // stable across languages: "fastest", "notoll", "shortest"
  final String label; // translated name of the route type
  final int minutes;
  final double km;
  final String note;
  final String via; // street the route follows for longest ('' if unknown)
  final List<LatLng> points;
  final List<Maneuver> maneuvers;
  final List<SpeedLimit> limits; // sorted by [SpeedLimit.from]
  final Toll? toll; // null when the route uses no toll road

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
    id: (j['id'] as String?) ?? '',
    toll: j['toll'] == null
        ? null
        : Toll.fromJson(j['toll'] as Map<String, dynamic>),
    via: (j['via'] as String?) ?? '',
    limits: [
      for (final l in (j['limits'] as List? ?? const []))
        SpeedLimit.fromJson(l as Map<String, dynamic>),
    ],
  );
}
