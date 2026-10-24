import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ThemeChoice { auto, light, dark }

/// When to warn about driving over the speed limit.
enum SpeedAlert {
  off('Mati', null),
  atLimit('Tepat had', 0),
  plus5('+5 km/j', 5),
  plus10('+10 km/j', 10);

  const SpeedAlert(this.label, this.toleranceKmh);
  final String label;

  /// Warn once speed exceeds the limit by more than this. Null = never warn.
  final int? toleranceKmh;
}

/// User preferences, saved on the device.
class AppSettings {
  const AppSettings({
    this.theme = ThemeChoice.auto,
    this.voiceOn = true,
    this.avoidTolls = false,
    this.speedAlert = SpeedAlert.plus5,
  });

  final ThemeChoice theme;
  final bool voiceOn; // spoken turn-by-turn instructions
  final bool avoidTolls; // start with the "Tanpa tol" route selected
  final SpeedAlert speedAlert; // red speedometer and a spoken warning over the limit

  AppSettings copyWith({
    ThemeChoice? theme,
    bool? voiceOn,
    bool? avoidTolls,
    SpeedAlert? speedAlert,
  }) =>
      AppSettings(
        theme: theme ?? this.theme,
        voiceOn: voiceOn ?? this.voiceOn,
        avoidTolls: avoidTolls ?? this.avoidTolls,
        speedAlert: speedAlert ?? this.speedAlert,
      );
}

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() {
    Future.microtask(_load);
    return const AppSettings();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      state = AppSettings(
        theme: ThemeChoice.values.firstWhere(
          (t) => t.name == p.getString('theme'),
          orElse: () => ThemeChoice.auto,
        ),
        voiceOn: p.getBool('voiceOn') ?? true,
        avoidTolls: p.getBool('avoidTolls') ?? false,
        speedAlert: SpeedAlert.values.firstWhere(
          (a) => a.name == p.getString('speedAlert'),
          orElse: () => SpeedAlert.plus5,
        ),
      );
    } catch (_) {
      // Defaults are fine if storage is unavailable.
    }
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('theme', state.theme.name);
      await p.setBool('voiceOn', state.voiceOn);
      await p.setBool('avoidTolls', state.avoidTolls);
      await p.setString('speedAlert', state.speedAlert.name);
    } catch (_) {}
  }

  void setSpeedAlert(SpeedAlert a) {
    state = state.copyWith(speedAlert: a);
    _save();
  }

  void setTheme(ThemeChoice t) {
    state = state.copyWith(theme: t);
    _save();
  }

  void setVoice(bool on) {
    state = state.copyWith(voiceOn: on);
    _save();
  }

  void setAvoidTolls(bool on) {
    state = state.copyWith(avoidTolls: on);
    _save();
  }
}

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);
