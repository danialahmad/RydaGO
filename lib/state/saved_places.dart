import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/place.dart';

/// Home, Work and favourite places, saved on the device.
class SavedPlaces {
  const SavedPlaces({this.home, this.work, this.favorites = const []});

  final Place? home;
  final Place? work;
  final List<Place> favorites;

  bool isFavorite(Place p) => favorites.any(p.isSameAs);

  Map<String, dynamic> toJson() => {
        'home': home?.toJson(),
        'work': work?.toJson(),
        'favorites': [for (final f in favorites) f.toJson()],
      };

  static SavedPlaces fromJson(Map<String, dynamic> j) => SavedPlaces(
        home: j['home'] == null ? null : Place.fromJson(j['home'] as Map<String, dynamic>),
        work: j['work'] == null ? null : Place.fromJson(j['work'] as Map<String, dynamic>),
        favorites: [
          for (final f in (j['favorites'] as List? ?? const []))
            Place.fromJson(f as Map<String, dynamic>),
        ],
      );
}

class SavedPlacesNotifier extends Notifier<SavedPlaces> {
  @override
  SavedPlaces build() {
    Future.microtask(_load);
    return const SavedPlaces();
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('savedPlaces');
      if (raw != null) {
        state = SavedPlaces.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      }
    } catch (_) {
      // Missing or corrupt storage: start empty.
    }
  }

  Future<void> _save() async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setString('savedPlaces', jsonEncode(state.toJson()));
    } catch (_) {}
  }

  void setHome(Place? p) {
    state = SavedPlaces(home: p, work: state.work, favorites: state.favorites);
    _save();
  }

  void setWork(Place? p) {
    state = SavedPlaces(home: state.home, work: p, favorites: state.favorites);
    _save();
  }

  /// Adds the place to favourites, or removes it if it is already there.
  void toggleFavorite(Place p) {
    final favs = state.isFavorite(p)
        ? state.favorites.where((f) => !f.isSameAs(p)).toList()
        : [p, ...state.favorites];
    state = SavedPlaces(home: state.home, work: state.work, favorites: favs);
    _save();
  }
}

final savedPlacesProvider =
    NotifierProvider<SavedPlacesNotifier, SavedPlaces>(SavedPlacesNotifier.new);

/// The last few destinations, newest first.
class RecentsNotifier extends Notifier<List<Place>> {
  @override
  List<Place> build() {
    Future.microtask(_load);
    return const [];
  }

  Future<void> _load() async {
    try {
      final p = await SharedPreferences.getInstance();
      final raw = p.getString('recents');
      if (raw == null) return;
      state = [
        for (final j in jsonDecode(raw) as List) Place.fromJson(j as Map<String, dynamic>),
      ];
    } catch (_) {
      // Missing or corrupt storage: start with no recents.
    }
  }

  Future<void> add(Place p) async {
    state = [p, ...state.where((o) => !o.isSameAs(p))].take(8).toList();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('recents', jsonEncode([for (final r in state) r.toJson()]));
    } catch (_) {}
  }
}

final recentsProvider =
    NotifierProvider<RecentsNotifier, List<Place>>(RecentsNotifier.new);
