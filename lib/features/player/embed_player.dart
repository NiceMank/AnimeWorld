import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';

/// Lecteur d'embed tiers (sibnet, uqload, embed4me, ansembed, vidmoly…).
///
/// Le site affiche ces URLs dans une `<iframe id="playerDF">`. Ici on les
/// charge dans une WebView dédiée avec :
/// * blocage des pop-ups / pop-unders (`window.open`) ;
/// * blocage des navigations JS vers un autre domaine que celui du lecteur
///   (technique des « clics piégés »), tout en acceptant les redirections
///   serveur (les hébergeurs changent régulièrement de domaine :
///   uqload.is → uqload.vc, minochinos.com → callistanise.com…) ;
/// * blocage des scripts publicitaires connus ;
/// * plein écran natif (bouton du lecteur HTML5 → écran complet).
class EmbedPlayer extends StatefulWidget {
  const EmbedPlayer({
    super.key,
    required this.url,
    required this.onToggleFullscreen,
    required this.isFullscreen,
    this.onOpenExternal,
    this.onNextPlayer,
    this.referer,
  });

  final String url;
  final VoidCallback onToggleFullscreen;
  final bool isFullscreen;
  final VoidCallback? onOpenExternal;

  /// Passe au lecteur suivant disponible (bouton de l'état d'erreur).
  final VoidCallback? onNextPlayer;

  /// URL de référent envoyée au chargement : le domaine du site COURANT
  /// (certains hébergeurs la vérifient pour autoriser la lecture).
  final String? referer;

  @override
  State<EmbedPlayer> createState() => _EmbedPlayerState();
}

class _EmbedPlayerState extends State<EmbedPlayer> {
  InAppWebViewController? _ctrl;
  double _progress = 0;
  bool _error = false;
  int _blocked = 0;

  /// Clé globale de la WebView : conservée lors du passage portrait ↔ plein
  /// écran (les widgets parents changent, la vidéo ne recharge pas).
  final _webKey = GlobalKey();

  /// Domaine courant du lecteur (mis à jour après une redirection serveur).
  late String _currentHost = Uri.tryParse(widget.url)?.host ?? '';

  /// Mots-clés de domaines publicitaires fréquents dans les embeds.
  static const _adKeywords = <String>[
    'doubleclick',
    'googlesyndication',
    'adnxs',
    'popads',
    'popcash',
    'propellerads',
    'exoclick',
    'trafficjunky',
    'juicyads',
    'adsterra',
    'hilltopads',
    'clickadu',
    'onclickalgo',
    'a-zzz.com',
    'acscdn.com',
    'adcash',
    'mgid.com',
    'taboola',
    'outbrain',
    'adsco.re',
    'kettledroopingcontinuation',
    'spendsdetachment',
    'realsrv',
    'tsyndicate',
    'adskeeper',
    'richads',
    'pushame',
    'mobtrks',
    'adspyglass',
    'trafficstars',
    'adtng',
    'ad-maven',
    'admaven',
  ];

  bool _isAd(Uri u) {
    final h = u.host.toLowerCase();
    return _adKeywords.any(h.contains);
  }

  static String _rootDomain(String host) {
    final parts = host.split('.');
    if (parts.length <= 2) return host;
    return parts.sublist(parts.length - 2).join('.');
  }

  /// Navigation JS de la frame principale : uniquement le domaine du lecteur
  /// (ou un domaine « frère » : vidmoly.biz → vidmoly.net…).
  bool _isAllowedMainFrame(Uri u) {
    if (u.scheme != 'http' && u.scheme != 'https') return false;
    if (_isAd(u)) return false;
    final base = _rootDomain(_currentHost);
    final target = _rootDomain(u.host);
    if (base == target) return true;
    final baseName = base.split('.').first;
    return baseName.length >= 4 && target.startsWith(baseName);
  }

