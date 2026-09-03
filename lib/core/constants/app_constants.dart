/// Constantes globales : domaines, CDN et paramètres réseau.
///
/// Toutes les URLs sont celles réellement utilisées par anime-sama.to
/// (cf. docs/ANALYSE_ANIME_SAMA.md).
class AppConstants {
  AppConstants._();

  static const String appName = 'AnimeWorld';
  static const String appVersion = '1.1.0';

  /// Domaine principal. Le site possède plusieurs miroirs (.to / .org / .fr) ;
  /// il est modifiable dans les paramètres si le domaine change.
  static const String defaultBaseUrl = 'https://anime-sama.to';

  /// CDN des images (jsDelivr sur le dépôt GitHub Anime-Sama/IMG).
  static const String cdnBase =
      'https://cdn.jsdelivr.net/gh/Anime-Sama/IMG@img';

  /// Fallback CDN (utilisé par certaines cartes du planning).
  static const String cdnFallback =
      'https://raw.githubusercontent.com/Anime-Sama/IMG/img';

  static const String userAgent =
      'Mozilla/5.0 (Linux; Android 15; Pixel 9) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/140.0.0.0 Mobile Safari/537.36';

  static const Duration connectTimeout = Duration(seconds: 15);
  static const Duration receiveTimeout = Duration(seconds: 25);

  /// 48 cartes par page sur /catalogue.
  static const int cataloguePageSize = 48;

  /// Limite des listes (favoris, watchlist, vus) imposée par le site.
  static const int listMax = 500;

  // ---- Helpers CDN -------------------------------------------------------

  /// Affiche (portrait) : contenu/thumb/{slug}.webp
  static String thumb(String slug) => '$cdnBase/contenu/thumb/$slug.webp';

  /// Bannière 800x450 : contenu/{slug}.jpg
  static String banner(String slug) => '$cdnBase/contenu/$slug.jpg';

  /// Drapeau : autres/flag_{code}.png
  static String flag(String code) => '$cdnBase/autres/flag_$code.png';

  static String get errorVideoImage => '$cdnBase/autres/erreur_videos.jpg';
}
