/// Langues gérées par le site (dossiers d'URL) et leur affichage.
///
/// Sur la page épisodes, le site teste `../{code}/` pour chaque langue et
/// n'affiche le bouton que si la page existe. AnimeWorld fait la même chose.
class LangInfo {
  final String code; // dossier URL : vostfr, vf, va…
  final String label; // libellé du bouton : VO, VF…
  final String flag; // code du drapeau CDN : jp, fr, en…
  final String historyLabel; // valeur stockée dans l'historique : VOSTFR, VF…
  const LangInfo(this.code, this.label, this.flag, this.historyLabel);

  String get flagUrl =>
      'https://cdn.jsdelivr.net/gh/Anime-Sama/IMG@img/autres/flag_$flag.png';
}

/// Ordre d'affichage identique au site.
const List<LangInfo> kAnimeLanguages = [
  LangInfo('vostfr', 'VO', 'jp', 'VOSTFR'),
  LangInfo('vf', 'VF', 'fr', 'VF'),
  LangInfo('va', 'VA', 'en', 'VA'),
  LangInfo('var', 'VAR', 'ar', 'VAR'),
  LangInfo('vkr', 'VKR', 'kr', 'VKR'),
  LangInfo('vcn', 'VCN', 'cn', 'VCN'),
  LangInfo('vqc', 'VQC', 'qc', 'VQC'),
  LangInfo('vj', 'VJ', 'jp', 'VJ'),
  LangInfo('vf1', 'VF1', 'fr', 'VF'),
  LangInfo('vf2', 'VF2', 'fr', 'VF'),
];

/// Langues disponibles pour les scans.
const List<LangInfo> kScanLanguages = [
  LangInfo('vf', 'VF', 'fr', 'VF'),
  LangInfo('va', 'VA', 'en', 'VA'),
];

LangInfo langFromCode(String code) {
  final c = code.toLowerCase();
  for (final l in kAnimeLanguages) {
    if (l.code == c) return l;
  }
  return LangInfo(c, c.toUpperCase(), 'jp', c.toUpperCase());
}

/// Convertit un code de drapeau (`flag_jp.png` → `jp`) en libellé de langue,
/// comme le fait `videos.js` (flagToLang).
String langLabelFromFlag(String flagCode) {
  switch (flagCode) {
    case 'jp':
      return 'VOSTFR';
    case 'en':
      return 'VASTFR';
    case 'cn':
      return 'VCN';
    case 'kr':
      return 'VKR';
    case 'ar':
      return 'VAR';
    case 'qc':
      return 'VQC';
    case 'fr':
      return 'VF';
    default:
      return 'VOSTFR';
  }
}
