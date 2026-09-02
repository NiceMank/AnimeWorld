import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../core/constants/app_constants.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/common.dart';

/// Lecteur de scans — équivalent de /catalogue/{slug}/scan/{lang}/ (scans.js).
///
/// * chapitres depuis `/s2/scans/get_nb_chap_et_img.php?oeuvre=…`
/// * images `/s2/scans/{oeuvre}/{chapitre}/{n}.jpg`
/// * mode Scroll ou Page par page (dossier « pp » si disponible)
/// * fond #020D18 / blanc / noir, plein écran
/// * progression `savedChapName/savedChapNb` + historique
class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
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
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  int _chapter = 0; // index dans chapterNames
  int _page = 0; // page courante (mode page)
  bool _initialized = false;
  bool _immersive = false;
  bool _showBars = true;
  final _scroll = ScrollController();
  PageController? _pageCtrl;

  String get _key => '${widget.slug}|${widget.folder}|${widget.lang}';

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    _scroll.dispose();
    super.dispose();
  }

  void _initFromStore(ScanPage page) {
    if (_initialized) return;
    _initialized = true;
    final store = ref.read(localStoreProvider);
    final saved = store.getProgress(page.path);
    var idx = saved?.num ?? 0;
    if (saved != null &&
        (idx >= page.chapterNames.length || page.chapterNames[idx] != saved.name)) {
      final byName = page.chapterNames.indexOf(saved.name);
      if (byName >= 0) idx = byName;
    }
    _chapter = idx.clamp(0, (page.chapterNames.length - 1).clamp(0, 1 << 20));
    WidgetsBinding.instance.addPostFrameCallback((_) => _persist(page));
  }

  Future<void> _persist(ScanPage page) async {
    if (!page.hasChapters) return;
    final store = ref.read(localStoreProvider);
    final name = page.chapterNames[_chapter];
    await store.setProgress(page.path, name, _chapter);
    final lang = widget.lang == 'va' ? 'VA' : 'VF';
    await store.addHistory(HistoryEntry(
      name: page.title.trim(),
      url: page.path,
      image: page.banner,
      type: page.seasonName.isNotEmpty ? page.seasonName : (widget.seasonName ?? 'Scans'),
      lang: lang,
      episode: name,
      num: _chapter,
    ));
    if (ref.read(sessionProvider).loggedIn) {
      ref.read(accountRepositoryProvider).syncHistory();
    }
  }

  void _goChapter(ScanPage page, int idx, {int startPage = 0}) {
    setState(() {
      _chapter = idx.clamp(0, page.chapterNames.length - 1);
      _page = startPage;
      _pageCtrl = null; // recréé par le nouveau _PageMode (clé = chapitre)
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
    _persist(page);
  }

  // Numéro réel du chapitre = index + 1 (comme scans.js : realChap = index+1)
  int _realChapter() => _chapter + 1;

  int _pagesCount(ScanPage page, {required bool pp}) {
    final real = _realChapter();
    if (pp && page.pagesPerChapterPP != null && page.pagesPerChapterPP![real] != null) {
      return page.pagesPerChapterPP![real]!;
    }
    return page.pagesPerChapter[real] ?? 0;
  }

  void _toggleImmersive() {
    setState(() {
      _immersive = !_immersive;
      _showBars = !_immersive;
    });
    SystemChrome.setEnabledSystemUIMode(
      _immersive ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
    );
  }

  @override
  Widget build(BuildContext context) {
    final pageAsync = ref.watch(scanPageProvider(_key));
    final store = ref.watch(localStoreProvider);
    final bg = Color(store.readerBg);
    final isPageMode = store.readingMode == 'page';

    return Scaffold(
      backgroundColor: bg,
      appBar: (_immersive && !_showBars)
          ? null
          : AppBar(
              backgroundColor: bg == Colors.white ? Colors.white : AppColors.bg,
              foregroundColor: bg == Colors.white ? Colors.black : Colors.white,
              title: Text(
                (pageAsync.asData?.value.title.trim() ?? '').toUpperCase(),
                style: const TextStyle(fontSize: 14),
              ),
              actions: [
                IconButton(
                  tooltip: 'Options de lecture',
                  icon: const Icon(Icons.tune_rounded),
                  onPressed: () => _showOptions(store),
                ),
                IconButton(
                  tooltip: 'Plein écran',
                  icon: Icon(_immersive ? Icons.fullscreen_exit : Icons.fullscreen),
                  onPressed: _toggleImmersive,
                ),
              ],
            ),
      body: pageAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(scanPageProvider(_key)),
        ),
        data: (page) {
          _initFromStore(page);
          if (!page.hasChapters) {
            return EmptyView(
              icon: Icons.menu_book_outlined,
              title: 'Aucun chapitre disponible',
              subtitle: page.message.isNotEmpty
                  ? page.message
                  : 'Ces scans ne sont pas encore disponibles.',
              actionLabel: 'Retour',
              onAction: () => context.pop(),
            );
          }
          final usePP = isPageMode &&
              page.pagesPerChapterPP != null &&
              page.pagesPerChapterPP![_realChapter()] != null;
          final count = _pagesCount(page, pp: usePP);
          final repo = ref.read(animeRepositoryProvider);
          final urls = [
            for (var i = 1; i <= count; i++)
              repo.scanImageUrl(page.title, _realChapter(), i, pp: usePP),
          ];

          return Column(children: [
            if (!_immersive || _showBars) _Toolbar(page: page, state: this, bg: bg),
            Expanded(
              child: GestureDetector(
                onTap: _immersive ? () => setState(() => _showBars = !_showBars) : null,
                child: isPageMode
                    ? _PageMode(
                        key: ValueKey('page-$_chapter-$usePP'),
                        urls: urls,
                        initialPage: _page,
                        bg: bg,
                        onPageChanged: (p) => setState(() => _page = p),
                        onPrevChapter: _chapter > 0
                            ? () => _goChapter(page, _chapter - 1)
                            : null,
                        onNextChapter: _chapter < page.chapterNames.length - 1
                            ? () => _goChapter(page, _chapter + 1)
                            : null,
                        controllerHolder: (c) => _pageCtrl = c,
                      )
                    : _ScrollMode(
                        urls: urls,
                        controller: _scroll,
                        bg: bg,
                        chapterLabel: page.chapterNames[_chapter],
                        onNextChapter: _chapter < page.chapterNames.length - 1
                            ? () => _goChapter(page, _chapter + 1)
                            : null,
                        onPrevChapter:
                            _chapter > 0 ? () => _goChapter(page, _chapter - 1) : null,
                      ),
              ),
            ),
            if (isPageMode && (!_immersive || _showBars))
              _PageNavBar(
                page: _page,
                total: count,
                bg: bg,
                onPrev: () {
                  if (_page > 0) {
                    _pageCtrl?.previousPage(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut);
                  } else if (_chapter > 0) {
                    // première page → chapitre précédent, dernière page
                    final prevReal = _chapter; // (index-1)+1
                    final n = page.pagesPerChapter[prevReal] ?? 1;
                    _goChapter(page, _chapter - 1, startPage: n - 1);
                  }
                },
                onNext: () {
                  if (_page < count - 1) {
                    _pageCtrl?.nextPage(
                        duration: const Duration(milliseconds: 200),
                        curve: Curves.easeOut);
                  } else if (_chapter < page.chapterNames.length - 1) {
                    _goChapter(page, _chapter + 1);
                  }
                },
              ),
          ]);
        },
      ),
    );
  }

  Future<void> _showChapterSheet(ScanPage page) async {
    final res = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ChapterSheet(names: page.chapterNames, current: _chapter),
    );
    if (res != null) _goChapter(page, res);
  }

  Future<void> _showOptions(dynamic store) async {
    await showModalBottomSheet(
      context: context,
      builder: (_) => Consumer(builder: (context, ref, _) {
        final s = ref.watch(localStoreProvider);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('OPTIONS DE LECTURE', style: TextStyle(fontWeight: FontWeight.w900)),
              const SizedBox(height: 14),
              const Text('LECTURE', style: TextStyle(fontSize: 11, color: AppColors.textDim, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'scroll', label: Text('Scroll'), icon: Icon(Icons.swap_vert_rounded)),
                  ButtonSegment(value: 'page', label: Text('Page par page'), icon: Icon(Icons.auto_stories_rounded)),
                ],
                selected: {s.readingMode},
                onSelectionChanged: (v) {
                  s.setReadingMode(v.first);
                  setState(() {
                    _pageCtrl = null;
                    _page = 0;
                  });
                },
              ),
              const SizedBox(height: 16),
              const Text('ARRIÈRE-PLAN', style: TextStyle(fontSize: 11, color: AppColors.textDim, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Row(children: [
                for (final c in const [0xFF020D18, 0xFFFFFFFF, 0xFF000000])
                  Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: InkWell(
                      onTap: () => s.setReaderBg(c),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        width: 44,
                        height: 34,
                        decoration: BoxDecoration(
                          color: Color(c),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: s.readerBg == c ? AppColors.accent : AppColors.border,
                            width: s.readerBg == c ? 2.5 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ]),
              const SizedBox(height: 8),
            ]),
          ),
        );
      }),
    );
  }
}

