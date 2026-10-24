import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// One refinement of a report type, e.g. police: "Tersembunyi".
/// [key] is what the API stores; the first subtype of a type is the default.
class ReportSubtype {
  const ReportSubtype(this.key, this.label);
  final String key;
  final String label;
}

/// The kinds of report a driver can make. [name] and each subtype key must match
/// the API (`reportSubtypes` in backend/main.go, documented in docs/API.md).
enum ReportType {
  police('Polis', Icons.local_police, Color(0xFF3F51B5), [
    ReportSubtype('visible', 'Kelihatan'),
    ReportSubtype('hidden', 'Tersembunyi'),
    ReportSubtype('other_side', 'Di sebelah lain'),
  ]),
  jam('Kesesakan', Icons.traffic, Color(0xFFF57C00), [
    ReportSubtype('moderate', 'Sederhana'),
    ReportSubtype('heavy', 'Teruk'),
    ReportSubtype('standstill', 'Terhenti'),
  ]),
  accident('Kemalangan', Icons.car_crash, Color(0xFFE5484D), [
    ReportSubtype('minor', 'Kecil'),
    ReportSubtype('major', 'Besar'),
    ReportSubtype('other_side', 'Di sebelah lain'),
  ]),
  hazard('Bahaya', Icons.warning_amber_rounded, Color(0xFFF2A900), [
    ReportSubtype('object', 'Objek di jalan'),
    ReportSubtype('pothole', 'Lubang'),
    ReportSubtype('stopped_vehicle', 'Kenderaan rosak'),
    ReportSubtype('construction', 'Kerja jalan'),
    ReportSubtype('broken_light', 'Lampu isyarat rosak'),
    ReportSubtype('weather', 'Cuaca buruk'),
  ]),
  camera('Kamera', Icons.videocam, Color(0xFF8E44AD), [
    ReportSubtype('speed', 'Kamera kelajuan'),
    ReportSubtype('red_light', 'Kamera lampu merah'),
  ]),
  closed('Jalan tutup', Icons.block, Color(0xFF37474F), [
    ReportSubtype('road', 'Jalan ditutup'),
    ReportSubtype('lane', 'Lorong ditutup'),
  ]);

  const ReportType(this.label, this.icon, this.color, this.subtypes);
  final String label;
  final IconData icon;
  final Color color;
  final List<ReportSubtype> subtypes;

  /// Label for a stored subtype key, or null if unknown.
  String? subtypeLabel(String? key) {
    for (final s in subtypes) {
      if (s.key == key) return s.label;
    }
    return null;
  }
}

/// A report from another driver (or yourself) shown on the map.
class Report {
  Report(this.type, this.lat, this.lng, {this.subtype});
  final ReportType type;
  final String? subtype;
  final double lat;
  final double lng;

  LatLng get pos => LatLng(lat, lng);

  /// "Polis · Tersembunyi" or just "Polis".
  String get title {
    final sub = type.subtypeLabel(subtype);
    return sub == null ? type.label : '${type.label} · $sub';
  }

  static Report fromJson(Map<String, dynamic> j) => Report(
        ReportType.values.byName(j['type'] as String),
        (j['lat'] as num).toDouble(),
        (j['lng'] as num).toDouble(),
        subtype: j['subtype'] as String?,
      );
}
