import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../models/route_summary.dart';
import '../../state/alternatives.dart';
import '../../state/navigation.dart';

/// "Faster route found, saves 6 min. Switch?" with Yes and No, shown over the map
/// while driving. It goes away by itself after [kSuggestionLife].
class RerouteSuggestion extends ConsumerWidget {
  const RerouteSuggestion({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final nav = ref.watch(navProvider);
    final alt = ref.watch(alternativesProvider);
    final pick = alt.suggestion;
    if (nav == null || nav.arrived || pick == null) {
      return const SizedBox.shrink();
    }
    final saving = nav.remainingMin + alt.currentDelayMin - pick.totalMin;
    final notifier = ref.read(alternativesProvider.notifier);

    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 8,
      borderRadius: BorderRadius.circular(22),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.alt_route_rounded, color: AppColors.brandDeep),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  s.fasterRoute,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ]),
            const SizedBox(height: 4),
            Text(
              [
                s.saves(saving),
                if (pick.route.via.isNotEmpty) s.via(pick.route.via),
              ].join(' · '),
              style: const TextStyle(color: AppColors.muted, fontSize: 14),
            ),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    backgroundColor: AppColors.go.withValues(alpha: 0.18),
                    foregroundColor: AppColors.go,
                  ),
                  onPressed: () => notifier.accept(pick),
                  icon: const Icon(Icons.check_rounded, size: 20),
                  label: Text(s.yes, style: const TextStyle(fontSize: 15)),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.tonalIcon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(46),
                    backgroundColor: AppColors.danger.withValues(alpha: 0.14),
                    foregroundColor: AppColors.danger,
                  ),
                  onPressed: () => notifier.decline(),
                  icon: const Icon(Icons.close_rounded, size: 20),
                  label: Text(s.no, style: const TextStyle(fontSize: 15)),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}

/// Opens the list of routes from where the driver is now (tap the bottom bar).
/// Picking one switches the drive to it.
void showRoutesSheet(BuildContext context, WidgetRef ref) {
  ref.read(alternativesProvider.notifier).refreshOptions();
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (_) => const _RoutesSheet(),
  );
}

class _RoutesSheet extends ConsumerWidget {
  const _RoutesSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final nav = ref.watch(navProvider);
    final alt = ref.watch(alternativesProvider);
    if (nav == null) return const SizedBox.shrink();
    final currentTotal = nav.remainingMin + alt.currentDelayMin;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            s.routesFromHere,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          if (alt.stuck)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                s.stuckInTraffic,
                style: const TextStyle(color: AppColors.muted),
              ),
            ),
          const SizedBox(height: 12),
          if (alt.loading && alt.options.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 28),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (alt.options.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: Text(s.noOtherRoutes),
            ),
          for (final c in alt.options)
            _RouteTile(
              choice: c,
              isCurrent: isSameRoad(
                c.route,
                remainingKm: nav.remainingM / 1000,
                via: nav.route.via,
              ),
              currentTotalMin: currentTotal,
              onTap: () {
                ref.read(alternativesProvider.notifier).accept(c);
                Navigator.of(context).pop();
              },
            ),
        ],
      ),
    );
  }
}

class _RouteTile extends StatelessWidget {
  const _RouteTile({
    required this.choice,
    required this.isCurrent,
    required this.currentTotalMin,
    required this.onTap,
  });

  final RouteChoice choice;
  final bool isCurrent;
  final int currentTotalMin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final r = choice.route;
    final diff = currentTotalMin - choice.totalMin; // positive: quicker than now
    final String? badge = isCurrent
        ? s.currentRoute
        : diff > 0
            ? s.saves(diff)
            : diff < 0
                ? s.slowerBy(-diff)
                : null;
    final badgeColor = isCurrent
        ? AppColors.brandDeep
        : diff > 0
            ? AppColors.go
            : AppColors.muted;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: isCurrent
            ? AppColors.brand.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: isCurrent ? null : onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: isCurrent
                    ? AppColors.brand
                    : Theme.of(context).dividerTheme.color!,
                width: isCurrent ? 2.5 : 1.5,
              ),
            ),
            child: Row(children: [
              SizedBox(
                width: 92,
                child: Text(
                  formatDuration(choice.totalMin, s),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      r.via.isEmpty ? r.label : s.via(r.via),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      [
                        '${r.km} km',
                        r.toll == null
                            ? s.noToll
                            : s.tollEstimate(formatRm(r.toll!.rm)),
                        if (choice.delayMin > 0) s.delaysOnRoute(choice.delayMin),
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              if (badge != null)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: badgeColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    badge,
                    style: TextStyle(
                      color: badgeColor,
                      fontWeight: FontWeight.w800,
                      fontSize: 12.5,
                    ),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}