// ---------------------------------------------------------------------------
// Barre d'outils (langues, sélecteur de chapitre, navigation)
// ---------------------------------------------------------------------------

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.page, required this.state, required this.bg});
  final ScanPage page;
  final _ReaderScreenState state;
  final Color bg;

  @override
  Widget build(BuildContext context) {
    final light = bg == Colors.white;
    final fg = light ? Colors.black : Colors.white;
    return Container(
      color: light ? const Color(0xFFF1F5F9) : AppColors.surface.withValues(alpha: 0.85),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Column(children: [
        Row(children: [
          for (final code in page.availableLangs) ...[
            LangPill(
              label: code.toUpperCase(),
              flag: code == 'va' ? 'en' : 'fr',
              selected: code == state.widget.lang,
              onTap: code == state.widget.lang
                  ? () {}
                  : () => context.pushReplacement(
                        '/read/${state.widget.slug}/${state.widget.folder}/$code'
                        '${state.widget.seasonName != null ? '?name=${Uri.encodeQueryComponent(state.widget.seasonName!)}' : ''}',
                      ),
            ),
            const SizedBox(width: 6),
          ],
          const Spacer(),
          Expanded(
            flex: 3,
            child: InkWell(
              onTap: () => state._showChapterSheet(page),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.accentDark, width: 1.5),
                ),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      page.chapterNames[state._chapter].toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 12, color: Colors.white),
                    ),
                  ),
                  const Icon(Icons.expand_more_rounded, size: 18, color: Colors.white),
                ]),
              ),
            ),
          ),
        ]),
        const SizedBox(height: 6),
        Row(children: [
          Expanded(
            child: _SmallBtn(
              icon: Icons.chevron_left_rounded,
              label: 'Précédent',
              fg: fg,
              onTap: state._chapter > 0
                  ? () => state._goChapter(page, state._chapter - 1)
                  : null,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _SmallBtn(
              icon: Icons.last_page_rounded,
              label: 'Dernier',
              fg: fg,
              onTap: () => state._goChapter(page, page.chapterNames.length - 1),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _SmallBtn(
              icon: Icons.chevron_right_rounded,
              label: 'Suivant',
              fg: fg,
              trailing: true,
              onTap: state._chapter < page.chapterNames.length - 1
                  ? () => state._goChapter(page, state._chapter + 1)
                  : null,
            ),
          ),
        ]),
        if (page.message.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(page.message,
                style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.8))),
          ),
      ]),
    );
  }
}

