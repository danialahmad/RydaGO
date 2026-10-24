import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:rydago/services/voice.dart';

/// A speech engine whose sentences finish only when the test says so.
class FakeEngine {
  final said = <String>[];
  final _done = <Completer<void>>[];
  int hushes = 0;

  Future<void> say(String text, String locale) {
    said.add(text);
    final c = Completer<void>();
    _done.add(c);
    return c.future;
  }

  Future<void> hush() async => hushes++;

  /// Finishes the sentence being said and lets the queue move on.
  Future<void> finish() async {
    _done.removeAt(0).complete();
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('a new sentence waits for the current one instead of cutting it off', () async {
    final engine = FakeEngine();
    final q = SpeechQueue(engine.say, engine.hush);
    q.add('In 500 meters, turn right', 'en-US');
    q.add('Police reported ahead', 'en-US');
    await Future<void>.delayed(Duration.zero);
    expect(engine.said, ['In 500 meters, turn right']);
    expect(engine.hushes, 0);

    await engine.finish();
    expect(engine.said, ['In 500 meters, turn right', 'Police reported ahead']);
  });

  test('only the newest sentences are kept while one is playing', () async {
    final engine = FakeEngine();
    final q = SpeechQueue(engine.say, engine.hush);
    q.add('one', 'en-US');
    q.add('two', 'en-US');
    q.add('three', 'en-US');
    q.add('four', 'en-US');
    await engine.finish();
    await engine.finish();
    await engine.finish();
    expect(engine.said, ['one', 'three', 'four']);
  });

  test('stop goes quiet and drops what was waiting', () async {
    final engine = FakeEngine();
    final q = SpeechQueue(engine.say, engine.hush);
    q.add('one', 'en-US');
    q.add('two', 'en-US');
    await q.stop();
    expect(engine.hushes, 1);
    await engine.finish();
    expect(engine.said, ['one']);

    // Speaks again straight away after a stop, without waiting for the old sentence.
    q.add('three', 'en-US');
    await Future<void>.delayed(Duration.zero);
    expect(engine.said, ['one', 'three']);
  });

  // testWidgets for its fake clock: the timeout is several seconds of real time.
  testWidgets('a sentence the engine never finishes is given up on', (tester) async {
    final engine = FakeEngine();
    final q = SpeechQueue(engine.say, engine.hush);
    q.add('stuck', 'en-US');
    q.add('next', 'en-US');
    await tester.pump();
    expect(engine.said, ['stuck']);
    await tester.pump(SpeechQueue.timeoutFor('stuck'));
    expect(engine.said, ['stuck', 'next']);
    await tester.pump(SpeechQueue.timeoutFor('next')); // leave no timer running
  });
}
