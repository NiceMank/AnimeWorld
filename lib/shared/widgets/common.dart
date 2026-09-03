import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/constants/app_constants.dart';
import '../../core/router.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/models.dart';

/// Image réseau avec cache, shimmer et fallback CDN (jsDelivr → raw GitHub).
class NetImage extends StatelessWidget {
  const NetImage(
    this.url, {
    super.key,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.borderRadius,
  });
  final String url;
  final BoxFit fit;
  final double? width;
  final double? height;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    Widget img = url.isEmpty
        ? _placeholder()
        : CachedNetworkImage(
            imageUrl: url,
            fit: fit,
            width: width,
            height: height,
            httpHeaders: const {'User-Agent': AppConstants.userAgent},
            placeholder: (_, _) => _shimmer(),
            errorWidget: (_, _, _) {
              if (url.startsWith(AppConstants.cdnBase)) {
                return CachedNetworkImage(
                  imageUrl: url.replaceFirst(
                    AppConstants.cdnBase,
                    AppConstants.cdnFallback,
                  ),
                  fit: fit,
                  width: width,
                  height: height,
                  errorWidget: (_, _, _) => _placeholder(),
                );
              }
              return _placeholder();
            },
          );
    if (borderRadius != null) {
      img = ClipRRect(borderRadius: borderRadius!, child: img);
    }
    return img;
  }

  Widget _shimmer() => Shimmer.fromColors(
        baseColor: AppColors.surface,
        highlightColor: AppColors.surface2,
        child: Container(width: width, height: height, color: AppColors.surface),
      );

  Widget _placeholder() => Container(
        width: width,
        height: height,
        color: AppColors.surface,
        alignment: Alignment.center,
        child: const Icon(Icons.image_not_supported_outlined,
            color: AppColors.textDim),
      );
}

/// Petit drapeau (CDN du site).
class FlagIcon extends StatelessWidget {
  const FlagIcon(this.code, {super.key, this.width = 20});
  final String code; // jp, fr, en… ou libellé VOSTFR/VF…
  final double width;

  static String codeFromLabel(String label) {
    final l = label.toUpperCase();
    if (l.startsWith('VF') || l == 'FR') return 'fr';
    if (l == 'VA' || l == 'VASTFR' || l == 'EN') return 'en';
    if (l == 'VKR' || l == 'KR') return 'kr';
    if (l == 'VCN' || l == 'CN') return 'cn';
    if (l == 'VAR' || l == 'AR') return 'ar';
    if (l == 'VQC') return 'qc';
    if (l == 'JP' || l == 'VOSTFR' || l == 'VO' || l == 'VJ') return 'jp';
    return label.toLowerCase();
  }

  @override
  Widget build(BuildContext context) {
    final c = code.length <= 2 && code == code.toLowerCase()
        ? code
        : codeFromLabel(code);
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: NetImage(AppConstants.flag(c), width: width, height: width * 0.7),
    );
  }
}

/// Badge type (Anime / Scans / Film…)
class TypeBadge extends StatelessWidget {
  const TypeBadge(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) {
    if (text.isEmpty) return const SizedBox.shrink();
    final scan = text.toLowerCase().contains('scan') ||
        text.toLowerCase().contains('webtoon') ||
        text.toLowerCase().contains('manga');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: (scan ? const Color(0xFF7C3AED) : AppColors.accent)
            .withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: const TextStyle(
            fontSize: 10, fontWeight: FontWeight.w800, color: Colors.white),
      ),
    );
  }
}

/// Carte affiche portrait (catalogue, classiques, pépites, similaires…)
class PosterCard extends StatelessWidget {
  const PosterCard({
    super.key,
    required this.title,
    required this.image,
    required this.onTap,
    this.subtitle,
    this.badge,
    this.lang,
    this.time,
    this.width = 120,
    this.progress,
    this.footer,
  });

  final String title;
  final String image;
  final VoidCallback onTap;
  final String? subtitle;
  final String? badge;
  final String? lang;
  final String? time;
  final double width;
  final double? progress;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AspectRatio(
              aspectRatio: 2 / 3,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    NetImage(image),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      height: 60,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withValues(alpha: 0.75)
                            ],
                          ),
                        ),
                      ),
                    ),
                    if (badge != null && badge!.isNotEmpty)
                      Positioned(top: 6, left: 6, child: TypeBadge(badge!)),
                    if (lang != null && lang!.isNotEmpty)
                      Positioned(top: 6, right: 6, child: FlagIcon(lang!, width: 22)),
                    if (progress != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: progress!.clamp(0.02, 1),
                          minHeight: 3,
                          backgroundColor: Colors.white24,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              title.toUpperCase(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 11.5, fontWeight: FontWeight.w700, height: 1.2),
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.play_circle_outline,
                    size: 12, color: AppColors.textDim),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 10.5, color: AppColors.textMuted)),
                ),
              ]),
            ],
            if (time != null && time!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Row(children: [
                const Icon(Icons.schedule, size: 12, color: AppColors.textDim),
                const SizedBox(width: 3),
                Expanded(
                  child: Text(time!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10.5, color: AppColors.textDim)),
                ),
              ]),
            ],
            ?footer,
          ],
        ),
      ),
    );
  }
}

