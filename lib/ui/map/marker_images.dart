import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../models/report.dart';

/// Names of the images registered with the map style.
String reportImageName(ReportType t) => 'report-${t.name}';
const destinationImageName = 'marker-destination';
const pinImageName = 'marker-pin';

/// Draws a marker (white ring, coloured disc, white Material icon) into a PNG.
/// Rendered at runtime so the app ships no image files and uses only Material icons.
Future<Uint8List> renderMarker(IconData icon, Color bg, {double px = 96}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final centre = Offset(px / 2, px / 2);
  canvas.drawCircle(centre, px / 2, Paint()..color = Colors.white);
  canvas.drawCircle(centre, px / 2 - 6, Paint()..color = bg);
  final glyph = TextPainter(
    textDirection: TextDirection.ltr,
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: px * 0.52,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: Colors.white,
      ),
    ),
  )..layout();
  glyph.paint(canvas, centre - Offset(glyph.width / 2, glyph.height / 2));
  final image = await recorder.endRecording().toImage(px.toInt(), px.toInt());
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Registers every marker image on the map. Must run again after each style load
/// (switching between the light and dark map drops the images).
Future<void> registerMarkerImages(MapLibreMapController c) async {
  for (final t in ReportType.values) {
    await c.addImage(reportImageName(t), await renderMarker(t.icon, t.color));
  }
  await c.addImage(
      destinationImageName, await renderMarker(Icons.flag, const Color(0xFFE5484D)));
  await c.addImage(
      pinImageName, await renderMarker(Icons.place, const Color(0xFF6C3FC5)));
  await c.setSymbolIconAllowOverlap(true);
}
