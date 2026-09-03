// Tests unitaires HORS LIGNE des parseurs (fixtures embarquées).
//
// Complément de parsers_live_test.dart (qui, lui, interroge le site réel) :
// ceux-ci doivent toujours passer, même sans réseau, dans `flutter test`.
import 'package:flutter_test/flutter_test.dart';

import 'package:animeworld/data/parsers/episodes_parser.dart';
import 'package:animeworld/data/parsers/html_parsers.dart';

// ---------------------------------------------------------------------------
// EpisodesParser — episodes.js
// ---------------------------------------------------------------------------

void main() {
  group('EpisodesParser.parsePlayers', () {
    test('extrait les lecteurs eps1..epsN avec le swap 1<->2 du site', () {
      const js = '''
var eps1 = ["https://sibnet.ru/embed1e1", "https://sibnet.ru/embed1e2"];
var eps2 = ["https://uqload.is/e1.html", "https://uqload.is/e2.html", "https://uqload.is/e3.html"];
var eps3 = ["https://vidmoly.to/e1.html"];
''';
      final players = EpisodesParser.parsePlayers(js);
      expect(players, hasLength(3));
      // swapLecteurs() : eps1 <-> eps2 → « Lecteur 1 » = ancien eps2.
      expect(players[0].index, 1);
      expect(players[0].urls, hasLength(3));
      expect(players[0].host, 'uqload.is');
      expect(players[1].urls, hasLength(2));
      // videos.js réécrit vidmoly.to/.net → vidmoly.biz.
      expect(players[2].urls.first, 'https://vidmoly.biz/e1.html');
    });

    test('ignore les blocs commentés et réécrit vidmoly comme le site', () {
      const js = '''
//var eps1 = ["https://spam.example/e1"];
var eps1 = ["//vidmoly.net/e1.html", "//vidmoly.to/e2.html"];
''';
      final players = EpisodesParser.parsePlayers(js);
      expect(players, hasLength(1));
      expect(players.first.urls[0], 'https://vidmoly.biz/e1.html');
      expect(players.first.urls[1], 'https://vidmoly.biz/e2.html');
    });

    test('vide si aucun lecteur (page sans épisodes)', () {
      expect(EpisodesParser.parsePlayers('var rien = 1;'), isEmpty);
    });

    test('episodeCount = max des listes', () {
      const js = 'var eps1 = ["a", "b"]; var eps2 = ["c"];';
      final count =
          EpisodesParser.episodeCount(EpisodesParser.parsePlayers(js));
      expect(count, 2);
    });
  });

  group('EpisodesParser.buildLabels', () {
    test('script par défaut : Episode 1..N', () {
      final labels = EpisodesParser.buildLabels(
        total: 5,
        scripts: ['\$(document).ready(function(){resetListe();finirListe(1);});'],
        unit: 'Episode',
      );
      expect(labels, List.generate(5, (i) => 'Episode ${i + 1}'));
    });

    test('numérotation custom (creerListe + finirListe avec début)', () {
      final labels = EpisodesParser.buildLabels(
        total: 14,
        scripts: ['''
function creerListe(a, b){ for(var i = a; i <= b; i++){ addItem(i); } }
function finirListe(debut){ /* … */ }
resetListe();
creerListe(1, 10);
finirListe(11);
'''],
        unit: 'Episode',
      );
      expect(labels, hasLength(14));
      expect(labels.first, 'Episode 1');
      expect(labels[10], 'Episode 11');
    });

    test('One Piece : offset épisodes spéciaux (finirListeOP)', () {
      final labels = EpisodesParser.buildLabels(
        total: 13,
        scripts: ['''
function finirListeOP(debut){ return 1080 + (tailleEpisodes - epRetards); }
resetListe();
newSP("1089");
newSP("1090");
finirListeOP(1091);
'''],
        unit: 'Episode',
      );
      // newSP préfixe l'unité (« Episode 1089 ») ; finirListeOP(1091) complète
      // jusqu'à 1080 + (13 - 2) = 1091.
      expect(labels, hasLength(3));
      expect(labels[0], 'Episode 1089');
      expect(labels[1], 'Episode 1090');
      expect(labels.last, 'Episode 1091');
    });

    test('jamais plus de libellés que d\'entrées réelles', () {
      final labels = EpisodesParser.buildLabels(
        total: 3,
        scripts: ['creerListe(1, 50);'],
        unit: 'Episode',
      );
      expect(labels, hasLength(3));
    });
  });

  // -------------------------------------------------------------------------
  // HtmlParsers — cartes de sorties (base des notifications)
  // -------------------------------------------------------------------------

  const episodeCard = '''
<div class="anime-card-premium" data-release-ts="1788000000">
  <a href="https://anime-sama.to/catalogue/kaiju-no-8/saison2/vostfr/">
    <img class="card-image" src="https://cdn.jsdelivr.net/gh/Anime-Sama/IMG@img/contenu/kaiju-no-8.jpg">
    <h3 class="card-title">Kaiju No. 8</h3>
    <span class="badge-text">Anime</span>
    <div class="info-item episode">Saison 2 Episode 9</div>
    <div class="info-item release-time">02/09/2026 20:10</div>
    <img class="flag-icon" src="https://cdn.jsdelivr.net/gh/Anime-Sama/IMG@img/autres/flag_jp.png" alt="VOSTFR">
  </a>
</div>''';

  const scanCard = '''
<div class="scan-card-premium" data-release-ts="1788000100">
  <a href="https://anime-sama.to/catalogue/one-piece/scan/vf/">
    <img class="card-image" src="https://cdn.jsdelivr.net/gh/Anime-Sama/IMG@img/contenu/one-piece.jpg">
    <h3 class="card-title">One Piece</h3>
    <span class="badge-text">Scans</span>
    <div class="info-item episode">Chapitre 1157</div>
    <div class="info-item release-time">02/09/2026 21:00</div>
    <img class="flag-icon" src="https://cdn.jsdelivr.net/gh/Anime-Sama/IMG@img/autres/flag_fr.png" alt="VF">
  </a>
</div>''';

  group('HtmlParsers.parseHome (fixtures)', () {
    // L'id du conteneur « sorties du jour » suit new Date().getDay().
    final jsDay = DateTime.now().weekday % 7;
    final html = '''
<html><body>
<div id="containerAjoutsAnimes">$episodeCard</div>
<div id="containerAjoutsScans">$scanCard</div>
<div class="fadeJours" id="$jsDay">
  <div class="titreJours">Sorties du Mercredi - 02/09</div>
  $episodeCard
</div>
</body></html>''';

    final home = HtmlParsers.parseHome(html);

    test('derniers épisodes', () {
      expect(home.latestEpisodes, hasLength(1));
      final ep = home.latestEpisodes.first;
      expect(ep.slug, 'kaiju-no-8');
      expect(ep.title, 'Kaiju No. 8');
      expect(ep.path, '/catalogue/kaiju-no-8/saison2/vostfr/');
      expect(ep.lang, 'VOSTFR');
      expect(ep.info, 'Saison 2 Episode 9');
      expect(ep.time, '02/09/2026 20:10');
      expect(ep.releaseTs, 1788000000);
      expect(ep.isScan, isFalse);
    });

    test('derniers scans', () {
      expect(home.latestScans, hasLength(1));
      final sc = home.latestScans.first;
      expect(sc.slug, 'one-piece');
      expect(sc.info, 'Chapitre 1157');
      expect(sc.lang, 'VF');
      expect(sc.isScan, isTrue);
    });

    test('sorties du jour', () {
      expect(home.todayLabel, contains('Mercredi'));
      expect(home.todayReleases, hasLength(1));
    });
  });

  group('HtmlParsers.parseContentPageInfo (fixtures)', () {
    test('extrait titre, bannière et fichier episodes.js', () {
      final info = HtmlParsers.parseContentPageInfo('''
<html><head>
<script src="https://anime-sama.to/catalogue/x/saison1/vostfr/episodes.js"></script>
</head><body>
<h2 id="titreOeuvre">Kaiju No. 8</h2>
<img id="imgOeuvre" src="https://cdn.jsdelivr.net/gh/Anime-Sama/IMG@img/contenu/kaiju-no-8.jpg">
<div id="messagePage"></div>
<script>
\$("#avOeuvre").html("Saison 2");
\$(document).ready(function(){resetListe();finirListe(1);});
</script>
</body></html>''');
      expect(info.rawTitle, 'Kaiju No. 8');
      expect(info.banner, contains('kaiju-no-8.jpg'));
      expect(info.episodesJsFile, contains('episodes.js'));
      expect(info.seasonName, 'Saison 2');
      expect(info.inlineScripts, isNotEmpty);
    });
  });
}
