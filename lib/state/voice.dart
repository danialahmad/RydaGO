import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/voice.dart';
import 'navigation.dart';
import 'reports.dart';
import 'settings.dart';

/// The speech engine. Tests override this with a fake.
final speakerProvider = Provider<Speaker>((ref) => TtsSpeaker());

/// Speaks while navigating (if voice is on in settings): turn instructions first,
/// otherwise a heads-up about a report ahead, otherwise a speeding warning.
/// Must be watched somewhere (the map screen does) to stay alive.
class VoiceGuide extends Notifier<void> {
  final _planner = VoicePlanner();

  @override
  void build() {
    ref.listen(navProvider, (prev, next) {
      if (next == null) {
        _planner.reset();
        ref.read(speakerProvider).stop();
        return;
      }
      final settings = ref.read(settingsProvider);
      // One sentence per update: speak() interrupts, so never queue two.
      final text = _planner.next(next) ??
          _planner.nextAlert(next, ref.read(reportsProvider)) ??
          _planner.speeding(next, settings.speedAlert.toleranceKmh);
      if (text != null && settings.voiceOn) {
        ref.read(speakerProvider).speak(text);
      }
    });
    ref.listen(settingsProvider, (prev, next) {
      if (!next.voiceOn) ref.read(speakerProvider).stop();
    });
  }
}

final voiceGuideProvider = NotifierProvider<VoiceGuide, void>(VoiceGuide.new);
