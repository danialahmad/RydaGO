import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../app/strings.dart';

/// One refinement of a report type, e.g. police: "Hidden". [label] is English;
/// [localLabel] gives the label in the app language.
/// [key] is what the API stores; the first subtype of a type is the default.
class ReportSubtype {
  const ReportSubtype(this.key, this.label);
  final String key;
  final String label;

  String localLabel(S s) => s.reportSubtype(key, label);
}

/// The kinds of report a driver can make. [name] and each subtype key must match
/// the API (`reportSubtypes` in backend/main.go, documented in docs/en/API.md and docs/ms/API.md).
enum ReportType {
  police('Police', Icons.local_police, Color(0xFF3F51B5), [
    ReportSubtype('visible', 'Visible'),
    ReportSubtype('hidden', 'Hidden'),
    ReportSubtype('other_side', 'Other side'),
  ]),
  jam('Traffic jam', Icons.traffic, Color(0xFFF57C00), [
    ReportSubtype('moderate', 'Moderate'),
    ReportSubtype('heavy', 'Heavy'),
    ReportSubtype('standstill', 'Standstill'),
  ]),
  accident('Accident', Icons.car_crash, Color(0xFFE5484D), [
    ReportSubtype('minor', 'Minor'),
    ReportSubtype('major', 'Major'),
    ReportSubtype('other_side', 'Other side'),
  ]),
  hazard('Hazard', Icons.warning_amber_rounded, Color(0xFFF2A900), [
    ReportSubtype('object', 'Object on road'),
    ReportSubtype('pothole', 'Pothole'),
    ReportSubtype('stopped_vehicle', 'Stopped vehicle'),
    ReportSubtype('construction', 'Roadwork'),
    ReportSubtype('broken_light', 'Broken traffic light'),
    ReportSubtype('weather', 'Bad weather'),
  ]),
  camera('Camera', Icons.videocam, Color(0xFF8E44AD), [
    ReportSubtype('speed', 'Speed camera'),
    ReportSubtype('red_light', 'Red-light camera'),
  ]),
  closed('Road closed', Icons.block, Color(0xFF37474F), [
    ReportSubtype('road', 'Road closed'),
    ReportSubtype('lane', 'Lane closed'),
  ]);

  const ReportType(this.label, this.icon, this.color, this.subtypes);
  final String label;
  final IconData icon;
  final Color color;
  final List<ReportSubtype> subtypes;

  String localLabel(S s) => s.reportType(name, label);

  /// Label for a stored subtype key in the app language, or null if unknown.
  String? subtypeLabel(String? key, S s) {
    for (final sub in subtypes) {
      if (sub.key == key) return sub.localLabel(s);
    }
    return null;
  }
}

/// A report from another driver (or yourself) shown on the map.
class Report {
  Report(
    this.type,
    this.lat,
    this.lng, {
    this.id = 0,
    this.subtype,
    this.up = 0,
    this.down = 0,
    this.mine = false,
  });

  final int id;
  final ReportType type;
  final String? subtype;
  final double lat;
  final double lng;
  final int up; // "still there" votes
  final int down; // "gone" votes
  final bool mine; // made by the signed-in user (they cannot vote on it)

  LatLng get pos => LatLng(lat, lng);

  /// "Police · Hidden" or just "Police".
  String title(S s) {
    final sub = type.subtypeLabel(subtype, s);
    final t = type.localLabel(s);
    return sub == null ? t : '$t · $sub';
  }

  /// How the voice says it, e.g. "Police, hidden" or "Speed camera".
  String spokenName(S s) =>
      s.reportSpoken(type.localLabel(s), type.subtypeLabel(subtype, s));

  Report copyWith({int? up, int? down}) => Report(
    type,
    lat,
    lng,
    id: id,
    subtype: subtype,
    up: up ?? this.up,
    down: down ?? this.down,
    mine: mine,
  );

  static Report fromJson(Map<String, dynamic> j) => Report(
    ReportType.values.byName(j['type'] as String),
    (j['lat'] as num).toDouble(),
    (j['lng'] as num).toDouble(),
    id: (j['id'] as num?)?.toInt() ?? 0,
    subtype: j['subtype'] as String?,
    up: (j['up'] as num?)?.toInt() ?? 0,
    down: (j['down'] as num?)?.toInt() ?? 0,
    mine: (j['mine'] as bool?) ?? false,
  );
}
