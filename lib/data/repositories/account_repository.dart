import 'dart:convert';

import '../local/local_store.dart';
import '../models/models.dart';
import '../network/api_client.dart';

/// Compte utilisateur & synchronisation — mêmes endpoints `/api/*` que le site
/// (defaut.js / login.js / profil.js).
class AccountRepository {
  AccountRepository(this._client, this._store);

  final ApiClient _client;
  final LocalStore _store;

  // ---------------------------------------------------------------------------
  // Auth
  // ---------------------------------------------------------------------------

  /// Retourne null si OK, sinon le message d'erreur.
  Future<String?> login(String pseudo, String password) async {
    final r = await _client.postJson('/api/auth/login.php', {
      'pseudo': pseudo,
      'password': password,
    });
    if (r.statusCode == 429) {
      return 'Trop de tentatives. Réessayez dans 1 heure.';
    }
    final data = _json(r.data);
    if (r.statusCode == 200 && (data['error'] == null)) {
      await _store.setUsername(pseudo);
      await syncFromServer();
      return null;
    }
    return data['error']?.toString() ?? 'Erreur de connexion';
  }

  Future<String?> register(String pseudo, String password) async {
    final r = await _client.postJson('/api/auth/register.php', {
      'pseudo': pseudo,
      'password': password,
    });
    if (r.statusCode == 429) {
      return 'Trop de créations de compte. Réessayez dans 1 heure.';
    }
    final data = _json(r.data);
    if (r.statusCode == 200 && data['error'] == null) {
      // Le site enchaîne sur une connexion automatique après inscription.
      return login(pseudo, password);
    }
    return data['error']?.toString() ?? 'Erreur lors de l\'inscription';
  }

  Future<void> logout() async {
    try {
      await _client.getText('/api/auth/logout.php');
    } catch (_) {}
    await _client.clearCookies();
    await _store.setUsername(null);
  }

  Map<String, dynamic> _json(String? s) {
    if (s == null || s.isEmpty) return {};
    try {
      final d = jsonDecode(s);
      return d is Map<String, dynamic> ? d : {};
    } catch (_) {
      return {};
    }
  }

  // ---------------------------------------------------------------------------
  // get-data / merge
  // ---------------------------------------------------------------------------

  Future<ServerData> getServerData() async {
    final r = await _client.getText('/api/get-data.php');
    final d = _json(r.data);
    if (d['logged_in'] != true) return const ServerData(loggedIn: false);
    return ServerData(
      loggedIn: true,
      needMerge: d['need_merge'] == true,
      progress: _parseProgress(d['progress']),
      favorites: _parseList(d['favorites']),
      watchlist: _parseList(d['watchlist']),
      viewed: _parseList(d['viewed']),
      history: _parseHistory(d['history']),
    );
  }

  Future<bool> isLoggedIn() async {
    try {
      return (await getServerData()).loggedIn;
    } catch (_) {
      return false;
    }
  }

  /// `loadAllDataFromServer()` : récupère les données serveur, fusionne si
  /// `need_merge`, sinon remplace le local par le serveur (en gardant la
  /// progression la plus avancée).
  Future<bool> syncFromServer() async {
    final server = await getServerData();
    if (!server.loggedIn) return false;

    if (server.needMerge) {
      final r = await _client.postJson('/api/merge-data.php', _localPayload());
      final d = _json(r.data);
      final merged = d['merged'];
      if (merged is Map<String, dynamic>) {
        await _applyServer(ServerData(
          loggedIn: true,
          progress: _parseProgress(merged['progress']),
          favorites: _parseList(merged['favorites']),
          watchlist: _parseList(merged['watchlist']),
          viewed: _parseList(merged['viewed']),
          history: _parseHistory(merged['history']),
        ));
      }
    } else {
      await _applyServer(server);
    }
    await _store.setLastSync(DateTime.now());
    return true;
  }

  Future<void> _applyServer(ServerData s) async {
    // progression : ne jamais reculer
    for (final e in s.progress.entries) {
      final local = _store.getProgress(e.key);
      if (local == null || e.value.num > local.num) {
        await _store.setProgress(e.key, e.value.name, e.value.num);
      }
    }
    await _store.setList(LocalStore.favPrefix, s.favorites);
    await _store.setList(LocalStore.watchPrefix, s.watchlist);
    await _store.setList(LocalStore.seenPrefix, s.viewed);
    if (s.history.isNotEmpty) await _store.setHistory(s.history);
  }

  // ---------------------------------------------------------------------------
  // sync-* (local → serveur)
  // ---------------------------------------------------------------------------