class _SmallBtn extends StatelessWidget {
  const _SmallBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.fg,
    this.trailing = false,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color fg;
  final bool trailing;
  @override
  Widget build(BuildContext context) {
    final children = [
      Icon(icon, size: 16, color: onTap == null ? fg.withValues(alpha: 0.35) : fg),
      Flexible(
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: onTap == null ? fg.withValues(alpha: 0.35) : fg)),
      ),
    ];
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
        side: BorderSide(color: fg.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: trailing ? children.reversed.toList() : children,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mode scroll
// ---------------------------------------------------------------------------

class _ScrollMode extends StatelessWidget {
  const _ScrollMode({
    required this.urls,
    required this.controller,
    required this.bg,
    required this.chapterLabel,
    this.onNextChapter,
    this.onPrevChapter,
  });
  final List<String> urls;
  final ScrollController controller;
  final Color bg;
  final String chapterLabel;
  final VoidCallback? onNextChapter;
  final VoidCallback? onPrevChapter;

  @override
  Widget build(BuildContext context) {
    final light = bg == Colors.white;
    return Stack(children: [
      ListView.builder(
        controller: controller,
        padding: const EdgeInsets.only(bottom: 24),
        scrollCacheExtent: const ScrollCacheExtent.pixels(2000),
        itemCount: urls.length + 1,
        itemBuilder: (_, i) {
          if (i == urls.length) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
              child: Column(children: [
                Text('Fin de $chapterLabel',
                    style: TextStyle(
                        color: light ? Colors.black54 : AppColors.textDim,
                        fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onPrevChapter,
                      icon: const Icon(Icons.chevron_left_rounded),
                      label: const Text('Précédent'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: onNextChapter,
                      icon: const Icon(Icons.chevron_right_rounded),
                      label: const Text('Chapitre suivant'),
                    ),
                  ),
                ]),
              ]),
            );
          }
          return Padding(
            padding: const EdgeInsets.only(top: 6), // scanGap
            child: _ScanImage(url: urls[i], index: i + 1, light: light),
          );
        },
      ),
      Positioned(
        right: 12,
        bottom: 12,
        child: FloatingActionButton.small(
          heroTag: 'top',
          backgroundColor: AppColors.surface2,
          onPressed: () => controller.animateTo(0,
              duration: const Duration(milliseconds: 400), curve: Curves.easeOut),
          child: const Icon(Icons.keyboard_arrow_up_rounded),
        ),
      ),
    ]);
  }
}

