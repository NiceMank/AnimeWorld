import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show ChangeNotifierProvider;

import '../data/local/local_store.dart';
import '../data/models/models.dart';
import '../data/network/api_client.dart';
import '../data/repositories/account_repository.dart';
import '../data/repositories/anime_repository.dart';
import '../data/services/release_watcher.dart';

/// Ces providers sont surchargés dans `main.dart` une fois l'initialisation
/// asynchrone terminée (Hive + cookies).
final apiClientProvider = Provider<ApiClient>((ref) {
  throw UnimplementedError('apiClientProvider doit être surchargé');
});

final localStoreProvider = ChangeNotifierProvider<LocalStore>((ref) {
  throw UnimplementedError('localStoreProvider doit être surchargé');
});

final animeRepositoryProvider = Provider<AnimeRepository>(
  (ref) => AnimeRepository(ref.watch(apiClientProvider)),
);

final accountRepositoryProvider = Provider<AccountRepository>(
  (ref) => AccountRepository(
    ref.watch(apiClientProvider),
    ref.watch(localStoreProvider),
  ),
);

// ---------------------------------------------------------------------------
// Données distantes
// ---------------------------------------------------------------------------

final homeProvider = FutureProvider<HomeData>(
  (ref) => ref.watch(animeRepositoryProvider).getHome(),
);

final planningProvider = FutureProvider<PlanningData>(
  (ref) => ref.watch(animeRepositoryProvider).getPlanning(),
);

final detailsProvider = FutureProvider.family<AnimeDetails, String>(
  (ref, slug) => ref.watch(animeRepositoryProvider).getDetails(slug),
);

/// Clé = "slug|folder|lang"
final episodePageProvider =
    FutureProvider.autoDispose.family<EpisodePage, String>((ref, key) {
  final p = key.split('|');
  return ref.watch(animeRepositoryProvider).getEpisodePage(p[0], p[1], p[2]);
});

final scanPageProvider =
    FutureProvider.autoDispose.family<ScanPage, String>((ref, key) {
  final p = key.split('|');
  return ref.watch(animeRepositoryProvider).getScanPage(p[0], p[1], p[2]);
});

final searchProvider = FutureProvider.autoDispose.family<List<SearchResult>, String>(
  (ref, q) => ref.watch(animeRepositoryProvider).search(q),
);

// ---------------------------------------------------------------------------
// Catalogue (filtres + pagination)
// ---------------------------------------------------------------------------

class CatalogueState {
  final CatalogueFilters filters;
  final List<CatalogueItem> items;
  final int page;
  final int totalPages;
  final bool loading;
  final bool loadingMore;
  final String? error;

  const CatalogueState({
    this.filters = const CatalogueFilters(),
    this.items = const [],
    this.page = 0,
    this.totalPages = 1,
    this.loading = false,
    this.loadingMore = false,
    this.error,
  });

  bool get hasMore => page < totalPages;

  CatalogueState copyWith({
    CatalogueFilters? filters,
    List<CatalogueItem>? items,
    int? page,
    int? totalPages,
    bool? loading,
    bool? loadingMore,
    String? error,
    bool clearError = false,
  }) =>
      CatalogueState(
        filters: filters ?? this.filters,
        items: items ?? this.items,
        page: page ?? this.page,
        totalPages: totalPages ?? this.totalPages,
        loading: loading ?? this.loading,
        loadingMore: loadingMore ?? this.loadingMore,
        error: clearError ? null : (error ?? this.error),
      );
}

class CatalogueNotifier extends Notifier<CatalogueState> {
  @override
  CatalogueState build() => const CatalogueState();

  int _requestId = 0;

  Future<void> load({CatalogueFilters? filters}) async {
    final f = filters ?? state.filters;
    final id = ++_requestId;
    state = state.copyWith(
      filters: f,
      loading: true,
      items: const [],
      page: 0,
      clearError: true,
    );
    try {
      final res = await ref.read(animeRepositoryProvider).getCatalogue(f, 1);
      if (id != _requestId) return;
      state = state.copyWith(
        items: res.items,
        page: 1,
        totalPages: res.totalPages,
        loading: false,
      );
    } catch (e) {
      if (id != _requestId) return;
      state = state.copyWith(loading: false, error: e.toString());
    }
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;
    final id = _requestId;
    state = state.copyWith(loadingMore: true);
    try {
      final next = state.page + 1;
      final res =
          await ref.read(animeRepositoryProvider).getCatalogue(state.filters, next);
      if (id != _requestId) return;
      state = state.copyWith(
        items: [...state.items, ...res.items],
        page: next,
        totalPages: res.totalPages,
        loadingMore: false,
      );
    } catch (e) {
      if (id != _requestId) return;
      state = state.copyWith(loadingMore: false, error: e.toString());
    }
  }