/// Ligne horizontale de cartes.
class HorizontalCards extends StatelessWidget {
  const HorizontalCards({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
    this.height = 258,
  });
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: itemCount,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: itemBuilder,
      ),
    );
  }
}

/// Carte catalogue prête à l'emploi.
class CatalogueCard extends StatelessWidget {
  const CatalogueCard(this.item, {super.key, this.width = 120});
  final CatalogueItem item;
  final double width;
  @override
  Widget build(BuildContext context) {
    return PosterCard(
      title: item.title,
      image: item.image,
      width: width,
      onTap: () => context.push('/anime/${item.slug}'),
      footer: item.types.isEmpty && item.langs.isEmpty
          ? null
          : Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Row(children: [
                Expanded(
                  child: Text(item.types.join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 10, color: AppColors.textDim)),
                ),
                for (final l in item.langs.take(3)) ...[
                  const SizedBox(width: 3),
                  FlagIcon(l, width: 14),
                ],
              ]),
            ),
    );
  }
}

/// Carte « sortie » (épisode / scan ajouté, planning).
class ReleaseCard extends StatelessWidget {
  const ReleaseCard(this.item, {super.key, this.width = 120, this.showTime = true});
  final ReleaseItem item;
  final double width;
  final bool showTime;
  @override
  Widget build(BuildContext context) {
    return PosterCard(
      title: item.title,
      image: item.image,
      width: width,
      badge: item.badge,
      lang: item.lang,
      subtitle: item.info,
      time: showTime ? item.time : null,
      onTap: () => openSitePath(context, item.path),
    );
  }
}

/// État d'erreur avec bouton réessayer.
class ErrorView extends StatelessWidget {
  const ErrorView({super.key, required this.message, this.onRetry});
  final String message;
  final VoidCallback? onRetry;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, size: 56, color: AppColors.textDim),
            const SizedBox(height: 14),
            const Text('Oups…',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 6),
            Text(
              _friendly(message),
              textAlign: TextAlign.center,
              style: const TextStyle(color: AppColors.textMuted),
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 18),
              ElevatedButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Réessayer'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  static String _friendly(String m) {
    final l = m.toLowerCase();
    if (l.contains('socket') || l.contains('connection') || l.contains('timeout')) {
      return 'Pas de connexion ou serveur injoignable. Vérifiez votre réseau (ou le domaine dans Profil › Paramètres).';
    }
    return m.replaceFirst('Exception: ', '');
  }
}

class EmptyView extends StatelessWidget {
  const EmptyView({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: AppColors.textDim),
            const SizedBox(height: 14),
            Text(title,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textMuted)),
            ],
            if (onAction != null) ...[
              const SizedBox(height: 18),
              ElevatedButton(onPressed: onAction, child: Text(actionLabel ?? 'OK')),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shimmer de ligne de cartes pendant le chargement.
class RowShimmer extends StatelessWidget {
  const RowShimmer({super.key, this.height = 258});
  final double height;
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Shimmer.fromColors(
        baseColor: AppColors.surface,
        highlightColor: AppColors.surface2,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: 5,
          separatorBuilder: (_, _) => const SizedBox(width: 10),
          itemBuilder: (_, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 120,
                height: 180,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(height: 8),
              Container(width: 100, height: 10, color: AppColors.surface),
              const SizedBox(height: 6),
              Container(width: 70, height: 10, color: AppColors.surface),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bouton pilule avec drapeau (sélecteur de langue VO/VF…).
class LangPill extends StatelessWidget {
  const LangPill({
    super.key,
    required this.label,
    required this.flag,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String flag;
  final bool selected;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: selected ? 1 : 0.55,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent.withValues(alpha: 0.18) : AppColors.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.accent : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            FlagIcon(flag, width: 22),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12)),
          ]),
        ),
      ),
    );
  }
}

void showSnack(
  BuildContext context,
  String msg, {
  bool error = false,
  String? actionLabel,
  VoidCallback? onAction,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.danger : AppColors.surface2,
      duration: actionLabel != null
          ? const Duration(seconds: 6)
          : const Duration(seconds: 3),
      action: actionLabel != null
          ? SnackBarAction(label: actionLabel, onPressed: onAction ?? () {})
          : null,
    ));
}
