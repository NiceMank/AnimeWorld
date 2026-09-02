import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/local_store.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/common.dart';
import '../catalogue/catalogue_screen.dart';

class DetailsScreen extends ConsumerStatefulWidget {
  const DetailsScreen({super.key, required this.slug});
  final String slug;
  @override
  ConsumerState<DetailsScreen> createState() => _DetailsScreenState();
}

class _DetailsScreenState extends ConsumerState<DetailsScreen> {
  bool _synopsisExpanded = false;

  /// URL telle que le site l'enregistre : /catalogue/{slug}/
  String get _url => '/catalogue/${widget.slug}/';

  Future<void> _toggle(String prefix, AnimeDetails d) async {
    final store = ref.read(localStoreProvider);
    final res = await store.toggleList(
      prefix,
      ListEntry(name: d.title, url: _url, image: d.thumb),
    );
    if (!mounted) return;
    if (res == null) {
      showSnack(context, 'Tu as atteint le maximum de 500 entrées.', error: true);
      return;
    }
    final label = switch (prefix) {
      LocalStore.favPrefix => 'favoris',
      LocalStore.watchPrefix => 'watchlist',
      _ => 'vus',
    };
    showSnack(context, res ? 'Ajouté aux $label' : 'Retiré des $label');
    // Synchro serveur si connecté (comme syncFavsToServer()).
    if (ref.read(sessionProvider).loggedIn) {
      ref.read(accountRepositoryProvider).syncListByPrefix(prefix);
    }
  }

  @override
  Widget build(BuildContext context) {
    final details = ref.watch(detailsProvider(widget.slug));
    final store = ref.watch(localStoreProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: details.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => SafeArea(
          child: Column(children: [
            Align(
              alignment: Alignment.centerLeft,
              child: BackButton(onPressed: () => context.pop()),
            ),
            Expanded(
              child: ErrorView(
                message: e.toString(),
                onRetry: () => ref.invalidate(detailsProvider(widget.slug)),
              ),
            ),
          ]),
        ),
        data: (d) {
          final inFav = store.isInList(LocalStore.favPrefix, _url);
          final inWatch = store.isInList(LocalStore.watchPrefix, _url);
          final inSeen = store.isInList(LocalStore.seenPrefix, _url);
          final progressFor = _lastProgress(store, d);

          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 230,
                pinned: true,
                backgroundColor: AppColors.bg,
                leading: const BackButton(),
                actions: [
                  IconButton(
                    tooltip: 'Ouvrir sur le site',
                    icon: const Icon(Icons.open_in_new_rounded),
                    onPressed: () => launchUrl(
                      Uri.parse(ref.read(animeRepositoryProvider).absolute(_url)),
                      mode: LaunchMode.externalApplication,
                    ),
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: Stack(fit: StackFit.expand, children: [
                    NetImage(d.banner),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.2),
                            AppColors.bg.withValues(alpha: 0.6),
                            AppColors.bg,
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 12,
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          NetImage(d.thumb,
                              width: 84,
                              height: 120,
                              borderRadius: BorderRadius.circular(8)),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  d.title.toUpperCase(),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w900,
                                      height: 1.1),
                                ),
                                if (d.altTitles.isNotEmpty)
                                  Text(
                                    d.altTitles,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                        fontSize: 11,
                                        fontStyle: FontStyle.italic,
                                        color: AppColors.textMuted),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Actions
                      Row(children: [
                        _ActionBtn(
                          icon: inWatch ? Icons.bookmark : Icons.bookmark_outline,
                          label: 'Watchlist',
                          active: inWatch,
                          onTap: () => _toggle(LocalStore.watchPrefix, d),
                        ),
                        const SizedBox(width: 8),
                        _ActionBtn(
                          icon: inFav ? Icons.favorite : Icons.favorite_outline,
                          label: 'Favoris',
                          active: inFav,
                          onTap: () => _toggle(LocalStore.favPrefix, d),
                        ),
                        const SizedBox(width: 8),
                        _ActionBtn(
                          icon: inSeen ? Icons.check_circle : Icons.check_circle_outline,
                          label: 'Vu',
                          active: inSeen,
                          onTap: () => _toggle(LocalStore.seenPrefix, d),
                        ),
                      ]),

                      // Reprendre
                      if (progressFor != null) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: () => openSitePath(
                                context, progressFor.url, seasonName: progressFor.type),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: Text(
                                'Reprendre · ${progressFor.type} · ${progressFor.episode}'),
                          ),
                        ),
                      ],

                      // Info card
                      if (d.info.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: AppColors.surface.withValues(alpha: 0.7),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppColors.border),
                          ),
                          child: Wrap(
                            runSpacing: 8,
                            children: [
                              for (final e in d.info.entries)
                                SizedBox(
                                  width: e.key == 'Studio'
                                      ? double.infinity
                                      : (MediaQuery.sizeOf(context).width - 56) / 2,
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text('${e.key} ',
                                          style: const TextStyle(
                                              color: AppColors.textDim,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w700)),
                                      Expanded(
                                        child: Text(e.value,
                                            style: const TextStyle(
                                                fontSize: 12.5,
                                                fontWeight: FontWeight.w600)),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Synopsis
              if (d.synopsis.isNotEmpty) ...[
                const SliverToBoxAdapter(child: SectionTitle('Synopsis')),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: GestureDetector(
                      onTap: () => setState(() => _synopsisExpanded = !_synopsisExpanded),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AnimatedSize(
                            duration: const Duration(milliseconds: 200),
                            alignment: Alignment.topCenter,
                            child: Text(
                              d.synopsis,
                              maxLines: _synopsisExpanded ? null : 5,
                              overflow: _synopsisExpanded ? null : TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: AppColors.textMuted, height: 1.6, fontSize: 13.5),
                            ),
                          ),
                          if (d.synopsis.length > 260)
                            Text(_synopsisExpanded ? 'Voir moins' : 'Voir plus',
                                style: const TextStyle(
                                    color: AppColors.accent,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],

              // Genres
              if (d.genres.isNotEmpty) ...[
                const SliverToBoxAdapter(child: SectionTitle('Genres')),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final g in d.genres)
                          ActionChip(
                            label: Text(g),
                            onPressed: () => openGenre(context, ref, g),
                            visualDensity: VisualDensity.compact,
                          ),
                      ],
                    ),
                  ),
                ),
              ],

              // Saisons / scans
              for (final g in d.groups) ...[
                SliverToBoxAdapter(child: SectionTitle(g.title)),
                if (g.description.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Text(g.description,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textDim, height: 1.4)),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final s in g.entries)
                          _SeasonTile(
                            entry: s,
                            thumb: d.thumb,
                            progress: store.getProgressForFolder(d.slug, s.folder),
                            onTap: () {
                              final lang = _preferredLang(store, s);
                              final path = '/catalogue/${d.slug}/${s.folder}/$lang/';
                              openSitePath(context, path, seasonName: s.name);
                            },
                          ),
                      ],
                    ),
                  ),
                ),
              ],
              if (d.groups.isEmpty)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('Aucune saison disponible pour le moment.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: AppColors.textDim)),
                  ),
                ),

              // Bande-annonce
              if (d.trailerUrl != null) ...[
                const SliverToBoxAdapter(child: SectionTitle('Bande-annonce')),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _TrailerCard(url: d.trailerUrl!),
                  ),
                ),
              ],

              // Similaires
              if (d.similar.isNotEmpty) ...[
                const SliverToBoxAdapter(child: SectionTitle('Œuvres similaires')),
                SliverToBoxAdapter(
                  child: HorizontalCards(
                    height: 240,
                    itemCount: d.similar.length,
                    itemBuilder: (_, i) => CatalogueCard(d.similar[i]),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          );
        },
      ),
    );
  }

  /// Langue à ouvrir pour une saison : comme le site, la langue déclarée par
  /// la fiche (vostfr / vf). L'écran de lecture détecte ensuite les autres
  /// langues disponibles et propose le switch (la préférence utilisateur y est
  /// appliquée automatiquement si elle existe).
  String _preferredLang(LocalStore store, SeasonEntry s) => s.defaultLang;

  /// Dernière entrée d'historique correspondant à cette œuvre.
  HistoryEntry? _lastProgress(LocalStore store, AnimeDetails d) {
    final h = store.getHistory().reversed;
    for (final e in h) {
      if (e.slug == d.slug) return e;
    }
    return null;
  }
}

