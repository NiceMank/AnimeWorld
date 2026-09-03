import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../core/router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';
import '../../features/notifications/notifications_screen.dart';
import '../../shared/widgets/common.dart';

/// Planning hebdomadaire — /planning (7 jours + œuvres sans jour fixe),
/// filtres Tous / Animes / Scans / VO / VF + recherche (côté client, comme le site).
class PlanningScreen extends ConsumerStatefulWidget {
  const PlanningScreen({super.key});
  @override
  ConsumerState<PlanningScreen> createState() => _PlanningScreenState();
}

class _PlanningScreenState extends ConsumerState<PlanningScreen>
    with SingleTickerProviderStateMixin {
  TabController? _tabs;
  String _type = 'all'; // all | Anime | Scan
  String _lang = 'all'; // all | VOSTFR | VF
  String _q = '';
  Timer? _clock;
  String _now = '';

  @override
  void initState() {
    super.initState();
    _tick();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!mounted) return;
    setState(() => _now = DateFormat('HH:mm:ss').format(DateTime.now()));
  }

  @override
  void dispose() {
    _clock?.cancel();
    _tabs?.dispose();
    super.dispose();
  }

  bool _match(ReleaseItem it) {
    if (_type == 'Anime' && it.isScan) return false;
    if (_type == 'Scan' && !it.isScan) return false;
    if (_lang == 'VF' && !it.lang.toUpperCase().startsWith('VF')) return false;
    if (_lang == 'VOSTFR' && it.lang.toUpperCase().startsWith('VF')) return false;
    if (_q.isNotEmpty && !it.title.toLowerCase().contains(_q.toLowerCase())) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final planning = ref.watch(planningProvider);
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: const Text('PLANNING'),
        actions: [
          const NotificationBellButton(),
          Container(
            margin: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.border),
            ),
            child: Text(_now,
                style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontFeatures: [FontFeature.tabularFigures()])),
          ),
        ],
      ),
      body: planning.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(planningProvider),
        ),
        data: (p) {
          if (p.days.isEmpty) {
            return const EmptyView(
                icon: Icons.event_busy_rounded, title: 'Planning indisponible');
          }
          final todayIdx = p.days.indexWhere((d) => d.isToday);
          if (_tabs != null && _tabs!.length != p.days.length) {
            _tabs!.dispose();
            _tabs = null;
          }
          _tabs ??= TabController(
            length: p.days.length,
            vsync: this,
            initialIndex: todayIdx < 0 ? 0 : todayIdx,
          );
          return Column(children: [
            TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelPadding: const EdgeInsets.symmetric(horizontal: 12),
              tabs: [
                for (final d in p.days)
                  Tab(
                    height: 48,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(d.name.substring(0, 3).toUpperCase(),
                            style: const TextStyle(fontSize: 12)),
                        Text(d.date,
                            style: TextStyle(
                                fontSize: 11,
                                fontWeight: d.isToday ? FontWeight.w900 : FontWeight.w500,
                                color: d.isToday ? AppColors.accent : AppColors.textDim)),
                      ],
                    ),
                  ),
              ],
            ),
            _Filters(
              type: _type,
              lang: _lang,
              onType: (v) => setState(() => _type = v),
              onLang: (v) => setState(() => _lang = v),
              onQuery: (v) => setState(() => _q = v),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  for (final d in p.days)
                    _DayList(
                      day: d,
                      items: d.items.where(_match).toList(),
                      noFixed: p.noFixedDay.where(_match).toList(),
                      onRefresh: () async {
                        ref.read(animeRepositoryProvider).clearCaches();
                        ref.invalidate(planningProvider);
                        await ref.read(planningProvider.future);
                      },
                    ),
                ],
              ),
            ),
          ]);
        },
      ),
    );
  }
}

class _Filters extends StatelessWidget {
  const _Filters({
    required this.type,
    required this.lang,
    required this.onType,
    required this.onLang,
    required this.onQuery,
  });
  final String type;
  final String lang;
  final ValueChanged<String> onType;
  final ValueChanged<String> onLang;
  final ValueChanged<String> onQuery;

