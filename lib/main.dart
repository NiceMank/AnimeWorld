import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/providers.dart';
import 'core/router.dart';
import 'core/theme/app_theme.dart';
import 'data/local/local_store.dart';
import 'data/network/api_client.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF070B16),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  final store = await LocalStore.open();
  final client = await ApiClient.create(baseUrl: store.baseUrl);

  runApp(
    ProviderScope(
      overrides: [
        localStoreProvider.overrideWith((ref) => store),
        apiClientProvider.overrideWithValue(client),
      ],
      child: const AnimeWorldApp(),
    ),
  );
}

class AnimeWorldApp extends ConsumerWidget {
  const AnimeWorldApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'AnimeWorld',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.dark,
      routerConfig: router,
      builder: (context, child) {
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
            textScaler: mq.textScaler.clamp(minScaleFactor: 0.9, maxScaleFactor: 1.15),
          ),
          child: _GlowBackground(child: child!),
        );
      },
    );
  }
}

/// Halos bleus flous en arrière-plan (comme body::before/after du site).
class _GlowBackground extends StatelessWidget {
  const _GlowBackground({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        const Positioned.fill(child: ColoredBox(color: AppColors.bg)),
        Positioned(
          top: -160,
          left: -160,
          child: _Glow(color: AppColors.glow1.withValues(alpha: 0.35)),
        ),
        Positioned(
          bottom: -200,
          right: -160,
          child: _Glow(color: AppColors.glow2.withValues(alpha: 0.18)),
        ),
        child,
      ],
    );
  }
}

class _Glow extends StatelessWidget {
  const _Glow({required this.color});
  final Color color;
  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 420,
        height: 420,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
        ),
      ),
    );
  }
}