  Map<String, dynamic> _listPayload(List<ListEntry> l) => {
        'nom': l.map((e) => e.name).toList(),
        'url': l.map((e) => e.url).toList(),
        'img': l.map((e) => e.image).toList(),
      };

  Map<String, dynamic> _historyPayload(List<HistoryEntry> h) => {
        'nom': h.map((e) => e.name).toList(),
        'url': h.map((e) => e.url).toList(),
        'img': h.map((e) => e.image).toList(),
        'type': h.map((e) => e.type).toList(),
        'lang': h.map((e) => e.lang).toList(),
        'ep': h.map((e) => e.episode).toList(),
        'num': h.map((e) => e.num).toList(),
      };

  Map<String, dynamic> _localPayload() => {
        'progress': {
          for (final e in _store.getAllProgress().entries)
            e.key: {'name': e.value.name, 'num': e.value.num},
        },
        'favorites': _listPayload(_store.getList(LocalStore.favPrefix)),
        'watchlist': _listPayload(_store.getList(LocalStore.watchPrefix)),
        'viewed': _listPayload(_store.getList(LocalStore.seenPrefix)),
        'history': _historyPayload(_store.getHistory()),
      };

  Future<void> _post(String path, Map<String, dynamic> body) async {
    try {
      await _client.postJson(path, body);
    } catch (_) {}
  }

  Future<void> syncFavorites() => _post('/api/sync-favorites.php', {
        'favorites': _listPayload(_store.getList(LocalStore.favPrefix)),
      });

  Future<void> syncWatchlist() => _post('/api/sync-watchlist.php', {
        'watchlist': _listPayload(_store.getList(LocalStore.watchPrefix)),
      });

  Future<void> syncViewed() => _post('/api/sync-viewed.php', {
        'viewed': _listPayload(_store.getList(LocalStore.seenPrefix)),
      });

  Future<void> syncHistory() => _post('/api/sync-history.php', {
        'history': _historyPayload(_store.getHistory()),
      });

  Future<void> syncProgress() => _post('/api/sync-progress.php', {
        'progress': {
          for (final e in _store.getAllProgress().entries)
            e.key: {'name': e.value.name, 'num': e.value.num},
        },
      });

  Future<void> syncListByPrefix(String prefix) {
    switch (prefix) {
      case LocalStore.favPrefix:
        return syncFavorites();
      case LocalStore.watchPrefix:
        return syncWatchlist();
      default:
        return syncViewed();
    }
  }

  /// Pousse tout le local vers le serveur (bouton « Synchroniser »).
  Future<void> syncAllToServer() async {
    if (!await isLoggedIn()) return;
    await Future.wait([
      syncFavorites(),
      syncWatchlist(),
      syncViewed(),
      syncHistory(),
      syncProgress(),
    ]);
    await _store.setLastSync(DateTime.now());
  }

  // ---------------------------------------------------------------------------
  // Parsing
  // ---------------------------------------------------------------------------

  Map<String, Progress> _parseProgress(dynamic raw) {
    final out = <String, Progress>{};
    if (raw is Map) {
      raw.forEach((k, v) {
        if (v is Map) {
          out['$k'] = Progress(
            name: '${v['name'] ?? ''}',
            num: int.tryParse('${v['num'] ?? 0}') ?? 0,
          );
        }
      });
    }
    return out;
  }

  List<ListEntry> _parseList(dynamic raw) {
    if (raw is! Map) return const [];
    final nom = (raw['nom'] as List?) ?? const [];
    final url = (raw['url'] as List?) ?? const [];
    final img = (raw['img'] as List?) ?? const [];
    return [
      for (var i = 0; i < url.length; i++)
        ListEntry(
          name: i < nom.length ? '${nom[i]}' : '',
          url: '${url[i]}',
          image: i < img.length ? '${img[i]}' : '',
        ),
    ];
  }

  List<HistoryEntry> _parseHistory(dynamic raw) {
    if (raw is! Map) return const [];
    List<dynamic> g(String k) => (raw[k] as List?) ?? const [];
    final nom = g('nom'), url = g('url'), img = g('img'), type = g('type');
    final lang = g('lang'), ep = g('ep'), num = g('num');
    return [
      for (var i = 0; i < url.length; i++)
        HistoryEntry(
          name: i < nom.length ? '${nom[i]}' : '',
          url: '${url[i]}',
          image: i < img.length ? '${img[i]}' : '',
          type: i < type.length ? '${type[i]}' : '',
          lang: i < lang.length ? '${lang[i]}' : '',
          episode: i < ep.length ? '${ep[i]}' : '',
          num: i < num.length ? (int.tryParse('${num[i]}') ?? 0) : 0,
        ),
    ];
  }
}
