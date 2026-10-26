import 'package:flutter_test/flutter_test.dart';
import 'package:rydago/models/route.dart';
import 'package:rydago/ui/widgets/nav_overlay.dart';
import 'package:flutter/material.dart' show Icons;

void main() {
  test('Maneuver reads exit sign and lanes, and tolerates their absence', () {
    final m = Maneuver.fromJson({
      'text': 'Take exit 3310A', 'type': 21, 'km': 1.2, 'index': 4,
      'exit': '3310A', 'toward': 'Gombak / Batu Caves',
      'lanes': [
        {'dirs': ['left', 'straight'], 'valid': true, 'active': true},
        {'dirs': ['right']},
      ],
    });
    expect((m.exit, m.toward), ('3310A', 'Gombak / Batu Caves'));
    expect(m.lanes, hasLength(2));
    expect(m.lanes[0].dirs, ['left', 'straight']);
    expect((m.lanes[0].valid, m.lanes[0].active), (true, true));
    expect((m.lanes[1].valid, m.lanes[1].active), (false, false));

    final plain = Maneuver.fromJson({'text': 'x', 'type': 10, 'km': 0.1, 'index': 1});
    expect((plain.exit, plain.toward), ('', ''));
    expect(plain.lanes, isEmpty);
  });

  test('laneIcon maps API directions to icons, unknown ones go straight', () {
    expect(laneIcon('left'), Icons.turn_left);
    expect(laneIcon('slight_right'), Icons.turn_slight_right);
    expect(laneIcon('merge_to_left'), Icons.straight);
  });
}
