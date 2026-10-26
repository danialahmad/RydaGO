import 'package:flutter_test/flutter_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:rydago/models/geo.dart';
import 'package:rydago/services/map_style.dart';

Map<String, dynamic> _style() => {
      'version': 8,
      'layers': [
        {'id': 'building-3d', 'type': 'fill-extrusion', 'source-layer': 'building'},
        {
          'id': 'road_minor',
          'type': 'line',
          'source-layer': 'transportation',
          'paint': {
            'line-width': ['interpolate', ['exponential', 1.2], ['zoom'], 14, 2.5, 20, 18],
          },
        },
        {
          'id': 'road_minor_casing',
          'type': 'line',
          'source-layer': 'transportation',
          'paint': {'line-width': 4},
        },
        {
          'id': 'road_major_rail',
          'type': 'line',
          'source-layer': 'transportation',
          'paint': {'line-width': 2},
        },
        {
          'id': 'road_path_pedestrian',
          'type': 'line',
          'source-layer': 'transportation',
          'paint': {'line-width': 1},
        },
        {'id': 'water', 'type': 'fill', 'source-layer': 'water', 'paint': {}},
      ],
    };

void main() {
  roadStyleTests();
  group('flattenStyle', () {
    test('drops 3D building extrusions and footpaths, and keeps the other layers', () {
      final out = flattenStyle(_style());
      final ids = (out['layers'] as List).map((l) => l['id']).toList();
      expect(ids, ['road_minor', 'road_minor_casing', 'road_major_rail', 'water']);
    });

    test('thickens road widths, scaling only the outputs of zoom expressions', () {
      final out = flattenStyle(_style(), roadScale: 2);
      final layers = {for (final l in out['layers'] as List) l['id']: l};
      expect(layers['road_minor']['paint']['line-width'],
          ['interpolate', ['exponential', 1.2], ['zoom'], 14, 3.33, 20, 36.0]);
      expect(layers['road_minor_casing']['paint']['line-width'], 8.0); // no zoom: full factor
    });

    test('leaves rails and non-road layers alone, and does not change the input', () {
      final input = _style();
      final out = flattenStyle(input, roadScale: 2);
      final layers = {for (final l in out['layers'] as List) l['id']: l};
      expect(layers['road_major_rail']['paint']['line-width'], 2);
      expect(layers['water']['paint'], isEmpty);
      expect((input['layers'] as List).length, 6); // original untouched
    });
  });

  test('scaleWidth handles step expressions and wraps non-numeric outputs', () {
    expect(scaleWidth(['step', ['zoom'], 1, 10, 2, 16, 4], 3), ['step', ['zoom'], 1.0, 10, 2.0, 16, 12.0]);
    expect(zoomFactor(2, 12), 1);
    expect(zoomFactor(2, 14.5), 1.5);
    expect(zoomFactor(2, 18), 2);
    expect(
        scaleWidth(['interpolate', ['linear'], ['zoom'], 5, ['get', 'w'], 9, 2], 2),
        ['interpolate', ['linear'], ['zoom'], 5, ['*', 1.0, ['get', 'w']], 9, 2.0]);
    expect(scaleWidth(['get', 'w'], 2), ['get', 'w']); // unknown shape: unchanged
  });

  test('offsetAhead moves along the bearing', () {
    const p = LatLng(3.0, 101.0);
    final north = offsetAhead(p, 0, 100);
    expect(north.latitude - p.latitude, closeTo(100 / 110540, 1e-7));
    expect(north.longitude, closeTo(p.longitude, 1e-9));
    final east = offsetAhead(p, 90, 100);
    expect(east.longitude - p.longitude, greaterThan(0));
    expect(east.latitude, closeTo(p.latitude, 1e-7));
    expect(haversineM(p, offsetAhead(p, 213, 45)), closeTo(45, 0.5));
  });
}

void roadStyleTests() {
  test('roadColor: white roads, grey casings, warm motorways, dim tunnels', () {
    expect(roadColor('road_minor'), '#ffffff');
    expect(roadColor('road_minor_casing'), '#b8bec7');
    expect(roadColor('road_motorway'), '#ffeeb8');
    expect(roadColor('road_trunk_primary_casing'), '#d9b44a');
    expect(roadColor('tunnel_minor'), '#eceef1');
  });

  test('flattenStyle recolours roads only when asked', () {
    String? colorOf(Map<String, dynamic> s, String id) => ((s['layers'] as List)
        .firstWhere((l) => l['id'] == id)['paint'] as Map)['line-color'] as String?;
    expect(colorOf(flattenStyle(_style()), 'road_minor'), isNull);
    expect(colorOf(flattenStyle(_style(), recolor: true), 'road_minor'), '#ffffff');
    expect(colorOf(flattenStyle(_style(), recolor: true), 'road_minor_casing'), '#b8bec7');
  });

  test('navZoom: closer when slow or near a turn, wider at speed', () {
    expect(navZoom(0, 1000), 18.0);
    expect(navZoom(null, 1000), 18.0);
    expect(navZoom(40, 1000), 18.0);
    expect(navZoom(70, 1000), 17.3);
    expect(navZoom(100, 1000), 16.5);
    expect(navZoom(140, 1000), 16.5); // capped
    expect(navZoom(100, 200), 17.8); // turn coming up: pull in
    expect(navZoom(20, 100), 18.0);
  });
}
