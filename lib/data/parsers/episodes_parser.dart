import '../models/models.dart';

/// Reproduit la logique de `videos.js` / `scans.js` du site :
/// * lecture des tableaux `var epsN = [...]` de episodes.js ;
/// * construction de la liste des épisodes/chapitres, y compris les scripts
///   personnalisés (`resetListe`, `creerListe`, `newSP`, `newSPF`, `finirListe`).
class EpisodesParser {
  EpisodesParser._();

  static final _varRe = RegExp(
    r'var\s+eps(\d+)\s*=\s*\[(.*?)\]\s*;?',
    dotAll: true,
  );
  static final _urlRe = RegExp(r'''["']([^"']+)["']''');

  /// Parse episodes.js → lecteurs triés comme le site les affiche.
  ///
  /// Le site fait `swapLecteurs()` : si eps2 existe, eps1 et eps2 sont
  /// échangés (le lecteur 1 affiché est donc `eps2`). On applique la même
  /// permutation pour que « Lecteur N » corresponde au site.
  static List<Player> parsePlayers(String js) {
    final byIndex = <int, List<String>>{};
    // Supprime les blocs /* … */ puis les lignes entièrement commentées
    // (« //'https://…', ») qu'un moteur JS ignorerait.
    final cleaned = js
        .replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '')
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    for (final m in _varRe.allMatches(cleaned)) {
      final idx = int.parse(m.group(1)!);
      final body = m.group(2)!;
      final urls = _urlRe
          .allMatches(body)
          .map((u) => _fixUrl(u.group(1)!.trim()))
          .where((u) => u.isNotEmpty)
          .toList();
      byIndex[idx] = urls;
    }
    if (byIndex.isEmpty) return const [];

    // swapLecteurs()
    if (byIndex.containsKey(1) && byIndex.containsKey(2)) {
      final tmp = byIndex[1]!;
      byIndex[1] = byIndex[2]!;
      byIndex[2] = tmp;
    }

