import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/constants/languages.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/common.dart';
import 'embed_player.dart';

/// Page de visionnage — équivalent de /catalogue/{slug}/{saison}/{lang}/.
///
/// Reproduit `videos.js` : sélecteur d'épisode et de lecteur, navigation
/// précédent/dernier/suivant, sauvegarde de la progression (savedEpName/Nb)
/// et de l'historique, switch de langue, message d'indisponibilité.
class EpisodeScreen extends ConsumerStatefulWidget {
  const EpisodeScreen({
    super.key,
    required this.slug,
    required this.folder,
    required this.lang,
    this.seasonName,
  });
  final String slug;
  final String folder;
  final String lang;
  final String? seasonName;

  @override
  ConsumerState<EpisodeScreen> createState() => _EpisodeScreenState();
}

class _EpisodeScreenState extends ConsumerState<EpisodeScreen> {
  int _episode = 0;
  int _player = 0;
  bool _initialized = false;
  bool _fullscreen = false;
  final _listKey = GlobalKey();
  final _scrollCtrl = ScrollController();

  /// Clé globale du lecteur : permet de déplacer la WebView entre la mise en
  /// page portrait et le plein écran sans recharger la vidéo.
  GlobalKey _playerKey = GlobalKey();
  String? _playerKeyUrl;

  String get _key => '${widget.slug}|${widget.folder}|${widget.lang}';

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _exitFullscreen(restoreOnly: true);
    _scrollCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Progression / historique (même logique que setCorrectEpisode/refreshVariables)
  // ---------------------------------------------------------------------------

