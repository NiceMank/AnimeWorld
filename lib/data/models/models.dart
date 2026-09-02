/// Modèles de données d'AnimeWorld.
///
/// Ils reflètent exactement ce que le site expose (HTML, episodes.js, JSON
/// scans, /api/get-data.php). Aucun champ inventé.
library;

/// Carte « catalogue » (utilisée sur /catalogue, « Derniers contenus sortis »,
/// « Classiques », « Pépites », « Œuvres similaires »).
class CatalogueItem {
  final String slug; // ex. "black-torch"
  final String title;
  final List<String> altTitles;
  final String image; // thumb webp
  final List<String> genres;
  final List<String> types; // Anime, Scans, Film…
  final List<String> langs; // JP, FR, EN
  final String synopsis;

  const CatalogueItem({
    required this.slug,
    required this.title,
    this.altTitles = const [],
    required this.image,
    this.genres = const [],
    this.types = const [],
    this.langs = const [],
    this.synopsis = '',
  });

  String get path => '/catalogue/$slug';
}

/// Résultat de la recherche instantanée (POST /template-php/defaut/fetch.php).
class SearchResult {
  final String slug;
  final String title;
  final String subtitle;
  final String image;
  const SearchResult({
    required this.slug,
    required this.title,
    required this.subtitle,
    required this.image,
  });
}

/// Slide du carrousel de l'accueil.
class HeroSlide {
  final String slug;
  final String title;
  final String badge; // "Saison 1 en cours"
  final String banner;
  final List<String> genres;
  final String synopsis;

  /// Liens « Visionner en … » : libellé (VOSTFR/VF/VKR) → chemin relatif
  /// (/catalogue/{slug}/saison1/vostfr/).
  final List<HeroCta> ctas;

  const HeroSlide({
    required this.slug,
    required this.title,
    required this.badge,
    required this.banner,
    required this.genres,
    required this.synopsis,
    required this.ctas,
  });
}

class HeroCta {
  final String label;
  final String flag; // jp, fr, kr…
  final String path;
  const HeroCta({required this.label, required this.flag, required this.path});
}

/// Carte « épisode/scan ajouté » et carte planning (anime-card-premium /
/// scan-card-premium).
class ReleaseItem {
  final String path; // /catalogue/{slug}/{saison}/{lang}/
  final String slug;
  final String title;
  final String image;
  final String badge; // Anime, Film, Scans, Webtoon…
  final String lang; // VOSTFR, VF, VKR…
  final String info; // "Saison 1 Episode 9" / "Chapitre 34" / "Saison 1"
  final String time; // "02/09/2026 20:10" ou "15h00"
  final bool problem; // planning-problem-red
  final int? releaseTs;

  const ReleaseItem({
    required this.path,
    required this.slug,
    required this.title,
    required this.image,
    this.badge = '',
    this.lang = '',
    this.info = '',
    this.time = '',
    this.problem = false,
    this.releaseTs,
  });

  bool get isScan {
    final b = badge.toLowerCase();
    return path.contains('/scan') ||
        b.contains('scan') ||
        b.contains('webtoon') ||
        b.contains('manga') ||
        b.contains('manhwa');
  }
}

/// Page d'accueil complète.
class HomeData {
  final List<HeroSlide> slides;
  final List<ReleaseItem> latestEpisodes;
  final List<ReleaseItem> latestScans;
  final List<CatalogueItem> latestContent;
  final List<CatalogueItem> classics;
  final List<CatalogueItem> gems;
  final String todayLabel; // "Sorties du Mercredi - 02/09"
  final List<ReleaseItem> todayReleases;

  const HomeData({
    required this.slides,
    required this.latestEpisodes,
    required this.latestScans,
    required this.latestContent,
    required this.classics,
    required this.gems,
    required this.todayLabel,
    required this.todayReleases,
  });
}

/// Une « saison » déclarée par panneauAnime()/panneauScan() sur la fiche.
class SeasonEntry {
  final String name; // "Saison 1", "Film", "Scans"…
  final String relativeUrl; // "saison1/vostfr", "scan/vf"
  final bool isScan;
  const SeasonEntry({
    required this.name,
    required this.relativeUrl,
    required this.isScan,
  });

  /// Dossier (saison1, film, scan…)
  String get folder => relativeUrl.split('/').first;

  /// Langue par défaut déclarée (vostfr / vf)
  String get defaultLang {
    final parts = relativeUrl.split('/');
    return parts.length > 1 ? parts[1] : (isScan ? 'vf' : 'vostfr');
  }
}

/// Groupe de saisons sous un même titre (« Anime », « Anime Version Kai »,
/// « Manga », « Autres »…).
class SeasonGroup {
  final String title;
  final String description; // ex. explication « Kai »
  final List<SeasonEntry> entries;
  const SeasonGroup({
    required this.title,
    required this.entries,
    this.description = '',
  });
}

