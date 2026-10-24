import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../models/place.dart';
import '../../state/auth.dart';
import '../../state/demo.dart';
import '../../state/saved_places.dart';
import '../../state/settings.dart';
import 'login_screen.dart';
import 'search_screen.dart';

/// Account, saved places, navigation and display preferences, demo mode, about.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final saved = ref.watch(savedPlacesProvider);
    final settings = ref.watch(settingsProvider);
    final demo = ref.watch(demoProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final s = S.of(context);

    void editPlace(SearchPurpose purpose) => Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => SearchScreen(purpose: purpose)));

    return Scaffold(
      appBar: AppBar(title: Text(s.settings)),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // ---- account ----
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: AppColors.brand,
                  child: Text(
                    auth == null ? '?' : auth.email[0].toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth?.email ?? s.notSignedIn,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        auth == null ? s.signInToReport : s.canReport,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                    ],
                  ),
                ),
                auth == null
                    ? FilledButton(
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const LoginScreen(),
                          ),
                        ),
                        child: Text(s.signIn),
                      )
                    : OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(0, 44),
                        ),
                        onPressed: () =>
                            ref.read(authProvider.notifier).logout(),
                        child: Text(s.signOut),
                      ),
              ],
            ),
          ),

          // ---- saved places ----
          _Section(s.mySpots),
          _PlaceRow(
            icon: Icons.home_rounded,
            label: s.home,
            place: saved.home,
            onEdit: () => editPlace(SearchPurpose.home),
            onClear: () => ref.read(savedPlacesProvider.notifier).setHome(null),
          ),
          _PlaceRow(
            icon: Icons.work_rounded,
            label: s.work,
            place: saved.work,
            onEdit: () => editPlace(SearchPurpose.work),
            onClear: () => ref.read(savedPlacesProvider.notifier).setWork(null),
          ),
          for (final f in saved.favorites)
            ListTile(
              leading: const Icon(Icons.star_rounded, color: Color(0xFFF2A900)),
              title: Text(
                f.name,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: f.area.isEmpty ? null : Text(f.area),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: s.remove,
                onPressed: () =>
                    ref.read(savedPlacesProvider.notifier).toggleFavorite(f),
              ),
            ),
          if (saved.favorites.isEmpty)
            ListTile(
              leading: const Icon(
                Icons.star_outline_rounded,
                color: AppColors.muted,
              ),
              title: Text(s.noFavorites),
              subtitle: Text(s.favoritesHint),
            ),

          // ---- navigation ----
          _Section(s.navigationSection),
          SwitchListTile(
            secondary: const Icon(Icons.record_voice_over_rounded),
            title: Text(s.voiceGuidance),
            subtitle: Text(s.voiceGuidanceSub),
            value: settings.voiceOn,
            onChanged: notifier.setVoice,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.toll_rounded),
            title: Text(s.avoidTolls),
            subtitle: Text(s.avoidTollsSub),
            value: settings.avoidTolls,
            onChanged: notifier.setAvoidTolls,
          ),
          ListTile(
            leading: const Icon(Icons.speed_rounded),
            title: Text(s.speedAlert),
            subtitle: Text(s.speedAlertSub),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: SegmentedButton<SpeedAlert>(
              showSelectedIcon: false,
              segments: [
                for (final a in SpeedAlert.values)
                  ButtonSegment(
                    value: a,
                    label: Text(
                      a.label(s),
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
              ],
              selected: {settings.speedAlert},
              onSelectionChanged: (s) => notifier.setSpeedAlert(s.first),
            ),
          ),

          // ---- display ----
          _Section(s.displaySection),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SegmentedButton<ThemeChoice>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: ThemeChoice.auto,
                  icon: const Icon(Icons.brightness_auto),
                  label: Text(s.themeAuto),
                ),
                ButtonSegment(
                  value: ThemeChoice.light,
                  icon: const Icon(Icons.light_mode_outlined),
                  label: Text(s.themeLight),
                ),
                ButtonSegment(
                  value: ThemeChoice.dark,
                  icon: const Icon(Icons.dark_mode_outlined),
                  label: Text(s.themeDark),
                ),
              ],
              selected: {settings.theme},
              onSelectionChanged: (s) => notifier.setTheme(s.first),
            ),
          ),

          // ---- language ----
          _Section(s.languageSection),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SegmentedButton<AppLang>(
                  showSelectedIcon: false,
                  segments: [
                    for (final l in AppLang.values)
                      ButtonSegment(value: l, label: Text(l.nativeName)),
                  ],
                  selected: {settings.lang},
                  onSelectionChanged: (v) => notifier.setLang(v.first),
                ),
                const SizedBox(height: 6),
                Text(
                  s.languageSub,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),

          // ---- developer ----
          _Section(s.developerSection),
          SwitchListTile(
            secondary: const Icon(Icons.science_outlined),
            title: Text(s.demoMode),
            subtitle: Text(s.demoModeSub),
            value: demo,
            onChanged: (v) => ref.read(demoProvider.notifier).set(v),
          ),

          // ---- about ----
          _Section(s.aboutSection),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: Text(s.appName),
            subtitle: Text(s.version),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              s.credits,
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 22, 16, 4),
    child: Text(
      title,
      style: const TextStyle(
        fontWeight: FontWeight.w800,
        color: AppColors.muted,
        fontSize: 13,
      ),
    ),
  );
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.icon,
    required this.label,
    required this.place,
    required this.onEdit,
    required this.onClear,
  });

  final IconData icon;
  final String label;
  final Place? place;
  final VoidCallback onEdit;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return ListTile(
      leading: Icon(icon, color: AppColors.brandDeep),
      title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text(place?.name ?? s.notSet),
      trailing: place == null
          ? TextButton(onPressed: onEdit, child: Text(s.set))
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: s.change,
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: onEdit,
                ),
                IconButton(
                  tooltip: s.remove,
                  icon: const Icon(Icons.delete_outline_rounded),
                  onPressed: onClear,
                ),
              ],
            ),
      onTap: onEdit,
    );
  }
}
