import 'package:flutter/material.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/constants/languages.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../data/local/local_store.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../shared/widgets/common.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});
  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _syncing = false;

  Future<void> _sync() async {
    setState(() => _syncing = true);
    try {
      final acc = ref.read(accountRepositoryProvider);
      await acc.syncAllToServer();
      await acc.syncFromServer();
      if (mounted) showSnack(context, 'Synchronisation terminée');
    } catch (e) {
      if (mounted) showSnack(context, 'Échec de la synchronisation', error: true);
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _logout() async {
    await ref.read(accountRepositoryProvider).logout();
    await ref.read(sessionProvider.notifier).refresh();
    if (mounted) showSnack(context, 'Déconnecté');
  }

  Future<void> _changeDomain() async {
    final store = ref.read(localStoreProvider);
    final ctrl = TextEditingController(text: store.baseUrl);
    final v = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Domaine du site'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          const Text(
            'Le site change parfois de domaine (.to / .org / .fr). '
            'Modifiez-le ici si le contenu ne charge plus.',
            style: TextStyle(fontSize: 12.5, color: AppColors.textMuted),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: ctrl,
            keyboardType: TextInputType.url,
            decoration: const InputDecoration(hintText: 'https://anime-sama.to'),
          ),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, AppConstants.defaultBaseUrl),
              child: const Text('Par défaut')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler')),
          ElevatedButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('Enregistrer')),
        ],
      ),
    );
    if (v != null && v.isNotEmpty) {
      await store.setBaseUrl(v);
      ref.read(apiClientProvider).baseUrl = v;
      ref.read(animeRepositoryProvider).clearCaches();
      ref.invalidate(homeProvider);
      ref.invalidate(planningProvider);
      if (mounted) showSnack(context, 'Domaine mis à jour');
    }
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(localStoreProvider);
    final session = ref.watch(sessionProvider);
    final history = store.getHistory().length;
    final watch = store.getList(LocalStore.watchPrefix).length;
    final fav = store.getList(LocalStore.favPrefix).length;
    final seen = store.getList(LocalStore.seenPrefix).length;

    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('PROFIL'),
        actions: const [NotificationBellButton()],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // En-tête compte
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                AppColors.surface,
                AppColors.accent.withValues(alpha: 0.12),
              ]),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor:
                      session.loggedIn ? AppColors.accent : AppColors.surface2,
                  child: session.loggedIn
                      ? Text(
                          (session.username ?? '?').substring(0, 1).toUpperCase(),
                          style: const TextStyle(
                              fontSize: 22, fontWeight: FontWeight.w900),
                        )
                      : const Icon(Icons.person_outline_rounded,
                          size: 30, color: AppColors.textDim),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(
                      session.loggedIn ? 'MEMBRE' : 'PROFIL LOCAL',
                      style: const TextStyle(
                          fontSize: 10.5,
                          letterSpacing: 1.2,
                          color: AppColors.accent,
                          fontWeight: FontWeight.w800),
                    ),
                    Text(
                      session.checking
                          ? 'Vérification…'
                          : (session.loggedIn
                              ? (session.username ?? '')
                              : 'Vous n\'êtes pas connecté'),
                      style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      session.loggedIn
                          ? (store.lastSync != null
                              ? 'Synchronisé · ${DateFormat('dd/MM HH:mm').format(store.lastSync!)}'
                              : 'Synchronisé avec votre compte')
                          : 'Votre bibliothèque est enregistrée sur cet appareil. Connectez-vous pour la synchroniser.',
                      style: const TextStyle(fontSize: 12, color: AppColors.textMuted),
                    ),
                  ]),
                ),
              ]),
              const SizedBox(height: 14),
              if (session.loggedIn)
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _syncing ? null : _sync,
                      icon: _syncing
                          ? const SizedBox(
                              width: 16, height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.sync_rounded),
                      label: const Text('Synchroniser'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _logout,
                      icon: const Icon(Icons.logout_rounded),
                      label: const Text('Se déconnecter'),
                    ),
                  ),
                ])
              else
                Row(children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => context.push('/login'),
                      icon: const Icon(Icons.login_rounded),
                      label: const Text('Se connecter'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => context.push('/login?register=1'),
                      child: const Text('Créer un compte'),
                    ),
                  ),
                ]),
            ]),
          ),
          const SizedBox(height: 12),

          // Stats
          Row(children: [
            _Stat('Historique', history, () => context.go('/library?tab=0')),
            _Stat('Watchlist', watch, () => context.go('/library?tab=1')),
            _Stat('Favoris', fav, () => context.go('/library?tab=2')),
            _Stat('Vus', seen, () => context.go('/library?tab=3')),
          ]),

          const SectionTitle('Notifications', padding: EdgeInsets.fromLTRB(0, 20, 0, 4)),
          _SwitchTile(
            icon: Icons.notifications_active_outlined,
            title: 'Notifications temps réel',
            subtitle: 'Alerte à la sortie d\'un nouvel épisode ou chapitre',
            value: store.notificationsEnabled,
            onChanged: (v) =>
                ref.read(notificationsProvider.notifier).toggleEnabled(v),
          ),
          if (store.notificationsEnabled) ...[
            _SwitchTile(
              icon: Icons.phone_android_rounded,
              title: 'Notifications système',
              subtitle: 'Bandeau même quand l\'app est en arrière-plan',
              value: store.systemNotificationsEnabled,
              onChanged: (v) async {
                final notifier = ref.read(notificationsProvider.notifier);
                if (v) await notifier.requestSystemPermission();
                await ref
                    .read(localStoreProvider)
                    .setSystemNotificationsEnabled(v);
              },
            ),
            _Tile(
              icon: Icons.schedule_rounded,
              title: 'Fréquence de vérification',
              value: _intervalLabel(store.notificationsIntervalMinutes),
              onTap: () => _pick(
                'Fréquence de vérification',
                const {
                  '2': 'Toutes les 2 minutes',
                  '5': 'Toutes les 5 minutes',
                  '15': 'Toutes les 15 minutes',
                  '30': 'Toutes les 30 minutes',
                  '60': 'Toutes les heures',
                },
                '${store.notificationsIntervalMinutes}',
                (v) async {
                  await ref
                      .read(localStoreProvider)
                      .setNotificationsIntervalMinutes(int.parse(v));
                  // ignore: unawaited_futures
                  ref.read(notificationsProvider.notifier).restart();
                },
              ),
            ),
            _SwitchTile(
              icon: Icons.play_circle_outline_rounded,
              title: 'Nouveaux épisodes',
              value: store.notifyEpisodes,
              onChanged: (v) => ref
                  .read(localStoreProvider)
                  .setNotifyEpisodes(v),
            ),
            _SwitchTile(
              icon: Icons.menu_book_rounded,
              title: 'Nouveaux chapitres (scans)',
              value: store.notifyScans,
              onChanged: (v) => ref.read(localStoreProvider).setNotifyScans(v),
            ),
            _Tile(
              icon: Icons.track_changes_rounded,
              title: 'Œuvres suivies',
              value: store.notificationsScope == 'all'
                  ? 'Toutes les sorties'
                  : 'Ma bibliothèque',
              onTap: () => _pick(
                'Œuvres à surveiller',
                const {
                  'library': 'Ma bibliothèque (watchlist, favoris, historique)',
                  'all': 'Toutes les sorties du site',
                },
                store.notificationsScope,
                ref.read(localStoreProvider).setNotificationsScope,
              ),
            ),
            _Tile(
              icon: Icons.history_rounded,
              title: 'Dernière vérification',
              value: NotificationsScreen.lastCheckShort(store.lastNotifCheck),
              onTap: () => context.push('/notifications'),
            ),
          ],

          const SectionTitle('Paramètres', padding: EdgeInsets.fromLTRB(0, 20, 0, 4)),

          _Tile(
            icon: Icons.dvr_rounded,
            title: 'Lecteur par défaut',
            value: 'Lecteur ${store.preferredPlayer + 1}',
            onTap: () => _pick(
              'Lecteur par défaut',
              {for (var i = 0; i < 8; i++) '$i': 'Lecteur ${i + 1}'},
              '${store.preferredPlayer}',
              (v) => store.setPreferredPlayer(int.parse(v)),
            ),
          ),
          _Tile(
            icon: Icons.translate_rounded,
            title: 'Langue préférée',
            value: langFromCode(store.preferredLang).historyLabel,
            onTap: () => _pick(
              'Langue préférée',
              {for (final l in kAnimeLanguages.take(3)) l.code: l.historyLabel},
              store.preferredLang,
              store.setPreferredLang,
            ),
          ),
          _Tile(
            icon: Icons.auto_stories_rounded,
            title: 'Mode de lecture des scans',
            value: store.readingMode == 'page' ? 'Page par page' : 'Scroll',
            onTap: () => _pick(
              'Mode de lecture',
              const {'scroll': 'Scroll', 'page': 'Page par page'},
              store.readingMode,
              store.setReadingMode,
            ),
          ),
          _Tile(
            icon: Icons.format_color_fill_rounded,
            title: 'Fond du lecteur de scans',
            trailing: Container(
              width: 22, height: 22,
              decoration: BoxDecoration(
                color: Color(store.readerBg),
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.border),
              ),
            ),
            onTap: () => _pick(
              'Fond du lecteur',
              const {'4278324504': 'Bleu nuit', '4294967295': 'Blanc', '4278190080': 'Noir'},
              '${store.readerBg}',
              (v) => store.setReaderBg(int.parse(v)),
            ),
          ),
          _Tile(
            icon: Icons.language_rounded,
            title: 'Domaine du site',
            value: store.baseUrl.replaceFirst('https://', ''),
            onTap: _changeDomain,
          ),
          _Tile(
            icon: Icons.cleaning_services_rounded,
            title: 'Vider le cache images',
            onTap: () async {
              await DefaultCacheManager().emptyCache();
              ref.read(animeRepositoryProvider).clearCaches();
              if (context.mounted) showSnack(context, 'Cache vidé');
            },
          ),

          const SectionTitle('Aide', padding: EdgeInsets.fromLTRB(0, 20, 0, 4)),
          _Tile(
            icon: Icons.help_outline_rounded,
            title: 'Aide & FAQ',
            onTap: () => context.push('/help'),
          ),
          _Tile(
            icon: Icons.discord,
            title: 'Discord de la communauté',
            onTap: () => launchUrl(Uri.parse('https://discord.gg/mKbYYbmxY8'),
                mode: LaunchMode.externalApplication),
          ),
          _Tile(
            icon: Icons.info_outline_rounded,
            title: 'À propos',
            value: 'v${AppConstants.appVersion}',
            onTap: () => showAboutDialog(
              context: context,
              applicationName: AppConstants.appName,
              applicationVersion: AppConstants.appVersion,
              applicationIcon: Image.asset('assets/icon/icon_foreground.png', width: 48),
              children: const [
                Text(
                  'AnimeWorld est un client mobile non officiel qui utilise les mêmes '
                  'sources et fonctionnalités que le site anime-sama. Les vidéos sont '
                  'hébergées par des lecteurs tiers.',
                  style: TextStyle(fontSize: 13),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const Text(
            'Ces sauvegardes restent un outil d\'appoint : pensez à reporter vos listes '
            'sur AniList ou MyAnimeList. Les comptes sont supprimés après 6 mois d\'inactivité.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11, color: AppColors.textDim, height: 1.4),
          ),
        ],
      ),
    );
  }

  Future<void> _pick(
    String title,
    Map<String, String> options,
    String current,
    Future<void> Function(String) onPick,
  ) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(title.toUpperCase(),
                  style: const TextStyle(fontWeight: FontWeight.w900)),
            ),
          ),
          RadioGroup<String>(
            groupValue: current,
            onChanged: (v) => Navigator.pop(context, v),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final e in options.entries)
                RadioListTile<String>(
                  value: e.key,
                  title: Text(e.value),
                  activeColor: AppColors.accent,
                ),
            ]),
          ),
          const SizedBox(height: 8),
        ]),
      ),
    );
    if (v != null) await onPick(v);
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.count, this.onTap);
  final String label;
  final int count;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.border),
          ),
          child: Column(children: [
            Text('$count',
                style: const TextStyle(
                    fontSize: 18, fontWeight: FontWeight.w900, color: AppColors.accent)),
            Text(label, style: const TextStyle(fontSize: 10.5, color: AppColors.textDim)),
          ]),
        ),
      ),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.title,
    required this.onTap,
    this.value,
    this.trailing,
  });
  final IconData icon;
  final String title;
  final String? value;
  final Widget? trailing;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon, color: AppColors.accent),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      trailing: trailing ??
          Row(mainAxisSize: MainAxisSize.min, children: [
            if (value != null)
              Text(value!, style: const TextStyle(color: AppColors.textDim, fontSize: 12)),
            const Icon(Icons.chevron_right_rounded, color: AppColors.textDim),
          ]),
      onTap: onTap,
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.onChanged,
    this.subtitle,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      leading: Icon(icon, color: AppColors.accent),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
      subtitle: subtitle == null
          ? null
          : Text(subtitle!,
              style: const TextStyle(fontSize: 11.5, color: AppColors.textDim)),
      trailing: Switch(value: value, onChanged: onChanged),
      onTap: () => onChanged(!value),
    );
  }
}

String _intervalLabel(int minutes) {
  switch (minutes) {
    case 2:
      return '2 min';
    case 15:
      return '15 min';
    case 30:
      return '30 min';
    case 60:
      return '1 h';
    default:
      return '5 min';
  }
}