  void setFilters(CatalogueFilters f) => load(filters: f);
  void reset() => load(filters: const CatalogueFilters());
}

final catalogueProvider =
    NotifierProvider<CatalogueNotifier, CatalogueState>(CatalogueNotifier.new);

// ---------------------------------------------------------------------------
// Session
// ---------------------------------------------------------------------------

class SessionState {
  final bool loggedIn;
  final String? username;
  final bool checking;
  const SessionState({this.loggedIn = false, this.username, this.checking = false});
}

class SessionNotifier extends Notifier<SessionState> {
  @override
  SessionState build() {
    final store = ref.read(localStoreProvider);
    Future.microtask(refresh);
    return SessionState(username: store.username, checking: true);
  }

  Future<void> refresh() async {
    final store = ref.read(localStoreProvider);
    final logged = await ref.read(accountRepositoryProvider).isLoggedIn();
    state = SessionState(
      loggedIn: logged,
      username: logged ? store.username : null,
      checking: false,
    );
  }
}

final sessionProvider =
    NotifierProvider<SessionNotifier, SessionState>(SessionNotifier.new);

// ---------------------------------------------------------------------------
// Notifications temps réel (veille des sorties)
// ---------------------------------------------------------------------------

class NotificationsState {
  final List<AppNotification> items; // du plus récent au plus ancien
  final DateTime? lastCheck;
  final bool checking;

  const NotificationsState({
    this.items = const [],
    this.lastCheck,
    this.checking = false,
  });

  int get unreadCount => items.where((n) => !n.read).length;

  NotificationsState copyWith({
    List<AppNotification>? items,
    DateTime? lastCheck,
    bool? checking,
  }) =>
      NotificationsState(
        items: items ?? this.items,
        lastCheck: lastCheck ?? this.lastCheck,
        checking: checking ?? this.checking,
      );
}

/// Veille des sorties : interroge la page d'accueil (derniers épisodes/scans)
/// à intervalle régulier et compare aux signatures connues (ReleaseDiff).
///
/// * premier cycle d'une installation = baseline silencieuse ;
/// * les nouveautés alimentent le centre de notifications in-app ;
/// * si « notifications système » est activée, un push Android/iOS est émis ;
/// * le timer ne tourne que lorsque les notifications sont activées.
class NotificationsNotifier extends Notifier<NotificationsState> {
  Timer? _timer;
  bool _checking = false;
  bool _starting = false;
  final _plugin = FlutterLocalNotificationsPlugin();
  bool _pluginReady = false;

  static const _channelEpisodes = AndroidNotificationChannel(
    'animeworld_episodes',
    'Nouveaux épisodes',
    description: 'Nouveaux épisodes des œuvres suivies',
    importance: Importance.high,
  );
  static const _channelScans = AndroidNotificationChannel(
    'animeworld_scans',
    'Nouveaux chapitres',
    description: 'Nouveaux chapitres des œuvres suivies',
    importance: Importance.high,
  );

  @override
  NotificationsState build() {
    ref.onDispose(_stop);
    Future.microtask(_start);
    final store = ref.read(localStoreProvider);
    return NotificationsState(
      items: store.getNotifications(),
      lastCheck: store.lastNotifCheck,
    );
  }

  Future<void> _start() async {
    if (_starting || !ref.mounted) return;
    _starting = true;
    try {
      await _syncFromStore();
      if (!ref.mounted) return;
      await _reschedule();
    } finally {
      _starting = false;
    }
  }

  /// (Re)démarre le polling selon les réglages — appelé après chaque
  /// modification de réglage.
  Future<void> _reschedule() async {
    if (!ref.mounted) return;
    final store = ref.read(localStoreProvider);
    _timer?.cancel();
    _timer = null;
    if (!store.notificationsEnabled) return;
    await _initPlugin();
    _timer = Timer.periodic(
      Duration(minutes: store.notificationsIntervalMinutes.clamp(1, 1440)),
      (_) => check(),
    );
    await check();
  }

  /// Relit les réglages depuis le store et relance le polling.
  Future<void> restart() async {
    await _syncFromStore();
    await _reschedule();
  }

  Future<void> _syncFromStore() async {
    if (!ref.mounted) return;
    final store = ref.read(localStoreProvider);
    state = state.copyWith(
      items: store.getNotifications(),
      lastCheck: store.lastNotifCheck,
    );
  }

