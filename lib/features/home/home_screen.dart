import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/common.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final home = ref.watch(homeProvider);
    final store = ref.watch(localStoreProvider);
    final history = store.getHistory().reversed.toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(children: [
          Image.asset('assets/icon/icon_foreground.png', height: 34),
          const SizedBox(width: 6),
          RichText(
            text: const TextSpan(
              style: TextStyle(
                  fontSize: 18, fontWeight: FontWeight.w900, letterSpacing: 1),
              children: [
                TextSpan(text: 'ANIME'),
                TextSpan(text: 'WORLD', style: TextStyle(color: AppColors.accent)),
              ],
            ),
          ),
        ]),
        actions: [
          IconButton(
            tooltip: 'Rechercher',
            onPressed: () => context.push('/search'),
            icon: const Icon(Icons.search_rounded),
          ),
          IconButton(
            tooltip: 'Aide',
            onPressed: () => context.push('/help'),
            icon: const Icon(Icons.help_outline_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: () async {
          ref.read(animeRepositoryProvider).clearCaches();
          ref.invalidate(homeProvider);
          await ref.read(homeProvider.future);
        },
        child: home.when(
          loading: () => ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: const [
              _HeroShimmer(),
              SectionTitle('Derniers épisodes ajoutés'),
              RowShimmer(),
              SectionTitle('Derniers scans ajoutés'),
              RowShimmer(),
            ],
          ),
          error: (e, _) => ListView(children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.7,
              child: ErrorView(
                message: e.toString(),
                onRetry: () => ref.invalidate(homeProvider),
              ),
            ),
          ]),
          data: (d) => ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              if (d.slides.isNotEmpty) HeroCarousel(slides: d.slides),
              if (history.isNotEmpty) ...[
                SectionTitle(
                  'Reprenez votre visionnage',
                  trailing: TextButton(
                    onPressed: () => context.go('/library?tab=0'),
                    child: const Text('Tout voir', style: TextStyle(fontSize: 12)),
                  ),
                ),
                HorizontalCards(
                  itemCount: history.length.clamp(0, 15),
                  itemBuilder: (_, i) {
                    final h = history[i];
                    return PosterCard(
                      title: h.name,
                      image: h.image,
                      badge: h.isScan ? 'Scans' : 'Anime',
                      lang: h.lang,
                      subtitle: h.episode,
                      time: h.type,
                      onTap: () => openSitePath(context, h.url, seasonName: h.type),
                    );
                  },
                ),
              ],
              if (d.latestEpisodes.isNotEmpty) ...[
                const SectionTitle('Derniers épisodes ajoutés'),
                HorizontalCards(
                  itemCount: d.latestEpisodes.length,
                  itemBuilder: (_, i) => ReleaseCard(d.latestEpisodes[i]),
                ),
              ],
              if (d.latestScans.isNotEmpty) ...[
                const SectionTitle('Derniers scans ajoutés'),
                HorizontalCards(
                  itemCount: d.latestScans.length,
                  itemBuilder: (_, i) => ReleaseCard(d.latestScans[i]),
                ),
              ],
              if (d.todayReleases.isNotEmpty) ...[
                SectionTitle(
                  d.todayLabel.isEmpty ? 'Sorties du jour' : d.todayLabel,
                  trailing: TextButton(
                    onPressed: () => context.go('/planning'),
                    child: const Text('Planning', style: TextStyle(fontSize: 12)),
                  ),
                ),
                HorizontalCards(
                  itemCount: d.todayReleases.length,
                  itemBuilder: (_, i) => ReleaseCard(d.todayReleases[i]),
                ),
              ],
              if (d.latestContent.isNotEmpty) ...[
                const SectionTitle('Derniers contenus sortis'),
                HorizontalCards(
                  height: 240,
                  itemCount: d.latestContent.length,
                  itemBuilder: (_, i) => CatalogueCard(d.latestContent[i]),
                ),
              ],
              if (d.classics.isNotEmpty) ...[
                const SectionTitle('Les classiques'),
                HorizontalCards(
                  height: 240,
                  itemCount: d.classics.length,
                  itemBuilder: (_, i) => CatalogueCard(d.classics[i]),
                ),
              ],
              if (d.gems.isNotEmpty) ...[
                const SectionTitle('Découvrez des pépites'),
                HorizontalCards(
                  height: 240,
                  itemCount: d.gems.length,
                  itemBuilder: (_, i) => CatalogueCard(d.gems[i]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Carrousel « à la une »
// ---------------------------------------------------------------------------

class HeroCarousel extends StatefulWidget {
  const HeroCarousel({super.key, required this.slides});
  final List<HeroSlide> slides;
  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  final _ctrl = PageController(viewportFraction: 0.92);
  Timer? _timer;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !_ctrl.hasClients) return;
      final next = (_index + 1) % widget.slides.length;
      _ctrl.animateToPage(next,
          duration: const Duration(milliseconds: 500), curve: Curves.easeOut);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 300,
          child: PageView.builder(
            controller: _ctrl,
            itemCount: widget.slides.length,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 5),
              child: _HeroSlideCard(slide: widget.slides[i]),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < widget.slides.length; i++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.symmetric(horizontal: 2.5),
                width: i == _index ? 18 : 6,
                height: 6,
                decoration: BoxDecoration(
                  color: i == _index ? AppColors.accent : AppColors.border,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _HeroSlideCard extends StatelessWidget {
  const _HeroSlideCard({required this.slide});
  final HeroSlide slide;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Stack(
        fit: StackFit.expand,
        children: [
          NetImage(slide.banner),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.35, 1],
                colors: [
                  Colors.black.withValues(alpha: 0.1),
                  Colors.black.withValues(alpha: 0.55),
                  Colors.black.withValues(alpha: 0.92),
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(onTap: () => context.push('/anime/${slide.slug}')),
            ),
          ),
          Positioned(
            left: 14,
            right: 14,
            bottom: 14,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (slide.badge.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: AppColors.accent.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(slide.badge.toUpperCase(),
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                const SizedBox(height: 6),
                Text(
                  slide.title.toUpperCase(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w900, height: 1.1),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 5,
                  runSpacing: 4,
                  children: [
                    for (final g in slide.genres.take(4))
                      Container(
                        padding:
                            const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(g, style: const TextStyle(fontSize: 10)),
                      ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  slide.synopsis,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11.5, color: AppColors.textMuted),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    for (final cta in slide.ctas)
                      InkWell(
                        onTap: () => openSitePath(context, cta.path),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: AppColors.accent,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            const Icon(Icons.play_arrow_rounded, size: 16),
                            const SizedBox(width: 4),
                            Text(cta.label,
                                style: const TextStyle(
                                    fontSize: 12, fontWeight: FontWeight.w800)),
                            const SizedBox(width: 6),
                            FlagIcon(cta.flag, width: 18),
                          ]),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroShimmer extends StatelessWidget {
  const _HeroShimmer();
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        height: 300,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Center(child: CircularProgressIndicator()),
      ),
    );
  }
}