/// Fiche complète d'une œuvre (/catalogue/{slug}/).
class AnimeDetails {
  final String slug;
  final String title;
  final String altTitles;
  final String banner;
  final String thumb;
  final String? trailerUrl; // embed YouTube
  final String synopsis;
  final List<String> genres;
  final Map<String, String> info; // État, Année, Épisodes/Chapitres, Studio
  final List<SeasonGroup> groups;
  final List<CatalogueItem> similar;

  const AnimeDetails({
    required this.slug,
    required this.title,
    required this.altTitles,
    required this.banner,
    required this.thumb,
    required this.trailerUrl,
    required this.synopsis,
    required this.genres,
    required this.info,
    required this.groups,
    required this.similar,
  });

  String get path => '/catalogue/$slug';
  List<SeasonEntry> get allSeasons => [for (final g in groups) ...g.entries];
}

/// Un lecteur (var epsN de episodes.js) : liste d'URLs d'embed, une par épisode.
class Player {
  final int index; // 1..8 (numéro affiché "Lecteur N")
  final List<String> urls;
  const Player({required this.index, required this.urls});

  String get host {
    if (urls.isEmpty) return '';
    final u = Uri.tryParse(urls.first);
    return u?.host.replaceFirst('www.', '') ?? '';
  }
}

/// Page épisodes complète (/catalogue/{slug}/{saison}/{lang}/ + episodes.js).
class EpisodePage {
  final String path; // chemin exact, sert de clé de progression
  final String slug;
  final String title; // #titreOeuvre
  final String seasonName; // $("#avOeuvre").html("…")
  final String banner; // #imgOeuvre
  final String lang; // dossier langue courant
  final List<String> episodeNames; // "Episode 1", "Le Film"…
  final List<Player> players; // déjà ordonnés comme sur le site (swap 1<->2)
  final String message; // #messagePage
  final List<String> availableLangs; // codes de langues disponibles

  const EpisodePage({
    required this.path,
    required this.slug,
    required this.title,
    required this.seasonName,
    required this.banner,
    required this.lang,
    required this.episodeNames,
    required this.players,
    required this.message,
    required this.availableLangs,
  });

  bool get hasEpisodes => players.isNotEmpty && episodeNames.isNotEmpty;
  int get episodeCount => episodeNames.length;

  String? urlFor(int playerIdx, int episodeIdx) {
    if (playerIdx < 0 || playerIdx >= players.length) return null;
    final list = players[playerIdx].urls;
    if (episodeIdx < 0 || episodeIdx >= list.length) return null;
    return list[episodeIdx];
  }
}

/// Page scans (/catalogue/{slug}/scan/{lang}/ + get_nb_chap_et_img.php).
class ScanPage {
  final String path;
  final String slug;
  final String title; // nom d'œuvre EXACT utilisé par l'API (#titreOeuvre)
  final String seasonName; // "Scans"
  final String banner;
  final String lang;
  final List<String> chapterNames; // "Chapitre 1"…
  final Map<int, int> pagesPerChapter; // n° chapitre réel → nb d'images
  final Map<int, int>? pagesPerChapterPP; // variante « page par page »
  final String message;
  final List<String> availableLangs;

  const ScanPage({
    required this.path,
    required this.slug,
    required this.title,
    required this.seasonName,
    required this.banner,
    required this.lang,
    required this.chapterNames,
    required this.pagesPerChapter,
    required this.pagesPerChapterPP,
    required this.message,
    required this.availableLangs,
  });

  bool get hasChapters => chapterNames.isNotEmpty;
}

/// Planning hebdomadaire.
class PlanningDay {
  final String name; // Lundi…
  final String date; // 31/08
  final bool isToday;
  final List<ReleaseItem> items;
  const PlanningDay({
    required this.name,
    required this.date,
    required this.isToday,
    required this.items,
  });
}

class PlanningData {
  final List<PlanningDay> days;
  final List<ReleaseItem> noFixedDay;
  const PlanningData({required this.days, required this.noFixedDay});
}

/// Entrée de liste (favoris / watchlist / vus) — 3 tableaux parallèles côté
/// site : nom / url / img.
class ListEntry {
  final String name;
  final String url; // /catalogue/{slug}/
  final String image;
  const ListEntry({required this.name, required this.url, required this.image});

  String get slug {
    final parts = url.split('/').where((p) => p.isNotEmpty).toList();
    final i = parts.indexOf('catalogue');
    return (i >= 0 && i + 1 < parts.length) ? parts[i + 1] : url;
  }
}

/// Entrée d'historique — tableaux histoNom/Url/Img/Type/Lang/Ep/Num.
class HistoryEntry {
  final String name;
  final String url; // /catalogue/{slug}/{saison}/{lang}/
  final String image;
  final String type; // nom de saison ("Saison 1", "Scans"…)
  final String lang; // VOSTFR, VF…
  final String episode; // "Episode 4" / "Chapitre 12"
  final int num; // index dans la liste
  const HistoryEntry({
    required this.name,
    required this.url,
    required this.image,
    required this.type,
    required this.lang,
    required this.episode,
    required this.num,
  });

