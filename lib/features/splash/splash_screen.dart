import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});
  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  )..forward();

  @override
  void initState() {
    super.initState();
    // Pré-chauffe l'accueil et la session pendant le splash.
    // Pré-chargement silencieux (les erreurs seront affichées sur l'accueil).
    unawaited(ref.read(homeProvider.future).then((_) {}, onError: (_) {}));
    Timer(const Duration(milliseconds: 1600), () {
      if (!mounted) return;
      final store = ref.read(localStoreProvider);
      context.go(store.onboardingDone ? '/' : '/onboarding');
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(flex: 3),
            ScaleTransition(
              scale: CurvedAnimation(parent: _c, curve: Curves.easeOutBack),
              child: FadeTransition(
                opacity: _c,
                child: Image.asset('assets/images/logo.png', width: 220),
              ),
            ),
            const Spacer(flex: 2),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(height: 12),
            const Text('Chargement…',
                style: TextStyle(color: AppColors.textDim, fontSize: 12)),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }
}
