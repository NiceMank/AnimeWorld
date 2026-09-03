import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/local_store.dart';
import '../../data/models/models.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../shared/widgets/common.dart';

/// Bibliothèque — équivalent de la section « pf-library » de /profil :
/// onglets Historique / Watchlist / Favoris / Vus, recherche, tri, filtres
/// type & langue, suppression, vider la liste.
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, this.initialTab = 0});
  final int initialTab;
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs =
      TabController(length: 4, vsync: this, initialIndex: widget.initialTab.clamp(0, 3));
  String _q = '';
  String _sort = 'recent'; // recent | old | az | za
  String _type = 'all'; // all | Anime | Scans
  String _lang = 'all';

  @override
  void didUpdateWidget(covariant LibraryScreen old) {
    super.didUpdateWidget(old);
    if (old.initialTab != widget.initialTab) _tabs.index = widget.initialTab.clamp(0, 3);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _confirmClear(String label, Future<void> Function() action) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Vider la liste ?'),
        content: Text('Tous les éléments de « $label » seront supprimés.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Vider', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (ok == true) await action();
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(localStoreProvider);
    final session = ref.watch(sessionProvider);
    final acc = ref.read(accountRepositoryProvider);

    final history = store.getHistory();
    final watch = store.getList(LocalStore.watchPrefix);
    final fav = store.getList(LocalStore.favPrefix);
    final seen = store.getList(LocalStore.seenPrefix);

    final langs = <String>{for (final h in history) if (h.lang.isNotEmpty) h.lang};

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('BIBLIOTHÈQUE'),
        actions: [
          const NotificationBellButton(),
          IconButton(
            tooltip: 'Vider la liste',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: () {
              switch (_tabs.index) {
                case 0:
                  _confirmClear('Historique', () async {
                    await store.clearHistory();
                    if (session.loggedIn) acc.syncHistory();
                  });
                case 1:
                  _confirmClear('Watchlist', () async {
                    await store.clearList(LocalStore.watchPrefix);
                    if (session.loggedIn) acc.syncWatchlist();
                  });
                case 2:
                  _confirmClear('Favoris', () async {
                    await store.clearList(LocalStore.favPrefix);
                    if (session.loggedIn) acc.syncFavorites();
                  });
                default:
                  _confirmClear('Vus', () async {
                    await store.clearList(LocalStore.seenPrefix);
                    if (session.loggedIn) acc.syncViewed();
                  });
              }
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          onTap: (_) => setState(() {}),
          tabs: [
            _tab('Historique', history.length),
            _tab('Watchlist', watch.length),
            _tab('Favoris', fav.length),
            _tab('Vus', seen.length),
          ],
        ),
      ),
      body: Column(children: [
        _Toolbar(
          sort: _sort,
          type: _type,
          lang: _lang,
          langs: langs.toList()..sort(),
          showLang: _tabs.index == 0,
          onQuery: (v) => setState(() => _q = v),
          onSort: (v) => setState(() => _sort = v),
          onType: (v) => setState(() => _type = v),
          onLang: (v) => setState(() => _lang = v),
        ),
        Expanded(
          child: TabBarView(
            controller: _tabs,
            children: [
              _HistoryList(
                entries: _filterHistory(history),
                onRemove: (e) async {
                  await store.removeHistory(e.url);
                  if (session.loggedIn) acc.syncHistory();
                },
              ),
              _EntriesGrid(
                entries: _filterEntries(watch),
                emptyIcon: Icons.bookmark_outline_rounded,
                emptyTitle: 'Votre watchlist est vide',
                onRemove: (e) async {
                  await store.removeFromList(LocalStore.watchPrefix, e.url);
                  if (session.loggedIn) acc.syncWatchlist();
                },
              ),
              _EntriesGrid(
                entries: _filterEntries(fav),
                emptyIcon: Icons.favorite_outline_rounded,
                emptyTitle: 'Aucun favori pour le moment',
                onRemove: (e) async {
                  await store.removeFromList(LocalStore.favPrefix, e.url);
                  if (session.loggedIn) acc.syncFavorites();
                },
              ),
              _EntriesGrid(
                entries: _filterEntries(seen),
                emptyIcon: Icons.check_circle_outline_rounded,
                emptyTitle: 'Aucune œuvre marquée comme vue',
                onRemove: (e) async {
                  await store.removeFromList(LocalStore.seenPrefix, e.url);
                  if (session.loggedIn) acc.syncViewed();
                },
              ),
            ],
          ),
        ),
      ]),
    );
  }

  Tab _tab(String label, int count) => Tab(
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(label),
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text('$count',
                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w800)),
          ),
        ]),
      );

  List<HistoryEntry> _filterHistory(List<HistoryEntry> h) {
    // Le site stocke le plus récent en dernier.
    var list = h.reversed.toList();
    if (_q.isNotEmpty) {
      list = list.where((e) => e.name.toLowerCase().contains(_q.toLowerCase())).toList();
    }
    if (_type == 'Anime') list = list.where((e) => !e.isScan).toList();
    if (_type == 'Scans') list = list.where((e) => e.isScan).toList();
    if (_lang != 'all') list = list.where((e) => e.lang == _lang).toList();
    switch (_sort) {
      case 'old':
        list = list.reversed.toList();
      case 'az':
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case 'za':
        list.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
    }
    return list;
  }

  List<ListEntry> _filterEntries(List<ListEntry> l) {
    var list = l.reversed.toList();
    if (_q.isNotEmpty) {
      list = list.where((e) => e.name.toLowerCase().contains(_q.toLowerCase())).toList();
    }
    switch (_sort) {
      case 'old':
        list = list.reversed.toList();
      case 'az':
        list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      case 'za':
        list.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase()));
    }
    return list;
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.sort,
    required this.type,
    required this.lang,
    required this.langs,
    required this.showLang,
    required this.onQuery,
    required this.onSort,
    required this.onType,
    required this.onLang,
  });
  final String sort, type, lang;
  final List<String> langs;
  final bool showLang;
  final ValueChanged<String> onQuery, onSort, onType, onLang;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: Column(children: [
        TextField(
          onChanged: onQuery,
          decoration: const InputDecoration(
            hintText: 'Rechercher dans cette liste…',
            prefixIcon: Icon(Icons.search_rounded, size: 20),
            isDense: true,
          ),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 36,
          child: ListView(scrollDirection: Axis.horizontal, children: [
            _DropChip(
              value: sort,
              items: const {
                'recent': 'Plus récent',
                'old': 'Plus ancien',
                'az': 'Nom (A → Z)',
                'za': 'Nom (Z → A)',
              },
              onChanged: onSort,
            ),
            if (showLang) ...[
              const SizedBox(width: 6),
              _Seg(value: type, items: const ['all', 'Anime', 'Scans'], labels: const ['Tous', 'Anime', 'Scans'], onChanged: onType),
              const SizedBox(width: 6),
              _DropChip(
                value: lang,
                items: {'all': 'Toutes les langues', for (final l in langs) l: l},
                onChanged: onLang,
              ),
            ],
          ]),
        ),
      ]),
    );
  }
}