  bool get isScan => url.contains('/scan') || url.contains('/s2/');

  String get slug {
    final parts = url.split('/').where((p) => p.isNotEmpty).toList();
    final i = parts.indexOf('catalogue');
    return (i >= 0 && i + 1 < parts.length) ? parts[i + 1] : url;
  }

  HistoryEntry copyWith({String? episode, int? num, String? type, String? lang}) =>
      HistoryEntry(
        name: name,
        url: url,
        image: image,
        type: type ?? this.type,
        lang: lang ?? this.lang,
        episode: episode ?? this.episode,
        num: num ?? this.num,
      );
}

/// Progression sauvegardée pour un chemin (savedEpName/savedEpNb).
class Progress {
  final String name;
  final int num;
  const Progress({required this.name, required this.num});
}

/// Filtres du catalogue (paramètres GET de /catalogue).
class CatalogueFilters {
  final String search;
  final Set<String> types;
  final Set<String> langs;
  final Set<String> status;
  final Set<String> genres;
  final int? yearMin;
  final int? yearMax;
  final int? episodesMin;
  final int? episodesMax;
  final int? chaptersMin;
  final int? chaptersMax;

  const CatalogueFilters({
    this.search = '',
    this.types = const {},
    this.langs = const {},
    this.status = const {},
    this.genres = const {},
    this.yearMin,
    this.yearMax,
    this.episodesMin,
    this.episodesMax,
    this.chaptersMin,
    this.chaptersMax,
  });

  int get activeCount =>
      types.length +
      langs.length +
      status.length +
      genres.length +
      (yearMin != null ? 1 : 0) +
      (yearMax != null ? 1 : 0) +
      (episodesMin != null ? 1 : 0) +
      (episodesMax != null ? 1 : 0) +
      (chaptersMin != null ? 1 : 0) +
      (chaptersMax != null ? 1 : 0);

  bool get isEmpty => activeCount == 0 && search.isEmpty;

  CatalogueFilters copyWith({
    String? search,
    Set<String>? types,
    Set<String>? langs,
    Set<String>? status,
    Set<String>? genres,
    int? yearMin,
    int? yearMax,
    int? episodesMin,
    int? episodesMax,
    int? chaptersMin,
    int? chaptersMax,
    bool clearNumbers = false,
  }) =>
      CatalogueFilters(
        search: search ?? this.search,
        types: types ?? this.types,
        langs: langs ?? this.langs,
        status: status ?? this.status,
        genres: genres ?? this.genres,
        yearMin: clearNumbers ? null : (yearMin ?? this.yearMin),
        yearMax: clearNumbers ? null : (yearMax ?? this.yearMax),
        episodesMin: clearNumbers ? null : (episodesMin ?? this.episodesMin),
        episodesMax: clearNumbers ? null : (episodesMax ?? this.episodesMax),
        chaptersMin: clearNumbers ? null : (chaptersMin ?? this.chaptersMin),
        chaptersMax: clearNumbers ? null : (chaptersMax ?? this.chaptersMax),
      );

  /// Construit la query string exactement comme le formulaire du site
  /// (tableaux PHP `type[]=`).
  Map<String, List<String>> toQuery(int page) {
    final q = <String, List<String>>{};
    if (search.isNotEmpty) q['search'] = [search];
    if (types.isNotEmpty) q['type[]'] = types.toList();
    if (langs.isNotEmpty) q['langue[]'] = langs.toList();
    if (status.isNotEmpty) q['current[]'] = status.toList();
    if (genres.isNotEmpty) q['genre[]'] = genres.toList();
    if (yearMin != null) q['annee_min'] = ['$yearMin'];
    if (yearMax != null) q['annee_max'] = ['$yearMax'];
    if (episodesMin != null) q['episodes_min'] = ['$episodesMin'];
    if (episodesMax != null) q['episodes_max'] = ['$episodesMax'];
    if (chaptersMin != null) q['chapitres_min'] = ['$chaptersMin'];
    if (chaptersMax != null) q['chapitres_max'] = ['$chaptersMax'];
    q['page'] = ['$page'];
    return q;
  }
}

class CataloguePage {
  final List<CatalogueItem> items;
  final int page;
  final int totalPages;
  const CataloguePage({
    required this.items,
    required this.page,
    required this.totalPages,
  });
}

/// Données renvoyées par /api/get-data.php lorsqu'on est connecté.
class ServerData {
  final bool loggedIn;
  final bool needMerge;
  final Map<String, Progress> progress;
  final List<ListEntry> favorites;
  final List<ListEntry> watchlist;
  final List<ListEntry> viewed;
  final List<HistoryEntry> history;

  const ServerData({
    required this.loggedIn,
    this.needMerge = false,
    this.progress = const {},
    this.favorites = const [],
    this.watchlist = const [],
    this.viewed = const [],
    this.history = const [],
  });
}
