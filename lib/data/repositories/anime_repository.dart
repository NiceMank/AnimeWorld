import 'dart:convert';

import '../../core/constants/app_constants.dart';
import '../../core/constants/languages.dart';
import '../models/models.dart';
import '../network/api_client.dart';
import '../parsers/episodes_parser.dart';
import '../parsers/html_parsers.dart';

class AppException implements Exception {
  final String message;
  const AppException(this.message);
  @override
  String toString() => message;
}

/// Accès au contenu du site (lecture seule). Reproduit les mêmes requêtes que
/// le navigateur sur anime-sama.to.
class AnimeRepository {
  AnimeRepository(this._client);

  final ApiClient _client;

  // Petits caches mémoire (durée de vie de l'application).
  HomeData? _homeCache;
  DateTime? _homeCacheAt;
  final Map<String, AnimeDetails> _detailsCache = {};
  final Map<String, List<String>> _langCache = {};
  PlanningData? _planningCache;
  DateTime? _planningAt;

  // ---------------------------------------------------------------------------
  // Accueil
  // ---------------------------------------------------------------------------

  Future<HomeData> getHome({bool force = false}) async {
    if (!force &&
        _homeCache != null &&
        _homeCacheAt != null &&
        DateTime.now().difference(_homeCacheAt!) < const Duration(minutes: 5)) {
      return _homeCache!;
    }
    final r = await _client.getText('/');
    if (r.statusCode != 200 || r.data == null) {
      throw AppException('Impossible de charger l\'accueil (${r.statusCode}).');
    }
    final data = HtmlParsers.parseHome(r.data!);
    _homeCache = data;
    _homeCacheAt = DateTime.now();
    return data;
  }

  // ---------------------------------------------------------------------------
  // Catalogue / recherche
  // ---------------------------------------------------------------------------

  Future<CataloguePage> getCatalogue(CatalogueFilters filters, int page) async {
    final r = await _client.getWithMultiQuery('/catalogue', filters.toQuery(page));
    if (r.statusCode != 200 || r.data == null) {
      throw AppException('Catalogue indisponible (${r.statusCode}).');
    }
    return HtmlParsers.parseCatalogue(r.data!, page);
  }

