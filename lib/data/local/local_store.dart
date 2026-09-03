import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_ce_flutter/hive_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../models/models.dart';

/// Stockage local — équivalent strict du `localStorage` du site :
///
/// * listes `favori*`, `watchlist*`, `vu*` (3 tableaux parallèles nom/url/img)
/// * historique `histo*` (7 tableaux)
/// * progression `savedEpName{path}` / `savedEpNb{path}` (et `savedChap*`)
/// * préférences (`readingMode`, lecteur par défaut, domaine…)
///
/// Conserver la même structure permet d'envoyer/recevoir tel quel les données
/// de `/api/get-data.php`, `/api/sync-*.php` et `/api/merge-data.php`.
class LocalStore extends ChangeNotifier {
  LocalStore._(this._box, this._prefs);

  static const _boxName = 'animeworld_data';
  static const _prefsName = 'animeworld_prefs';

  final Box _box;
  final Box _prefs;

  static Future<LocalStore> open() async {
    await Hive.initFlutter();
    final box = await Hive.openBox(_boxName);
    final prefs = await Hive.openBox(_prefsName);
    return LocalStore._(box, prefs);
  }

  // ---------------------------------------------------------------------------
  // Helpers bas niveau (tableaux JSON comme sur le site)
  // ---------------------------------------------------------------------------

  List<dynamic> _arr(String key) {
    final raw = _box.get(key);
    if (raw == null) return [];
    if (raw is List) return List<dynamic>.from(raw);
    try {
      final d = jsonDecode(raw as String);
      return d is List ? d : [];
    } catch (_) {
      return [];
    }
  }

  Future<void> _setArr(String key, List<dynamic> v) => _box.put(key, v);

  // ---------------------------------------------------------------------------
  // Listes : favoris / watchlist / vus
  // ---------------------------------------------------------------------------

  static const favPrefix = 'favori';
  static const watchPrefix = 'watchlist';
  static const seenPrefix = 'vu';

  List<ListEntry> getList(String prefix) {
    final noms = _arr('${prefix}Nom');
    final urls = _arr('${prefix}Url');
    final imgs = _arr('${prefix}Img');
    final out = <ListEntry>[];
    for (var i = 0; i < urls.length; i++) {
      out.add(ListEntry(
        name: i < noms.length ? '${noms[i]}' : '',
        url: '${urls[i]}',
        image: i < imgs.length ? '${imgs[i]}' : '',
      ));
    }
    return out;
  }

  Future<void> setList(String prefix, List<ListEntry> entries) async {
    await _setArr('${prefix}Nom', entries.map((e) => e.name).toList());
    await _setArr('${prefix}Url', entries.map((e) => e.url).toList());
    await _setArr('${prefix}Img', entries.map((e) => e.image).toList());
    notifyListeners();
  }

  bool isInList(String prefix, String url) =>
      _arr('${prefix}Url').contains(_normUrl(url));

  /// Ajoute ou retire (toggle) comme les boutons Watchlist/Favoris/Vu.
  /// Retourne `null` si la limite de 500 est atteinte.
  Future<bool?> toggleList(String prefix, ListEntry entry) async {
    final list = getList(prefix);
    final url = _normUrl(entry.url);
    final idx = list.indexWhere((e) => e.url == url);
    if (idx >= 0) {
      list.removeAt(idx);
      await setList(prefix, list);
      return false;
    }
    if (list.length >= AppConstants.listMax) return null;
    list.add(ListEntry(name: entry.name, url: url, image: entry.image));
    await setList(prefix, list);
    return true;
  }

  Future<void> removeFromList(String prefix, String url) async {
    final list = getList(prefix)..removeWhere((e) => e.url == _normUrl(url));
    await setList(prefix, list);
  }

  Future<void> clearList(String prefix) => setList(prefix, const []);

  /// Le site utilise `window.location.pathname` (avec slash final) comme url.
  String _normUrl(String url) {
    var u = url;
    if (u.startsWith('http')) u = Uri.parse(u).path;
    if (!u.startsWith('/')) u = '/$u';
    return u;
  }

  // ---------------------------------------------------------------------------
  // Historique
  // ---------------------------------------------------------------------------

