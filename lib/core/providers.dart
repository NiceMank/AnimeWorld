import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show ChangeNotifierProvider;

import '../data/local/local_store.dart';
import '../data/models/models.dart';
import '../data/network/api_client.dart';
import '../data/repositories/account_repository.dart';
import '../data/repositories/anime_repository.dart';

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
