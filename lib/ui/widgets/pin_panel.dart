import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

import '../../app/theme.dart';
import '../../models/place.dart';
import '../../state/trip.dart';
import 'map_buttons.dart';
import 'report_sheet.dart';

/// Shown after a long press on the map: go to that spot, or report something there.
class PinPanel extends ConsumerWidget {
  const PinPanel({super.key, required this.pin});
  final LatLng pin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coords = '${pin.latitude.toStringAsFixed(5)}, ${pin.longitude.toStringAsFixed(5)}';
    return BottomPanel(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          const CircleAvatar(
            radius: 22,
            backgroundColor: Color(0xFF6C3FC5),
            child: Icon(Icons.place, color: Colors.white),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Lokasi dipilih',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              Text(coords, style: const TextStyle(color: AppColors.muted)),
            ]),
          ),
          IconButton(
            tooltip: 'Tutup',
            onPressed: () => ref.read(pinProvider.notifier).set(null),
            icon: const Icon(Icons.close),
          ),
        ]),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: AppColors.go),
              onPressed: () => chooseDestination(
                  ref, Place('Lokasi dipilih', coords, Icons.place, pin)),
              icon: const Icon(Icons.navigation_rounded),
              label: const Text('Pergi'),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => openReportFlow(context, ref),
              icon: const Icon(Icons.add_alert_rounded),
              label: const Text('Lapor'),
            ),
          ),
        ]),
      ]),
    );
  }
}
