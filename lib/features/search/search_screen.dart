import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/widgets/common.dart';

/// Recherche instantanée — même endpoint que la barre du site
/// (POST /template-php/defaut/fetch.php, débounce 180 ms).
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  String _query = '';

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 180), () {
      if (mounted) setState(() => _query = v.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = _query.isEmpty
        ? null
        : ref.watch(searchProvider(_query));
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: TextField(
          controller: _ctrl,
          autofocus: true,
          textInputAction: TextInputAction.search,
          onChanged: _onChanged,
          onSubmitted: (v) {
            // Entrée → ouvre le premier résultat (comme le site)
            final r = results?.asData?.value;
            if (r != null && r.isNotEmpty) context.push('/anime/${r.first.slug}');
          },
          decoration: InputDecoration(
            hintText: 'Rechercher…',
            prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textDim),
            suffixIcon: _ctrl.text.isEmpty
                ? null
                : IconButton(
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () {
                      _ctrl.clear();
                      setState(() => _query = '');
                    },
                  ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
        ),
      ),
      body: results == null
          ? const EmptyView(
              icon: Icons.manage_search_rounded,
              title: 'Recherchez un anime ou un scan',
              subtitle: 'Titre original, français ou alternatif.',
            )
          : results.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(
                message: e.toString(),
                onRetry: () => ref.invalidate(searchProvider(_query)),
              ),
              data: (list) => list.isEmpty
                  ? EmptyView(
                      icon: Icons.search_off_rounded,
                      title: 'Aucun résultat pour « $_query »',
                      actionLabel: 'Chercher dans le catalogue',
                      onAction: () {
                        ref
                            .read(catalogueProvider.notifier)
                            .setFilters(ref.read(catalogueProvider).filters.copyWith(search: _query));
                        context.go('/catalogue');
                      },
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: list.length,
                      separatorBuilder: (_, _) => const Divider(height: 1, indent: 84),
                      itemBuilder: (_, i) {
                        final r = list[i];
                        return ListTile(
                          onTap: () => context.push('/anime/${r.slug}'),
                          leading: NetImage(r.image,
                              width: 52, height: 72,
                              borderRadius: BorderRadius.circular(6)),
                          title: Text(r.title,
                              style: const TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: r.subtitle.isEmpty
                              ? null
                              : Text(r.subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                      color: AppColors.textDim, fontSize: 12)),
                          trailing: const Icon(Icons.chevron_right_rounded,
                              color: AppColors.textDim),
                        );
                      },
                    ),
            ),
    );
  }
}