  List<HistoryEntry> getHistory() {
    final nom = _arr('histoNom');
    final url = _arr('histoUrl');
    final img = _arr('histoImg');
    final type = _arr('histoType');
    final lang = _arr('histoLang');
    final ep = _arr('histoEp');
    final num = _arr('histoNum');
    final out = <HistoryEntry>[];
    for (var i = 0; i < url.length; i++) {
      out.add(HistoryEntry(
        name: i < nom.length ? '${nom[i]}' : '',
        url: '${url[i]}',
        image: i < img.length ? '${img[i]}' : '',
        type: i < type.length ? '${type[i]}' : '',
        lang: i < lang.length ? '${lang[i]}' : '',
        episode: i < ep.length ? '${ep[i]}' : '',
        num: i < num.length ? (int.tryParse('${num[i]}') ?? 0) : 0,
      ));
    }
    return out; // ordre du site : le plus récent en DERNIER
  }

  Future<void> setHistory(List<HistoryEntry> h) async {
    await _setArr('histoNom', h.map((e) => e.name).toList());
    await _setArr('histoUrl', h.map((e) => e.url).toList());
    await _setArr('histoImg', h.map((e) => e.image).toList());
    await _setArr('histoType', h.map((e) => e.type).toList());
    await _setArr('histoLang', h.map((e) => e.lang).toList());
    await _setArr('histoEp', h.map((e) => e.episode).toList());
    await _setArr('histoNum', h.map((e) => e.num).toList());
    notifyListeners();
  }

  /// `addHistorique()` : insère ou met à jour puis déplace en fin de liste.
  Future<void> addHistory(HistoryEntry entry) async {
    final h = getHistory();
    final idx = h.indexWhere((e) => e.url == entry.url);
    if (idx >= 0) h.removeAt(idx);
    h.add(entry);
    // Limite raisonnable (le site conserve tout ; on borne à 500 comme les listes)
    while (h.length > AppConstants.listMax) {
      h.removeAt(0);
    }
    await setHistory(h);
  }

  Future<void> removeHistory(String url) async {
    final h = getHistory()..removeWhere((e) => e.url == url);
    await setHistory(h);
  }

  Future<void> clearHistory() => setHistory(const []);

  // ---------------------------------------------------------------------------
  // Progression (savedEpName / savedEpNb / savedChapName / savedChapNb)
  // ---------------------------------------------------------------------------

  /// Le site teste `/scan/`, `/scans/` et `/s2/` ; on accepte aussi les
  /// dossiers dérivés (`scan_one_shot`, `scan-end-line`, `scan_noir-et-blanc`).
  static bool isScanUrl(String url) => url.contains('/scan') || url.contains('/s2/');

  /// Progression la plus récente pour une saison, toutes langues confondues
  /// (ex. l'utilisateur a regardé en VF alors que la fiche déclare vostfr).
  Progress? getProgressForFolder(String slug, String folder) {
    final prefix = '/catalogue/$slug/$folder/';
    // L'historique est ordonné du plus ancien au plus récent.
    for (final h in getHistory().reversed) {
      if (h.url.startsWith(prefix)) {
        return Progress(name: h.episode, num: h.num);
      }
    }
    return null;
  }

  Progress? getProgress(String path) {
    final scan = isScanUrl(path);
    final name = _box.get(scan ? 'savedChapName$path' : 'savedEpName$path');
    final num = _box.get(scan ? 'savedChapNb$path' : 'savedEpNb$path');
    if (name == null && num == null) return null;
    return Progress(
      name: name?.toString() ?? '',
      num: int.tryParse(num?.toString() ?? '') ?? 0,
    );
  }

  Future<void> setProgress(String path, String name, int num) async {
    final scan = isScanUrl(path);
    await _box.put(scan ? 'savedChapName$path' : 'savedEpName$path', name);
    await _box.put(scan ? 'savedChapNb$path' : 'savedEpNb$path', num);
  }

  /// Tous les chemins ayant une progression (pour la synchro serveur).
  Map<String, Progress> getAllProgress() {
    final out = <String, Progress>{};
    for (final k in _box.keys) {
      final key = k.toString();
      String? path;
      if (key.startsWith('savedEpName')) {
        path = key.substring('savedEpName'.length);
      } else if (key.startsWith('savedChapName')) {
        path = key.substring('savedChapName'.length);
      }
      if (path == null) continue;
      final p = getProgress(path);
      if (p != null) out[path] = p;
    }
    return out;
  }

