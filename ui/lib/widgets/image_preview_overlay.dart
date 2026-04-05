import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Represents the source of an image to preview.
sealed class ImagePreviewSource {}

class FileImageSource extends ImagePreviewSource {
  final String path;
  FileImageSource(this.path);
}

class NetworkImageSource extends ImagePreviewSource {
  final String url;
  NetworkImageSource(this.url);
}

class MemoryImageSource extends ImagePreviewSource {
  final Uint8List bytes;
  MemoryImageSource(this.bytes);
}

/// Lightweight full-screen image preview overlay with pinch-to-zoom and swipe.
///
/// Supports Hero-based zoom transition when [heroTag] is provided.
/// Wrap the source thumbnail in a [Hero] widget with the same tag.
class ImagePreviewOverlay {
  ImagePreviewOverlay._();

  /// Show preview for a single image.
  static Future<void> show(
    BuildContext context, {
    required ImagePreviewSource source,
    String? heroTag,
  }) {
    return showAll(
      context,
      sources: [source],
      initialIndex: 0,
      heroTag: heroTag,
    );
  }

  /// Show preview for multiple images with swipe navigation.
  static Future<void> showAll(
    BuildContext context, {
    required List<ImagePreviewSource> sources,
    int initialIndex = 0,
    String? heroTag,
  }) {
    assert(sources.isNotEmpty);
    return Navigator.of(context).push(
      _ImagePreviewRoute(
        sources: sources,
        initialIndex: initialIndex,
        heroTag: heroTag,
      ),
    );
  }
}

/// Custom route that supports Hero transitions with a transparent background.
class _ImagePreviewRoute extends PageRoute<void> {
  final List<ImagePreviewSource> sources;
  final int initialIndex;
  final String? heroTag;

  _ImagePreviewRoute({
    required this.sources,
    required this.initialIndex,
    this.heroTag,
  });

  @override
  bool get opaque => false;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 250);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return _ImagePreviewPage(
      sources: sources,
      initialIndex: initialIndex,
      heroTag: heroTag,
      animation: animation,
    );
  }
}

class _ImagePreviewPage extends StatefulWidget {
  final List<ImagePreviewSource> sources;
  final int initialIndex;
  final String? heroTag;
  final Animation<double> animation;

  const _ImagePreviewPage({
    required this.sources,
    required this.initialIndex,
    this.heroTag,
    required this.animation,
  });

  @override
  State<_ImagePreviewPage> createState() => _ImagePreviewPageState();
}

class _ImagePreviewPageState extends State<_ImagePreviewPage> {
  late final PageController _pageController;
  late int _currentIndex;
  bool _isZoomed = false;

  bool get _hasMultipleImages => widget.sources.length > 1;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _dismiss() => Navigator.of(context).pop();

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return AnimatedBuilder(
      animation: widget.animation,
      builder: (context, child) {
        return ColoredBox(
          color: Color.fromRGBO(0, 0, 0, 0.87 * widget.animation.value),
          child: child,
        );
      },
      child: Stack(
        children: [
          // Image page view (swipeable)
          PageView.builder(
            controller: _pageController,
            itemCount: widget.sources.length,
            physics: _isZoomed
                ? const NeverScrollableScrollPhysics()
                : const BouncingScrollPhysics(),
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemBuilder: (context, index) {
              // Only apply hero to the initially tapped image while it's visible
              final shouldHero = index == widget.initialIndex &&
                  _currentIndex == widget.initialIndex &&
                  widget.heroTag != null;
              return _InteractiveImagePage(
                source: widget.sources[index],
                onTap: _dismiss,
                onScaleChanged: (zoomed) {
                  if (_isZoomed != zoomed) setState(() => _isZoomed = zoomed);
                },
                heroTag: shouldHero ? widget.heroTag : null,
              );
            },
          ),

          // Page indicator
          if (_hasMultipleImages)
            Positioned(
              bottom: bottomPadding + 20,
              left: 0,
              right: 0,
              child: FadeTransition(
                opacity: widget.animation,
                child: _buildPageIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPageIndicator() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(widget.sources.length, (index) {
        final isActive = index == _currentIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: isActive ? 18 : 6,
          height: 6,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(3),
            color: isActive ? Colors.white : Colors.white38,
          ),
        );
      }),
    );
  }
}

/// A single interactive image page with zoom and tap-to-dismiss.
class _InteractiveImagePage extends StatefulWidget {
  final ImagePreviewSource source;
  final VoidCallback onTap;
  final ValueChanged<bool> onScaleChanged;
  final String? heroTag;

  const _InteractiveImagePage({
    required this.source,
    required this.onTap,
    required this.onScaleChanged,
    this.heroTag,
  });

  @override
  State<_InteractiveImagePage> createState() => _InteractiveImagePageState();
}

class _InteractiveImagePageState extends State<_InteractiveImagePage> {
  final TransformationController _transformController =
      TransformationController();

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget image = _buildImage(widget.source);

    if (widget.heroTag != null) {
      image = Hero(
        tag: widget.heroTag!,
        // Animate border radius from rounded thumbnail to full-screen
        flightShuttleBuilder: (_, animation, __, ___, ____) {
          return AnimatedBuilder(
            animation: animation,
            builder: (context, child) {
              return ClipRRect(
                borderRadius: BorderRadius.lerp(
                  BorderRadius.circular(12),
                  BorderRadius.zero,
                  animation.value,
                )!,
                child: child,
              );
            },
            child: _buildImage(widget.source),
          );
        },
        child: image,
      );
    }

    return GestureDetector(
      onTap: widget.onTap,
      // Double-tap to toggle zoom
      onDoubleTapDown: (details) => _handleDoubleTap(details),
      child: InteractiveViewer(
        transformationController: _transformController,
        minScale: 1.0,
        maxScale: 5.0,
        onInteractionEnd: (_) {
          final scale = _transformController.value.getMaxScaleOnAxis();
          widget.onScaleChanged(scale > 1.05);
        },
        child: Center(child: image),
      ),
    );
  }

  void _handleDoubleTap(TapDownDetails details) {
    final currentScale = _transformController.value.getMaxScaleOnAxis();
    if (currentScale > 1.05) {
      // Reset to original
      _transformController.value = Matrix4.identity();
      widget.onScaleChanged(false);
    } else {
      // Zoom to 2.5x at tap position
      final position = details.localPosition;
      const targetScale = 2.5;
      final zoomed = Matrix4.identity()
        ..translate(
          -position.dx * (targetScale - 1),
          -position.dy * (targetScale - 1),
        )
        ..scale(targetScale);
      _transformController.value = zoomed;
      widget.onScaleChanged(true);
    }
  }

  static Widget _buildImage(ImagePreviewSource source) {
    return switch (source) {
      FileImageSource(path: final p) => Image.file(
          File(p),
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildError(),
        ),
      NetworkImageSource(url: final u) => Image.network(
          u,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildError(),
        ),
      MemoryImageSource(bytes: final b) => Image.memory(
          b,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => _buildError(),
        ),
    };
  }

  static Widget _buildError() {
    return const Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.broken_image_outlined, size: 48, color: Colors.white54),
        SizedBox(height: 8),
        Text(
          '无法加载图片',
          style: TextStyle(color: Colors.white54, fontSize: 14),
        ),
      ],
    );
  }
}