  Future<List<SearchResult>> search(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];
    final r = await _client.postForm('/template-php/defaut/fetch.php', {'query': q});
    if (r.statusCode != 200 || r.data == null) return const [];
    return HtmlParsers.parseSearch(r.data!);
  }

  // ---------------------------------------------------------------------------
  // Fiche
  // ---------------------------------------------------------------------------

  Future<AnimeDetails> getDetails(String slug, {bool force = false}) async {
    if (!force && _detailsCache.containsKey(slug)) return _detailsCache[slug]!;
    final r = await _client.getText('/catalogue/$slug/');
    if (r.statusCode == 404) throw const AppException('Œuvre introuvable.');
    if (r.statusCode != 200 || r.data == null) {
      throw AppException('Fiche indisponible (${r.statusCode}).');
    }
    final d = HtmlParsers.parseDetails(r.data!, slug);
    _detailsCache[slug] = d;
    return d;
  }

  // ---------------------------------------------------------------------------
  // Langues disponibles (afficheLangueAnime)
  // ---------------------------------------------------------------------------

  /// Le site fait un GET sur `../{lang}` pour chaque langue et affiche le
  /// bouton si la requête réussit. Ici : 404 = absente ; 200 = présente si
  /// episodes.js contient des lecteurs (pour les animes).
  Future<List<String>> availableLanguages(
    String slug,
    String folder, {
    required bool isScan,
  }) async {
    final key = '$slug/$folder';
    if (_langCache.containsKey(key)) return _langCache[key]!;
    final candidates = isScan ? kScanLanguages : kAnimeLanguages;
    final results = await Future.wait(candidates.map((l) async {
      final path = '/catalogue/$slug/$folder/${l.code}/';
      if (isScan) {
        return await _client.statusOf(path) == 200 ? l.code : null;
      }
      // Pour un anime, `episodes.js` suffit : 404 si la langue n'existe pas,
      // 200 avec des `var eps` si elle est disponible (fichier de 2-3 Ko).
      try {
        final js = await _client.getText('${path}episodes.js');
        if (js.statusCode == 200 && (js.data ?? '').contains('eps')) return l.code;
      } catch (_) {}
      return null;
    }));
    final langs = results.whereType<String>().toList();
    _langCache[key] = langs;
    return langs;
  }

  // ---------------------------------------------------------------------------
  // Épisodes
  // ---------------------------------------------------------------------------

  Future<EpisodePage> getEpisodePage(
    String slug,
    String folder,
    String lang,
  ) async {
    final path = '/catalogue/$slug/$folder/$lang/';
    final pageResp = await _client.getText(path);
    if (pageResp.statusCode == 404) {
      throw const AppException('Cette saison n\'existe pas dans cette langue.');
    }
    if (pageResp.statusCode != 200 || pageResp.data == null) {
      throw AppException('Page indisponible (${pageResp.statusCode}).');
    }
    final info = HtmlParsers.parseContentPageInfo(pageResp.data!);

    final jsResp = await _client.getText('$path${info.episodesJsFile}');
    final players = jsResp.statusCode == 200
        ? EpisodesParser.parsePlayers(jsResp.data ?? '')
        : const <Player>[];
    final total = EpisodesParser.episodeCount(players);
    final labels = total == 0
        ? const <String>[]
        : EpisodesParser.buildLabels(
            total: total,
            scripts: info.inlineScripts,
            unit: 'Episode',
          );

    // Langues disponibles (en parallèle, non bloquant si erreur)
    List<String> langs;
    try {
      langs = await availableLanguages(slug, folder, isScan: false);
    } catch (_) {
      langs = [lang];
    }
    if (!langs.contains(lang)) langs = [lang, ...langs];

    return EpisodePage(
      path: path,
      slug: slug,
      title: info.title,
      seasonName: info.seasonName,
      banner: info.banner.isNotEmpty ? info.banner : AppConstants.banner(slug),
      lang: lang,
      episodeNames: labels,
      players: players,
      message: info.message,
      availableLangs: langs,
    );
  }

  // ---------------------------------------------------------------------------
  // Scans
  // ---------------------------------------------------------------------------

  Future<Map<int, int>?> _scanChapters(String oeuvre) async {
    final r = await _client.getText(
      '/s2/scans/get_nb_chap_et_img.php',
      query: {'oeuvre': oeuvre},
    );
    if (r.statusCode != 200 || r.data == null) return null;
    try {
      final d = jsonDecode(r.data!);
      if (d is! Map || d.containsKey('error')) return null;
      final out = <int, int>{};
      d.forEach((k, v) {
        final ch = int.tryParse('$k');
        final n = int.tryParse('$v');
        if (ch != null && n != null) out[ch] = n;
      });
      return out.isEmpty ? null : out;
    } catch (_) {
      return null;
    }
  }

  Future<ScanPage> getScanPage(String slug, String folder, String lang) async {
    final path = '/catalogue/$slug/$folder/$lang/';
    final pageResp = await _client.getText(path);
    if (pageResp.statusCode == 404) {
      throw const AppException('Ces scans n\'existent pas dans cette langue.');
    }
    if (pageResp.statusCode != 200 || pageResp.data == null) {
      throw AppException('Page indisponible (${pageResp.statusCode}).');
    }
    final info = HtmlParsers.parseContentPageInfo(pageResp.data!);

    // ⚠️ nom d'œuvre = innerHTML brut de #titreOeuvre (espaces inclus).
    final oeuvre = info.rawTitle;
    final chapters = await _scanChapters(oeuvre) ??
        await _scanChapters(info.title) ??
        <int, int>{};
    Map<int, int>? pp;
    if (chapters.isNotEmpty) {
      pp = await _scanChapters('$oeuvre pp');
    }

    final total = chapters.length;
    final labels = total == 0
        ? const <String>[]
        : EpisodesParser.buildLabels(
            total: total,
            scripts: info.inlineScripts,
            unit: 'Chapitre',
          );

    List<String> langs;
    try {
      langs = await availableLanguages(slug, folder, isScan: true);
    } catch (_) {
      langs = [lang];
    }
    if (!langs.contains(lang)) langs = [lang, ...langs];

    return ScanPage(
      path: path,
      slug: slug,
      title: oeuvre,
      seasonName: info.seasonName.isEmpty ? 'Scans' : info.seasonName,
      banner: info.banner.isNotEmpty ? info.banner : AppConstants.banner(slug),
      lang: lang,
      chapterNames: labels,
      pagesPerChapter: chapters,
      pagesPerChapterPP: pp,
      message: info.message,
      availableLangs: langs,
    );
  }

  /// URL d'une page de scan : /s2/scans/{oeuvre}/{chapitre}/{n}.jpg
  String scanImageUrl(String oeuvre, int chapter, int page, {bool pp = false}) {
    final name = pp ? '$oeuvre pp' : oeuvre;
    return _client.absolute(
      '/s2/scans/${Uri.encodeComponent(name)}/$chapter/$page.jpg',
    );
  }

  // ---------------------------------------------------------------------------
  // Planning
  // ---------------------------------------------------------------------------

  Future<PlanningData> getPlanning({bool force = false}) async {
    if (!force &&
        _planningCache != null &&
        _planningAt != null &&
        DateTime.now().difference(_planningAt!) < const Duration(minutes: 10)) {
      return _planningCache!;
    }
    final r = await _client.getText('/planning');
    if (r.statusCode != 200 || r.data == null) {
      throw AppException('Planning indisponible (${r.statusCode}).');
    }
    final p = HtmlParsers.parsePlanning(r.data!);
    _planningCache = p;
    _planningAt = DateTime.now();
    return p;
  }

  void clearCaches() {
    _homeCache = null;
    _detailsCache.clear();
    _langCache.clear();
    _planningCache = null;
  }

  String absolute(String p) => _client.absolute(p);
}
