// Tests hors ligne de la logique de diff des notifications temps réel
// (ReleaseDiff) et du modèle AppNotification.
import 'package:flutter_test/flutter_test.dart';

import 'package:animeworld/data/models/models.dart';
import 'package:animeworld/data/services/release_watcher.dart';

ReleaseItem _ep(
  String slug, {
  String season = 'saison1',
  String lang = 'vostfr',
  String info = 'Saison 1 Episode 1',
  bool isScan = false,
}) =>
    ReleaseItem(
      path: '/catalogue/$slug/$season/$lang/',
      slug: slug,
      title: slug,
      image: 'https://cdn.example.com/$slug.jpg',
      badge: isScan ? 'Scans' : 'Anime',
      lang: lang.toUpperCase(),
      info: info,
    );

void main() {
  group('ReleaseDiff.compute', () {
    test('première vérification = baseline silencieuse (aucune notification)',
        () {
      final res = ReleaseDiff.compute(
        releases: [_ep('one-piece'), _ep('kaiju-no-8')],
        known: const {},
        baseline: true,
        filter: (_) => true,
      );
      expect(res.notifications, isEmpty);
      expect(res.allKeys, hasLength(2));
      expect(
        res.allKeys.first,
        '/catalogue/one-piece/saison1/vostfr/::Saison 1 Episode 1',
      );
    });

    test('détection d\'une nouvelle sortie après baseline', () {
      final first = ReleaseDiff.compute(
        releases: [_ep('one-piece', info: 'Saison 1 Episode 10')],
        known: const {},
        baseline: true,
        filter: (_) => true,
      );
      final second = ReleaseDiff.compute(
        releases: [
          _ep('one-piece', info: 'Saison 1 Episode 10'),
          _ep('one-piece', info: 'Saison 1 Episode 11'),
        ],
        known: first.allKeys,
        baseline: false,
        filter: (_) => true,
      );
      expect(second.notifications, hasLength(1));
      final n = second.notifications.single;
      expect(n.title, 'one-piece');
      expect(n.body, contains('Saison 1 Episode 11'));
      expect(n.body, contains('(VOSTFR)'));
      expect(n.kind, 'episode');
      expect(n.path, '/catalogue/one-piece/saison1/vostfr/');
      expect(n.read, isFalse);
    });

    test('déduplication : rien de nouveau si rien n\'a changé', () {
      const known = {
        '/catalogue/one-piece/saison1/vostfr/::Saison 1 Episode 10',
      };
      final res = ReleaseDiff.compute(
        releases: [_ep('one-piece', info: 'Saison 1 Episode 10')],
        known: known,
        baseline: false,
        filter: (_) => true,
      );
      expect(res.notifications, isEmpty);
    });

    test('nouvelle saison = nouvelle notification (chemin différent)', () {
      final res = ReleaseDiff.compute(
        releases: [
          _ep('one-piece', info: 'Saison 1 Episode 10'),
          _ep('one-piece', season: 'saison2', info: 'Saison 2 Episode 1'),
        ],
        known: {'/catalogue/one-piece/saison1/vostfr/::Saison 1 Episode 10'},
        baseline: false,
        filter: (_) => true,
      );
      expect(res.notifications, hasLength(1));
      expect(res.notifications.single.path, contains('saison2'));
    });

    test('filtre canaux : scans désactivés', () {
      final res = ReleaseDiff.compute(
        releases: [
          _ep('one-piece', isScan: true, info: 'Chapitre 1157'),
          _ep('kaiju-no-8', info: 'Saison 2 Episode 9'),
        ],
        known: const {},
        baseline: false,
        filter: (r) => !r.isScan, // canal scans désactivé
      );
      expect(res.notifications, hasLength(1));
      expect(res.notifications.single.kind, 'episode');
      // Les scans restent enregistrés comme vus même s'ils sont filtrés.
      expect(res.allKeys.length, 2);
    });

    test('filtre périmètre : œuvre non suivie', () {
      final res = ReleaseDiff.compute(
        releases: [
          _ep('inconnu'),
          _ep('one-piece'),
        ],
        known: const {},
        baseline: false,
        filter: (r) => r.slug == 'one-piece',
      );
      expect(res.notifications, hasLength(1));
      expect(res.notifications.single.title, 'one-piece');
    });

    test('garde-fou anti-spam (maxNew)', () {
      final releases =
          List.generate(50, (i) => _ep('anime-$i', info: 'Episode ${i + 1}'));
      final res = ReleaseDiff.compute(
        releases: releases,
        known: const {},
        baseline: false,
        filter: (_) => true,
      );
      expect(res.notifications, hasLength(20));
    });

    test('horodatage depuis data-release-ts', () {
      final res = ReleaseDiff.compute(
        releases: [
          ReleaseItem(
            path: '/catalogue/x/saison1/vostfr/',
            slug: 'x',
            title: 'X',
            image: 'https://cdn.example.com/x.jpg',
            info: 'Saison 1 Episode 2',
            releaseTs: 1788000000,
          ),
        ],
        known: const {},
        baseline: false,
        filter: (_) => true,
      );
      expect(
        res.notifications.single.at.toUtc(),
        DateTime.fromMillisecondsSinceEpoch(1788000000 * 1000, isUtc: true),
      );
    });

    test('le kind reflète les scans', () {
      final res = ReleaseDiff.compute(
        releases: [_ep('one-piece', isScan: true, info: 'Chapitre 1157')],
        known: const {},
        baseline: false,
        filter: (_) => true,
      );
      expect(res.notifications.single.kind, 'scan');
      expect(res.notifications.single.body, contains('Chapitre 1157'));
    });
  });

  group('AppNotification (sérialisation)', () {
    test('roundtrip JSON', () {
      final n = AppNotification(
        id: '/catalogue/x/saison1/vostfr/::Saison 1 Episode 3',
        title: 'X',
        body: 'Saison 1 Episode 3 (VOSTFR) est disponible',
        path: '/catalogue/x/saison1/vostfr/',
        image: 'https://cdn.example.com/x.jpg',
        kind: 'episode',
        lang: 'VOSTFR',
        at: DateTime(2026, 9, 3, 10),
      );
      final back = AppNotification.fromJson(n.toJson());
      expect(back.id, n.id);
      expect(back.title, n.title);
      expect(back.body, n.body);
      expect(back.path, n.path);
      expect(back.kind, n.kind);
      expect(back.lang, n.lang);
      expect(back.read, isFalse);
      expect(back.at.toIso8601String(), n.at.toIso8601String());
    });

    test('copyWith(read: true)', () {
      final n = AppNotification(
        id: 'a',
        title: 'T',
        body: 'B',
        path: '/p',
        image: '',
        kind: 'episode',
        lang: 'VF',
        at: DateTime(2026, 9, 3, 10),
      );
      expect(n.copyWith(read: true).read, isTrue);
      expect(n.read, isFalse);
    });
  });
}