  @override
  Widget build(BuildContext context) {
    Widget chip(String label, bool sel, VoidCallback on, {Widget? avatar}) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: FilterChip(
            label: Text(label),
            avatar: avatar,
            selected: sel,
            showCheckmark: false,
            onSelected: (_) => on(),
            visualDensity: VisualDensity.compact,
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(children: [
        Expanded(
          child: SizedBox(
            height: 36,
            child: ListView(scrollDirection: Axis.horizontal, children: [
              chip('Tous', type == 'all' && lang == 'all', () {
                onType('all');
                onLang('all');
              }),
              chip('Animes', type == 'Anime', () => onType(type == 'Anime' ? 'all' : 'Anime')),
              chip('Scans', type == 'Scan', () => onType(type == 'Scan' ? 'all' : 'Scan')),
              chip('VO', lang == 'VOSTFR', () => onLang(lang == 'VOSTFR' ? 'all' : 'VOSTFR'),
                  avatar: const FlagIcon('jp', width: 16)),
              chip('VF', lang == 'VF', () => onLang(lang == 'VF' ? 'all' : 'VF'),
                  avatar: const FlagIcon('fr', width: 16)),
            ]),
          ),
        ),
        SizedBox(
          width: 130,
          height: 36,
          child: TextField(
            onChanged: onQuery,
            decoration: const InputDecoration(
              hintText: 'Rechercher…',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              prefixIcon: Icon(Icons.search_rounded, size: 16),
              prefixIconConstraints: BoxConstraints(minWidth: 30),
            ),
            style: const TextStyle(fontSize: 12),
          ),
        ),
      ]),
    );
  }
}

class _DayList extends StatelessWidget {
  const _DayList({
    required this.day,
    required this.items,
    required this.noFixed,
    required this.onRefresh,
  });
  final PlanningDay day;
  final List<ReleaseItem> items;
  final List<ReleaseItem> noFixed;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: AppColors.accent,
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
            child: Text(
              'SORTIES DU ${day.name.toUpperCase()} - ${day.date}',
              style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 0.8),
            ),
          ),
          if (items.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Aucune sortie ce jour (avec ces filtres).',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textDim)),
            )
          else
            for (final it in items) _Row(item: it),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _Notice(
              'Le jour actuel est en surbrillance et le planning s\'actualise tous les lundis soir. '
              'La saison d\'une œuvre est terminée si elle ne figure plus sur le planning.',
            ),
          ),
          if (noFixed.isNotEmpty) ...[
            const SectionTitle('Œuvres en cours sans jours fixes'),
            HorizontalCards(
              height: 210,
              itemCount: noFixed.length,
              itemBuilder: (_, i) => ReleaseCard(noFixed[i], showTime: false),
            ),
          ],
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.item});
  final ReleaseItem item;
  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: () => openSitePath(context, item.path),
      leading: NetImage(item.image,
          width: 48, height: 68, borderRadius: BorderRadius.circular(6)),
      title: Text(item.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.5)),
      subtitle: Row(children: [
        TypeBadge(item.badge),
        const SizedBox(width: 6),
        if (item.lang.isNotEmpty) FlagIcon(item.lang, width: 16),
        const SizedBox(width: 6),
        Expanded(
          child: Text(item.info,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: AppColors.textDim)),
        ),
      ]),
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: item.problem
              ? AppColors.danger.withValues(alpha: 0.25)
              : AppColors.accent.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: item.problem ? AppColors.danger : AppColors.accent.withValues(alpha: 0.5)),
        ),
        child: Text(
          item.problem ? 'Reporté' : (item.time.isEmpty ? '—' : item.time),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
        ),
      ),
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.info_outline_rounded, size: 16, color: AppColors.accent),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: const TextStyle(fontSize: 12, color: AppColors.textMuted, height: 1.4)),
        ),
      ]),
    );
  }
}
