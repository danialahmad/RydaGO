import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/strings.dart';

enum ThemeChoice { auto, light, dark }

/// When to warn about driving over the speed limit.
enum SpeedAlert {
  off(null),
  atLimit(0),
  plus5(5),
  plus10(10);

  const SpeedAlert(this.toleranceKmh);

  String label(S s) => switch (this) {
    off => s.alertOff,
    atLimit => s.alertAtLimit,
    plus5 => s.alertPlus(5),
    plus10 => s.alertPlus(10),
  };

  /// Warn once speed exceeds the limit by more than this. Null = never warn.
  final int? toleranceKmh;
}

/// User preferences, saved on the device.
class AppSettings {
  const AppSettings({
    this.theme = ThemeChoice.auto,
    this.voiceOn = true,
    this.avoidTolls = false,
    this.avoidHighways = false,
    this.speedAlert = SpeedAlert.plus5,
    this.lang = AppLang.en,
  });

  final ThemeChoice theme;
  final bool voiceOn; // spoken turn-by-turn instructions
  final bool avoidTolls; // start with the "Tanpa tol" route selected
  final bool avoidHighways; // route around expressways, e.g. for a slow, scenic drive
  final SpeedAlert
  speedAlert; // red speedometer and a spoken warning over the limit
  final AppLang lang; // language of the UI, voice and route directions

  AppSettings copyWith({
    ThemeChoice? theme,
    bool? voiceOn,
    bool? avoidTolls,
    bool? avoidHighways,
    SpeedAlert? speedAlert,
    AppLang? lang,
  }) => AppSettings(
    theme: theme ?? this.theme,
    voiceOn: voiceOn ?? this.voiceOn,
    avoidTolls: avoidTolls ?? this.avoidTolls,
    avoidHighways: avoidHighways ?? this.avoidHighways,
    speedAlert: speedAlert ?? this.speedAlert,
    lang: lang ?? this.lang,
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
        avoidHighways: p.getBool('avoidHighways') ?? false,
        speedAlert: SpeedAlert.values.firstWhere(
          (a) => a.name == p.getString('speedAlert'),
          orElse: () => SpeedAlert.plus5,
        ),
        lang: AppLang.values.firstWhere(
          (l) => l.code == p.getString('lang'),
          orElse: () => AppLang.en,
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
      await p.setBool('avoidHighways', state.avoidHighways);
      await p.setString('speedAlert', state.speedAlert.name);
      await p.setString('lang', state.lang.code);
    } catch (_) {}
  }

  void setLang(AppLang l) {
    state = state.copyWith(lang: l);
    _save();
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

  void setAvoidHighways(bool on) {
    state = state.copyWith(avoidHighways: on);
    _save();
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);
