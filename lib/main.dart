import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/theme.dart';
import 'state/settings.dart';
import 'ui/screens/map_screen.dart';

void main() => runApp(const ProviderScope(child: WazeRevampApp()));

class WazeRevampApp extends ConsumerWidget {
  const WazeRevampApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final choice = ref.watch(settingsProvider.select((s) => s.theme));
    return MaterialApp(
      title: 'Waze Revamp',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: switch (choice) {
        ThemeChoice.auto => ThemeMode.system,
        ThemeChoice.light => ThemeMode.light,
        ThemeChoice.dark => ThemeMode.dark,
      },
      home: const MapScreen(),
    );
  }
}