  InAppWebViewSettings get _settings => InAppWebViewSettings(
        userAgent: AppConstants.userAgent,
        mediaPlaybackRequiresUserGesture: false,
        allowsInlineMediaPlayback: true,
        javaScriptCanOpenWindowsAutomatically: false,
        supportMultipleWindows: true, // pour intercepter et bloquer les popups
        useShouldOverrideUrlLoading: true,
        transparentBackground: true,
        iframeAllowFullscreen: true,
        allowsPictureInPictureMediaPlayback: true,
        useHybridComposition: true,
        // Android : vidéos HTTP servies par des embeds HTTPS (sinon écran
        // noir) + cookies tiers requis par plusieurs hébergeurs.
        mixedContentMode: MixedContentMode.MIXED_CONTENT_COMPATIBILITY_MODE,
        thirdPartyCookiesEnabled: true,
        domStorageEnabled: true,
        // Une règle par mot-clé : la syntaxe des content blockers WebKit ne
        // garantit pas l'alternation « | ».
        contentBlockers: [
          for (final k in _adKeywords)
            ContentBlocker(
              trigger: ContentBlockerTrigger(
                urlFilter: '.*${k.replaceAll('.', '\\.')}.*',
                resourceType: [
                  ContentBlockerTriggerResourceType.SCRIPT,
                  ContentBlockerTriggerResourceType.DOCUMENT,
                  ContentBlockerTriggerResourceType.RAW,
                  ContentBlockerTriggerResourceType.IMAGE,
                ],
              ),
              action: ContentBlockerAction(type: ContentBlockerActionType.BLOCK),
            ),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final webView = KeyedSubtree(
      key: _webKey,
      child: InAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri(widget.url),
          headers: {
            'Referer': widget.referer ?? '${AppConstants.defaultBaseUrl}/',
          },
        ),
        initialSettings: _settings,
        onWebViewCreated: (c) => _ctrl = c,
        onProgressChanged: (_, p) {
          if (mounted) setState(() => _progress = p / 100);
        },
        onLoadStop: (_, url) {
          // Le lecteur peut rediriger son propre domaine (uqload.is →
          // .vc…) : on suit pour que les règles de navigation restent
          // justes.
          final host = url?.host ?? '';
          if (host.isNotEmpty && host != _currentHost && mounted) {
            setState(() => _currentHost = host);
          }
        },
        onReceivedError: (_, req, err) {
          if (req.isForMainFrame == true && mounted) setState(() => _error = true);
        },
        onReceivedHttpError: (_, req, resp) {
          final code = resp.statusCode ?? 0;
          if (req.isForMainFrame == true && code >= 400 && mounted) {
            setState(() => _error = true);
          }
        },
        shouldOverrideUrlLoading: (_, action) async {
          final u = action.request.url;
          if (u == null) return NavigationActionPolicy.ALLOW;
          if (_isAd(u)) {
            _countBlocked();
            return NavigationActionPolicy.CANCEL;
          }
          if (!action.isForMainFrame) return NavigationActionPolicy.ALLOW;
          // Redirection serveur (changement de domaine de l'hébergeur) : OK.
          if (action.isRedirect == true) {
            _currentHost = u.host;
            return NavigationActionPolicy.ALLOW;
          }
          if (_isAllowedMainFrame(u)) {
            _currentHost = u.host;
            return NavigationActionPolicy.ALLOW;
          }
          // Navigation JS vers un site externe = pub piégée.
          _countBlocked();
          return NavigationActionPolicy.CANCEL;
        },
        // window.open() → toujours bloqué (pop-under publicitaires)
        onCreateWindow: (_, _) async {
          _countBlocked();
          return false;
        },
        onEnterFullscreen: (_) {
          if (!widget.isFullscreen) widget.onToggleFullscreen();
        },
        onExitFullscreen: (_) {
          if (widget.isFullscreen) widget.onToggleFullscreen();
        },
      ),
    );

    final player = Stack(
      fit: StackFit.expand,
      children: [
        webView,
        if (_progress < 1 && !_error)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(value: _progress, minHeight: 2),
          ),
        if (_error)
          Container(
            color: AppColors.surface,
            alignment: Alignment.center,
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.error_outline_rounded, size: 36, color: AppColors.danger),
              const SizedBox(height: 8),
              Text(
                'Vidéo indisponible sur ce lecteur '
                '${_currentHost.isEmpty ? '' : '($_currentHost)'}.\n'
                'Essayez un autre lecteur.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 6, alignment: WrapAlignment.center, children: [
                OutlinedButton(
                  onPressed: () {
                    setState(() => _error = false);
                    _ctrl?.reload();
                  },
                  child: const Text('Recharger'),
                ),
                if (widget.onNextPlayer != null)
                  FilledButton.icon(
                    onPressed: () {
                      setState(() => _error = false);
                      widget.onNextPlayer!();
                    },
                    icon: const Icon(Icons.skip_next_rounded, size: 18),
                    label: const Text('Lecteur suivant'),
                  ),
                if (widget.onOpenExternal != null)
                  OutlinedButton(
                    onPressed: widget.onOpenExternal,
                    child: const Text('Ouvrir dans le navigateur'),
                  ),
              ]),
            ]),
          ),
        // Barre d'outils discrète
        Positioned(
          right: 6,
          top: 6,
          child: Row(children: [
            if (_blocked > 0)
              Container(
                margin: const EdgeInsets.only(right: 6),
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(children: [
                  const Icon(Icons.shield_rounded, size: 12, color: AppColors.success),
                  const SizedBox(width: 3),
                  Text(
                    '$_blocked pub${_blocked > 1 ? 's' : ''} bloquée${_blocked > 1 ? 's' : ''}',
                    style: const TextStyle(fontSize: 10),
                  ),
                ]),
              ),
            _MiniBtn(
              icon: Icons.refresh_rounded,
              tooltip: 'Recharger',
              onTap: () {
                setState(() => _error = false);
                _ctrl?.reload();
              },
            ),
            const SizedBox(width: 4),
            _MiniBtn(
              icon: widget.isFullscreen
                  ? Icons.fullscreen_exit_rounded
                  : Icons.fullscreen_rounded,
              tooltip: 'Plein écran',
              onTap: widget.onToggleFullscreen,
            ),
          ]),
        ),
      ],
    );

    if (widget.isFullscreen) return ColoredBox(color: Colors.black, child: player);
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: ColoredBox(color: Colors.black, child: player),
    );
  }

  void _countBlocked() {
    if (!mounted) return;
    setState(() => _blocked++);
  }
}

class _MiniBtn extends StatelessWidget {
  const _MiniBtn({required this.icon, required this.onTap, required this.tooltip});
  final IconData icon;
  final VoidCallback onTap;
  final String tooltip;
  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.black54,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(icon, size: 18, color: Colors.white),
        ),
      ),
    );
  }
}
