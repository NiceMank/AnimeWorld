import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/constants/app_constants.dart';
import '../../core/theme/app_theme.dart';

class _Faq {
  final String q;
  final String a;
  const _Faq(this.q, this.a);
}

/// Contenu repris de /aide (« Problèmes récurrents ») adapté à l'application.
const _faqs = [
  _Faq(
    'Vidéo indisponible ou « Video playback error »',
    'Certains opérateurs bloquent le lecteur 1. Changez de lecteur dans le menu « Lecteur » '
    '(Lecteur 2, 3…), essayez la 4G/5G au lieu du Wi-Fi ou utilisez un VPN. Le problème vient '
    'de l\'hébergeur vidéo, pas de l\'application.',
  ),
  _Faq(
    'Une pub s\'ouvre quand je touche le lecteur',
    'Les lecteurs tiers contiennent des pop-ups. AnimeWorld bloque les fenêtres externes et les '
    'domaines publicitaires connus (compteur « pubs bloquées » en haut du lecteur). Si une pub '
    'passe quand même, touchez à nouveau le bouton lecture ou changez de lecteur.',
  ),
  _Faq(
    'Les épisodes ne s\'affichent pas avec un VPN',
    'Avec NordVPN, désactivez la protection contre les menaces (Threat Protection) qui bloque '
    'certains hébergeurs vidéo. Avec d\'autres VPN, changez de serveur.',
  ),
  _Faq(
    'Problème avec un épisode ou un chapitre',
    'Essayez d\'abord un autre lecteur (ou une autre langue). Pour les scans, tirez vers le bas '
    'pour recharger ou basculez entre les modes Scroll et Page par page.',
  ),
  _Faq(
    'Le contenu ne charge plus du tout',
    'Le site change parfois de nom de domaine (.to, .org, .fr). Allez dans Profil › Domaine du '
    'site et saisissez le nouveau domaine. Vérifiez aussi votre connexion.',
  ),
  _Faq(
    'Ma progression n\'est pas synchronisée',
    'La synchronisation nécessite un compte (Profil › Se connecter). Sans compte, tout reste '
    'enregistré sur cet appareil. Utilisez « Synchroniser » pour forcer l\'envoi.',
  ),
  _Faq(
    'Confidentialité',
    'AnimeWorld ne collecte aucune donnée personnelle. Les listes et la progression sont '
    'stockées localement et, si vous vous connectez, sur votre compte anime-sama uniquement.',
  ),
  _Faq(
    'DMCA',
    'AnimeWorld n\'héberge aucun contenu : l\'application affiche les mêmes sources que le site '
    'anime-sama (lecteurs vidéo tiers et images de scans). Pour toute réclamation, contactez '
    'directement le site.',
  ),
];

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(title: const Text('AIDE')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          const Text(
            'Vous trouverez ici une liste de solutions aux problèmes les plus fréquents.',
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          for (final f in _faqs)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              decoration: BoxDecoration(
                color: AppColors.surface.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.border),
              ),
              child: Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  title: Text(f.q,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                  iconColor: AppColors.accent,
                  collapsedIconColor: AppColors.textDim,
                  childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                  children: [
                    Text(f.a,
                        style: const TextStyle(
                            color: AppColors.textMuted, height: 1.5, fontSize: 13)),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => launchUrl(Uri.parse('${AppConstants.defaultBaseUrl}/aide'),
                mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.open_in_new_rounded),
            label: const Text('Page d\'aide complète du site'),
          ),
        ],
      ),
    );
  }
}
