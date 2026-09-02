import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smooth_page_indicator/smooth_page_indicator.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';

class _Page {
  final IconData icon;
  final String title;
  final String text;
  const _Page(this.icon, this.title, this.text);
}

const _pages = [
  _Page(
    Icons.smart_display_rounded,
    'Des milliers d\'animes',
    'Streaming VOSTFR et VF, films, OAV et scans, tout au même endroit — le même catalogue que le site, dans votre poche.',
  ),
  _Page(
    Icons.menu_book_rounded,
    'Lisez vos scans',
    'Mode défilement ou page par page, fond personnalisable et reprise automatique au dernier chapitre lu.',
  ),
  _Page(
    Icons.calendar_month_rounded,
    'Planning & bibliothèque',
    'Sorties du jour, favoris, watchlist et historique. Connectez votre compte pour tout synchroniser.',
  ),
];

class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});
  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  final _ctrl = PageController();
  int _index = 0;

  Future<void> _finish({bool toLogin = false}) async {
    await ref.read(localStoreProvider).setOnboardingDone();
    if (!mounted) return;
    context.go('/');
    if (toLogin) context.push('/login');
  }

  @override
  Widget build(BuildContext context) {
    final last = _index == _pages.length - 1;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => _finish(),
                child: const Text('Passer',
                    style: TextStyle(color: AppColors.textDim)),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _ctrl,
                itemCount: _pages.length,
                onPageChanged: (i) => setState(() => _index = i),
                itemBuilder: (_, i) => _Slide(page: _pages[i]),
              ),
            ),
            SmoothPageIndicator(
              controller: _ctrl,
              count: _pages.length,
              effect: const ExpandingDotsEffect(
                dotHeight: 8,
                dotWidth: 8,
                activeDotColor: AppColors.accent,
                dotColor: AppColors.border,
              ),
            ),
            const SizedBox(height: 28),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (last) {
                      _finish();
                    } else {
                      _ctrl.nextPage(
                        duration: const Duration(milliseconds: 350),
                        curve: Curves.easeOut,
                      );
                    }
                  },
                  child: Text(last ? 'Commencer' : 'Suivant'),
                ),
              ),
            ),
            SizedBox(
              height: 48,
              child: last
                  ? TextButton(
                      onPressed: () => _finish(toLogin: true),
                      child: const Text('J\'ai déjà un compte'),
                    )
                  : null,
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

class _Slide extends StatelessWidget {
  const _Slide({required this.page});
  final _Page page;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 190,
            height: 190,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [
                AppColors.accent.withValues(alpha: 0.35),
                AppColors.accent.withValues(alpha: 0.02),
              ]),
            ),
            child: Icon(page.icon, size: 96, color: AppColors.accent),
          ),
          const SizedBox(height: 40),
          Text(
            page.title.toUpperCase(),
            textAlign: TextAlign.center,
            style: const TextStyle(
                fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 0.8),
          ),
          const SizedBox(height: 14),
          Text(
            page.text,
            textAlign: TextAlign.center,
            style: const TextStyle(color: AppColors.textMuted, height: 1.5),
          ),
        ],
      ),
    );
  }
}
