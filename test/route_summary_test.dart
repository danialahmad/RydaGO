import 'package:flutter_test/flutter_test.dart';
import 'package:rydago/models/report.dart';
import 'package:rydago/models/route_summary.dart';

import 'helpers.dart';

void main() {
  test('reportsOnRoute counts reports on the road by type and ignores nearby roads', () {
    final route = straightRoute(); // runs east along lat 3.0 from lng 101.0
    final reports = [
      Report(ReportType.camera, 3.0, 101.003, id: 1),
      Report(ReportType.camera, 3.0001, 101.006, id: 2), // ~11 m off: still on it
      Report(ReportType.police, 3.0, 101.008, id: 3),
      Report(ReportType.jam, 3.002, 101.004, id: 4), // 220 m north: another road
    ];
    final counts = reportsOnRoute(route, reports);
    expect(counts, {ReportType.camera: 2, ReportType.police: 1});
  });

  test('an empty list, or a route too short to measure, gives no counts', () {
    expect(reportsOnRoute(straightRoute(), const []), isEmpty);
  });
}
