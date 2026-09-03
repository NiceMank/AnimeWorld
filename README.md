# AnimeWorld

[![Build & Release](https://github.com/NiceMank/AnimeWorld/actions/workflows/build.yml/badge.svg)](https://github.com/NiceMank/AnimeWorld/actions/workflows/build.yml)
[![Release](https://img.shields.io/github/v/release/NiceMank/AnimeWorld?label=APK)](https://github.com/NiceMank/AnimeWorld/releases/latest)

Client mobile **Flutter** (Android & iOS) reproduisant l'intégralité des fonctionnalités
d'anime-sama.to, avec **les mêmes sources de données** que le site (HTML, `episodes.js`,
API JSON des scans et endpoints `/api/*` du compte).

> Le site ne propose aucune API JSON publique : l'application effectue exactement les mêmes
> requêtes HTTP que le navigateur et parse les réponses. Voir `docs/ANALYSE_ANIME_SAMA.md`
> pour l'analyse complète (endpoints, sélecteurs DOM, formats).

## Fonctionnalités (parité avec le site)

| Écran | Source | Fonctionnalités |
|---|---|---|
| **Splash / Onboarding** | — | 3 écrans de présentation, accès direct à la connexion |
| **Accueil** | `GET /` | Carrousel « à la une » (CTA VOSTFR/VF/VKR), Reprenez votre visionnage, Derniers épisodes, Derniers scans, Sorties du jour, Derniers contenus, Classiques, Pépites |
| **Catalogue** | `GET /catalogue?…` | Recherche, filtres identiques au site (type, langue, statut, année, épisodes, chapitres, 109 genres), pagination infinie (48/page) |
| **Recherche** | `POST /template-php/defaut/fetch.php` | Recherche instantanée (débounce 180 ms), Entrée = 1er résultat |
| **Fiche** | `GET /catalogue/{slug}/` | Bannière, titres alternatifs, État/Année/Épisodes/Studio, synopsis, genres (cliquables), saisons/films/OAV/Kai/scans (`panneauAnime`/`panneauScan`), bande-annonce, œuvres similaires, boutons **Watchlist / Favoris / Vu**, bouton Reprendre |
| **Lecteur épisodes** | `GET …/{saison}/{lang}/` + `episodes.js` | Lecteurs 1..N (même ordre que le site, `swapLecteurs`), sélecteur épisode/lecteur, précédent/dernier/suivant, numérotation spéciale (`creerListe`, `newSP`, `newSPF`, `finirListe`, offset One Piece), switch de langue (détection VOSTFR/VF/VA/VKR/VCN/VAR/VQC/VF1/VF2), plein écran paysage, blocage des pop-ups/pubs, écran allumé, progression + historique |
| **Lecteur scans** | `get_nb_chap_et_img.php` + `/s2/scans/…/{n}.jpg` | Chapitres (numérotation custom), mode Scroll / Page par page (dossier « pp »), fond bleu nuit/blanc/noir, plein écran, zoom, préchargement, VF/VA, progression + historique |
| **Planning** | `GET /planning` | 7 jours (jour courant sélectionné), horloge, filtres Tous/Animes/Scans/VO/VF + recherche, retards, « Œuvres en cours sans jours fixes » |
| **Bibliothèque** | local + `/api/*` | Historique / Watchlist / Favoris / Vus avec compteurs, recherche, tri, filtres type & langue, suppression, vider |
| **Notifications** | `GET /` (polling temps réel) | Veille des sorties : nouveaux épisodes/chapitres des œuvres suivies (watchlist, favoris, historique) ou de tout le site. Centre de notifications avec badge temps réel, bannière in-app, notifications système (Android 13+ / iOS), fréquence configurable (2 min → 1 h), canaux épisodes/scans |
| **Profil** | `/api/auth/*`, `/api/get-data.php`, `/api/sync-*.php`, `/api/merge-data.php` | Connexion / inscription (mêmes règles), synchronisation bidirectionnelle, statistiques, paramètres (lecteur par défaut, langue, mode de lecture, fond, **domaine du site**, cache) |
| **Aide** | `/aide` | FAQ des problèmes récurrents, confidentialité, DMCA |

Le stockage local reprend **exactement les clés du `localStorage` du site**
(`favoriNom/Url/Img`, `watchlist*`, `vu*`, `histo*`, `savedEpName{path}`, `savedChapNb{path}`…),
ce qui garantit une synchronisation compatible avec un compte existant.

## Architecture

```
lib/
├─ main.dart                      # bootstrap (Hive, cookies, thème, halos)
├─ core/
│  ├─ constants/                  # domaines, CDN, 109 genres, langues
│  ├─ providers.dart              # Riverpod (repos, catalogue, session)
│  ├─ router.dart                 # go_router + openSitePath()
│  └─ theme/app_theme.dart        # charte (noir, sky-500, slate-900)
├─ data/
│  ├─ models/models.dart
│  ├─ network/api_client.dart     # Dio + cookies persistants + UA mobile
│  ├─ parsers/html_parsers.dart   # accueil, catalogue, fiche, planning, recherche
│  ├─ parsers/episodes_parser.dart# episodes.js + scripts de numérotation
│  ├─ local/local_store.dart      # équivalent localStorage (Hive)
│  └─ repositories/               # anime_repository, account_repository
├─ features/                      # un dossier par écran
└─ shared/widgets/common.dart     # cartes, images, états, pilules
test/parsers_live_test.dart       # 40 tests contre les vraies pages du site
design/                           # visuels de référence (logo + écrans)
docs/ANALYSE_ANIME_SAMA.md        # analyse complète du site
```

## Télécharger l'APK

Les APK sont construits automatiquement par GitHub Actions à chaque tag `v*` :
**[Releases → dernière version](https://github.com/NiceMank/AnimeWorld/releases/latest)**
(`AnimeWorld-arm64-v8a.apk` pour la plupart des téléphones, `AnimeWorld-universal.apk` sinon).

## Compiler l'application

Prérequis : Flutter ≥ 3.38 (testé avec 3.47.2 / Dart 3.13), Android SDK (API 24+) et/ou Xcode.

```bash
cd AnimeWorld
flutter pub get
flutter run                     # sur un appareil / émulateur connecté

# APK de release (à installer sur votre téléphone)
flutter build apk --release --split-per-abi
#  → build/app/outputs/flutter-apk/app-arm64-v8a-release.apk

# iOS
flutter build ios --release
```

Les icônes ont déjà été générées (`flutter pub run flutter_launcher_icons` si vous changez
`assets/icon/`).

### Tests des parseurs (contre le site en ligne)

```bash
dart test/parsers_live_test.dart      # intégration : vraies pages du site
flutter test                          # tests unitaires hors ligne (CI)
dart run tool/diagnose_player.dart    # diagnostic du lecteur vidéo
```

Le workflow GitHub Actions (`Build & Release`) exécute à chaque push/PR :

1. `flutter analyze` (bloquant) ;
2. `flutter test` — tests unitaires hors ligne (bloquant) ;
3. les tests des parseurs contre le site réel (non bloquant : le site peut
   être indisponible) ;
4. le diagnostic du lecteur vidéo (page épisode → episodes.js → lecteurs
   extraits → accessibilité des hébergeurs).

## Notes

* **Domaine** : le site change parfois de domaine (`.to` / `.org` / `.fr`). Modifiable dans
  *Profil › Domaine du site* sans mise à jour de l'application.
* **Lecteurs vidéo** : les vidéos sont hébergées par des tiers (embed4me, ansembed, sibnet,
  uqload, vidmoly, sendvid…). Certains sont bloqués par des opérateurs ; la WebView autorise
  désormais le contenu mixte (vidéos HTTP dans les embeds HTTPS) et les cookies tiers, et un
  bouton **Lecteur suivant** permet d'enchaîner quand un hébergeur est mort.
  Certains hébergeurs (ex. sibnet) filtrent les requêtes hors navigateur : la WebView intégrée
  se comporte comme Chrome mobile.
* **Notifications** : « temps réel » = interrogation du site à intervalle régulier
  (2 min → 1 h, configurable) pendant que l'app est ouverte, + vérification au retour au
  premier plan. Le site ne propose pas de serveur de push ; la première vérification établit
  une baseline silencieuse (pas de rafale de notifications à l'installation).
* **Pubs** : la WebView bloque `window.open`, les navigations vers des domaines externes et une
  liste de régies publicitaires ; un compteur indique le nombre de pubs bloquées.
* L'application n'héberge aucun contenu et n'est pas affiliée au site.
