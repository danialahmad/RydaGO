import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum ThemeChoice { auto, light, dark }

/// User preferences, saved on the device.
class AppSettings {
  const AppSettings({
    this.theme = ThemeChoice.auto,
    this.voiceOn = true,
    this.avoidTolls = false,
  });

  final ThemeChoice theme;
  final bool voiceOn; // spoken turn-by-turn instructions
  final bool avoidTolls; // start with the "Tanpa tol" route selected

  AppSettings copyWith({ThemeChoice? theme, bool? voiceOn, bool? avoidTolls}) =>
      AppSettings(
        theme: theme ?? this.theme,
        voiceOn: voiceOn ?? this.voiceOn,
        avoidTolls: avoidTolls ?? this.avoidTolls,
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
    } catch (_) {}
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
