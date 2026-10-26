import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../models/route.dart';
import '../../models/route_summary.dart';
import '../../state/reports.dart';
import '../../state/navigation.dart';
import '../../state/settings.dart';
import '../../state/trip.dart';
import 'map_buttons.dart';

/// After a destination is chosen: the routes on offer, with arrival times and how
/// much slower each is than the fastest, and a big "Mula" button.
class RoutePreviewPanel extends ConsumerWidget {
  const RoutePreviewPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final dest = ref.watch(destinationProvider);
    if (dest == null) return const SizedBox.shrink();
    final async = ref.watch(routesProvider);
    final routes = async.isLoading
        ? const <RouteOption>[]
        : (async.value ?? const <RouteOption>[]);
    final selected = clampRouteIndex(
      ref.watch(routeIndexProvider),
      routes.length,
    );

    // With "Avoid tolls" on, start with the toll-free route selected.
    ref.listen(routesProvider, (_, next) {
      final r = next.value;
      if (r == null || r.isEmpty || !ref.read(settingsProvider).avoidTolls) {
        return;
      }
      final i = r.indexWhere((x) => x.id == 'notoll');
      if (i >= 0) ref.read(routeIndexProvider.notifier).set(i);
    });

    final fastest = routes.isEmpty
        ? 0
        : routes.indexOf(
            routes.reduce((a, b) => b.minutes < a.minutes ? b : a),
          );

    return BottomPanel(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: s.cancel,
                onPressed: () =>
                    ref.read(destinationProvider.notifier).set(null),
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dest.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (dest.area.isNotEmpty)
                      Text(
                        dest.area,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: AppColors.muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (async.isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 36),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    s.findingRoutes,
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            )
          else if (async.hasError)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off, color: AppColors.muted),
                  const SizedBox(width: 12),
                  Expanded(child: Text(s.routesFailed)),
                  TextButton(
                    onPressed: () => ref.invalidate(routesProvider),
                    child: Text(s.retry),
                  ),
                ],
              ),
            )
          else
            for (var i = 0; i < routes.length; i++)
              _RouteCard(
                route: routes[i],
                selected: i == selected,
                isFastest: i == fastest,
                extraMin: routes[i].minutes - routes[fastest].minutes,
                onTap: () => ref.read(routeIndexProvider.notifier).set(i),
              ),
          if (!async.isLoading && !async.hasError && routes.isNotEmpty)
            _RouteSummary(route: routes[selected]),
          const SizedBox(height: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: AppColors.go),
            onPressed: routes.isEmpty
                ? null
                : () {
                    if (!startNavigation(ref)) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(s.needGps)),
                      );
                    }
                  },
            icon: const Icon(Icons.navigation_rounded),
            label: Text(s.start),
          ),
        ],
      ),
    );
  }
}

class _RouteCard extends StatelessWidget {
  const _RouteCard({
    required this.route,
    required this.selected,
    required this.isFastest,
    required this.extraMin,
    required this.onTap,
  });

  final RouteOption route;
  final bool selected;
  final bool isFastest;
  final int extraMin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final scheme = Theme.of(context).colorScheme;
    final arrival = formatClock(
      DateTime.now().add(Duration(minutes: route.minutes)),
      s,
    );
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: selected
            ? AppColors.brand.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 14, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: selected
                    ? AppColors.brand
                    : Theme.of(context).dividerTheme.color!,
                width: selected ? 2.5 : 1.5,
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 92,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        formatDuration(route.minutes, s),
                        style: const TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        s.arrive(arrival),
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.muted,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        route.label,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        route.via.isEmpty
                            ? '${route.km} km'
                            : '${route.km} km · ${s.via(route.via)}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.65),
                        ),
                      ),
                      Text(
                        route.toll == null
                            ? s.noToll
                            : s.tollEstimate(formatRm(route.toll!.rm)),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                          color: route.toll == null
                              ? AppColors.go
                              : scheme.onSurface.withValues(alpha: 0.8),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isFastest)
                  _Tag(text: s.tagFastest, color: AppColors.go)
                else if (extraMin > 0)
                  _Tag(text: s.tagSlower(extraMin), color: AppColors.muted)
                else
                  _Tag(text: s.tagSame, color: AppColors.muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      text,
      style: TextStyle(
        color: color,
        fontWeight: FontWeight.w800,
        fontSize: 12.5,
      ),
    ),
  );
}

/// What to expect on the selected route: the road reports lying on it (cameras,
/// police, accidents ...), so the driver knows before setting off.
class _RouteSummary extends ConsumerWidget {
  const _RouteSummary({required this.route});
  final RouteOption route;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);
    final counts = reportsOnRoute(route, ref.watch(reportsProvider));
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            s.onThisRoute,
            style: const TextStyle(
              color: AppColors.muted,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          if (counts.isEmpty)
            Text(s.nothingReported, style: const TextStyle(fontSize: 13)),
          for (final e in counts.entries)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: e.key.color.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(e.key.icon, size: 16, color: e.key.color),
                const SizedBox(width: 4),
                Text(
                  '${e.key.localLabel(s)} × ${e.value}',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: e.key.color,
                  ),
                ),
              ]),
            ),
        ],
      ),
    );
  }
}