  Future<void> setAllProgress(Map<String, Progress> progress) async {
    for (final e in progress.entries) {
      await setProgress(e.key, e.value.name, e.value.num);
    }
  }

  /// Épisodes marqués comme vus pour un chemin (fonctionnalité AnimeWorld :
  /// coche dans la liste des épisodes). Stocké à part.
  Set<int> getWatchedIndexes(String path) {
    final raw = _box.get('watched$path');
    if (raw is List) return raw.map((e) => int.tryParse('$e') ?? -1).toSet();
    return {};
  }

  Future<void> markWatched(String path, int index) async {
    final s = getWatchedIndexes(path)..add(index);
    await _box.put('watched$path', s.toList());
  }

  // ---------------------------------------------------------------------------
  // Préférences
  // ---------------------------------------------------------------------------

  bool get onboardingDone => _prefs.get('onboardingDone', defaultValue: false);
  Future<void> setOnboardingDone() async {
    await _prefs.put('onboardingDone', true);
    notifyListeners();
  }

  String get readingMode => _prefs.get('readingMode', defaultValue: 'scroll');
  Future<void> setReadingMode(String m) async {
    await _prefs.put('readingMode', m);
    notifyListeners();
  }

  int get readerBg => _prefs.get('readerBg', defaultValue: 0xFF020D18);
  Future<void> setReaderBg(int c) async {
    await _prefs.put('readerBg', c);
    notifyListeners();
  }

  /// Lecteur préféré (index 0-based). Le site retient le dernier choisi par
  /// session ; l'app le mémorise durablement.
  int get preferredPlayer => _prefs.get('preferredPlayer', defaultValue: 0);
  Future<void> setPreferredPlayer(int i) async {
    await _prefs.put('preferredPlayer', i);
    notifyListeners();
  }

  String get preferredLang => _prefs.get('preferredLang', defaultValue: 'vostfr');
  Future<void> setPreferredLang(String l) async {
    await _prefs.put('preferredLang', l);
    notifyListeners();
  }

  String get baseUrl =>
      _prefs.get('baseUrl', defaultValue: AppConstants.defaultBaseUrl);
  Future<void> setBaseUrl(String u) async {
    await _prefs.put('baseUrl', u);
    notifyListeners();
  }

  String? get username => _prefs.get('username');
  Future<void> setUsername(String? u) async {
    if (u == null) {
      await _prefs.delete('username');
    } else {
      await _prefs.put('username', u);
    }
    notifyListeners();
  }

  DateTime? get lastSync {
    final v = _prefs.get('lastSync');
    return v == null ? null : DateTime.tryParse(v);
  }

  Future<void> setLastSync(DateTime d) async {
    await _prefs.put('lastSync', d.toIso8601String());
    notifyListeners();
  }

