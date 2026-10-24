import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    void editPlace(SearchPurpose purpose) => Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => SearchScreen(purpose: purpose)));

    return Scaffold(
      appBar: AppBar(title: const Text('Tetapan')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          // ---- account ----
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              CircleAvatar(
                radius: 30,
                backgroundColor: AppColors.brand,
                child: Text(
                  auth == null ? '?' : auth.email[0].toUpperCase(),
                  style: const TextStyle(
                      color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(auth?.email ?? 'Belum log masuk',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  Text(auth == null ? 'Log masuk untuk menghantar laporan' : 'Boleh menghantar laporan',
                      style: const TextStyle(color: AppColors.muted)),
                ]),
              ),
              auth == null
                  ? FilledButton(
                      style: FilledButton.styleFrom(minimumSize: const Size(0, 44)),
                      onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const LoginScreen())),
                      child: const Text('Log masuk'),
                    )
                  : OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 44)),
                      onPressed: () => ref.read(authProvider.notifier).logout(),
                      child: const Text('Log keluar'),
                    ),
            ]),
          ),

          // ---- saved places ----
          const _Section('TEMPAT SAYA'),
          _PlaceRow(
            icon: Icons.home_rounded,
            label: 'Rumah',
            place: saved.home,
            onEdit: () => editPlace(SearchPurpose.home),
            onClear: () => ref.read(savedPlacesProvider.notifier).setHome(null),
          ),
          _PlaceRow(
            icon: Icons.work_rounded,
            label: 'Kerja',
            place: saved.work,
            onEdit: () => editPlace(SearchPurpose.work),
            onClear: () => ref.read(savedPlacesProvider.notifier).setWork(null),
          ),
          for (final f in saved.favorites)
            ListTile(
              leading: const Icon(Icons.star_rounded, color: Color(0xFFF2A900)),
              title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: f.area.isEmpty ? null : Text(f.area),
              trailing: IconButton(
                tooltip: 'Buang',
                icon: const Icon(Icons.delete_outline_rounded),
                onPressed: () => ref.read(savedPlacesProvider.notifier).toggleFavorite(f),
              ),
            ),
          if (saved.favorites.isEmpty)
            const ListTile(
              leading: Icon(Icons.star_outline_rounded, color: AppColors.muted),
              title: Text('Tiada kegemaran'),
              subtitle: Text('Tekan bintang pada hasil carian untuk simpan'),
            ),

          // ---- navigation ----
          const _Section('NAVIGASI'),
          SwitchListTile(
            secondary: const Icon(Icons.record_voice_over_rounded),
            title: const Text('Arahan suara'),
            subtitle: const Text('Sebut belokan seterusnya dalam bahasa Melayu'),
            value: settings.voiceOn,
            onChanged: notifier.setVoice,
          ),
          SwitchListTile(
            secondary: const Icon(Icons.toll_rounded),
            title: const Text('Elak tol'),
            subtitle: const Text('Pilih laluan tanpa tol dahulu'),
            value: settings.avoidTolls,
            onChanged: notifier.setAvoidTolls,
          ),

          // ---- display ----
          const _Section('PAPARAN'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: SegmentedButton<ThemeChoice>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                    value: ThemeChoice.auto, icon: Icon(Icons.brightness_auto), label: Text('Auto')),
                ButtonSegment(
                    value: ThemeChoice.light, icon: Icon(Icons.light_mode_outlined), label: Text('Cerah')),
                ButtonSegment(
                    value: ThemeChoice.dark, icon: Icon(Icons.dark_mode_outlined), label: Text('Gelap')),
              ],
              selected: {settings.theme},
              onSelectionChanged: (s) => notifier.setTheme(s.first),
            ),
          ),

          // ---- developer ----
          const _Section('PEMBANGUN'),
          SwitchListTile(
            secondary: const Icon(Icons.science_outlined),
            title: const Text('Mod demo pemanduan'),
            subtitle: const Text(
                'Lokasi palsu bergerak di sepanjang laluan. GPS sebenar diabaikan. Berguna untuk pratonton tanpa memandu.'),
            value: demo,
            onChanged: (v) => ref.read(demoProvider.notifier).set(v),
          ),

          // ---- about ----
          const _Section('TENTANG'),
          const ListTile(
            leading: Icon(Icons.info_outline_rounded),
            title: Text('Waze Revamp'),
            subtitle: Text('Versi 0.1.0 · projek bebas'),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
            child: Text(
              'Peta © penyumbang OpenStreetMap, dihidangkan oleh OpenFreeMap. '
              'Laluan oleh Valhalla, carian oleh Nominatim, kedua-duanya dijalankan sendiri. '
              'Projek ini tiada kaitan dengan Waze atau Google.',
              style: TextStyle(color: AppColors.muted, fontSize: 12.5, height: 1.4),
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
        child: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w800, color: AppColors.muted, fontSize: 13)),
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
  Widget build(BuildContext context) => ListTile(
        leading: Icon(icon, color: AppColors.brandDeep),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(place?.name ?? 'Belum ditetapkan'),
        trailing: place == null
            ? TextButton(onPressed: onEdit, child: const Text('Tetapkan'))
            : Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(
                    tooltip: 'Tukar',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: onEdit),
                IconButton(
                    tooltip: 'Buang',
                    icon: const Icon(Icons.delete_outline_rounded),
                    onPressed: onClear),
              ]),
        onTap: onEdit,
      );
}