    final keys = byIndex.keys.toList()..sort();
    var display = 0;
    final players = <Player>[];
    for (final k in keys) {
      final urls = byIndex[k]!;
      if (urls.isEmpty) continue;
      display++;
      players.add(Player(index: display, urls: urls));
    }
    return players;
  }

  /// Réécritures d'URL faites par le site.
  static String _fixUrl(String url) {
    var u = url;
    // videos.js : vidmoly.to / vidmoly.net → vidmoly.biz
    u = u.replaceAll(RegExp(r'vidmoly\.(to|net)'), 'vidmoly.biz');
    if (u.startsWith('//')) u = 'https:$u';
    return u;
  }

  /// Nombre d'épisodes = longueur du premier tableau (eps1 côté site,
  /// c'est-à-dire le plus long en pratique ; on prend le max pour être sûr).
  static int episodeCount(List<Player> players) {
    if (players.isEmpty) return 0;
    var max = 0;
    for (final p in players) {
      if (p.urls.length > max) max = p.urls.length;
    }
    return max;
  }

  /// Construit les libellés (« Episode 1 »… ou « Chapitre 1 »…) en exécutant
  /// le script personnalisé éventuel de la page, exactement comme le site.
  ///
  /// [total] = nombre d'entrées disponibles (épisodes du lecteur ou chapitres).
  /// [scripts] = contenu des balises <script> inline de la page.
  static List<String> buildLabels({
    required int total,
    required List<String> scripts,
    required String unit, // "Episode" ou "Chapitre"
  }) {
    // Cherche le script « custom » : celui qui contient resetListe() suivi
    // d'appels de construction (hors le bloc $(document).ready standard).
    String? custom;
    for (final s in scripts) {
      final cleaned = _stripComments(s);
      if (!cleaned.contains('resetListe(')) continue;
      if (cleaned.contains('creerListe(') ||
          cleaned.contains('newSP(') ||
          cleaned.contains('newSPF(') ||
          cleaned.contains('finirListe')) {
        // Le bloc standard ($(document).ready) contient resetListe();finirListe(1);
        // et rien d'autre : on préfère un script plus riche s'il existe.
        if (custom == null || cleaned.length > custom.length) custom = cleaned;
      }
    }

    final labels = <String>[];
    var specials = 0;

    void creerListe(int a, int b) {
      for (var i = a; i <= b; i++) {
        labels.add('$unit $i');
      }
    }

    void finirListe(int debut, {int offset = 0}) {
      for (var i = debut; i <= offset + (total - specials); i++) {
        labels.add('$unit $i');
      }
    }

    if (custom == null || _isDefaultScript(custom)) {
      creerListe(1, total);
      return labels;
    }

    // Offset spécial One Piece : function finirListeOP(debut){ ... 1088+(...) }
    int opOffset = 0;
    final opDef = RegExp(r'(\d+)\s*\+\s*\(\s*tailleEpisodes\s*-\s*epRetards\s*\)')
        .firstMatch(custom);
    if (opDef != null) opOffset = int.parse(opDef.group(1)!);

    // Exécution séquentielle des instructions (hors définitions de fonctions)
    final body = _removeFunctionDefinitions(custom);
    final callRe = RegExp(
      r'''(resetListe|creerListe|newSPF|newSP|finirListe\w*)\s*\(([^()]*(?:\([^()]*\)[^()]*)*)\)''',
    );
    for (final m in callRe.allMatches(body)) {
      final fn = m.group(1)!;
      final args = m.group(2)!.trim();
      switch (fn) {
        case 'resetListe':
          labels.clear();
          specials = 0;
          break;
        case 'creerListe':
          final nums = _ints(args);
          if (nums.length >= 2) creerListe(nums[0], nums[1]);
          break;
        case 'newSP':
          final v = args.replaceAll(RegExp(r'''^["']|["']$'''), '');
          labels.add('$unit $v');
          specials++;
          break;
        case 'newSPF':
          final v = _unquote(args);
          labels.add(v);
          specials++;
          break;
        default: // finirListe / finirListeOP…
          final nums = _ints(args);
          final debut = nums.isNotEmpty ? nums.first : 1;
          finirListe(debut, offset: fn == 'finirListe' ? 0 : opOffset);
      }
    }

    if (labels.isEmpty) creerListe(1, total);
    // Sécurité : jamais plus de libellés que d'entrées réelles.
    if (labels.length > total && total > 0) {
      return labels.sublist(0, total);
    }
    return labels;
  }

  static bool _isDefaultScript(String s) {
    final compact = s.replaceAll(RegExp(r'\s+'), '');
    // bloc standard : resetListe();finirListe(1);
    return !compact.contains('creerListe(') &&
        !compact.contains('newSP') &&
        RegExp(r'finirListe\(1\)').hasMatch(compact);
  }

  static String _stripComments(String s) {
    var out = s.replaceAll(RegExp(r'/\*.*?\*/', dotAll: true), '');
    out = out.replaceAll(RegExp(r'//[^\n]*'), '');
    return out;
  }

  static String _removeFunctionDefinitions(String s) {
    // supprime "function name(...){ ... }" (une profondeur d'accolades)
    return s.replaceAll(
      RegExp(r'function\s+\w+\s*\([^)]*\)\s*\{(?:[^{}]|\{[^{}]*\})*\}'),
      '',
    );
  }

  static List<int> _ints(String args) => RegExp(r'-?\d+')
      .allMatches(args)
      .map((m) => int.parse(m.group(0)!))
      .toList();

  static String _unquote(String s) {
    var v = s.trim();
    if ((v.startsWith('"') && v.endsWith('"')) ||
        (v.startsWith("'") && v.endsWith("'"))) {
      v = v.substring(1, v.length - 1);
    }
    return v.replaceAll(r"\'", "'").replaceAll(r'\"', '"');
  }
}