  void _initFromStore(EpisodePage page) {
    if (_initialized) return;
    _initialized = true;
    final store = ref.read(localStoreProvider);
    final saved = store.getProgress(page.path);
    var idx = saved?.num ?? 0;
    // Le NOM fait foi si l'index ne correspond plus
    if (saved != null &&
        (idx >= page.episodeNames.length || page.episodeNames[idx] != saved.name)) {
      final byName = page.episodeNames.indexOf(saved.name);
      if (byName >= 0) idx = byName;
    }
    _episode = idx.clamp(0, (page.episodeCount - 1).clamp(0, 1 << 20));
    _player = store.preferredPlayer.clamp(0, (page.players.length - 1).clamp(0, 99));
    // Si le lecteur préféré n'a pas cet épisode, on prend le premier qui l'a
    if (page.urlFor(_player, _episode) == null) {
      for (var i = 0; i < page.players.length; i++) {
        if (page.urlFor(i, _episode) != null) {
          _player = i;
          break;
        }
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _persist(page));
  }

  Future<void> _persist(EpisodePage page) async {
    if (!page.hasEpisodes) return;
    final store = ref.read(localStoreProvider);
    final name = page.episodeNames[_episode];
    await store.setProgress(page.path, name, _episode);
    await store.markWatched(page.path, _episode);
    // Langue affichée dans l'historique (VOSTFR/VF/VKR…)
    final lang = langFromCode(widget.lang).historyLabel;
    await store.addHistory(HistoryEntry(
      name: page.title,
      url: page.path,
      image: page.banner,
      type: page.seasonName.isNotEmpty ? page.seasonName : (widget.seasonName ?? ''),
      lang: lang,
      episode: name,
      num: _episode,
    ));
    if (ref.read(sessionProvider).loggedIn) {
      ref.read(accountRepositoryProvider).syncHistory();
    }
  }

  void _select(EpisodePage page, {int? episode, int? player}) {
    setState(() {
      if (episode != null) _episode = episode.clamp(0, page.episodeCount - 1);
      if (player != null) {
        _player = player.clamp(0, page.players.length - 1);
        ref.read(localStoreProvider).setPreferredPlayer(_player);
      }
    });
    _persist(page);
  }

  // ---------------------------------------------------------------------------
  // Plein écran
  // ---------------------------------------------------------------------------

  void _enterFullscreen() {
    setState(() => _fullscreen = true);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  void _exitFullscreen({bool restoreOnly = false}) {
    if (!restoreOnly) setState(() => _fullscreen = false);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final pageAsync = ref.watch(episodePageProvider(_key));

    return PopScope(
      canPop: !_fullscreen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _fullscreen) _exitFullscreen();
      },
      child: Scaffold(
        backgroundColor: _fullscreen ? Colors.black : Colors.transparent,
        appBar: _fullscreen
            ? null
            : AppBar(
                title: Text(
                  (widget.seasonName ?? pageAsync.asData?.value.seasonName ?? '')
                      .toUpperCase(),
                  style: const TextStyle(fontSize: 14),
                ),
                actions: [
                  IconButton(
                    tooltip: 'Fiche',
                    icon: const Icon(Icons.info_outline_rounded),
                    onPressed: () => context.push('/anime/${widget.slug}'),
                  ),
                ],
              ),
        body: pageAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorView(
            message: e.toString(),
            onRetry: () => ref.invalidate(episodePageProvider(_key)),
          ),
          data: (page) {
            _initFromStore(page);
            if (_fullscreen) return _buildFullscreen(page);
            return _buildPortrait(page);
          },
        ),
      ),
    );
  }

  Widget _buildPlayer(EpisodePage page, {required bool fullscreen}) {
    if (!page.hasEpisodes) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Stack(fit: StackFit.expand, children: [
          NetImage(page.banner),
          const ColoredBox(color: Color(0xAA000000)),
          const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Aucun épisode disponible pour le moment.\nRevenez plus tard ou changez de langue.',
                textAlign: TextAlign.center,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ]),
      );
    }
    final url = page.urlFor(_player, _episode);
    if (url == null) {
      return AspectRatio(
        aspectRatio: 16 / 9,
        child: Container(
          color: AppColors.surface,
          alignment: Alignment.center,
          padding: const EdgeInsets.all(16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.videocam_off_rounded, size: 40, color: AppColors.textDim),
            const SizedBox(height: 8),
            const Text('Cet épisode n\'est pas disponible sur ce lecteur.',
                textAlign: TextAlign.center),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: () {
                for (var i = 0; i < page.players.length; i++) {
                  if (page.urlFor(i, _episode) != null) {
                    _select(page, player: i);
                    break;
                  }
                }
              },
              child: const Text('Changer de lecteur'),
            ),
          ]),
        ),
      );
    }
    if (_playerKeyUrl != url) {
      _playerKey = GlobalKey();
      _playerKeyUrl = url;
    }
    return EmbedPlayer(
      key: _playerKey,
      url: url,
      onToggleFullscreen: fullscreen ? _exitFullscreen : _enterFullscreen,
      isFullscreen: fullscreen,
      onOpenExternal: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
    );
  }

  Widget _buildFullscreen(EpisodePage page) {
    return Stack(children: [
      Positioned.fill(child: _buildPlayer(page, fullscreen: true)),
      Positioned(
        top: 8,
        left: 8,
        child: SafeArea(
          child: Row(children: [
            IconButton.filledTonal(
              onPressed: _exitFullscreen,
              icon: const Icon(Icons.arrow_back_rounded),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${page.title} — ${page.episodeNames[_episode]}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ]),
        ),
      ),
      Positioned(
        bottom: 8,
        right: 8,
        child: SafeArea(
          child: Row(children: [
            IconButton.filledTonal(
              tooltip: 'Épisode précédent',
              onPressed: _episode > 0 ? () => _select(page, episode: _episode - 1) : null,
              icon: const Icon(Icons.skip_previous_rounded),
            ),
            IconButton.filledTonal(
              tooltip: 'Épisode suivant',
              onPressed: _episode < page.episodeCount - 1
                  ? () => _select(page, episode: _episode + 1)
                  : null,
              icon: const Icon(Icons.skip_next_rounded),
            ),
            IconButton.filledTonal(
              tooltip: 'Lecteur',
              onPressed: () => _showPlayerSheet(page),
              icon: const Icon(Icons.dvr_rounded),
            ),
          ]),
        ),
      ),
    ]);
  }

  Widget _buildPortrait(EpisodePage page) {
    final store = ref.watch(localStoreProvider);
    final watched = store.getWatchedIndexes(page.path);
    final saved = store.getProgress(page.path);

    return CustomScrollView(
      controller: _scrollCtrl,
      slivers: [
        SliverToBoxAdapter(child: _buildPlayer(page, fullscreen: false)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Titre + saison
                InkWell(
                  onTap: () => context.push('/anime/${widget.slug}'),
                  child: Row(children: [
                    NetImage(page.banner,
                        width: 64, height: 40, borderRadius: BorderRadius.circular(6)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(page.title.toUpperCase(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.w900, fontSize: 16)),
                          Text(
                            (page.seasonName.isNotEmpty
                                    ? page.seasonName
                                    : (widget.seasonName ?? ''))
                                .toUpperCase(),
                            style: const TextStyle(
                                color: AppColors.textDim,
                                fontWeight: FontWeight.w700,
                                fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
                  ]),
                ),
                const SizedBox(height: 10),

                // Langues
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final code in page.availableLangs)
                      LangPill(
                        label: langFromCode(code).label,
                        flag: langFromCode(code).flag,
                        selected: code == widget.lang,
                        onTap: code == widget.lang
                            ? () {}
                            : () {
                                ref.read(localStoreProvider).setPreferredLang(code);
                                context.pushReplacement(
                                  '/watch/${widget.slug}/${widget.folder}/$code'
                                  '${widget.seasonName != null ? '?name=${Uri.encodeQueryComponent(widget.seasonName!)}' : ''}',
                                );
                              },
                      ),
                  ],
                ),

                if (page.message.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
                    ),
                    child: Text(page.message, style: const TextStyle(fontSize: 12.5)),
                  ),
                ],

                if (page.hasEpisodes) ...[
                  const SizedBox(height: 12),
                  // Sélecteurs épisode / lecteur
                  Row(children: [
                    Expanded(
                      flex: 3,
                      child: _Selector(
                        icon: Icons.play_circle_outline_rounded,
                        label: page.episodeNames[_episode],
                        onTap: () => _showEpisodeSheet(page),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: _Selector(
                        icon: Icons.dvr_rounded,
                        label: 'Lecteur ${page.players[_player].index}',
                        onTap: () => _showPlayerSheet(page),
                      ),
                    ),
                  ]),
                  if (saved != null) ...[
                    const SizedBox(height: 6),
                    Text(
                      'DERNIÈRE SÉLECTION : ${saved.name}'.toUpperCase(),
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.textDim, letterSpacing: 0.5),
                    ),
                  ],
                  const SizedBox(height: 10),
                  // Navigation
                  Row(children: [
                    Expanded(
                      child: _NavBtn(
                        icon: Icons.chevron_left_rounded,
                        label: 'Précédent',
                        onTap: _episode > 0
                            ? () => _select(page, episode: _episode - 1)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _NavBtn(
                        icon: Icons.last_page_rounded,
                        label: 'Dernier',
                        onTap: () => _select(page, episode: page.episodeCount - 1),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _NavBtn(
                        icon: Icons.chevron_right_rounded,
                        label: 'Suivant',
                        trailingIcon: true,
                        onTap: _episode < page.episodeCount - 1
                            ? () => _select(page, episode: _episode + 1)
                            : null,
                      ),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  const Text(
                    'Pub insistante ou vidéo indisponible ? Changez de lecteur.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 12, fontStyle: FontStyle.italic, color: AppColors.textMuted),
                  ),
                ],
              ],
            ),
          ),
        ),

        if (page.hasEpisodes) ...[
          SliverToBoxAdapter(
            child: SectionTitle(
              'Épisodes (${page.episodeCount})',
              trailing: TextButton.icon(
                onPressed: () => _showEpisodeSheet(page),
                icon: const Icon(Icons.grid_view_rounded, size: 16),
                label: const Text('Grille', style: TextStyle(fontSize: 12)),
              ),
            ),
          ),
          SliverList.builder(
            key: _listKey,
            itemCount: page.episodeCount,
            itemBuilder: (_, i) {
              final selected = i == _episode;
              final seen = watched.contains(i);
              final available = page.urlFor(_player, i) != null;
              return ListTile(
                dense: true,
                selected: selected,
                selectedTileColor: AppColors.accent.withValues(alpha: 0.18),
                onTap: () => _select(page, episode: i),
                leading: Icon(
                  selected
                      ? Icons.play_arrow_rounded
                      : (seen ? Icons.check_circle_rounded : Icons.play_circle_outline_rounded),
                  color: selected
                      ? AppColors.accent
                      : (seen ? AppColors.success : AppColors.textDim),
                ),
                title: Text(
                  page.episodeNames[i],
                  style: TextStyle(
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                    color: available ? null : AppColors.textDim,
                  ),
                ),
                trailing: !available
                    ? const Text('Autre lecteur',
                        style: TextStyle(fontSize: 10, color: AppColors.textDim))
                    : null,
              );
            },
          ),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Bottom sheets
  // ---------------------------------------------------------------------------

  Future<void> _showEpisodeSheet(EpisodePage page) async {
    final store = ref.read(localStoreProvider);
    final watched = store.getWatchedIndexes(page.path);
    final res = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EpisodeGridSheet(
        names: page.episodeNames,
        current: _episode,
        watched: watched,
      ),
    );
    if (res != null) _select(page, episode: res);
  }

  Future<void> _showPlayerSheet(EpisodePage page) async {
    final res = await showModalBottomSheet<int>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text('CHOISIR UN LECTEUR',
                  style: TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
          for (var i = 0; i < page.players.length; i++)
            ListTile(
              selected: i == _player,
              selectedTileColor: AppColors.accent.withValues(alpha: 0.15),
              leading: Icon(
                i == _player ? Icons.radio_button_checked : Icons.radio_button_off,
                color: i == _player ? AppColors.accent : AppColors.textDim,
              ),
              title: Text('Lecteur ${page.players[i].index}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text(
                '${page.players[i].host} · ${page.players[i].urls.length} épisodes'
                '${page.urlFor(i, _episode) == null ? ' · épisode courant indisponible' : ''}',
                style: const TextStyle(fontSize: 11, color: AppColors.textDim),
              ),
              onTap: () => Navigator.pop(context, i),
            ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (res != null) _select(page, player: res);
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

class _Selector extends StatelessWidget {
  const _Selector({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.accentDark, width: 1.5),
        ),
        child: Row(children: [
          Icon(icon, size: 18, color: AppColors.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5)),
          ),
          const Icon(Icons.expand_more_rounded, size: 18),
        ]),
      ),
    );
  }
}

class _NavBtn extends StatelessWidget {
  const _NavBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.trailingIcon = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool trailingIcon;
  @override
  Widget build(BuildContext context) {
    final children = [
      Icon(icon, size: 18),
      const SizedBox(width: 2),
      Flexible(
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      ),
    ];
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        backgroundColor: AppColors.surface.withValues(alpha: 0.7),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: trailingIcon ? children.reversed.toList() : children,
      ),
    );
  }
}

