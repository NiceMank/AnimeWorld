import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/auth/login_screen.dart';
import '../features/catalogue/catalogue_screen.dart';
import '../features/details/details_screen.dart';
import '../features/help/help_screen.dart';
import '../features/home/home_screen.dart';
import '../features/library/library_screen.dart';
import '../features/notifications/notifications_screen.dart';
import '../features/onboarding/onboarding_screen.dart';
import '../features/planning/planning_screen.dart';
import '../features/player/episode_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/reader/reader_screen.dart';
import '../features/search/search_screen.dart';
import '../features/shell/app_shell.dart';
import '../features/splash/splash_screen.dart';
import 'providers.dart';

final _rootKey = GlobalKey<NavigatorState>();

final routerProvider = Provider<GoRouter>((ref) {
  // `read` et non `watch` : le store notifie à chaque modification de liste,
  // ce qui recréerait le routeur (et perdrait la pile de navigation).
  final store = ref.read(localStoreProvider);
  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    redirect: (context, state) {
      final loc = state.uri.path;
      if (loc == '/splash') return null;
      if (!store.onboardingDone && loc != '/onboarding') return '/onboarding';
      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, _) => const SplashScreen()),
      GoRoute(path: '/onboarding', builder: (_, _) => const OnboardingScreen()),
      GoRoute(
        path: '/login',
        builder: (_, s) =>
            LoginScreen(register: s.uri.queryParameters['register'] == '1'),
      ),
      GoRoute(path: '/help', builder: (_, _) => const HelpScreen()),
      GoRoute(path: '/search', builder: (_, _) => const SearchScreen()),
      GoRoute(
        path: '/notifications',
        builder: (_, _) => const NotificationsScreen(),
      ),

      // Fiche + lecture (plein écran, hors shell)
      GoRoute(
        path: '/anime/:slug',
        builder: (_, s) => DetailsScreen(slug: s.pathParameters['slug']!),
      ),
      GoRoute(
        path: '/watch/:slug/:folder/:lang',
        builder: (_, s) => EpisodeScreen(
          slug: s.pathParameters['slug']!,
          folder: s.pathParameters['folder']!,
          lang: s.pathParameters['lang']!,
          seasonName: s.uri.queryParameters['name'],
        ),
      ),
      GoRoute(
        path: '/read/:slug/:folder/:lang',
        builder: (_, s) => ReaderScreen(
          slug: s.pathParameters['slug']!,
          folder: s.pathParameters['folder']!,
          lang: s.pathParameters['lang']!,
          seasonName: s.uri.queryParameters['name'],
        ),
      ),

      // Shell avec barre de navigation
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/catalogue',
              builder: (_, s) => CatalogueScreen(
                initialGenre: s.uri.queryParameters['genre'],
                initialType: s.uri.queryParameters['type'],
              ),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/planning', builder: (_, _) => const PlanningScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: '/library',
              builder: (_, s) => LibraryScreen(
                initialTab: int.tryParse(s.uri.queryParameters['tab'] ?? '') ?? 0,
              ),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
          ]),
        ],
      ),
    ],
  );
});

/// Ouvre un chemin du site (/catalogue/{slug}/{saison}/{lang}/) dans l'écran
/// approprié de l'application.
void openSitePath(BuildContext context, String path, {String? seasonName}) {
  final parts = path.split('/').where((p) => p.isNotEmpty).toList();
  final i = parts.indexOf('catalogue');
  if (i < 0 || i + 1 >= parts.length) return;
  final slug = parts[i + 1];
  if (parts.length <= i + 2) {
    context.push('/anime/$slug');
    return;
  }
  final folder = parts[i + 2];
  final lang = parts.length > i + 3 ? parts[i + 3] : 'vostfr';
  final q = seasonName != null ? '?name=${Uri.encodeQueryComponent(seasonName)}' : '';
  if (folder.startsWith('scan')) {
    context.push('/read/$slug/$folder/$lang$q');
  } else {
    context.push('/watch/$slug/$folder/$lang$q');
  }
}
