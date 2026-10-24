import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/voice.dart';
import 'navigation.dart';
import 'settings.dart';

/// The speech engine. Tests override this with a fake.
final speakerProvider = Provider<Speaker>((ref) => TtsSpeaker());

/// Speaks navigation instructions while navigating (if voice is on in settings).
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
      final text = _planner.next(next);
      if (text != null && ref.read(settingsProvider).voiceOn) {
        ref.read(speakerProvider).speak(text);
      }
    });
    ref.listen(settingsProvider, (prev, next) {
      if (!next.voiceOn) ref.read(speakerProvider).stop();
    });
  }
}

final voiceGuideProvider = NotifierProvider<VoiceGuide, void>(VoiceGuide.new);
