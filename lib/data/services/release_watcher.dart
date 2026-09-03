import '../models/models.dart';

// ---------------------------------------------------------------------------
// Diff « temps réel » des notifications (logique pure, testée hors ligne)
// ---------------------------------------------------------------------------

/// Compare les sorties actuelles du site avec les signatures déjà vues et
/// produit les nouvelles notifications.
///
/// Une sortie est identifiée par `{chemin}::{libellé}` : une même page
/// (ex. /catalogue/x/saison1/vostfr/) génère une notification par nouvel
/// épisode ou chapitre (« Saison 1 Episode 9 », « Chapitre 34 »…).
class ReleaseDiff {
  ReleaseDiff._();

  static String signatureOf(ReleaseItem r) => '${r.path}::${r.info}';

  /// [known] = signatures déjà enregistrées.
  /// [baseline] = première vérification : on enregistre tout sans notifier
  /// (évite de spammer 30+ notifications à l'installation).
  /// [filter] = filtre canaux/périmètre (épisodes, scans, bibliothèque…).
  /// [maxNew] = garde-fou anti-spam par vérification.
  static DiffResult compute({
    required List<ReleaseItem> releases,
    required Set<String> known,
    required bool baseline,
    required bool Function(ReleaseItem) filter,
    int maxNew = 20,
  }) {
    final fresh = <AppNotification>[];
    final allKeys = <String>{};

    for (final r in releases) {
      final sig = signatureOf(r);
      allKeys.add(sig);
      if (baseline || known.contains(sig)) continue;
      if (!filter(r)) continue;
      if (fresh.any((n) => n.id == sig)) continue;
      fresh.add(AppNotification(
        id: sig,
        title: r.title,
        body: _bodyFor(r),
        path: r.path,
        image: r.image,
        kind: r.isScan ? 'scan' : 'episode',
        lang: r.lang,
        at: r.releaseTs != null && r.releaseTs! > 0
            ? DateTime.fromMillisecondsSinceEpoch(r.releaseTs! * 1000)
            : DateTime.now(),
      ));
      if (fresh.length >= maxNew) break;
    }

    return DiffResult(notifications: fresh, allKeys: allKeys);
  }

  static String _bodyFor(ReleaseItem r) {
    final label = r.info.isEmpty ? 'Nouvelle sortie' : r.info;
    return r.lang.isNotEmpty
        ? '$label (${r.lang}) est disponible'
        : '$label est disponible';
  }
}

class DiffResult {
  final List<AppNotification> notifications;
  final Set<String> allKeys;
  const DiffResult({required this.notifications, required this.allKeys});
}
