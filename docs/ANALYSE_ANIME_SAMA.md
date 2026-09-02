# Analyse complète — anime-sama.to (référence pour AnimeWorld)

> Analyse réalisée le 02/09/2026 à partir du site en production (HTML, JS et endpoints réels).
> Le site n'a **pas d'API JSON publique** : c'est un site PHP + jQuery qui génère du HTML côté serveur
> et charge quelques ressources JS/JSON dynamiques. AnimeWorld reproduit donc exactement les mêmes
> requêtes HTTP que le navigateur et parse les réponses (HTML scraping + fichiers `episodes.js` + JSON scans).

---

## 1. Domaines & ressources statiques

| Ressource | URL |
|---|---|
| Site | `https://anime-sama.to` (miroirs canoniques : anime-sama.org / anime-sama.fr) |
| CDN images | `https://cdn.jsdelivr.net/gh/Anime-Sama/IMG@img/` (fallback : `https://raw.githubusercontent.com/Anime-Sama/IMG/img/`) |
| Miniature (affiche) | `.../contenu/thumb/{slug}.webp` |
| Bannière large 800x450 | `.../contenu/{slug}.jpg` |
| Drapeaux langues | `.../autres/flag_{jp,fr,en,kr,cn,ar,qc}.png` |
| Image "vidéo indisponible" | `.../autres/erreur_videos.jpg` |
| Logo | `.../autres/logo.png` (carré) / `logo_banniere.png` |

Aucun header particulier n'est requis (User-Agent Dart accepté, pas de vérification Referer, pas de CORS bloquant
côté app native). Toutes les pages sont servies par Cloudflare (HTTP/2, x-frame-options SAMEORIGIN → le site
lui-même ne doit pas être mis dans une iframe, mais les **lecteurs vidéo tiers**, eux, sont embarquables).

---

## 2. Pages & endpoints

### 2.1 Accueil `GET /`
HTML avec plusieurs sections (identifiants DOM stables) :

| Section | Sélecteur | Contenu |
|---|---|---|
| Carrousel « à la une » | `#akTrack .ak-slide` | bannière `.ak-slide-bg img`, badge `.ak-badge` ("Saison 1 en cours"), `.ak-slide-title`, `.ak-genre-tag`, `.ak-slide-synopsis`, CTA `.ak-slide-cta[href]` (un lien par langue avec drapeau) |
| Reprenez votre visionnage | `#containerVisionnages` | rempli **côté client** depuis localStorage (historique) |
| Derniers épisodes ajoutés | `#containerAjoutsAnimes .anime-card-premium` | `a[href]`, `img.card-image`, `.badge-text` (Anime/Film…), `.flag-icon[alt]` (langue), `.card-title`, `.info-text` ("Saison 1 Episode 9"), `.time-text` ("02/09/2026 20:10") |
| Derniers scans ajoutés | `#containerAjoutsScans .scan-card-premium` | idem, `.info-text` = "Chapitre 34" |
| Derniers contenus sortis | `#containerSorties .catalog-card` | carte catalogue (voir 2.2) |
| Les classiques | `#containerClassiques .catalog-card` | idem |
| Découvrez des pépites | `#containerPepites .catalog-card` | idem |
| Sorties du jour | `#containerLundi … #containerDimanche` (`div#0..6.fadeJours`) | planning du jour (même carte que la page planning) |

### 2.2 Catalogue `GET /catalogue`
Formulaire GET, 48 cartes par page, ~50 pages.

Paramètres query (tableaux PHP `[]`) :
- `search=<texte>` (recherche titre / titres alternatifs)
- `type[]=` `Anime` | `Scans` | `Film` | `Autres`
- `langue[]=` `VOSTFR` | `VF` | `VASTFR`
- `current[]=` `En cours` | `Terminé`
- `genre[]=` (109 genres, liste complète dans `lib/core/constants/genres.dart`)
- `annee_min`, `annee_max`, `episodes_min`, `episodes_max`, `chapitres_min`, `chapitres_max`
- `page=N`

Carte `.catalog-card` :
```
a[href]  -> /catalogue/{slug}
img.card-image[src]           -> thumb webp
h2.card-title                 -> titre
p.alternate-titles            -> titres alternatifs (séparés par virgules)
.genre-tags .genre-tag        -> genres (tronqués à 5 + "…")
.type-row .info-value         -> "Anime", "Scans", "Anime, Scans", "Film"…
.lang-flags .lang-flag[title] -> JP / FR / EN
.synopsis-tooltip .synopsis-content -> synopsis
```
Pagination : `#list_pagination a[href='?page=N']` (dernier lien = nombre de pages).

