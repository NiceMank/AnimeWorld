import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/genres.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../shared/widgets/common.dart';

/// Catalogue — mêmes filtres que le formulaire GET /catalogue du site.
class CatalogueScreen extends ConsumerStatefulWidget {
  const CatalogueScreen({super.key, this.initialGenre, this.initialType});
  final String? initialGenre;
  final String? initialType;

  @override
  ConsumerState<CatalogueScreen> createState() => _CatalogueScreenState();
}

class _CatalogueScreenState extends ConsumerState<CatalogueScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
        ref.read(catalogueProvider.notifier).loadMore();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final st = ref.read(catalogueProvider);
      if (widget.initialGenre != null || widget.initialType != null) {
        ref.read(catalogueProvider.notifier).setFilters(CatalogueFilters(
          genres: widget.initialGenre != null ? {widget.initialGenre!} : {},
          types: widget.initialType != null ? {widget.initialType!} : {},
        ));
      } else if (st.items.isEmpty && !st.loading) {
        ref.read(catalogueProvider.notifier).load();
      }
      _search.text = ref.read(catalogueProvider).filters.search;
    });
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  void _toggleQuick(String key, String value) {
    final f = ref.read(catalogueProvider).filters;
    Set<String> t(Set<String> s) =>
        s.contains(value) ? ({...s}..remove(value)) : ({...s}..add(value));
    switch (key) {
      case 'type':
        ref.read(catalogueProvider.notifier).setFilters(f.copyWith(types: t(f.types)));
      case 'lang':
        ref.read(catalogueProvider.notifier).setFilters(f.copyWith(langs: t(f.langs)));
      case 'status':
        ref.read(catalogueProvider.notifier).setFilters(f.copyWith(status: t(f.status)));
    }
  }

  Future<void> _openFilters() async {
    final st = ref.read(catalogueProvider);
    final res = await showModalBottomSheet<CatalogueFilters>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FiltersSheet(initial: st.filters),
    );
    if (res != null) {
      ref.read(catalogueProvider.notifier).setFilters(res);
      _search.text = res.search;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Garde le champ de recherche synchronisé avec les filtres (ex. depuis
    // l'écran Recherche ou la fiche d'une œuvre).
    ref.listen(catalogueProvider.select((s) => s.filters.search), (_, next) {
      if (_search.text != next) _search.text = next;
    });
    final st = ref.watch(catalogueProvider);
    final f = st.filters;
    final width = MediaQuery.sizeOf(context).width;
    final cols = width > 700 ? 5 : 3;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('CATALOGUE'),
        actions: [
          const NotificationBellButton(),
          Stack(children: [
            IconButton(
              tooltip: 'Filtres',
              onPressed: _openFilters,
              icon: const Icon(Icons.tune_rounded),
            ),
            if (f.activeCount > 0)
              Positioned(
                right: 6,
                top: 6,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: const BoxDecoration(
                      color: AppColors.accent, shape: BoxShape.circle),
                  child: Text('${f.activeCount}',
                      style: const TextStyle(
                          fontSize: 9, fontWeight: FontWeight.w800)),
                ),
              ),
          ]),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
            child: TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              onSubmitted: (v) => ref
                  .read(catalogueProvider.notifier)
                  .setFilters(f.copyWith(search: v.trim())),
              decoration: InputDecoration(
                hintText: 'Rechercher dans le catalogue…',
                prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textDim),
                suffixIcon: f.search.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () {
                          _search.clear();
                          ref
                              .read(catalogueProvider.notifier)
                              .setFilters(f.copyWith(search: ''));
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 40,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final t in kCatalogueTypes)
                  _QuickChip(
                    label: t,
                    selected: f.types.contains(t),
                    onTap: () => _toggleQuick('type', t),
                  ),
                for (final l in kCatalogueLangs)
                  _QuickChip(
                    label: l,
                    selected: f.langs.contains(l),
                    onTap: () => _toggleQuick('lang', l),
                  ),
                for (final s in kCatalogueStatus)
                  _QuickChip(
                    label: s,
                    selected: f.status.contains(s),
                    onTap: () => _toggleQuick('status', s),
                  ),
                if (!f.isEmpty)
                  _QuickChip(
                    label: 'Réinitialiser',
                    icon: Icons.close_rounded,
                    selected: false,
                    onTap: () {
                      _search.clear();
                      ref.read(catalogueProvider.notifier).reset();
                    },
                  ),
              ],
            ),
          ),
          if (f.genres.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    for (final g in f.genres)
                      InputChip(
                        label: Text(g, style: const TextStyle(fontSize: 11)),
                        selected: true,
                        onDeleted: () => ref
                            .read(catalogueProvider.notifier)
                            .setFilters(f.copyWith(genres: {...f.genres}..remove(g))),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: st.loading
                ? const Center(child: CircularProgressIndicator())
                : st.error != null && st.items.isEmpty
                    ? ErrorView(
                        message: st.error!,
                        onRetry: () => ref.read(catalogueProvider.notifier).load(),
                      )
                    : st.items.isEmpty
                        ? EmptyView(
                            icon: Icons.filter_alt_off_rounded,
                            title: 'Aucun résultat',
                            subtitle: 'Essayez d\'autres filtres.',
                            actionLabel: 'Réinitialiser',
                            onAction: () =>
                                ref.read(catalogueProvider.notifier).reset(),
                          )
                        : RefreshIndicator(
                            color: AppColors.accent,
                            onRefresh: () =>
                                ref.read(catalogueProvider.notifier).load(),
                            child: GridView.builder(
                              controller: _scroll,
                              padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                              gridDelegate:
                                  SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: cols,
                                mainAxisSpacing: 12,
                                crossAxisSpacing: 10,
                                childAspectRatio: 0.47,
                              ),
                              itemCount: st.items.length + (st.hasMore ? cols : 0),
                              itemBuilder: (_, i) {
                                if (i >= st.items.length) {
                                  return const Center(
                                    child: SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    ),
                                  );
                                }
                                return CatalogueCard(st.items[i], width: double.infinity);
                              },
                            ),
                          ),
          ),
          if (!st.loading && st.items.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 4),
              alignment: Alignment.center,
              child: Text(
                'Page ${st.page} / ${st.totalPages}  ·  ${st.items.length} titres chargés',
                style: const TextStyle(fontSize: 11, color: AppColors.textDim),
              ),
            ),
        ],
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: FilterChip(
        label: Text(label),
        avatar: icon != null ? Icon(icon, size: 14) : null,
        selected: selected,
        showCheckmark: false,
        onSelected: (_) => onTap(),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Feuille de filtres complète
// ---------------------------------------------------------------------------

class FiltersSheet extends StatefulWidget {
  const FiltersSheet({super.key, required this.initial});
  final CatalogueFilters initial;
  @override
  State<FiltersSheet> createState() => _FiltersSheetState();
}

class _FiltersSheetState extends State<FiltersSheet> {
  late CatalogueFilters f = widget.initial;
  late final _yMin = TextEditingController(text: f.yearMin?.toString() ?? '');
  late final _yMax = TextEditingController(text: f.yearMax?.toString() ?? '');
  late final _eMin = TextEditingController(text: f.episodesMin?.toString() ?? '');
  late final _eMax = TextEditingController(text: f.episodesMax?.toString() ?? '');
  late final _cMin = TextEditingController(text: f.chaptersMin?.toString() ?? '');
  late final _cMax = TextEditingController(text: f.chaptersMax?.toString() ?? '');
  String _genreQuery = '';

  Set<String> _t(Set<String> s, String v) =>
      s.contains(v) ? ({...s}..remove(v)) : ({...s}..add(v));

  CatalogueFilters _build() => CatalogueFilters(
        search: f.search,
        types: f.types,
        langs: f.langs,
        status: f.status,
        genres: f.genres,
        yearMin: int.tryParse(_yMin.text),
        yearMax: int.tryParse(_yMax.text),
        episodesMin: int.tryParse(_eMin.text),
        episodesMax: int.tryParse(_eMax.text),
        chaptersMin: int.tryParse(_cMin.text),
        chaptersMax: int.tryParse(_cMax.text),
      );

  @override
  Widget build(BuildContext context) {
    final genres = kGenres
        .where((g) => g.toLowerCase().contains(_genreQuery.toLowerCase()))
        .toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (_, scroll) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
            child: Row(children: [
              const Expanded(
                child: Text('FILTRES',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
              ),
              IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded)),
            ]),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                _label('Type'),
                _chips(kCatalogueTypes, f.types,
                    (v) => setState(() => f = f.copyWith(types: _t(f.types, v)))),
                _label('Langue'),
                _chips(kCatalogueLangs, f.langs,
                    (v) => setState(() => f = f.copyWith(langs: _t(f.langs, v)))),
                _label('Statut'),
                _chips(kCatalogueStatus, f.status,
                    (v) => setState(() => f = f.copyWith(status: _t(f.status, v)))),
                _label('Année'),
                _range(_yMin, _yMax),
                _label('Épisodes'),
                _range(_eMin, _eMax),
                _label('Chapitres'),
                _range(_cMin, _cMax),
                _label('Genres (${f.genres.length})'),
                TextField(
                  decoration: const InputDecoration(
                    hintText: 'Filtrer les genres…',
                    prefixIcon: Icon(Icons.search_rounded, size: 18),
                    isDense: true,
                  ),
                  onChanged: (v) => setState(() => _genreQuery = v),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final g in genres)
                      FilterChip(
                        label: Text(g),
                        selected: f.genres.contains(g),
                        onSelected: (_) =>
                            setState(() => f = f.copyWith(genres: _t(f.genres, g))),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, const CatalogueFilters()),
                    child: const Text('Réinitialiser'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, _build()),
                    child: const Text('Appliquer'),
                  ),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: AppColors.textDim,
                letterSpacing: 0.8)),
      );

  Widget _chips(List<String> all, Set<String> sel, ValueChanged<String> on) => Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final v in all)
            FilterChip(
              label: Text(v),
              selected: sel.contains(v),
              onSelected: (_) => on(v),
              visualDensity: VisualDensity.compact,
            ),
        ],
      );

  Widget _range(TextEditingController a, TextEditingController b) => Row(children: [
        Expanded(
          child: TextField(
            controller: a,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'Min', isDense: true),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 10),
          child: Text('—', style: TextStyle(color: AppColors.textDim)),
        ),
        Expanded(
          child: TextField(
            controller: b,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(hintText: 'Max', isDense: true),
          ),
        ),
      ]);
}

/// Raccourci : ouvrir le catalogue filtré sur un genre.
void openGenre(BuildContext context, WidgetRef ref, String genre) {
  ref.read(catalogueProvider.notifier).setFilters(CatalogueFilters(genres: {genre}));
  context.go('/catalogue');
}
