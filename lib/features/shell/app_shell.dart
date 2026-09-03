import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';

class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key, required this.shell});
  final StatefulNavigationShell shell;

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  /// Dernière notification affichée en bannière (évite les doublons).
  String? _lastBannerId;
  final _lifecycle = _Lifecycle();

  @override
  void initState() {
    super.initState();
    // « Temps réel » : revérification dès que l'app revient au premier plan.
    _lifecycle.onResume = _onResume;
    WidgetsBinding.instance.addObserver(_lifecycle);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(_lifecycle);
    super.dispose();
  }

  void _onResume() {
    if (mounted) ref.read(notificationsProvider.notifier).check();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<NotificationsState>(notificationsProvider, (prev, next) {
      final latest = next.items.isEmpty ? null : next.items.first;
      if (prev == null || latest == null || latest.read) return;
      if (latest.id == _lastBannerId) return;
      // Bannière seulement si l'item vient d'être détecté (absent de l'état
      // précédent) — pas au premier rendu ni au retour sur l'écran.
      if (prev.items.any((n) => n.id == latest.id)) return;
      _lastBannerId = latest.id;
      _showBanner(context, latest);
    });

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: widget.shell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: widget.shell.currentIndex,
        onDestinationSelected: (i) => widget.shell
            .goBranch(i, initialLocation: i == widget.shell.currentIndex),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Accueil',
          ),
          NavigationDestination(
            icon: Icon(Icons.grid_view_outlined),
            selectedIcon: Icon(Icons.grid_view_rounded),
            label: 'Catalogue',
          ),
          NavigationDestination(
            icon: Icon(Icons.calendar_month_outlined),
            selectedIcon: Icon(Icons.calendar_month_rounded),
            label: 'Planning',
          ),
          NavigationDestination(
            icon: Icon(Icons.bookmarks_outlined),
            selectedIcon: Icon(Icons.bookmarks_rounded),
            label: 'Bibliothèque',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline_rounded),
            selectedIcon: Icon(Icons.person_rounded),
            label: 'Profil',
          ),
        ],
      ),
    );
  }

  void _showBanner(BuildContext context, AppNotification n) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: const Duration(seconds: 6),
        backgroundColor: AppColors.surface2,
        content: Text(
          '🔔 ${n.title} — ${n.body}',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        action: SnackBarAction(
          label: 'Voir',
          onPressed: () {
            ref.read(notificationsProvider.notifier).markRead(n.id);
            openSitePath(context, n.path);
          },
        ),
      ));
  }
}

class _Lifecycle with WidgetsBindingObserver {
  VoidCallback? onResume;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) onResume?.call();
  }
}