  bool get autoNextEpisode => _prefs.get('autoNext', defaultValue: false);
  Future<void> setAutoNextEpisode(bool v) async {
    await _prefs.put('autoNext', v);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // Notifications temps réel (veille des sorties)
  // ---------------------------------------------------------------------------

  static const _notifKey = 'notifications';
  static const _notifSigsKey = 'releaseSignatures';
  static const _notifMax = 150;

  List<AppNotification> getNotifications() {
    final raw = _box.get(_notifKey);
    if (raw is! List) return const [];
    return raw
        .map((e) {
          try {
            if (e is Map) return AppNotification.fromJson(Map<String, dynamic>.from(e));
            if (e is String) {
              return AppNotification.fromJson(
                Map<String, dynamic>.from(jsonDecode(e) as Map),
              );
            }
          } catch (_) {}
          return null;
        })
        .whereType<AppNotification>()
        .toList(); // trié du plus récent au plus ancien
  }

  /// Ajoute en tête, dédoublonne par id et borne la liste.
  Future<void> addNotifications(List<AppNotification> added) async {
    if (added.isEmpty) return;
    final seen = <String>{};
    final out = <AppNotification>[];
    for (final n in [...added, ...getNotifications()]) {
      if (!seen.add(n.id)) continue;
      out.add(n);
      if (out.length >= _notifMax) break;
    }
    await _box.put(_notifKey, out.map((n) => n.toJson()).toList());
    notifyListeners();
  }

  Future<void> markNotificationRead(String id) async {
    final out = <AppNotification>[];
    for (final n in getNotifications()) {
      out.add(n.id == id ? n.copyWith(read: true) : n);
    }
    await _box.put(_notifKey, out.map((n) => n.toJson()).toList());
    notifyListeners();
  }

  Future<void> markAllNotificationsRead() async {
    await _box.put(
      _notifKey,
      getNotifications().map((n) => n.copyWith(read: true).toJson()).toList(),
    );
    notifyListeners();
  }

  Future<void> clearNotifications() async {
    await _box.put(_notifKey, <Map<String, dynamic>>[]);
    notifyListeners();
  }

  int get unreadNotificationCount =>
      getNotifications().where((n) => !n.read).length;

  /// Signatures des sorties déjà vues (`{path}::{info}`) — base du diff
  /// « temps réel ». Stockées dans la box de données (pas de notification
  /// pour l'utilisateur).
  Set<String> get releaseSignatures {
    final raw = _box.get(_notifSigsKey);
    if (raw is List) return raw.map((e) => '$e').toSet();
    return const {};
  }

  Future<void> setReleaseSignatures(Set<String> sigs) =>
      _box.put(_notifSigsKey, sigs.toList());

  DateTime? get lastNotifCheck {
    final v = _prefs.get('lastNotifCheck');
    return v == null ? null : DateTime.tryParse('$v');
  }

  Future<void> setLastNotifCheck(DateTime d) async {
    await _prefs.put('lastNotifCheck', d.toIso8601String());
    notifyListeners();
  }

  // Réglages notifications ---------------------------------------------------

  /// Veille active (centre de notifications + polling). Activée par défaut.
  bool get notificationsEnabled =>
      _prefs.get('notificationsEnabled', defaultValue: true);
  Future<void> setNotificationsEnabled(bool v) async {
    await _prefs.put('notificationsEnabled', v);
    notifyListeners();
  }

  /// Notifier aussi via les notifications système (bandeau Android/iOS).
  bool get systemNotificationsEnabled =>
      _prefs.get('systemNotifications', defaultValue: true);
  Future<void> setSystemNotificationsEnabled(bool v) async {
    await _prefs.put('systemNotifications', v);
    notifyListeners();
  }

  /// Période du polling (minutes) — 2, 5, 15, 30 ou 60.
  int get notificationsIntervalMinutes =>
      _prefs.get('notifInterval', defaultValue: 5);
  Future<void> setNotificationsIntervalMinutes(int v) async {
    await _prefs.put('notifInterval', v);
    notifyListeners();
  }

  bool get notifyEpisodes => _prefs.get('notifyEpisodes', defaultValue: true);
  Future<void> setNotifyEpisodes(bool v) async {
    await _prefs.put('notifyEpisodes', v);
    notifyListeners();
  }

  bool get notifyScans => _prefs.get('notifyScans', defaultValue: true);
  Future<void> setNotifyScans(bool v) async {
    await _prefs.put('notifyScans', v);
    notifyListeners();
  }

  /// Périmètre : `library` (watchlist + favoris + historique) ou `all`.
  String get notificationsScope =>
      _prefs.get('notifScope', defaultValue: 'library');
  Future<void> setNotificationsScope(String v) async {
    await _prefs.put('notifScope', v);
    notifyListeners();
  }

  /// L'œuvre est-elle suivie (watchlist, favoris, vus ou historique) ?
  bool isTrackedSlug(String slug) {
    final s = slug.toLowerCase();
    bool fromEntry(String url) {
      final parts = url.split('/').where((p) => p.isNotEmpty).toList();
      final i = parts.indexOf('catalogue');
      return i >= 0 &&
          i + 1 < parts.length &&
          parts[i + 1].toLowerCase() == s;
    }

    for (final e in getList(watchPrefix)) {
      if (fromEntry(e.url)) return true;
    }
    for (final e in getList(favPrefix)) {
      if (fromEntry(e.url)) return true;
    }
    for (final e in getList(seenPrefix)) {
      if (fromEntry(e.url)) return true;
    }
    for (final h in getHistory()) {
      if (fromEntry(h.url)) return true;
    }
    return false;
  }

  Future<void> wipeAll() async {
    await _box.clear();
    notifyListeners();
  }
}