class _DropChip extends StatelessWidget {
  const _DropChip({required this.value, required this.items, required this.onChanged});
  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      initialValue: value,
      onSelected: onChanged,
      color: AppColors.surface2,
      itemBuilder: (_) => [
        for (final e in items.entries) PopupMenuItem(value: e.key, child: Text(e.value)),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Text(items[value] ?? value, style: const TextStyle(fontSize: 12)),
          const Icon(Icons.expand_more_rounded, size: 16),
        ]),
      ),
    );
  }
}

class _Seg extends StatelessWidget {
  const _Seg({required this.value, required this.items, required this.labels, required this.onChanged});
  final String value;
  final List<String> items;
  final List<String> labels;
  final ValueChanged<String> onChanged;
  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (var i = 0; i < items.length; i++)
          InkWell(
            onTap: () => onChanged(items[i]),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: value == items[i] ? AppColors.accent.withValues(alpha: 0.25) : null,
                borderRadius: BorderRadius.circular(7),
              ),
              child: Text(labels[i],
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: value == items[i] ? FontWeight.w800 : FontWeight.w500)),
            ),
          ),
      ]),
    );
  }
}

class _HistoryList extends StatelessWidget {
  const _HistoryList({required this.entries, required this.onRemove});
  final List<HistoryEntry> entries;
  final ValueChanged<HistoryEntry> onRemove;
  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return EmptyView(
        icon: Icons.history_rounded,
        title: 'Historique vide',
        subtitle: 'Les épisodes et chapitres que vous ouvrez apparaîtront ici.',
        actionLabel: 'Explorer le catalogue',
        onAction: () => context.go('/catalogue'),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1, indent: 80),
      itemBuilder: (_, i) {
        final e = entries[i];
        return Dismissible(
          key: ValueKey(e.url),
          direction: DismissDirection.endToStart,
          background: Container(
            color: AppColors.danger.withValues(alpha: 0.3),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 20),
            child: const Icon(Icons.delete_outline_rounded),
          ),
          onDismissed: (_) => onRemove(e),
          child: ListTile(
            onTap: () => openSitePath(context, e.url, seasonName: e.type),
            leading: NetImage(e.image,
                width: 56, height: 56, borderRadius: BorderRadius.circular(6)),
            title: Text(e.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700)),
            subtitle: Row(children: [
              TypeBadge(e.isScan ? 'Scans' : 'Anime'),
              const SizedBox(width: 6),
              if (e.lang.isNotEmpty) FlagIcon(e.lang, width: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '${e.type.isNotEmpty ? '${e.type} · ' : ''}${e.episode}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textDim),
                ),
              ),
            ]),
            trailing: IconButton(
              icon: const Icon(Icons.play_circle_fill_rounded, color: AppColors.accent, size: 30),
              onPressed: () => openSitePath(context, e.url, seasonName: e.type),
            ),
          ),
        );
      },
    );
  }
}

class _EntriesGrid extends StatelessWidget {
  const _EntriesGrid({
    required this.entries,
    required this.emptyIcon,
    required this.emptyTitle,
    required this.onRemove,
  });
  final List<ListEntry> entries;
  final IconData emptyIcon;
  final String emptyTitle;
  final ValueChanged<ListEntry> onRemove;
  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return EmptyView(
        icon: emptyIcon,
        title: emptyTitle,
        subtitle: 'Ajoutez des œuvres depuis leur fiche.',
        actionLabel: 'Explorer le catalogue',
        onAction: () => context.go('/catalogue'),
      );
    }
    final cols = MediaQuery.sizeOf(context).width > 700 ? 5 : 3;
    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        mainAxisSpacing: 12,
        crossAxisSpacing: 10,
        childAspectRatio: 0.5,
      ),
      itemCount: entries.length,
      itemBuilder: (_, i) {
        final e = entries[i];
        return Stack(children: [
          PosterCard(
            title: e.name,
            image: e.image,
            width: double.infinity,
            onTap: () => context.push('/anime/${e.slug}'),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: InkWell(
              onTap: () => onRemove(e),
              borderRadius: BorderRadius.circular(12),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded, size: 14),
              ),
            ),
          ),
        ]);
      },
    );
  }
}
