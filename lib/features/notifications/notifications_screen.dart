import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';
import '../../shared/widgets/common.dart';

/// Bouton cloche pour les AppBars : badge temps réel du nombre de
/// notifications non lues.
class NotificationBellButton extends ConsumerWidget {
  const NotificationBellButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(
      notificationsProvider.select((s) => s.unreadCount),
    );
    return Stack(alignment: Alignment.center, children: [
      IconButton(
        tooltip: 'Notifications',
        onPressed: () => context.push('/notifications'),
        icon: const Icon(Icons.notifications_none_rounded),
      ),
      if (unread > 0)
        Positioned(
          top: 7,
          right: 7,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1.5),
            decoration: BoxDecoration(
              color: AppColors.danger,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(color: AppColors.bg, width: 1.5),
            ),
            constraints: const BoxConstraints(minWidth: 17),
            child: Text(
              unread > 99 ? '99+' : '$unread',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 9.5,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                height: 1.1,
              ),
            ),
          ),
        ),
    ]);
  }
}

/// Centre de notifications : nouveaux épisodes/chapitres détectés par la
/// veille temps réel. Pull-to-refresh = vérification immédiate.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(notificationsProvider);

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('NOTIFICATIONS'),
        actions: [
          if (state.items.isNotEmpty) ...[
            if (state.unreadCount > 0)
              IconButton(
                tooltip: 'Tout marquer comme lu',
                icon: const Icon(Icons.done_all_rounded),
                onPressed: () =>
                    ref.read(notificationsProvider.notifier).markAllRead(),
              ),
            IconButton(
              tooltip: 'Tout supprimer',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('Supprimer les notifications ?'),
                    content: const Text(
                        'L\'historique des notifications sera effacé. La veille '
                        'continuera de détecter les prochaines sorties.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Annuler')),
                      ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Supprimer')),
                    ],
                  ),
                );
                if (ok == true) {
                  ref.read(notificationsProvider.notifier).clearAll();
                }
              },
            ),
          ],
        ],
      ),
      body: RefreshIndicator(
        color: AppColors.accent,
        onRefresh: () => ref.read(notificationsProvider.notifier).check(),
        child: state.items.isEmpty
            ? ListView(children: [
                SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.75,
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Icon(
                        Icons.notifications_none_rounded,
                        size: 52,
                        color: AppColors.textDim.withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Aucune notification',
                        style: TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          'Les nouveaux épisodes et chapitres des œuvres que '
                          'vous suivez apparaîtront ici.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12.5, color: AppColors.textDim),
                        ),
                      ),
                    ]),
                  ),
                ),
              ])
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 24),
                itemCount: state.items.length,
                itemBuilder: (_, i) {
                  final n = state.items[i];
                  return _NotificationTile(
                    notification: n,
                    onTap: () {
                      ref.read(notificationsProvider.notifier).markRead(n.id);
                      openSitePath(context, n.path);
                    },
                  );
                },
              ),
      ),
      bottomNavigationBar: state.items.isEmpty
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                child: Row(children: [
                  Expanded(
                    child: Text(
                      state.checking
                          ? 'Vérification des nouvelles sorties…'
                          : lastCheckShort(state.lastCheck),
                      style: const TextStyle(
                          fontSize: 11.5, color: AppColors.textDim),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Vérifier maintenant',
                    onPressed: state.checking
                        ? null
                        : () =>
                            ref.read(notificationsProvider.notifier).check(),
                    icon: const Icon(Icons.refresh_rounded,
                        color: AppColors.accent),
                  ),
                ]),
              ),
            ),
    );
  }

  /// Libellé court de la dernière vérification (réutilisé par le profil).
  static String lastCheckShort(DateTime? dt) {
    if (dt == null) return 'Jamais';
    final d = DateTime.now().difference(dt);
    if (d.inSeconds < 90) return 'À l\'instant';
    if (d.inMinutes < 60) return 'Il y a ${d.inMinutes} min';
    if (d.inHours < 24) return 'Il y a ${d.inHours} h';
    return DateFormat('dd/MM à HH:mm').format(dt);
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.notification, required this.onTap});
  final AppNotification notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = notification;
    final isScan = n.kind == 'scan';
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: n.read ? AppColors.surface.withValues(alpha: 0.55) : AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: n.read ? AppColors.border : AppColors.accentDark,
        ),
      ),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 46,
            height: 62,
            child: NetImage(n.image),
          ),
        ),
        title: Row(children: [
          Icon(
            isScan
                ? Icons.menu_book_rounded
                : Icons.play_circle_outline_rounded,
            size: 14,
            color: isScan ? AppColors.warning : AppColors.accent,
          ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              n.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
          if (!n.read)
            Container(
              width: 8,
              height: 8,
              margin: const EdgeInsets.only(left: 6),
              decoration: const BoxDecoration(
                color: AppColors.accent,
                shape: BoxShape.circle,
              ),
            ),
        ]),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(n.body,
                style: const TextStyle(fontSize: 12.5, color: AppColors.textMuted)),
            const SizedBox(height: 3),
            Text(
              _timeLabel(n.at),
              style: const TextStyle(fontSize: 10.5, color: AppColors.textDim),
            ),
          ]),
        ),
        isThreeLine: true,
      ),
    );
  }

  static String _timeLabel(DateTime at) {
    final now = DateTime.now();
    final d = now.difference(at);
    if (d.inMinutes < 1) return 'à l\'instant';
    if (d.inMinutes < 60) return 'il y a ${d.inMinutes} min';
    if (d.inHours < 24) return 'il y a ${d.inHours} h';
    if (d.inDays < 7) return 'il y a ${d.inDays} j';
    return DateFormat('dd/MM/yyyy').format(at);
  }
}