class _ScanImage extends StatelessWidget {
  const _ScanImage({required this.url, required this.index, required this.light});
  final String url;
  final int index;
  final bool light;
  @override
  Widget build(BuildContext context) {
    return CachedNetworkImage(
      imageUrl: url,
      httpHeaders: const {
        'User-Agent': AppConstants.userAgent,
        'Referer': '${AppConstants.defaultBaseUrl}/',
      },
      fit: BoxFit.fitWidth,
      width: double.infinity,
      fadeInDuration: const Duration(milliseconds: 150),
      placeholder: (_, _) => AspectRatio(
        aspectRatio: 0.7,
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(height: 8),
            Text('Page $index',
                style: TextStyle(
                    fontSize: 11, color: light ? Colors.black45 : AppColors.textDim)),
          ]),
        ),
      ),
      errorWidget: (_, _, _) => AspectRatio(
        aspectRatio: 1.5,
        child: Center(
          child: Text('Page $index indisponible',
              style: TextStyle(color: light ? Colors.black45 : AppColors.textDim)),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mode page par page
// ---------------------------------------------------------------------------

class _PageMode extends StatefulWidget {
  const _PageMode({
    super.key,
    required this.urls,
    required this.initialPage,
    required this.bg,
    required this.onPageChanged,
    required this.controllerHolder,
    this.onPrevChapter,
    this.onNextChapter,
  });
  final List<String> urls;
  final int initialPage;
  final Color bg;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<PageController> controllerHolder;
  final VoidCallback? onPrevChapter;
  final VoidCallback? onNextChapter;

  @override
  State<_PageMode> createState() => _PageModeState();
}

class _PageModeState extends State<_PageMode> {
  late final PageController _ctrl =
      PageController(initialPage: widget.initialPage.clamp(0, (widget.urls.length - 1).clamp(0, 1 << 20)));

  @override
  void initState() {
    super.initState();
    widget.controllerHolder(_ctrl);
    // Pré-chargement des 2 pages suivantes
    WidgetsBinding.instance.addPostFrameCallback((_) => _preload(widget.initialPage));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _preload(int from) {
    for (var i = from + 1; i <= from + 2 && i < widget.urls.length; i++) {
      precacheImage(
        CachedNetworkImageProvider(widget.urls[i],
            headers: const {'User-Agent': AppConstants.userAgent}),
        context,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.urls.isEmpty) {
      return const Center(child: Text('Aucune page.'));
    }
    return PhotoViewGallery.builder(
      pageController: _ctrl,
      itemCount: widget.urls.length,
      backgroundDecoration: BoxDecoration(color: widget.bg),
      onPageChanged: (p) {
        widget.onPageChanged(p);
        _preload(p);
      },
      builder: (_, i) => PhotoViewGalleryPageOptions(
        imageProvider: CachedNetworkImageProvider(
          widget.urls[i],
          headers: const {
            'User-Agent': AppConstants.userAgent,
            'Referer': '${AppConstants.defaultBaseUrl}/',
          },
        ),
        minScale: PhotoViewComputedScale.contained,
        maxScale: PhotoViewComputedScale.covered * 3,
        heroAttributes: PhotoViewHeroAttributes(tag: widget.urls[i]),
      ),
      loadingBuilder: (_, _) => const Center(child: CircularProgressIndicator()),
    );
  }
}

class _PageNavBar extends StatelessWidget {
  const _PageNavBar({
    required this.page,
    required this.total,
    required this.bg,
    required this.onPrev,
    required this.onNext,
  });
  final int page;
  final int total;
  final Color bg;
  final VoidCallback onPrev;
  final VoidCallback onNext;
  @override
  Widget build(BuildContext context) {
    final light = bg == Colors.white;
    final fg = light ? Colors.black : Colors.white;
    return SafeArea(
      top: false,
      child: Container(
        color: light ? const Color(0xFFF1F5F9) : AppColors.surface.withValues(alpha: 0.85),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(children: [
          TextButton.icon(
            onPressed: onPrev,
            icon: Icon(Icons.chevron_left_rounded, color: fg),
            label: Text('Page préc.', style: TextStyle(color: fg, fontSize: 12)),
          ),
          Expanded(
            child: Text(
              'Page ${page + 1} / $total',
              textAlign: TextAlign.center,
              style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 12.5),
            ),
          ),
          TextButton.icon(
            onPressed: onNext,
            iconAlignment: IconAlignment.end,
            icon: Icon(Icons.chevron_right_rounded, color: fg),
            label: Text('Page suiv.', style: TextStyle(color: fg, fontSize: 12)),
          ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Feuille de sélection de chapitre
// ---------------------------------------------------------------------------

class _ChapterSheet extends StatefulWidget {
  const _ChapterSheet({required this.names, required this.current});
  final List<String> names;
  final int current;
  @override
  State<_ChapterSheet> createState() => _ChapterSheetState();
}

class _ChapterSheetState extends State<_ChapterSheet> {
  String _q = '';
  bool _desc = true;

  @override
  Widget build(BuildContext context) {
    var idx = <int>[];
    for (var i = 0; i < widget.names.length; i++) {
      if (_q.isEmpty || widget.names[i].toLowerCase().contains(_q.toLowerCase())) idx.add(i);
    }
    if (_desc) idx = idx.reversed.toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, scroll) => Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
          child: Row(children: [
            Expanded(
              child: Text('CHAPITRES (${widget.names.length})',
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
            IconButton(
              tooltip: 'Inverser l\'ordre',
              onPressed: () => setState(() => _desc = !_desc),
              icon: Icon(_desc ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded),
            ),
            IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded)),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: TextField(
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              hintText: 'Aller au chapitre…',
              prefixIcon: Icon(Icons.search_rounded, size: 18),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _q = v.trim()),
            onSubmitted: (v) {
              final n = int.tryParse(v.trim());
              if (n != null && n >= 1 && n <= widget.names.length) {
                Navigator.pop(context, n - 1);
              } else if (idx.isNotEmpty) {
                Navigator.pop(context, idx.first);
              }
            },
          ),
        ),
        Expanded(
          child: ListView.builder(
            controller: scroll,
            itemCount: idx.length,
            itemBuilder: (_, k) {
              final i = idx[k];
              final sel = i == widget.current;
              return ListTile(
                dense: true,
                selected: sel,
                selectedTileColor: AppColors.accent.withValues(alpha: 0.18),
                leading: Icon(
                  sel ? Icons.bookmark_rounded : Icons.menu_book_outlined,
                  color: sel ? AppColors.accent : AppColors.textDim,
                ),
                title: Text(widget.names[i],
                    style: TextStyle(fontWeight: sel ? FontWeight.w800 : FontWeight.w600)),
                onTap: () => Navigator.pop(context, i),
              );
            },
          ),
        ),
      ]),
    );
  }
}
