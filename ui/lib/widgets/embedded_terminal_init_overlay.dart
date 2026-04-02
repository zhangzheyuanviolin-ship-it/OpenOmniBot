import 'dart:async';

import 'package:flutter/material.dart';
import 'package:ui/services/special_permission.dart';
import 'package:ui/utils/ui.dart';

class EmbeddedTerminalInitOverlay extends StatefulWidget {
  const EmbeddedTerminalInitOverlay({super.key});

  @override
  State<EmbeddedTerminalInitOverlay> createState() =>
      _EmbeddedTerminalInitOverlayState();
}

class _EmbeddedTerminalInitOverlayState
    extends State<EmbeddedTerminalInitOverlay> {
  StreamSubscription<EmbeddedTerminalInitProgress>? _progressSubscription;
  Timer? _dismissTimer;
  EmbeddedTerminalInitSnapshot? _snapshot;
  int? _lastHandledCompletionMillis;
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _progressSubscription = embeddedTerminalInitProgressStream.listen((_) {
      unawaited(_reloadSnapshot());
    });
    unawaited(_reloadSnapshot());
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _progressSubscription?.cancel();
    super.dispose();
  }

  Future<void> _reloadSnapshot() async {
    try {
      final snapshot = await getEmbeddedTerminalInitSnapshot();
      if (!mounted) {
        return;
      }
      _applySnapshot(snapshot);
    } catch (_) {}
  }

  void _applySnapshot(EmbeddedTerminalInitSnapshot snapshot) {
    final completionMillis = snapshot.completedAt?.millisecondsSinceEpoch;

    if (snapshot.running) {
      _dismissTimer?.cancel();
    } else if (snapshot.completed) {
      _scheduleDismiss();
      if (completionMillis != null &&
          completionMillis != _lastHandledCompletionMillis) {
        _lastHandledCompletionMillis = completionMillis;
        _showCompletionToast(snapshot);
      }
    } else {
      _dismissTimer?.cancel();
    }

    setState(() {
      _snapshot = snapshot;
      _visible = snapshot.running || snapshot.completed;
    });
  }

  void _scheduleDismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) {
        return;
      }
      setState(() {
        _visible = false;
      });
    });
  }

  void _showCompletionToast(EmbeddedTerminalInitSnapshot snapshot) {
    final success = snapshot.success == true;
    final message = snapshot.stage.isNotEmpty
        ? snapshot.stage
        : success
        ? 'Alpine 环境已准备完成'
        : 'Alpine 环境准备失败，可稍后重试';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      showToast(
        message,
        type: success ? ToastType.success : ToastType.error,
        duration: const Duration(seconds: 3),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    final shouldRender = snapshot != null && (_visible || snapshot.running);
    if (!shouldRender) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final tone = _overlayToneFor(snapshot!);
    final progress = snapshot.success == true
        ? 1.0
        : snapshot.progress.clamp(0.04, 0.99);

    return IgnorePointer(
      ignoring: true,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Align(
            alignment: Alignment.topCenter,
            child: AnimatedSlide(
              offset: _visible ? Offset.zero : const Offset(0, -0.12),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              child: AnimatedOpacity(
                opacity: _visible ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.96),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: tone.borderColor,
                        width: 1,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: tone.shadowColor,
                          blurRadius: 28,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: tone.iconBackground,
                                  shape: BoxShape.circle,
                                ),
                                child: Icon(
                                  tone.icon,
                                  size: 18,
                                  color: tone.accentColor,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  _titleFor(snapshot),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: const Color(0xFF162033),
                                  ),
                                ),
                              ),
                              Text(
                                _badgeLabelFor(snapshot, progress),
                                style: theme.textTheme.labelMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: tone.accentColor,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            snapshot.stage.isNotEmpty
                                ? snapshot.stage
                                : _fallbackStageFor(snapshot),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: const Color(0xFF344256),
                              height: 1.45,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _supportingMessageFor(snapshot),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: const Color(0xFF6B7890),
                              height: 1.45,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 12),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(999),
                            child: LinearProgressIndicator(
                              minHeight: 6,
                              value: progress,
                              backgroundColor: tone.trackColor,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                tone.accentColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _titleFor(EmbeddedTerminalInitSnapshot snapshot) {
    if (snapshot.running) {
      return '正在后台准备 Alpine 环境';
    }
    if (snapshot.success == true) {
      return 'Alpine 环境已准备完成';
    }
    return 'Alpine 环境准备失败';
  }

  String _badgeLabelFor(
    EmbeddedTerminalInitSnapshot snapshot,
    double progress,
  ) {
    if (snapshot.running) {
      return '${(progress * 100).round()}%';
    }
    if (snapshot.success == true) {
      return '完成';
    }
    return '需重试';
  }

  String _supportingMessageFor(EmbeddedTerminalInitSnapshot snapshot) {
    if (snapshot.running) {
      return '初始化会在后台继续进行，你可以直接继续使用应用。';
    }
    if (snapshot.success == true) {
      return '相关 CLI 和运行环境已经就绪，后续能力可以直接使用。';
    }
    return '可稍后前往 Alpine 环境页面重新执行准备流程。';
  }

  String _fallbackStageFor(EmbeddedTerminalInitSnapshot snapshot) {
    if (snapshot.running) {
      return '正在为首次启动准备必要的终端运行能力。';
    }
    if (snapshot.success == true) {
      return '内嵌 Alpine 终端和基础 Agent CLI 包均已就绪。';
    }
    return '内嵌 Alpine 环境准备未完成。';
  }

  _EmbeddedTerminalOverlayTone _overlayToneFor(
    EmbeddedTerminalInitSnapshot snapshot,
  ) {
    if (snapshot.running) {
      return const _EmbeddedTerminalOverlayTone(
        accentColor: Color(0xFF0EA5E9),
        borderColor: Color(0xFFD6EEFB),
        iconBackground: Color(0xFFEAF7FE),
        trackColor: Color(0xFFE6F5FE),
        shadowColor: Color(0x140EA5E9),
        icon: Icons.terminal_rounded,
      );
    }
    if (snapshot.success == true) {
      return const _EmbeddedTerminalOverlayTone(
        accentColor: Color(0xFF16A34A),
        borderColor: Color(0xFFD9F3E3),
        iconBackground: Color(0xFFEAF8EF),
        trackColor: Color(0xFFE3F6EA),
        shadowColor: Color(0x1216A34A),
        icon: Icons.check_circle_rounded,
      );
    }
    return const _EmbeddedTerminalOverlayTone(
      accentColor: Color(0xFFF97316),
      borderColor: Color(0xFFFCE3D1),
      iconBackground: Color(0xFFFFF2E8),
      trackColor: Color(0xFFFFE8D8),
      shadowColor: Color(0x14F97316),
      icon: Icons.error_rounded,
    );
  }
}

class _EmbeddedTerminalOverlayTone {
  const _EmbeddedTerminalOverlayTone({
    required this.accentColor,
    required this.borderColor,
    required this.iconBackground,
    required this.trackColor,
    required this.shadowColor,
    required this.icon,
  });

  final Color accentColor;
  final Color borderColor;
  final Color iconBackground;
  final Color trackColor;
  final Color shadowColor;
  final IconData icon;
}
