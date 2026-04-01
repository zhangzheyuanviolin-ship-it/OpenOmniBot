import 'dart:io';
import 'dart:ui';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:ui/services/app_background_service.dart';

enum BackgroundPreviewKind { chat, workspace }

class AppBackgroundLayer extends StatelessWidget {
  final AppBackgroundConfig config;
  final Color fallbackColor;
  final Key? layerKey;
  final bool showLoadFailureOverlay;

  const AppBackgroundLayer({
    super.key,
    required this.config,
    this.fallbackColor = const Color(0xFFF9FCFF),
    this.layerKey,
    this.showLoadFailureOverlay = false,
  });

  @override
  Widget build(BuildContext context) {
    final alignment = Alignment(config.focalX, config.focalY);
    final image = _buildImage(alignment);

    return Stack(
      key: layerKey,
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            color: fallbackColor,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                fallbackColor,
                Color.lerp(fallbackColor, Colors.white, 0.35)!,
              ],
            ),
          ),
        ),
        if (image != null) image,
        if (config.isActive) _buildMaskLayer(),
      ],
    );
  }

  Widget _buildMaskLayer() {
    final whiteMaskOpacity = _whiteMaskOpacity();
    final darkMaskOpacity = _darkMaskOpacity();
    final blurSigma = config.blurSigma.clamp(0, 24).toDouble();
    final whiteMask = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(
              alpha: (whiteMaskOpacity + 0.04).clamp(0.0, 0.85),
            ),
            const Color(0xFFF6FAFF).withValues(alpha: whiteMaskOpacity),
            const Color(
              0xFFEDF4FF,
            ).withValues(alpha: (whiteMaskOpacity * 0.9).clamp(0.0, 0.8)),
          ],
        ),
      ),
    );

    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (blurSigma > 0)
            BackdropFilter(
              filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
              child: whiteMask,
            )
          else
            whiteMask,
          if (darkMaskOpacity > 0)
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: darkMaskOpacity),
              ),
            ),
        ],
      ),
    );
  }

  Widget? _buildImage(Alignment alignment) {
    if (!config.isActive) {
      return null;
    }
    switch (config.sourceType) {
      case AppBackgroundSourceType.local:
        final file = File(config.localImagePath);
        if (!file.existsSync()) {
          return null;
        }
        return Image.file(
          file,
          fit: BoxFit.cover,
          alignment: alignment,
          errorBuilder: (_, __, ___) => const SizedBox.shrink(),
        );
      case AppBackgroundSourceType.remote:
        final imageUrl = config.remoteImageUrl.trim();
        if (imageUrl.isEmpty) {
          return null;
        }
        return CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          alignment: alignment,
          placeholder: (_, __) => const SizedBox.expand(),
          errorWidget: (_, __, ___) => showLoadFailureOverlay
              ? const _BackgroundLoadFailurePlaceholder()
              : const SizedBox.shrink(),
        );
      case AppBackgroundSourceType.none:
        return null;
    }
  }

  double _whiteMaskOpacity() {
    final lightenBoost = ((config.brightness - 1).clamp(0.0, 0.5) / 0.5) * 0.18;
    return (0.14 + config.frostOpacity + lightenBoost).clamp(0.12, 0.78);
  }

  double _darkMaskOpacity() {
    return (((1 - config.brightness).clamp(0.0, 0.5)) / 0.5 * 0.24).clamp(
      0.0,
      0.24,
    );
  }
}

class AppBackgroundPreview extends StatelessWidget {
  final AppBackgroundConfig config;
  final BackgroundPreviewKind kind;
  final ValueChanged<Offset>? onFocalPointChanged;
  final bool showDragHint;

