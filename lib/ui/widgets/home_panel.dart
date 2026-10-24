import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../models/place.dart';
import '../../state/saved_places.dart';
import '../../state/trip.dart';
import '../screens/search_screen.dart';
import 'map_buttons.dart';

/// The default bottom panel: "Mau ke mana?" plus Home, Work and favourite shortcuts.
class HomePanel extends ConsumerWidget {
  const HomePanel({super.key});

  void _openSearch(BuildContext context, SearchPurpose purpose) => Navigator.of(context)
      .push(MaterialPageRoute(builder: (_) => SearchScreen(purpose: purpose)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final saved = ref.watch(savedPlacesProvider);
    final scheme = Theme.of(context).colorScheme;

    return BottomPanel(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Material(
          color: Theme.of(context).inputDecorationTheme.fillColor,
          borderRadius: BorderRadius.circular(30),
          child: InkWell(
            borderRadius: BorderRadius.circular(30),
            onTap: () => _openSearch(context, SearchPurpose.destination),
            child: Container(
              height: 58,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Row(children: [
                Icon(Icons.search_rounded, color: scheme.onSurface, size: 28),
                const SizedBox(width: 12),
                Text('Mau ke mana?',
                    style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                        color: scheme.onSurface.withValues(alpha: 0.7))),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 64,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _Shortcut(
                icon: Icons.home_rounded,
                label: 'Rumah',
                sub: saved.home?.name ?? 'Tetapkan',
                set: saved.home != null,
                onTap: () => saved.home != null
                    ? chooseDestination(ref, saved.home!)
                    : _openSearch(context, SearchPurpose.home),
                onLongPress: () => _openSearch(context, SearchPurpose.home),
              ),
              _Shortcut(
                icon: Icons.work_rounded,
                label: 'Kerja',
                sub: saved.work?.name ?? 'Tetapkan',
                set: saved.work != null,
                onTap: () => saved.work != null
                    ? chooseDestination(ref, saved.work!)
                    : _openSearch(context, SearchPurpose.work),
                onLongPress: () => _openSearch(context, SearchPurpose.work),
              ),
              for (final f in saved.favorites)
                _Shortcut(
                  icon: Icons.star_rounded,
                  label: f.name,
                  sub: f.area,
                  set: true,
                  onTap: () => chooseDestination(ref, f),
                  onLongPress: () => _confirmRemove(context, ref, f),
                ),
            ],
          ),
        ),
      ]),
    );
  }

  void _confirmRemove(BuildContext context, WidgetRef ref, Place p) {
    ref.read(savedPlacesProvider.notifier).toggleFavorite(p);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text('${p.name} dibuang daripada kegemaran'),
        action: SnackBarAction(
          label: 'Asal semula',
          onPressed: () => ref.read(savedPlacesProvider.notifier).toggleFavorite(p),
        ),
      ));
  }
}

class _Shortcut extends StatelessWidget {
  const _Shortcut({
    required this.icon,
    required this.label,
    required this.sub,
    required this.set,
    required this.onTap,
    required this.onLongPress,
  });

  final IconData icon;
  final String label;
  final String sub;
  final bool set; // false = a "set this up" prompt, drawn quieter
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(right: 10),
      child: Material(
        color: scheme.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          onLongPress: onLongPress,
          child: Container(
            constraints: const BoxConstraints(minWidth: 118, maxWidth: 190),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(
                radius: 19,
                backgroundColor:
                    set ? AppColors.brand.withValues(alpha: 0.2) : Colors.transparent,
                child: Icon(icon, size: 22, color: set ? AppColors.brandDeep : AppColors.muted),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: set ? AppColors.muted : AppColors.brandDeep,
                            fontWeight: set ? FontWeight.w500 : FontWeight.w700)),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