### 2.3 Recherche instantanée `POST /template-php/defaut/fetch.php`
Body `application/x-www-form-urlencoded` : `query=<texte>`. Réponse : fragment HTML
```
a.asn-search-result[href] > img.asn-search-result-img[src] + h3.asn-search-result-title + p.asn-search-result-subtitle
```
(débounce 180 ms côté site).

### 2.4 Fiche œuvre `GET /catalogue/{slug}/`
```
h1                                  -> titre
h2#titreAlter                       -> titres alternatifs
meta[property=og:image]             -> bannière
iframe#bandeannonce[src]            -> trailer YouTube (embed)
.info-card .info-lbl / .info-val    -> État, Année, Épisodes (ou Chapitres), Studio
p#synopsisText                      -> synopsis
.genres-wrap .genre-pill            -> genres
h2 "Anime" / "Anime Version Kai" / "Manga" / "Autres" + <script> panneauAnime("Nom", "saison1/vostfr") / panneauScan("Scans", "scan/vf")
#containerSimilaires .catalog-card  -> œuvres similaires
```
Les **saisons** sont déclarées via des appels JS `panneauAnime(nom, urlRelative)` et `panneauScan(nom, urlRelative)`.
Exemples réels : `saison1`, `saison2-1`, `saison1hs` (hors-série), `film`, `oav`, `kai`, `kai2`, `kaihs`, `scan`, `scan_one_shot`, `scan-end-line`.
L'URL déclarée contient la langue par défaut (`vostfr` pour anime, `vf` pour scan) ; les autres langues se
découvrent en testant `../{lang}/` (voir 2.5).

Boutons d'action : Watchlist / Favoris / Vu (stockage local + synchro serveur si connecté).

### 2.5 Page épisodes `GET /catalogue/{slug}/{saison}/{lang}/`
Langues possibles : `vostfr`, `vf`, `va`, `var`, `vkr`, `vcn`, `vqc`, `vj`, `vf1`, `vf2` (anime) ; `vf`, `va` (scans).
Une langue existe si `GET ../{lang}/` répond 200 **et** que son `episodes.js` contient au moins un `var eps`.
(⚠️ le serveur répond 200 même pour une saison inexistante, avec un `episodes.js` vide `//`).

Contenu utile :
```
img#imgOeuvre[src]                  -> bannière
h3#titreOeuvre                      -> titre
<script> $("#avOeuvre").html("Saison 1")   -> nom de la saison
<script src='episodes.js?filever=NNNN'>    -> lecteurs
<script> resetListe(); creerListe(a,b); newSP(n); newSPF("Nom"); finirListe(n); -> numérotation custom
<p id="messagePage">                -> message d'info éventuel
```

**`episodes.js`** (JavaScript, pas JSON) :
```js
var eps1 = [ 'https://lpayer.embed4me.com/#3maxc', ... ];   // lecteur 1
var eps2 = [ 'https://ansembed.net/embed-xxxx.html', ... ]; // lecteur 2
var eps3 = [ 'https://video.sibnet.ru/shell.php?videoid=6234425', ... ];
var eps4 = [ 'https://uqload.is/embed-xxxx.html', ... ];
var eps5 = [ 'https://minochinos.com/embed/xxxx', ... ];
```
- `epsN[i]` = URL d'embed de l'épisode `i+1` pour le lecteur `N`. Chaque lecteur est un hébergeur tiers (embed4me,
  ansembed, sibnet, uqload, minochinos, vidmoly, sendvid, oneupload…).
- Le site **échange eps1 et eps2** à l'affichage (`swapLecteurs()`), et réécrit `vidmoly.to|net` → `vidmoly.biz`.
- Le nombre d'épisodes = longueur de `eps1`.
- Numérotation des épisodes : par défaut "Episode 1..N" ; sinon script custom :
  `resetListe()` vide ; `creerListe(debut, fin)` ajoute "Episode debut..fin" ; `newSP(n)` ajoute "Episode n" spécial ;
  `newSPF("Titre")` ajoute un libellé libre (films) ; `finirListe(debut)` complète jusqu'à `N - nbSpéciaux`.
  (One Piece Egghead utilise un `finirListeOP` custom avec offset 1088 → géré par regex spécifique).
- Progression : localStorage `savedEpName{path}` / `savedEpNb{path}` (index) + historique.

