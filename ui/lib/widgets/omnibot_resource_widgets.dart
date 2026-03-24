import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:ui/services/omnibot_resource_service.dart';
import 'package:video_player/video_player.dart';

class OmnibotInlineResourceEmbed extends StatelessWidget {
  final OmnibotResourceMetadata metadata;
  final bool plainStyle;

  const OmnibotInlineResourceEmbed({
    super.key,
    required this.metadata,
    this.plainStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    final maxWidth = math.min(MediaQuery.sizeOf(context).width - 72, 360.0);
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: switch (metadata.embedKind) {
        'image' => _OmnibotInlineImageCard(
          metadata: metadata,
          plainStyle: plainStyle,
        ),
        'audio' => _OmnibotInlineAudioPlayer(
          metadata: metadata,
          plainStyle: plainStyle,
        ),
        'video' => _OmnibotInlineVideoPlayer(
          metadata: metadata,
          plainStyle: plainStyle,
        ),
        _ => OmnibotResourceLinkCard(
          metadata: metadata,
          plainStyle: plainStyle,
        ),
      },
    );
  }
}

class OmnibotResourceLinkCard extends StatelessWidget {
  final OmnibotResourceMetadata metadata;
  final bool plainStyle;

  const OmnibotResourceLinkCard({
    super.key,
    required this.metadata,
    this.plainStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    final icon = switch (metadata.previewKind) {
      'pdf' => Icons.picture_as_pdf_outlined,
      'html' => Icons.language_outlined,
      'text' => Icons.description_outlined,
      'code' => Icons.code_outlined,
      'directory' => Icons.folder_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
    return InkWell(
      onTap: () => _openMetadata(metadata),
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: plainStyle ? Colors.transparent : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: plainStyle
              ? null
              : Border.all(color: const Color(0xFFD8E4F8)),
          boxShadow: plainStyle
              ? null
              : const [
                  BoxShadow(
                    color: Color(0x12243258),
                    blurRadius: 10,
                    offset: Offset(0, 4),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF3FF),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, size: 20, color: const Color(0xFF1F4ED8)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    metadata.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    metadata.shellPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF64748B),
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.open_in_new_rounded,
              size: 18,
              color: Color(0xFF64748B),
            ),
          ],
        ),
      ),
    );
  }
}

class _OmnibotInlineImageCard extends StatelessWidget {
  final OmnibotResourceMetadata metadata;
  final bool plainStyle;

  const _OmnibotInlineImageCard({
    required this.metadata,
    this.plainStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openMetadata(metadata),
      borderRadius: BorderRadius.circular(16),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: plainStyle
              ? null
              : Border.all(color: const Color(0xFFD8E4F8)),
          color: plainStyle ? Colors.transparent : Colors.white,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: metadata.exists
              ? Image.file(
                  File(metadata.path),
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => _MissingResourceCard(
                    metadata: metadata,
                    icon: Icons.broken_image_outlined,
                    subtitle: '图片加载失败',
                    plainStyle: plainStyle,
                  ),
                )
              : _MissingResourceCard(
                  metadata: metadata,
                  icon: Icons.image_not_supported_outlined,
                  subtitle: '图片不存在或暂不可读',
                  plainStyle: plainStyle,
                ),
        ),
      ),
    );
  }
}

class _OmnibotInlineAudioPlayer extends StatefulWidget {
  final OmnibotResourceMetadata metadata;
  final bool plainStyle;

  const _OmnibotInlineAudioPlayer({
    required this.metadata,
    this.plainStyle = false,
  });

  @override
  State<_OmnibotInlineAudioPlayer> createState() =>
      _OmnibotInlineAudioPlayerState();
}

class _OmnibotInlineAudioPlayerState extends State<_OmnibotInlineAudioPlayer> {
  late final AudioPlayer _player;
  Duration? _duration;
  Object? _error;
  bool _isReady = false;

  @override
  void initState() {
    super.initState();
    _player = AudioPlayer();
    _player.durationStream.listen((value) {
      if (!mounted) return;
      setState(() => _duration = value);
    });
    _initialize();
  }