  const AppBackgroundPreview({
    super.key,
    required this.config,
    required this.kind,
    this.onFocalPointChanged,
    this.showDragHint = false,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: AspectRatio(
        aspectRatio: 0.68,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final previewContent = Stack(
              fit: StackFit.expand,
              children: [
                AppBackgroundLayer(
                  config: config,
                  fallbackColor: const Color(0xFFF9FCFF),
                  layerKey: ValueKey('app-background-preview-${kind.name}'),
                  showLoadFailureOverlay: true,
                ),
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: kind == BackgroundPreviewKind.chat
                      ? const _ChatPreviewChrome()
                      : const _WorkspacePreviewChrome(),
                ),
                if (showDragHint && config.hasResolvedImage)
                  Positioned(
                    left: 12,
                    bottom: 12,
                    child: IgnorePointer(
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.54),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: const Text(
                          '拖动预览移动图片',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );

            if (onFocalPointChanged == null) {
              return previewContent;
            }

            return GestureDetector(
              key: ValueKey('app-background-preview-drag-${kind.name}'),
              behavior: HitTestBehavior.opaque,
              onPanDown: (details) {
                onFocalPointChanged!(
                  _normalizedOffsetForPosition(
                    details.localPosition,
                    constraints.biggest,
                  ),
                );
              },
              onPanUpdate: (details) {
                onFocalPointChanged!(
                  _normalizedOffsetForPosition(
                    details.localPosition,
                    constraints.biggest,
                  ),
                );
              },
              child: previewContent,
            );
          },
        ),
      ),
    );
  }

  Offset _normalizedOffsetForPosition(Offset localPosition, Size size) {
    if (size.width <= 0 || size.height <= 0) {
      return const Offset(0, 0);
    }
    final normalizedX = ((localPosition.dx / size.width) * 2 - 1)
        .clamp(-1.0, 1.0)
        .toDouble();
    final normalizedY = ((localPosition.dy / size.height) * 2 - 1)
        .clamp(-1.0, 1.0)
        .toDouble();
    return Offset(normalizedX, normalizedY);
  }
}

Color backgroundSurfaceColor({
  required bool translucent,
  double opacity = 0.78,
}) {
  return translucent ? Colors.white.withValues(alpha: opacity) : Colors.white;
}

class _ChatPreviewChrome extends StatelessWidget {
  const _ChatPreviewChrome();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 54,
          decoration: BoxDecoration(
            color: backgroundSurfaceColor(translucent: true, opacity: 0.72),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0x66D9E6FB)),
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: Column(
            children: [
              const _PreviewMessageCard(
                alignment: Alignment.centerLeft,
                widthFactor: 0.66,
              ),
              const SizedBox(height: 14),
              const _PreviewMessageCard(
                alignment: Alignment.centerRight,
                widthFactor: 0.52,
              ),
              const Spacer(),
              Container(
                height: 64,
                decoration: BoxDecoration(
                  color: backgroundSurfaceColor(
                    translucent: true,
                    opacity: 0.76,
                  ),
                  borderRadius: BorderRadius.circular(22),
                  border: Border.all(color: const Color(0x55D7E2F4)),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _WorkspacePreviewChrome extends StatelessWidget {
  const _WorkspacePreviewChrome();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 48,
          decoration: BoxDecoration(
            color: backgroundSurfaceColor(translucent: true, opacity: 0.74),
            borderRadius: BorderRadius.circular(16),
          ),
        ),
        const SizedBox(height: 18),
        Expanded(
          child: Column(
            children: List.generate(5, (index) {
              return Padding(
                padding: EdgeInsets.only(bottom: index == 4 ? 0 : 10),
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    color: backgroundSurfaceColor(
                      translucent: true,
                      opacity: 0.7 + index * 0.02,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}

class _PreviewMessageCard extends StatelessWidget {
  final Alignment alignment;
  final double widthFactor;

  const _PreviewMessageCard({
    required this.alignment,
    required this.widthFactor,
  });

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: alignment,
      child: FractionallySizedBox(
        widthFactor: widthFactor,
        child: Container(
          height: 62,
          decoration: BoxDecoration(
            color: backgroundSurfaceColor(translucent: true, opacity: 0.78),
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }
}

class _BackgroundLoadFailurePlaceholder extends StatelessWidget {
  const _BackgroundLoadFailurePlaceholder();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.58),
          borderRadius: BorderRadius.circular(999),
        ),
        child: const Text(
          '图片加载失败',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