### 2.6 Page scans `GET /catalogue/{slug}/scan/{lang}/`
- Titre `h3#titreOeuvre` = **nom d'œuvre utilisé par l'API scans** (ex. "One Piece Couleur").
- **API JSON** `GET /s2/scans/get_nb_chap_et_img.php?oeuvre={nomOeuvre}` →
  `{"1":57,"2":25,...}` = nombre d'images par chapitre (`{"error":"..."}` si inconnu).
- Variante page-par-page : même appel avec `oeuvre={nomOeuvre} pp`.
- Image : `GET /s2/scans/{nomOeuvre}/{chapitre}/{n}.jpg`.
- Numérotation custom : mêmes fonctions (`creerListe`, `newSPF`, `finirListe`) dans un `<script>` de la page.
- Options UI : plein écran, couleur de fond (#020D18 / blanc / noir), mode Scroll ou Page par page.
- Progression : localStorage `savedChapName{path}` / `savedChapNb{path}`.

### 2.7 Planning `GET /planning`
- 7 colonnes `#planningClass > div#0..6` (Lundi→Dimanche) avec `h2.titreJours` + `p` (date jj/mm) ; jour courant = `.selectedRow`.
- Carte `.planning-card` : classes `Anime|Scan` + `VOSTFR|VF`, `data-title`, `data-release-ts` (epoch),
  `a[href]`, `img.card-image`, `.badge-text`, `.flag-icon[alt]`, `.card-title`, `.planning-time .info-text` ("15h00"),
  `.info-text` ("Saison 1" / "Chapitre"). Classe `.planning-problem-red` = retard/problème.
- Section « Œuvres en cours sans jours fixes » : liste horizontale de cartes.
- Filtres client : Tous / Animes / Scans / VO / VF / recherche.

### 2.8 Compte & synchronisation (`/api/*`, JSON, cookie de session PHP)
| Endpoint | Méthode | Body | Réponse |
|---|---|---|---|
| `/api/auth/login.php` | POST | `{"pseudo","password"}` | 200 ok / 4xx `{"error"}` / 429 rate-limit |
| `/api/auth/register.php` | POST | `{"pseudo","password"}` (pseudo 3-30 `[a-zA-Z0-9_-]`, mdp ≥12 + symbole) | idem |
| `/api/auth/logout.php` | GET | — | — |
| `/api/get-data.php` | GET | — | `{"logged_in":false}` ou `{"logged_in":true,"need_merge":bool,"progress":{path:{name,num}},"favorites":{nom[],url[],img[]},"watchlist":{...},"viewed":{...},"history":{nom[],url[],img[],type[],lang[],ep[],num[]}}` |
| `/api/merge-data.php` | POST | `{progress,favorites,watchlist,viewed,history}` | `{"merged":{...}}` |
| `/api/sync-favorites.php` | POST | `{"favorites":{nom,url,img}}` | — |
| `/api/sync-watchlist.php` | POST | `{"watchlist":{...}}` | — |
| `/api/sync-viewed.php` | POST | `{"viewed":{...}}` | — |
| `/api/sync-history.php` | POST | `{"history":{nom,url,img,type,lang,ep,num}}` | — |
| `/api/sync-progress.php` | POST | `{"progress":{path:{name,num}}}` | — |

Limite : 500 entrées par liste. Comptes supprimés après 6 mois d'inactivité.

### 2.9 Aide `GET /aide`
Sections : Problèmes récurrents, Liste de solutions, Politique de confidentialité, DMCA (statique).

---

## 3. Modèle de données local (identique au site — clés localStorage)

```
favoriNom / favoriUrl / favoriImg          (3 tableaux parallèles)
watchlistNom / watchlistUrl / watchlistImg
vuNom / vuUrl / vuImg
histoNom / histoUrl / histoImg / histoType / histoLang / histoEp / histoNum
savedEpName{path} / savedEpNb{path}
savedChapName{path} / savedChapNb{path}
readingMode  ("scroll" | "page")
```
AnimeWorld utilise Hive avec exactement la même sémantique afin que la synchro `/api/*` soit compatible.

---

## 4. Charte graphique du site (reprise et modernisée dans AnimeWorld)

- Fond : `#000000` avec halos bleus radiaux (`rgb(0,71,177)` → `#00ccff`) ; surfaces `rgba(15,23,42,.7)` (slate-900).
- Accent : sky-500 `#0ea5e9` (boutons, outlines, badges), sky-900 pour les états actifs.
- Texte : blanc / gris `#cbd5e1`, `#94a3b8`.
- Cartes : radius 6px, image 2:3, badge type (Anime/Scans/Film) + drapeau langue en haut.
- Typo : Inter/Tailwind défaut, titres UPPERCASE bold.