  Future<void> check() async {
    if (_checking) return;
    final store = ref.read(localStoreProvider);
    if (!store.notificationsEnabled) return;
    _checking = true;
    state = state.copyWith(checking: true);
    try {
      final home = await ref.read(animeRepositoryProvider).getHome(force: true);
      if (!ref.mounted) return;
      final releases = [...home.latestEpisodes, ...home.latestScans];
      final sigs = store.releaseSignatures;
      final res = ReleaseDiff.compute(
        releases: releases,
        known: sigs,
        baseline: sigs.isEmpty,
        filter: (r) => _filter(store, r),
      );
      if (res.notifications.isNotEmpty) {
        await store.addNotifications(res.notifications);
        await _notifySystem(res.notifications);
      }
      await store.setReleaseSignatures(res.allKeys);
      final now = DateTime.now();
      await store.setLastNotifCheck(now);
      state = state.copyWith(
        items: store.getNotifications(),
        lastCheck: now,
        checking: false,
      );
    } catch (_) {
      // Erreur réseau / parsing : silencieuse, nouvelle tentative au
      // prochain cycle.
      state = state.copyWith(checking: false);
    } finally {
      _checking = false;
    }
  }

  bool _filter(LocalStore store, ReleaseItem r) {
    final isScan = r.isScan;
    if (isScan && !store.notifyScans) return false;
    if (!isScan && !store.notifyEpisodes) return false;
    if (store.notificationsScope == 'library' && !store.isTrackedSlug(r.slug)) {
      return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Notifications système (Android 13+ / iOS)
  // ---------------------------------------------------------------------------

  Future<void> _initPlugin() async {
    if (_pluginReady || kIsWeb) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          // Les permissions iOS sont demandées plus tard, à la demande
          // (voir requestSystemPermission), pas au démarrage.
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
        ),
      );
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createChannel(_channelEpisodes);
      await android?.createChannel(_channelScans);
      _pluginReady = true;
    } catch (_) {
      // Plateforme non supportée (tests) : le centre in-app reste fonctionnel.
    }
  }

  /// Demande la permission système (Android 13+, iOS). Retourne true si
  /// accordée ou indéterminable.
  Future<bool> requestSystemPermission() async {
    if (kIsWeb) return false;
    await _initPlugin();
    try {
      if (Platform.isIOS) {
        final ios = _plugin.resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin>();
        final granted = await ios
            ?.requestPermissions(alert: true, badge: true, sound: true);
        return granted ?? true;
      }
      if (Platform.isAndroid) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        final granted = await android?.requestNotificationsPermission();
        return granted ?? true;
      }
    } catch (_) {}
    return true;
  }

  Future<bool> systemPermissionGranted() async {
    if (kIsWeb) return false;
    await _initPlugin();
    try {
      if (Platform.isAndroid) {
        final android = _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        return await android?.areNotificationsEnabled() ?? true;
      }
      if (Platform.isIOS) return true; // pas d'API de lecture simple
    } catch (_) {}
    return true;
  }

  Future<void> _notifySystem(List<AppNotification> fresh) async {
    final store = ref.read(localStoreProvider);
    if (!store.systemNotificationsEnabled || fresh.isEmpty || kIsWeb) return;
    try {
      if (!await systemPermissionGranted()) return;
      for (final n in fresh.take(5)) {
        final isScan = n.kind == 'scan';
        final details = NotificationDetails(
          android: AndroidNotificationDetails(
            isScan ? _channelScans.id : _channelEpisodes.id,
            isScan ? _channelScans.name : _channelEpisodes.name,
            channelDescription: isScan
                ? _channelScans.description
                : _channelEpisodes.description,
            importance: Importance.high,
            priority: Priority.high,
            styleInformation: BigTextStyleInformation(n.body),
          ),
          iOS: const DarwinNotificationDetails(
            presentAlert: true,
            presentSound: true,
          ),
        );
        await _plugin.show(
          id: n.path.hashCode & 0x7fffffff,
          title: n.title,
          body: n.body,
          notificationDetails: details,
          payload: n.path,
        );
      }
    } catch (_) {
      // Les notifications système sont un plus : ne jamais faire échouer
      // la veille.
    }
  }

  // ---------------------------------------------------------------------------
  // Actions du centre de notifications
  // ---------------------------------------------------------------------------

  Future<void> markRead(String id) async {
    await ref.read(localStoreProvider).markNotificationRead(id);
    await _syncFromStore();
  }

  Future<void> markAllRead() async {
    await ref.read(localStoreProvider).markAllNotificationsRead();
    await _syncFromStore();
  }

  Future<void> clearAll() async {
    await ref.read(localStoreProvider).clearNotifications();
    await _syncFromStore();
  }

  Future<void> toggleEnabled(bool v) async {
    final store = ref.read(localStoreProvider);
    await store.setNotificationsEnabled(v);
    if (v && store.systemNotificationsEnabled) {
      await requestSystemPermission();
    }
    await restart();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }
}

final notificationsProvider =
    NotifierProvider<NotificationsNotifier, NotificationsState>(
        NotificationsNotifier.new);
