// Tests d'intégration des parseurs contre les pages HTML réelles du site,
// sauvegardées dans /home/user/analysis (ou téléchargées à la volée).
//
// Lancer :  dart test/parsers_live_test.dart
import 'dart:convert';
import 'dart:io';

import 'package:animeworld/data/parsers/episodes_parser.dart';
import 'package:animeworld/data/parsers/html_parsers.dart';

int _fail = 0;
void check(bool cond, String label, [Object? detail]) {
  if (cond) {
    stdout.writeln('  ✓ $label');
  } else {
    _fail++;
    stdout.writeln('  ✗ $label ${detail ?? ''}');
  }
}

Future<String> fetch(String url) async {
  final c = HttpClient();
  final r = await c.getUrl(Uri.parse(url));
  r.headers.set('User-Agent', 'Mozilla/5.0 (Linux; Android 13; Pixel 7)');
  final resp = await r.close();
  final body = await resp.transform(utf8.decoder).join();
  c.close();
  return body;
}

Future<String> load(String file, String url) async {
  final f = File('/home/user/analysis/$file');
  if (await f.exists()) return f.readAsString();
  return fetch(url);
}

Future<void> main() async {
  const base = 'https://anime-sama.to';

  stdout.writeln('▶ Accueil');
  final home = HtmlParsers.parseHome(await load('home.html', '$base/'));
  check(home.slides.length >= 5, 'slides carrousel (${home.slides.length})');
  check(home.slides.first.ctas.isNotEmpty, 'CTA du 1er slide: ${home.slides.first.ctas.map((c) => '${c.label}→${c.path}').join(', ')}');
  check(home.latestEpisodes.length >= 5, 'derniers épisodes (${home.latestEpisodes.length})');
  final ep = home.latestEpisodes.first;
  check(ep.info.contains('Episode') || ep.info.contains('Saison'), 'info épisode "${ep.info}" · ${ep.time} · ${ep.lang} · ${ep.badge}');
  check(home.latestScans.length >= 5, 'derniers scans (${home.latestScans.length}) ex: ${home.latestScans.first.title} / ${home.latestScans.first.info}');
  check(home.latestContent.isNotEmpty, 'derniers contenus (${home.latestContent.length})');
  check(home.classics.isNotEmpty, 'classiques (${home.classics.length}) ex: ${home.classics.first.title} ${home.classics.first.types} ${home.classics.first.langs}');
  check(home.gems.isNotEmpty, 'pépites (${home.gems.length})');
  const jours = ['Dimanche', 'Lundi', 'Mardi', 'Mercredi', 'Jeudi', 'Vendredi', 'Samedi'];
  final expectedDay = jours[DateTime.now().weekday % 7];
  check(home.todayReleases.isNotEmpty && home.todayLabel.contains(expectedDay), 'sorties du jour "${home.todayLabel}" (${home.todayReleases.length}) ex: ${home.todayReleases.first.title} ${home.todayReleases.first.time} ${home.todayReleases.first.info}');

  stdout.writeln('▶ Catalogue');
  final cat = HtmlParsers.parseCatalogue(await load('catalogue.html', '$base/catalogue'), 1);
  check(cat.items.length == 48, '48 cartes (${cat.items.length})');
  check(cat.totalPages >= 40, 'pages totales (${cat.totalPages})');
  final c0 = cat.items.first;
  check(c0.slug.isNotEmpty && c0.genres.isNotEmpty && c0.synopsis.isNotEmpty, 'carte: ${c0.slug} | ${c0.title} | ${c0.genres.take(3)} | ${c0.types} | ${c0.langs}');

  stdout.writeln('▶ Recherche');
  final s = HtmlParsers.parseSearch(await fetchPost('$base/template-php/defaut/fetch.php', 'query=naruto'));
  check(s.length >= 3, 'résultats (${s.length}) ex: ${s.first.slug} / ${s.first.title}');

  stdout.writeln('▶ Fiche Black Torch');
  final d = HtmlParsers.parseDetails(await load('anime_page.html', '$base/catalogue/black-torch/'), 'black-torch');
  check(d.title.toLowerCase().contains('black torch'), 'titre "${d.title}"');
  check(d.synopsis.length > 50, 'synopsis');
  check(d.genres.contains('Action'), 'genres ${d.genres}');
  check(d.info['État'] == 'En cours' && d.info['Année'] == '2026', 'info ${d.info}');
  check(d.groups.length == 2, 'groupes ${d.groups.map((g) => '${g.title}:${g.entries.map((e) => '${e.name}@${e.relativeUrl}').toList()}').toList()}');
  check(d.trailerUrl != null && d.trailerUrl!.contains('youtube'), 'trailer ${d.trailerUrl}');
  check(d.similar.isNotEmpty, 'similaires (${d.similar.length})');

  stdout.writeln('▶ Fiche One Piece (saisons complexes)');
  final op = HtmlParsers.parseDetails(await fetch('$base/catalogue/one-piece/'), 'one-piece');
  final names = op.allSeasons.map((e) => e.name).toList();
  check(names.contains('Films') && names.any((n) => n.startsWith('Kai')) && names.any((n) => n.startsWith('Scan')) && op.groups.length == 3, 'saisons (${names.length}) : ${names.take(6)} … groupes=${op.groups.map((g) => g.title)}');

  stdout.writeln('▶ episodes.js Black Torch (swap + lecteurs)');
  final js = await load('episodes_black_torch.js', '$base/catalogue/black-torch/saison1/vostfr/episodes.js');
  final players = EpisodesParser.parsePlayers(js);
  check(players.length == 5, '5 lecteurs (${players.length})');
  check(players.first.urls.first.contains('ansembed'), 'Lecteur 1 = eps2 après swap (${players.first.host})');
  check(players[1].host.contains('embed4me'), 'Lecteur 2 = eps1 (${players[1].host})');
  check(EpisodesParser.episodeCount(players) == 9, '9 épisodes');
  final page = HtmlParsers.parseContentPageInfo(await load('episode_page.html', '$base/catalogue/black-torch/saison1/vostfr/'));
  check(page.title == 'Black Torch' && page.rawTitle == 'Black Torch  ', 'titre "${page.title}" brut="${page.rawTitle}"');
  check(page.seasonName == 'Saison 1', 'nom saison "${page.seasonName}"');
  check(page.episodesJsFile.startsWith('episodes.js?filever='), page.episodesJsFile);
  final labels = EpisodesParser.buildLabels(total: 9, scripts: page.inlineScripts, unit: 'Episode');
  check(labels.length == 9 && labels.first == 'Episode 1' && labels.last == 'Episode 9', 'labels $labels');

  stdout.writeln('▶ One Piece films (newSPF)');
  final filmHtml = await fetch('$base/catalogue/one-piece/film/vostfr/');
  final filmInfo = HtmlParsers.parseContentPageInfo(filmHtml);
  final filmJs = await fetch('$base/catalogue/one-piece/film/vostfr/${filmInfo.episodesJsFile}');
  final filmPlayers = EpisodesParser.parsePlayers(filmJs);
  final filmTotal = EpisodesParser.episodeCount(filmPlayers);
  final filmLabels = EpisodesParser.buildLabels(total: filmTotal, scripts: filmInfo.inlineScripts, unit: 'Episode');
  check(filmInfo.seasonName == 'Film', 'saison "${filmInfo.seasonName}"');
  check(filmLabels.first == 'Le Film' && filmLabels.contains('Strong World') && filmLabels.contains('RED'), 'labels films (${filmLabels.length}/$filmTotal): ${filmLabels.take(4)} … ${filmLabels.skip(filmLabels.length - 2)}');

  stdout.writeln('▶ One Piece Egghead (creerListe + newSPF + finirListeOP offset)');
  final egHtml = await fetch('$base/catalogue/one-piece/saison11/vostfr/');
  final egInfo = HtmlParsers.parseContentPageInfo(egHtml);
  final egJs = await fetch('$base/catalogue/one-piece/saison11/vostfr/${egInfo.episodesJsFile}');
  final egPlayers = EpisodesParser.parsePlayers(egJs);
  final egTotal = EpisodesParser.episodeCount(egPlayers);
  final egLabels = EpisodesParser.buildLabels(total: egTotal, scripts: egInfo.inlineScripts, unit: 'Episode');
  check(egLabels.first == 'Episode 1089', 'premier label ${egLabels.first}');
  check(egLabels.contains('EggHead SP 1') && egLabels[4] == 'EggHead SP 1', 'spéciaux insérés (idx4=${egLabels[4]})');
  check(egLabels.length == egTotal, 'nb labels == nb épisodes (${egLabels.length} vs $egTotal), dernier=${egLabels.last}');

  stdout.writeln('▶ Scans (API JSON)');
  final scanHtml = await load('scan_page.html', '$base/catalogue/black-torch/scan/vf/');
  final scanInfo = HtmlParsers.parseContentPageInfo(scanHtml);
  final api = await fetch('$base/s2/scans/get_nb_chap_et_img.php?oeuvre=${Uri.encodeComponent(scanInfo.rawTitle)}');
  final chapters = jsonDecode(api) as Map;
  check(!chapters.containsKey('error') && chapters.isNotEmpty, 'chapitres Black Torch via titre brut "${scanInfo.rawTitle}" → ${chapters.length} chapitres');
  final scanLabels = EpisodesParser.buildLabels(total: chapters.length, scripts: scanInfo.inlineScripts, unit: 'Chapitre');
  // Black Torch déclare ses chapitres via newSPF("Volume N") → labels custom
  check(scanLabels.length == chapters.length && (scanLabels.first == 'Chapitre 1' || scanLabels.first.startsWith('Volume')), 'labels custom $scanLabels');
  final opScanHtml = await fetch('$base/catalogue/one-piece/scan/vf/');
  final opScanInfo = HtmlParsers.parseContentPageInfo(opScanHtml);
  final opApi = jsonDecode(await fetch('$base/s2/scans/get_nb_chap_et_img.php?oeuvre=${Uri.encodeComponent(opScanInfo.rawTitle)}')) as Map;
  final opLabels = EpisodesParser.buildLabels(total: opApi.length, scripts: opScanInfo.inlineScripts, unit: 'Chapitre');
  check(opApi.length > 1000 && opLabels.first == 'Chapitre 1' && opLabels.length == opApi.length, 'One Piece "${opScanInfo.rawTitle}" → ${opApi.length} chapitres, labels ${opLabels.take(2)}…${opLabels.last}');

  stdout.writeln('▶ Planning');
  final pl = HtmlParsers.parsePlanning(await load('planning.html', '$base/planning'));
  check(pl.days.length == 7 && pl.days.where((d) => d.isToday).length == 1, '7 jours + 1 jour courant (${pl.days.map((d) => '${d.name} ${d.date}${d.isToday ? '*' : ''}').join(', ')})');
  final anyDay = pl.days.firstWhere((d) => d.items.isNotEmpty);
  final it = anyDay.items.first;
  check(it.time.contains('h') && it.title.isNotEmpty, '${anyDay.name}: ${it.title} · ${it.time} · ${it.info} · ${it.lang} · ${it.badge} · ts=${it.releaseTs}');
  check(pl.noFixedDay.length > 20, 'sans jour fixe (${pl.noFixedDay.length}) ex: ${pl.noFixedDay.first.title} → ${pl.noFixedDay.first.path}');

  stdout.writeln(_fail == 0 ? '\n✅ Tous les tests passent' : '\n❌ $_fail test(s) en échec');
  exit(_fail == 0 ? 0 : 1);
}

Future<String> fetchPost(String url, String form) async {
  final c = HttpClient();
  final r = await c.postUrl(Uri.parse(url));
  r.headers.set('User-Agent', 'Mozilla/5.0 (Linux; Android 13; Pixel 7)');
  r.headers.contentType = ContentType('application', 'x-www-form-urlencoded');
  r.write(form);
  final resp = await r.close();
  final body = await resp.transform(utf8.decoder).join();
  c.close();
  return body;
}
