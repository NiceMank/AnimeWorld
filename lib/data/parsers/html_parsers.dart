import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../../core/constants/app_constants.dart';
import '../models/models.dart';

/// Parseurs HTML des pages du site. Les sélecteurs proviennent de l'analyse
/// du DOM réel (docs/ANALYSE_ANIME_SAMA.md).
class HtmlParsers {
  HtmlParsers._();

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static String _txt(Element? e) =>
      (e?.text ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

  static String _attr(Element? e, String name) => (e?.attributes[name] ?? '').trim();

  /// Extrait le slug d'un href de type /catalogue/{slug}/… (absolu ou relatif).
  static String slugFromHref(String href) {
    final m = RegExp(r'/catalogue/([^/?#]+)').firstMatch(href);
    return m?.group(1) ?? '';
  }

  /// Normalise un href vers un chemin relatif au domaine (/catalogue/...).
  static String pathFromHref(String href) {
    var h = href.trim();
    if (h.startsWith('http')) {
      final u = Uri.tryParse(h);
      if (u != null) h = u.path;
    }
    if (!h.startsWith('/')) h = '/$h';
    return h;
  }

  static String _flagCode(String src) {
    final m = RegExp(r'flag_(\w+)\.png').firstMatch(src);
    return m?.group(1) ?? '';
  }

  static String _fixImage(String src, String slug) {
    if (src.isEmpty && slug.isNotEmpty) return AppConstants.thumb(slug);
    return src;
  }

  // ---------------------------------------------------------------------------
  // Cartes
  // ---------------------------------------------------------------------------

  /// `.catalog-card`
  static CatalogueItem? parseCatalogueCard(Element card) {
    final a = card.querySelector('a');
    if (a == null) return null;
    final href = _attr(a, 'href');
    final slug = slugFromHref(href);
    if (slug.isEmpty) return null;
    final title = _txt(card.querySelector('.card-title'));
    final alt = _txt(card.querySelector('.alternate-titles'));
    final genres = card
        .querySelectorAll('.genre-tag')
        .map(_txt)
        .where((g) => g.isNotEmpty && g != '…')
        .toList();
    final types = _txt(card.querySelector('.type-row .info-value'))
        .split(',')
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toList();
    final langs = card
        .querySelectorAll('.lang-flag')
        .map((e) => _attr(e, 'title'))
        .where((t) => t.isNotEmpty)
        .toList();
    final synopsis = _txt(card.querySelector('.synopsis-content'));
    return CatalogueItem(
      slug: slug,
      title: title,
      altTitles: alt.isEmpty
          ? const []
          : alt.split(',').map((t) => t.trim()).where((t) => t.isNotEmpty).toList(),
      image: _fixImage(_attr(card.querySelector('img.card-image'), 'src'), slug),
      genres: genres,
      types: types,
      langs: langs,
      synopsis: synopsis,
    );
  }

  /// `.anime-card-premium` / `.scan-card-premium` (ajouts récents + planning)
  static ReleaseItem? parseReleaseCard(Element card) {
    final a = card.querySelector('a');
    if (a == null) return null;
    final href = _attr(a, 'href');
    final slug = slugFromHref(href);
    if (slug.isEmpty) return null;
    final flag = card.querySelector('.flag-icon');
    final lang = _attr(flag, 'alt').isNotEmpty
        ? _attr(flag, 'alt')
        : _attr(flag, 'title');
    final infos = card.querySelectorAll('.info-item');
    String info = '';
    String time = '';
    for (final it in infos) {
      final cls = it.className;
      final t = _txt(it);
      if (cls.contains('release-time') || cls.contains('planning-time')) {
        time = t;
      } else if (t.isNotEmpty) {
        // Sur le planning, l'heure "15h00" est dans .info-item.episode avec
        // font-bold : on la détecte par le format.
        if (RegExp(r'^\d{1,2}h\d{2}$').hasMatch(t) && time.isEmpty) {
          time = t;
        } else if (info.isEmpty) {
          info = t;
        }
      }
    }
    // Fallback : .time-text / .info-text
    if (time.isEmpty) time = _txt(card.querySelector('.time-text'));
    if (info.isEmpty) info = _txt(card.querySelector('.info-text'));

    final ts = int.tryParse(_attr(card, 'data-release-ts'));
    return ReleaseItem(
      path: pathFromHref(href),
      slug: slug,
      title: _txt(card.querySelector('.card-title')),
      image: _fixImage(_attr(card.querySelector('img.card-image'), 'src'), slug),
      badge: _txt(card.querySelector('.badge-text')),
      lang: lang,
      info: info,
      time: time,
      problem: card.className.contains('planning-problem-red'),
      releaseTs: ts,
    );
  }

  static List<CatalogueItem> _catalogueCards(Element? container) {
    if (container == null) return const [];
    return container
        .querySelectorAll('.catalog-card')
        .map(parseCatalogueCard)
        .whereType<CatalogueItem>()
        .toList();
  }

  static List<ReleaseItem> _releaseCards(Element? container) {
    if (container == null) return const [];
    return container
        .querySelectorAll('.anime-card-premium, .scan-card-premium')
        .map(parseReleaseCard)
        .whereType<ReleaseItem>()
        .toList();
  }

  // ---------------------------------------------------------------------------
  // Accueil
  // ---------------------------------------------------------------------------

  static HomeData parseHome(String htmlSrc) {
    final doc = html_parser.parse(htmlSrc);

    // Carrousel
    final slides = <HeroSlide>[];
    final seen = <String>{};
    for (final s in doc.querySelectorAll('#akTrack .ak-slide')) {
      final ctas = <HeroCta>[];
      for (final a in s.querySelectorAll('.ak-slide-cta')) {
        final href = _attr(a, 'href');
        final img = a.querySelector('img');
        ctas.add(HeroCta(
          label: _attr(img, 'alt').isNotEmpty
              ? _attr(img, 'alt')
              : _txt(a).replaceFirst('Visionner en', '').trim(),
          flag: _flagCode(_attr(img, 'src')),
          path: pathFromHref(href),
        ));
      }
      final slug = ctas.isNotEmpty
          ? slugFromHref(ctas.first.path)
          : slugFromHref(_attr(s.querySelector('a'), 'href'));
      if (slug.isEmpty || seen.contains(slug)) continue; // clones du carrousel
      seen.add(slug);
      slides.add(HeroSlide(
        slug: slug,
        title: _txt(s.querySelector('.ak-slide-title')),
        badge: _txt(s.querySelector('.ak-badge')),
        banner: _attr(s.querySelector('.ak-slide-bg img'), 'src').isNotEmpty
            ? _attr(s.querySelector('.ak-slide-bg img'), 'src')
            : AppConstants.banner(slug),
        genres: s.querySelectorAll('.ak-genre-tag').map(_txt).toList(),
        synopsis: _txt(s.querySelector('.ak-slide-synopsis')),
        ctas: ctas,
      ));
    }

    // Sorties du jour : les 7 conteneurs (id 0..6, 0 = dimanche) sont tous
    // masqués côté serveur ; le JS du site affiche celui de `new Date().getDay()`.
    // ⚠️ `getElementById('0')` du package html renvoie la racine pour les ids
    // numériques : on itère donc explicitement sur `div.fadeJours`.
    String todayLabel = '';
    var today = <ReleaseItem>[];
    final idx = DateTime.now().weekday % 7; // Dart : lundi=1..dimanche=7 → JS 0..6
    for (final day in doc.querySelectorAll('div.fadeJours')) {
      if (day.id != '$idx') continue;
      todayLabel = _txt(day.querySelector('.titreJours'));
      today = _releaseCards(day);
      break;
    }

    return HomeData(
      slides: slides,
      latestEpisodes: _releaseCards(doc.getElementById('containerAjoutsAnimes')),
      latestScans: _releaseCards(doc.getElementById('containerAjoutsScans')),
      latestContent: _catalogueCards(doc.getElementById('containerSorties')),
      classics: _catalogueCards(doc.getElementById('containerClassiques')),
      gems: _catalogueCards(doc.getElementById('containerPepites')),
      todayLabel: todayLabel,
      todayReleases: today,
    );
  }

  // ---------------------------------------------------------------------------
  // Catalogue & recherche
  // ---------------------------------------------------------------------------

  static CataloguePage parseCatalogue(String htmlSrc, int page) {
    final doc = html_parser.parse(htmlSrc);
    final items = doc
        .querySelectorAll('.catalog-card')
        .map(parseCatalogueCard)
        .whereType<CatalogueItem>()
        .toList();
    var total = 1;
    for (final a in doc.querySelectorAll('#list_pagination a')) {
      final m = RegExp(r'page=(\d+)').firstMatch(_attr(a, 'href'));
      if (m != null) {
        final n = int.parse(m.group(1)!);
        if (n > total) total = n;
      }
    }
    if (items.isEmpty && page == 1) total = 0;
    return CataloguePage(items: items, page: page, totalPages: total);
  }

  static List<SearchResult> parseSearch(String fragment) {
    final doc = html_parser.parseFragment(fragment);
    final out = <SearchResult>[];
    for (final a in doc.querySelectorAll('a.asn-search-result')) {
      final slug = slugFromHref(_attr(a, 'href'));
      if (slug.isEmpty) continue;
      out.add(SearchResult(
        slug: slug,
        title: _txt(a.querySelector('.asn-search-result-title')),
        subtitle: _txt(a.querySelector('.asn-search-result-subtitle')),
        image: _fixImage(_attr(a.querySelector('img'), 'src'), slug),
      ));
    }
    return out;
  }

  // ---------------------------------------------------------------------------
  // Fiche œuvre
  // ---------------------------------------------------------------------------

  static final _panneauRe = RegExp(
    r'''panneau(Anime|Scan)\(\s*["']([^"']*)["']\s*,\s*["']([^"']*)["']\s*\)''',
  );

  static AnimeDetails parseDetails(String htmlSrc, String slug) {
    final doc = html_parser.parse(htmlSrc);

    final title = _txt(doc.querySelector('h1')).isNotEmpty
        ? _txt(doc.querySelector('h1'))
        : _txt(doc.querySelector('title')).split('|').first.trim();
    final alt = _txt(doc.getElementById('titreAlter'));
    final banner = _attr(
      doc.querySelector('meta[property="og:image"]'),
      'content',
    );
    final trailer = _attr(doc.getElementById('bandeannonce'), 'src');
    final synopsis = _txt(doc.getElementById('synopsisText'));
    final genres = doc
        .querySelectorAll('.genres-wrap .genre-pill')
        .map(_txt)
        .where((g) => g.isNotEmpty)
        .toList();

    // Info card : suite de .info-lbl / .info-val
    final info = <String, String>{};
    final grid = doc.querySelector('.info-grid');
    if (grid != null) {
      String? currentLabel;
      for (final child in grid.children) {
        if (child.className.contains('info-lbl')) {
          currentLabel = _txt(child);
        } else if (child.className.contains('info-val') && currentLabel != null) {
          var v = _txt(child).replaceAll(RegExp(r'\s*Voir plus$'), '');
          info[currentLabel] = v;
          currentLabel = null;
        }
      }
    }

    // Groupes de saisons : chaque <h2> de section est suivi d'un <div>
    // contenant un <script> avec des appels panneauAnime/panneauScan.
    final groups = <SeasonGroup>[];
    for (final h2 in doc.querySelectorAll('h2')) {
      final cls = h2.className;
      if (!cls.contains('border-b-2') || !cls.contains('mt-5')) continue;
      final groupTitle = _txt(h2);
      // Le conteneur suivant (parfois précédé d'un <p> explicatif, ex. « Kai »)
      Element? next = h2.nextElementSibling;
      String description = '';
      var hops = 0;
      while (next != null && next.localName != 'h2' && hops < 4) {
        if (next.localName == 'p') description = _txt(next);
        if (next.querySelector('script') != null) break;
        next = next.nextElementSibling;
        hops++;
      }
      if (next == null || next.localName == 'h2') continue;
      final script = next.querySelector('script')?.text ?? '';
      final entries = <SeasonEntry>[];
      for (final m in _panneauRe.allMatches(script)) {
        final name = m.group(2)!.trim();
        final url = m.group(3)!.trim();
        if (name == 'nom' || url == 'url') continue; // le commentaire d'exemple
        entries.add(SeasonEntry(
          name: name,
          relativeUrl: url.replaceAll(RegExp(r'^/+|/+$'), ''),
          isScan: m.group(1) == 'Scan',
        ));
      }
      if (entries.isNotEmpty) {
        groups.add(SeasonGroup(
          title: groupTitle,
          entries: entries,
          description: description,
        ));
      }
    }

    final similar = _catalogueCards(doc.getElementById('containerSimilaires'));

    return AnimeDetails(
      slug: slug,
      title: title,
      altTitles: alt,
      banner: banner.isNotEmpty ? banner : AppConstants.banner(slug),
      thumb: AppConstants.thumb(slug),
      trailerUrl: trailer.isNotEmpty ? trailer : null,
      synopsis: synopsis,
      genres: genres,
      info: info,
      groups: groups,
      similar: similar,
    );
  }

  // ---------------------------------------------------------------------------
  // Page épisodes / scans : infos communes
  // ---------------------------------------------------------------------------

  static final _avOeuvreRe =
      RegExp(r'''\$\(\s*["']#avOeuvre["']\s*\)\.html\(\s*["']([^"']*)["']\s*\)''');

  /// Extrait titre, bannière, nom de saison, message et script de liste
  /// custom d'une page épisodes ou scans.
  static ContentPageInfo parseContentPageInfo(String htmlSrc) {
    final doc = html_parser.parse(htmlSrc);
    final title = doc.getElementById('titreOeuvre')?.text ?? '';
    final banner = _attr(doc.getElementById('imgOeuvre'), 'src');
    final message = _txt(doc.getElementById('messagePage'));

    String seasonName = '';
    final scripts = doc.querySelectorAll('script');
    final inlineScripts = <String>[];
    for (final s in scripts) {
      if (_attr(s, 'src').isNotEmpty) continue;
      final t = s.text;
      inlineScripts.add(t);
      final m = _avOeuvreRe.firstMatch(t);
      if (m != null && m.group(1)!.isNotEmpty) seasonName = m.group(1)!;
    }

    // filever de episodes.js
    String? episodesJs;
    final m = RegExp(r'''episodes\.js\?filever=(\d+)''').firstMatch(htmlSrc);
    if (m != null) episodesJs = 'episodes.js?filever=${m.group(1)}';

    // Le titre brut est conservé tel quel (espaces compris) car il sert de
    // clé exacte à l'API des scans ("Black Torch  ").
    return ContentPageInfo(
      rawTitle: title,
      banner: banner,
      seasonName: seasonName,
      message: message,
      inlineScripts: inlineScripts,
      episodesJsFile: episodesJs ?? 'episodes.js',
      is404: doc.querySelector('title')?.text.contains('404') == true,
    );
  }

  // ---------------------------------------------------------------------------
  // Planning
  // ---------------------------------------------------------------------------

  static PlanningData parsePlanning(String htmlSrc) {
    final doc = html_parser.parse(htmlSrc);
    final days = <PlanningDay>[];
    final track = doc.getElementById('planningClass');
    if (track != null) {
      for (final col in track.children) {
        final name = _txt(col.querySelector('.titreJours'));
        if (name.isEmpty) continue;
        final date = _txt(col.querySelector('p'));
        // Le jour courant porte la classe de surbrillance `bg-sky-900`
        // (toutes les colonnes ont `selectedRow`).
        days.add(PlanningDay(
          name: name,
          date: date,
          isToday: col.className.contains('bg-sky-900'),
          items: _releaseCards(col),
        ));
      }
    }
    // « Œuvres en cours sans jours fixes » : la liste horizontale qui suit le h2
    var noFixed = <ReleaseItem>[];
    for (final h2 in doc.querySelectorAll('h2')) {
      if (_txt(h2).toLowerCase().contains('sans jours fixes')) {
        noFixed = _releaseCards(h2.nextElementSibling);
        break;
      }
    }
    return PlanningData(days: days, noFixedDay: noFixed);
  }
}

/// Infos brutes d'une page épisodes/scans.
class ContentPageInfo {
  final String rawTitle;
  final String banner;
  final String seasonName;
  final String message;
  final List<String> inlineScripts;
  final String episodesJsFile;
  final bool is404;
  const ContentPageInfo({
    required this.rawTitle,
    required this.banner,
    required this.seasonName,
    required this.message,
    required this.inlineScripts,
    required this.episodesJsFile,
    required this.is404,
  });

  String get title => rawTitle.replaceAll(RegExp(r'\s+'), ' ').trim();
}
