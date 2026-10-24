import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/strings.dart';
import '../../app/theme.dart';
import '../../models/place.dart';
import '../../services/api.dart';
import '../../state/saved_places.dart';
import '../../state/settings.dart';
import '../../state/trip.dart';
import '../../state/user_loc.dart';

/// What picking a result does.
enum SearchPurpose { destination, home, work }

/// "Where to?": Home/Work, favourites, recent places, and live address search.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key, this.purpose = SearchPurpose.destination});
  final SearchPurpose purpose;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  Timer? _debounce;
  String _query = '';
  List<Place> _results = const [];
  bool _loading = false;
  String? _error;
  int _seq = 0; // lets us drop responses that arrive out of order

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    final q = value.trim();
    final seq = ++_seq;
    if (q.length < 2) {
      setState(() {
        _query = q;
        _results = const [];
        _loading = false;
        _error = null;
      });
      return;
    }
    setState(() {
      _query = q;
      _loading = true;
      _error = null;
    });
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      try {
        final r = await Api.searchPlaces(
          q,
          ref.read(userLocProvider).pos,
          ref.read(settingsProvider).lang,
        );
        if (!mounted || seq != _seq) return;
        setState(() {
          _results = r;
          _loading = false;
        });
      } catch (_) {
        if (!mounted || seq != _seq) return;
        setState(() {
          _results = const [];
          _loading = false;
          _error = 'search'; // shown as S.searchFailed
        });
      }
    });
  }

  void _pick(Place p) {
    final saved = ref.read(savedPlacesProvider.notifier);
    final messenger = ScaffoldMessenger.of(context);
    final s = S.of(context);
    switch (widget.purpose) {
      case SearchPurpose.destination:
        chooseDestination(ref, p);
      case SearchPurpose.home:
        saved.setHome(p);
        messenger.showSnackBar(SnackBar(content: Text(s.homeSet(p.name))));
      case SearchPurpose.work:
        saved.setWork(p);
        messenger.showSnackBar(SnackBar(content: Text(s.workSet(p.name))));
    }
    Navigator.of(context).pop();
  }

  String get _title => switch (widget.purpose) {
    SearchPurpose.destination => S.of(context).whereTo,
    SearchPurpose.home => S.of(context).setHomeTitle,
    SearchPurpose.work => S.of(context).setWorkTitle,
  };

  Widget _tile(Place p, {IconData? icon, bool starrable = false}) {
    final saved = ref.watch(savedPlacesProvider);
    final starred = saved.isFavorite(p);
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: CircleAvatar(
        backgroundColor: AppColors.brand.withValues(alpha: 0.16),
        child: Icon(icon ?? p.icon, color: AppColors.brandDeep),
      ),
      title: Text(
        p.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
      ),
      subtitle: p.area.isEmpty
          ? null
          : Text(p.area, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: starrable
          ? IconButton(
              tooltip: starred
                  ? S.of(context).removeFavorite
                  : S.of(context).addFavorite,
              icon: Icon(
                starred ? Icons.star_rounded : Icons.star_outline_rounded,
                color: starred ? const Color(0xFFF2A900) : AppColors.muted,
              ),
              onPressed: () =>
                  ref.read(savedPlacesProvider.notifier).toggleFavorite(p),
            )
          : null,
      onTap: () => _pick(p),
    );
  }

  Widget _header(String text) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
    child: Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w800,
        color: AppColors.muted,
        fontSize: 13,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final saved = ref.watch(savedPlacesProvider);
    final recents = ref.watch(recentsProvider);
    final isDestination = widget.purpose == SearchPurpose.destination;
    final browsing = _query.length < 2;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(70),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            child: TextField(
              autofocus: true,
              onChanged: _onChanged,
              textInputAction: TextInputAction.search,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
              decoration: InputDecoration(
                hintText: S.of(context).searchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(14),
                        child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2.5),
                        ),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
      body: ListView(
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                S.of(context).searchFailed,
                style: const TextStyle(color: AppColors.danger),
              ),
            )
          else if (browsing) ...[
            if (isDestination) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Row(
                  children: [
                    Expanded(
                      child: _HomeWorkCard(
                        icon: Icons.home_rounded,
                        label: S.of(context).home,
                        place: saved.home,
                        onSet: () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) =>
                                const SearchScreen(purpose: SearchPurpose.home),
                          ),
                        ),
                        onGo: _pick,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _HomeWorkCard(
                        icon: Icons.work_rounded,
                        label: S.of(context).work,
                        place: saved.work,
                        onSet: () => Navigator.of(context).pushReplacement(
                          MaterialPageRoute(
                            builder: (_) =>
                                const SearchScreen(purpose: SearchPurpose.work),
                          ),
                        ),
                        onGo: _pick,
                      ),
                    ),
                  ],
                ),
              ),
              if (saved.favorites.isNotEmpty) ...[
                _header(S.of(context).favoritesHeader),
                for (final f in saved.favorites)
                  _tile(f, icon: Icons.star_rounded, starrable: true),
              ],
            ],
            if (recents.isNotEmpty) ...[
              _header(S.of(context).recentHeader),
              for (final r in recents)
                _tile(r, icon: Icons.history_rounded, starrable: isDestination),
            ] else if (saved.favorites.isEmpty)
              Padding(
                padding: const EdgeInsets.all(28),
                child: Text(
                  S.of(context).searchEmpty,
                  style: const TextStyle(color: AppColors.muted, fontSize: 15),
                ),
              ),
          ] else if (_results.isEmpty && !_loading)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  S.of(context).noResults,
                  style: const TextStyle(color: AppColors.muted, fontSize: 15),
                ),
              ),
            )
          else
            for (final p in _results) _tile(p, starrable: isDestination),
        ],
      ),
    );
  }
}

class _HomeWorkCard extends StatelessWidget {
  const _HomeWorkCard({
    required this.icon,
    required this.label,
    required this.place,
    required this.onSet,
    required this.onGo,
  });

  final IconData icon;
  final String label;
  final Place? place;
  final VoidCallback onSet;
  final void Function(Place) onGo;

  @override
  Widget build(BuildContext context) {
    final p = place;
    return Material(
      color: AppColors.brand.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => p == null ? onSet() : onGo(p),
        onLongPress: onSet,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: AppColors.brandDeep, size: 30),
              const SizedBox(height: 10),
              Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 17,
                ),
              ),
              Text(
                p?.name ?? S.of(context).tapToSet,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: p == null ? AppColors.brandDeep : AppColors.muted,
                  fontWeight: p == null ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
