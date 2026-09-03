// Diagnostic du lecteur vidéo contre le site réel.
//
// Vérifie toute la chaîne de données « lecteur » : page d'épisode →
// episodes.js → lecteurs/URLs extraits → accessibilité des hébergeurs.
// Aucune dépendance Flutter : exécutable avec `dart run`.
//
//   dart run tool/diagnose_player.dart                      # auto (accueil)
//   dart run tool/diagnose_player.dart one-piece saison1 vostfr
//
// Sortie attendue en CI : ▶/✓/✗ + résumé. Code de sortie 1 si aucun lecteur
// n'est trouvé sur les pages testées (chaîne cassée), 0 sinon.
import 'dart:convert';
import 'dart:io';

import 'package:animeworld/core/constants/app_constants.dart';
import 'package:animeworld/data/parsers/episodes_parser.dart';
import 'package:animeworld/data/parsers/html_parsers.dart';

Future<void> main(List<String> args) async {
  final base = AppConstants.defaultBaseUrl;
  var failures = 0;

  final targets = <List<String>>[];
  if (args.length >= 3) {
    targets.add([args[0], args[1], args[2]]);
  } else {
    stdout.writeln('▶ Accueil : recherche d\'un épisode récent…');
    final homeHtml = await _get('$base/', [200]);
    if (homeHtml == null) {
      stdout.writeln('  ✗ accueil inaccessible (HTTP/connexion)');
      exit(1);
    }
    final home = HtmlParsers.parseHome(homeHtml);
    stdout.writeln(
        '  ✓ derniers épisodes : ${home.latestEpisodes.length}, '
        'derniers scans : ${home.latestScans.length}');
    if (home.latestEpisodes.isEmpty) {
      stdout.writeln('  ✗ aucun épisode récent sur l\'accueil');
      exit(1);
    }
    for (final r in home.latestEpisodes.take(2)) {
      final p = r.path.split('/').where((s) => s.isNotEmpty).toList();
      final i = p.indexOf('catalogue');
      if (i + 3 < p.length) targets.add([p[i + 1], p[i + 2], p[i + 3]]);
    }
  }

  for (final t in targets) {
    final slug = t[0], folder = t[1], lang = t[2];
    final path = '/catalogue/$slug/$folder/$lang/';
    stdout.writeln('▶ $path');
    final html = await _get('$base$path', [200, 404]);
    if (html == null) {
      failures++;
      continue;
    }
    final info = HtmlParsers.parseContentPageInfo(html);
    stdout.writeln(
        '  page  : titre="${info.rawTitle}" js=${info.episodesJsFile} '
        '404=${info.is404}');
    if (info.is404) {
      stdout.writeln('  ✗ page 404');
      failures++;
      continue;
    }

    final js = await _get('$base$path${info.episodesJsFile}', [200]);
    if (js == null) {
      stdout.writeln('  ✗ episodes.js inaccessible');
      failures++;
      continue;
    }
    final players = EpisodesParser.parsePlayers(js);
    final total = EpisodesParser.episodeCount(players);
    stdout.writeln(
        '  parse : ${players.length} lecteur(s), $total épisode(s) '
        '[eps brut: ${RegExp(r'var\s+eps(\d+)').allMatches(js).length}]');
    if (players.isEmpty) {
      stdout.writeln('  ✗ AUCUN lecteur extrait — contenu episodes.js :');
      stdout.writeln(js.length > 800 ? '${js.substring(0, 800)}…' : js);
      failures++;
      continue;
    }
    for (final p in players.take(4)) {
      final first = p.urls.first;
      final host = Uri.tryParse(first)?.host ?? '?';
      final status = await _status(first);
      stdout.writeln(
          '  ✓ Lecteur ${p.index} [$host] ${p.urls.length} ép. '
          '→ premier URL HTTP $status');
      stdout.writeln('    $first');
    }
  }

  if (failures > 0) {
    stdout.writeln('✗ Diagnostic : $failures échec(s).');
    exit(1);
  }
  stdout.writeln('✓ Diagnostic : chaîne lecteur opérationnelle.');
}

final _ua = AppConstants.userAgent;

Future<String?> _get(String url, List<int> expected) async {
  try {
    final c = HttpClient();
    c.connectionTimeout = const Duration(seconds: 15);
    c.userAgent = _ua;
    final req = await c.getUrl(Uri.parse(url));
    req.headers.set('Accept', '*/*');
    final resp = await req.close();
    final body = await resp.transform(utf8.decoder).join();
    c.close();
    if (!expected.contains(resp.statusCode)) {
      stdout.writeln('  ✗ HTTP ${resp.statusCode} ← $url');
      return null;
    }
    return body;
  } catch (e) {
    stdout.writeln('  ✗ $e ← $url');
    return null;
  }
}

Future<int> _status(String url) async {
  try {
    final c = HttpClient();
    c.connectionTimeout = const Duration(seconds: 12);
    c.userAgent = _ua;
    final req = await c.openUrl('GET', Uri.parse(url));
    final resp = await req.close();
    await resp.drain<void>();
    c.close();
    return resp.statusCode;
  } catch (e) {
    stdout.writeln('    (erreur accès: $e)');
    return 0;
  }
}