class _ActionBtn extends StatelessWidget {
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? AppColors.accent : AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: active ? AppColors.accent : AppColors.border),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 6),
              Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }
}

class _SeasonTile extends StatelessWidget {
  const _SeasonTile({
    required this.entry,
    required this.thumb,
    required this.onTap,
    this.progress,
  });
  final SeasonEntry entry;
  final String thumb;
  final VoidCallback onTap;
  final Progress? progress;

  @override
  Widget build(BuildContext context) {
    final w = (MediaQuery.sizeOf(context).width - 40) / 2;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        width: w,
        height: 76,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.border, width: 1.5),
        ),
        child: Stack(fit: StackFit.expand, children: [
          Opacity(opacity: 0.35, child: NetImage(thumb)),
          if (entry.isScan)
            const ColoredBox(color: Color(0x66000000)),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(entry.isScan ? Icons.menu_book_rounded : Icons.play_circle_fill_rounded,
                      size: 18, color: Colors.white),
                  const SizedBox(height: 3),
                  Text(
                    entry.name,
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: entry.name.length > 30 ? 11 : 13),
                  ),
                  if (progress != null && progress!.name.isNotEmpty)
                    Text(progress!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 10, color: AppColors.accent)),
                ],
              ),
            ),
          ),
        ]),
      ),
    );
  }
}

class _TrailerCard extends StatelessWidget {
  const _TrailerCard({required this.url});
  final String url;

  String? get _videoId {
    final m = RegExp(r'(?:embed/|v=|youtu\.be/)([\w-]{6,})').firstMatch(url);
    return m?.group(1);
  }

  @override
  Widget build(BuildContext context) {
    final id = _videoId;
    final thumb = id != null ? 'https://img.youtube.com/vi/$id/hqdefault.jpg' : '';
    final watchUrl = id != null ? 'https://www.youtube.com/watch?v=$id' : url;
    return InkWell(
      onTap: () => launchUrl(Uri.parse(watchUrl), mode: LaunchMode.externalApplication),
      borderRadius: BorderRadius.circular(10),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: Stack(fit: StackFit.expand, children: [
            NetImage(thumb),
            const ColoredBox(color: Color(0x55000000)),
            const Center(
              child: Icon(Icons.play_circle_fill_rounded, size: 64, color: Colors.white),
            ),
            const Positioned(
              right: 10,
              bottom: 8,
              child: Text('YouTube',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
    );
  }
}