class _EpisodeGridSheet extends StatefulWidget {
  const _EpisodeGridSheet({
    required this.names,
    required this.current,
    required this.watched,
  });
  final List<String> names;
  final int current;
  final Set<int> watched;
  @override
  State<_EpisodeGridSheet> createState() => _EpisodeGridSheetState();
}

class _EpisodeGridSheetState extends State<_EpisodeGridSheet> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final indexes = <int>[];
    for (var i = 0; i < widget.names.length; i++) {
      if (_q.isEmpty || widget.names[i].toLowerCase().contains(_q.toLowerCase())) {
        indexes.add(i);
      }
    }
    // Les libellés sont-ils tous numériques ("Episode N") ? → grille compacte
    final numeric = widget.names.every((n) => RegExp(r'^Episode \d+$').hasMatch(n));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, scroll) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(children: [
            const Expanded(
              child: Text('CHOISIR UN ÉPISODE',
                  style: TextStyle(fontWeight: FontWeight.w900)),
            ),
            IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            keyboardType: numeric ? TextInputType.number : TextInputType.text,
            decoration: const InputDecoration(
              hintText: 'Aller à l\'épisode…',
              prefixIcon: Icon(Icons.search_rounded, size: 18),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _q = v.trim()),
            onSubmitted: (v) {
              // Saisie directe d'un numéro (comme l'appui long sur le select)
              final n = int.tryParse(v.trim());
              if (n != null && n >= 1 && n <= widget.names.length) {
                Navigator.pop(context, n - 1);
              } else if (indexes.isNotEmpty) {
                Navigator.pop(context, indexes.first);
              }
            },
          ),
        ),
        Expanded(
          child: numeric
              ? GridView.builder(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 64,
                    mainAxisSpacing: 8,
                    crossAxisSpacing: 8,
                  ),
                  itemCount: indexes.length,
                  itemBuilder: (_, k) {
                    final i = indexes[k];
                    final sel = i == widget.current;
                    final seen = widget.watched.contains(i);
                    return InkWell(
                      onTap: () => Navigator.pop(context, i),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        decoration: BoxDecoration(
                          color: sel ? AppColors.accent : AppColors.surface2,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                              color: sel ? AppColors.accent : AppColors.border),
                        ),
                        child: Stack(children: [
                          Center(
                            child: Text(
                              widget.names[i].replaceFirst('Episode ', ''),
                              style: const TextStyle(
                                  fontWeight: FontWeight.w800, fontSize: 14),
                            ),
                          ),
                          if (seen && !sel)
                            const Positioned(
                              right: 4,
                              bottom: 3,
                              child: Icon(Icons.check_rounded,
                                  size: 12, color: AppColors.success),
                            ),
                        ]),
                      ),
                    );
                  },
                )
              : ListView.builder(
                  controller: scroll,
                  itemCount: indexes.length,
                  itemBuilder: (_, k) {
                    final i = indexes[k];
                    final sel = i == widget.current;
                    return ListTile(
                      dense: true,
                      selected: sel,
                      selectedTileColor: AppColors.accent.withValues(alpha: 0.18),
                      leading: Icon(
                        widget.watched.contains(i)
                            ? Icons.check_circle_rounded
                            : Icons.play_circle_outline_rounded,
                        color: widget.watched.contains(i)
                            ? AppColors.success
                            : AppColors.textDim,
                      ),
                      title: Text(widget.names[i]),
                      onTap: () => Navigator.pop(context, i),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}