  Future<void> _initialize() async {
    if (!widget.metadata.exists) return;
    try {
      await _player.setFilePath(widget.metadata.path);
      if (!mounted) return;
      setState(() => _isReady = true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    if (!_isReady) return;
    if (_player.playing) {
      await _player.pause();
      return;
    }
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    await _player.play();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.metadata.exists || _error != null) {
      return _MissingResourceCard(
        metadata: widget.metadata,
        icon: Icons.audio_file_outlined,
        subtitle: _error == null ? '音频不存在或暂不可读' : '音频加载失败',
        plainStyle: widget.plainStyle,
      );
    }
    return StreamBuilder<PlayerState>(
      stream: _player.playerStateStream,
      builder: (context, snapshot) {
        final playerState = snapshot.data;
        final isPlaying = playerState?.playing ?? false;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: widget.plainStyle ? Colors.transparent : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: widget.plainStyle
                ? null
                : Border.all(color: const Color(0xFFD8E4F8)),
            boxShadow: widget.plainStyle
                ? null
                : const [
                    BoxShadow(
                      color: Color(0x12243258),
                      blurRadius: 10,
                      offset: Offset(0, 4),
                    ),
                  ],
          ),
          child: Row(
            children: [
              IconButton.filledTonal(
                onPressed: _isReady ? _togglePlayback : null,
                icon: Icon(
                  isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.metadata.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _duration == null ? '音频资源' : _formatDuration(_duration!),
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: '打开预览',
                onPressed: () => _openMetadata(widget.metadata),
                icon: const Icon(Icons.open_in_new_rounded),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _OmnibotInlineVideoPlayer extends StatefulWidget {
  final OmnibotResourceMetadata metadata;
  final bool plainStyle;

  const _OmnibotInlineVideoPlayer({
    required this.metadata,
    this.plainStyle = false,
  });

  @override
  State<_OmnibotInlineVideoPlayer> createState() =>
      _OmnibotInlineVideoPlayerState();
}

class _OmnibotInlineVideoPlayerState extends State<_OmnibotInlineVideoPlayer> {
  VideoPlayerController? _controller;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    if (!widget.metadata.exists) return;
    final controller = VideoPlayerController.file(File(widget.metadata.path));
    try {
      await controller.initialize();
      controller.setLooping(false);
      controller.addListener(() {
        if (mounted) {
          setState(() {});
        }
      });
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (error) {
      await controller.dispose();
      if (!mounted) return;
      setState(() => _error = error);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _togglePlayback() async {
    final controller = _controller;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
      if (mounted) {
        setState(() {});
      }
      return;
    }
    if (controller.value.position >= controller.value.duration) {
      await controller.seekTo(Duration.zero);
    }
    await controller.play();
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.metadata.exists || _error != null) {
      return _MissingResourceCard(
        metadata: widget.metadata,
        icon: Icons.video_file_outlined,
        subtitle: _error == null ? '视频不存在或暂不可读' : '视频加载失败',
        plainStyle: widget.plainStyle,
      );
    }
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return Container(
        height: 180,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: widget.plainStyle ? Colors.transparent : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: widget.plainStyle
              ? null
              : Border.all(color: const Color(0xFFD8E4F8)),
        ),
        child: const CircularProgressIndicator(),
      );
    }
    return Container(
      decoration: BoxDecoration(
        color: widget.plainStyle ? Colors.transparent : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: widget.plainStyle
            ? null
            : Border.all(color: const Color(0xFFD8E4F8)),
        boxShadow: widget.plainStyle
            ? null
            : const [
                BoxShadow(
                  color: Color(0x12243258),
                  blurRadius: 10,
                  offset: Offset(0, 4),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AspectRatio(
          aspectRatio: controller.value.aspectRatio == 0
              ? 16 / 9
              : controller.value.aspectRatio,
          child: Stack(
            alignment: Alignment.center,
            children: [
              VideoPlayer(controller),
              DecoratedBox(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0x55000000)],
                  ),
                ),
                child: const SizedBox.expand(),
              ),
              IconButton.filled(
                onPressed: _togglePlayback,
                iconSize: 28,
                icon: Icon(
                  controller.value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MissingResourceCard extends StatelessWidget {
  final OmnibotResourceMetadata metadata;
  final IconData icon;
  final String subtitle;
  final bool plainStyle;

  const _MissingResourceCard({
    required this.metadata,
    required this.icon,
    required this.subtitle,
    this.plainStyle = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _openMetadata(metadata),
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: plainStyle ? Colors.transparent : const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(14),
          border: plainStyle
              ? null
              : Border.all(color: const Color(0xFFF2D4A5)),
        ),
        child: Row(
          children: [
            Icon(icon, size: 20, color: const Color(0xFFB45309)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    metadata.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF92400E),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(
              Icons.open_in_new_rounded,
              size: 18,
              color: Color(0xFF92400E),
            ),
          ],
        ),
      ),
    );
  }
}

Future<void> _openMetadata(OmnibotResourceMetadata metadata) async {
  if (metadata.isDirectory) {
    await OmnibotResourceService.openWorkspace(
      absolutePath: metadata.path,
      shellPath: metadata.shellPath,
      uri: metadata.uri,
    );
    return;
  }
  await OmnibotResourceService.openFilePath(
    metadata.path,
    uri: metadata.uri,
    title: metadata.title,
    previewKind: metadata.previewKind,
    mimeType: metadata.mimeType,
    shellPath: metadata.shellPath,
  );
}

String _formatDuration(Duration duration) {
  final totalSeconds = duration.inSeconds;
  final minutes = (totalSeconds ~/ 60).toString().padLeft(2, '0');
  final seconds = (totalSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
