import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../../models/chat_message_model.dart';
import '../chat_page_models.dart';
import '../../command_overlay/widgets/message_bubble.dart';
import '../../command_overlay/widgets/chat_input_area.dart';

enum ChatSurfaceMode { workspace, normal, openclaw }

/// 聊天页面 AppBar
class ChatAppBar extends StatelessWidget {
  final VoidCallback onMenuTap;
  final VoidCallback onCompanionTap;
  final ChatSurfaceMode activeMode;
  final ValueChanged<ChatSurfaceMode> onModeChanged;
  final String? activeModelId;
  final ValueChanged<BuildContext>? onModelTap;
  final ChatIslandDisplayLayer displayLayer;
  final ValueChanged<ChatIslandDisplayLayer> onDisplayLayerChanged;
  final VoidCallback onTerminalTap;
  final VoidCallback onBrowserTap;
  final bool isBrowserEnabled;
  final String? activeToolType;
  final bool isCompanionModeEnabled;
  final bool isCompanionToggleLoading;

  const ChatAppBar({
    super.key,
    required this.onMenuTap,
    required this.onCompanionTap,
    required this.activeMode,
    required this.onModeChanged,
    this.activeModelId,
    this.onModelTap,
    this.displayLayer = ChatIslandDisplayLayer.mode,
    required this.onDisplayLayerChanged,
    required this.onTerminalTap,
    required this.onBrowserTap,
    this.isBrowserEnabled = false,
    this.activeToolType,
    this.isCompanionModeEnabled = false,
    this.isCompanionToggleLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconTint = Colors.grey[800]!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: Row(
        children: [
          // 左侧菜单按钮 - 和主页一样的样式
          GestureDetector(
            onTap: onMenuTap,
            child: Container(
              color: Colors.transparent,
              padding: const EdgeInsets.all(15),
              child: SvgPicture.asset(
                'assets/home/drawer_icon.svg',
                width: 20,
                height: 20,
                colorFilter: ColorFilter.mode(iconTint, BlendMode.srcIn),
              ),
            ),
          ),
          // 顶部模式滑块
          Expanded(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 176),
                child: _ChatModeModelSwitcher(
                  activeMode: activeMode,
                  onModeChanged: onModeChanged,
                  activeModelId: activeModelId,
                  onModelTap: onModelTap,
                  displayLayer: displayLayer,
                  onDisplayLayerChanged: onDisplayLayerChanged,
                  onTerminalTap: onTerminalTap,
                  onBrowserTap: onBrowserTap,
                  isBrowserEnabled: isBrowserEnabled,
                  activeToolType: activeToolType,
                ),
              ),
            ),
          ),
          // 右侧小万陪伴按钮
          GestureDetector(
            onTap: isCompanionToggleLoading ? null : onCompanionTap,
            child: Container(
              color: Colors.transparent,
              padding: const EdgeInsets.all(15),
              child: isCompanionToggleLoading
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          isCompanionModeEnabled
                              ? const Color(0xFF1930D9)
                              : iconTint,
                        ),
                      ),
                    )
                  : SvgPicture.asset(
                      'assets/home/avatar.svg',
                      width: 20,
                      height: 20,
                      colorFilter: ColorFilter.mode(
                        isCompanionModeEnabled
                            ? const Color(0xFF1930D9)
                            : iconTint,
                        BlendMode.srcIn,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatModeModelSwitcher extends StatefulWidget {
  const _ChatModeModelSwitcher({
    required this.activeMode,
    required this.onModeChanged,
    this.activeModelId,
    this.onModelTap,
    required this.displayLayer,
    required this.onDisplayLayerChanged,
    required this.onTerminalTap,
    required this.onBrowserTap,
    required this.isBrowserEnabled,
    this.activeToolType,
  });

  final ChatSurfaceMode activeMode;
  final ValueChanged<ChatSurfaceMode> onModeChanged;
  final String? activeModelId;
  final ValueChanged<BuildContext>? onModelTap;
  final ChatIslandDisplayLayer displayLayer;
  final ValueChanged<ChatIslandDisplayLayer> onDisplayLayerChanged;
  final VoidCallback onTerminalTap;
  final VoidCallback onBrowserTap;
  final bool isBrowserEnabled;
  final String? activeToolType;

  @override
  State<_ChatModeModelSwitcher> createState() => _ChatModeModelSwitcherState();
}

class _ChatModeModelSwitcherState extends State<_ChatModeModelSwitcher> {
  static const Duration _idleDelay = Duration(milliseconds: 1700);
  static const Duration _switchDuration = Duration(milliseconds: 460);
  static const double _verticalSwitchThreshold = 10;
  static const double _verticalVelocityThreshold = 240;
  static const double _switcherHeight = 32;

  Timer? _idleTimer;
  double _verticalDragDelta = 0;

  String get _modelLabel {
    final text = (widget.activeModelId ?? '').trim();
    if (text.isEmpty) {
      return '未设置模型';
    }
    return text;
  }

  bool get _canRevealModelLabel =>
      widget.activeMode == ChatSurfaceMode.normal &&
      (widget.activeModelId ?? '').trim().isNotEmpty;

  bool get _shouldAutoRevealModel =>
      _canRevealModelLabel &&
      widget.displayLayer == ChatIslandDisplayLayer.mode;

  int _layerOrder(ChatIslandDisplayLayer layer) => switch (layer) {
    ChatIslandDisplayLayer.model => 0,
    ChatIslandDisplayLayer.mode => 1,
    ChatIslandDisplayLayer.tools => 2,
  };

  @override
  void initState() {
    super.initState();
    _armIdleTimer();
  }

  @override
  void didUpdateWidget(covariant _ChatModeModelSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeMode != widget.activeMode ||
        oldWidget.displayLayer != widget.displayLayer) {
      _armIdleTimer();
      return;
    }
    final previousModelId = (oldWidget.activeModelId ?? '').trim();
    final currentModelId = (widget.activeModelId ?? '').trim();
    if (previousModelId != currentModelId) {
      _armIdleTimer();
    }
  }

  @override
  void dispose() {
    _idleTimer?.cancel();
    super.dispose();
  }

  void _armIdleTimer() {
    _idleTimer?.cancel();
    if (!_shouldAutoRevealModel) {
      return;
    }
    _idleTimer = Timer(_idleDelay, () {
      if (!mounted || !_shouldAutoRevealModel) {
        return;
      }
      widget.onDisplayLayerChanged(ChatIslandDisplayLayer.model);
    });
  }

  void _handleSliderInteraction() {
    _idleTimer?.cancel();
    if (widget.activeMode == ChatSurfaceMode.normal &&
        widget.displayLayer != ChatIslandDisplayLayer.mode) {
      widget.onDisplayLayerChanged(ChatIslandDisplayLayer.mode);
    }
    _armIdleTimer();
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    _verticalDragDelta += details.delta.dy;
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final shouldToggle =
        _verticalDragDelta.abs() > _verticalSwitchThreshold ||
        velocity.abs() > _verticalVelocityThreshold;
    if (!shouldToggle) {
      _verticalDragDelta = 0;
      return;
    }
    final intent = _verticalDragDelta + velocity * 0.015;
    _verticalDragDelta = 0;

    if (widget.activeMode != ChatSurfaceMode.normal) {
      return;
    }
    _idleTimer?.cancel();
    if (intent > 0) {
      if (widget.displayLayer != ChatIslandDisplayLayer.tools) {
        widget.onDisplayLayerChanged(ChatIslandDisplayLayer.tools);
      }
      return;
    }
    if (_canRevealModelLabel &&
        widget.displayLayer != ChatIslandDisplayLayer.model) {
      widget.onDisplayLayerChanged(ChatIslandDisplayLayer.model);
    }
  }

  @override
  Widget build(BuildContext context) {
    final modelLabelWidget = Builder(
      builder: (anchorContext) {
        final text = Text(
          _modelLabel,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 14,
            color: Color(0xFF9DA9BB),
            fontWeight: FontWeight.w500,
          ),
        );
        if (widget.onModelTap == null) {
          return Center(child: text);
        }
        return InkWell(
          onTap: () {
            _idleTimer?.cancel();
            widget.onModelTap?.call(anchorContext);
          },
          borderRadius: BorderRadius.circular(999),
          child: Center(child: text),
        );
      },
    );
    final toolLayerWidget = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: _ChatIslandToolButton(
              key: const ValueKey('chat-island-terminal-button'),
              icon: Icons.code_rounded,
              label: '终端',
              isActive: widget.activeToolType?.trim() == 'terminal',
              tooltip: '打开终端',
              onTap: () {
                _idleTimer?.cancel();
                widget.onTerminalTap();
              },
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _ChatIslandToolButton(
              key: const ValueKey('chat-island-browser-button'),
              icon: Icons.language_rounded,
              label: '浏览器',
              isActive: widget.activeToolType?.trim() == 'browser',
              isEnabled: widget.isBrowserEnabled,
              tooltip: widget.isBrowserEnabled
                  ? '打开当前会话浏览器'
                  : '当前会话还没有可用的浏览器会话',
              onTap: () {
                _idleTimer?.cancel();
                widget.onBrowserTap();
              },
            ),
          ),
        ],
      ),
    );
    final currentOrder = _layerOrder(widget.displayLayer);

    double topFor(ChatIslandDisplayLayer layer) {
      return (_layerOrder(layer) - currentOrder) * _switcherHeight;
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD9E6FB), width: 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: SizedBox(
          height: _switcherHeight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onVerticalDragUpdate: _handleVerticalDragUpdate,
            onVerticalDragEnd: _handleVerticalDragEnd,
            onVerticalDragCancel: () {
              _verticalDragDelta = 0;
            },
            child: Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.hardEdge,
              children: [
                AnimatedPositioned(
                  duration: _switchDuration,
                  curve: Curves.easeInOutCubicEmphasized,
                  left: 0,
                  right: 0,
                  height: _switcherHeight,
                  top: topFor(ChatIslandDisplayLayer.mode),
                  child: ChatModeSlider(
                    activeMode: widget.activeMode,
                    onChanged: widget.onModeChanged,
                    onInteracted: _handleSliderInteraction,
                  ),
                ),
                AnimatedPositioned(
                  duration: _switchDuration,
                  curve: Curves.easeInOutCubicEmphasized,
                  left: 0,
                  right: 0,
                  height: _switcherHeight,
                  top: topFor(ChatIslandDisplayLayer.model),
                  child: modelLabelWidget,
                ),
                AnimatedPositioned(
                  duration: _switchDuration,
                  curve: Curves.easeInOutCubicEmphasized,
                  left: 0,
                  right: 0,
                  height: _switcherHeight,
                  top: topFor(ChatIslandDisplayLayer.tools),
                  child: toolLayerWidget,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChatIslandToolButton extends StatelessWidget {
  const _ChatIslandToolButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.isEnabled = true,
    this.isActive = false,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isEnabled;
  final bool isActive;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final foreground = !isEnabled
        ? const Color(0xFFB8C4D8)
        : isActive
        ? const Color(0xFF1930D9)
        : const Color(0xFF617390);
    final background = isActive ? const Color(0xFFE9EEFF) : Colors.transparent;
    final child = InkWell(
      onTap: isEnabled ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: foreground,
              ),
            ),
          ],
        ),
      ),
    );
    if (tooltip == null || tooltip!.trim().isEmpty) {
      return child;
    }
    return Tooltip(message: tooltip, child: child);
  }
}

class ChatModeSlider extends StatefulWidget {
  final ChatSurfaceMode activeMode;
  final ValueChanged<ChatSurfaceMode> onChanged;
  final VoidCallback? onInteracted;

  const ChatModeSlider({
    super.key,
    required this.activeMode,
    required this.onChanged,
    this.onInteracted,
  });

  @override
  State<ChatModeSlider> createState() => _ChatModeSliderState();
}

class _ChatModeSliderState extends State<ChatModeSlider> {
  static const String _workspaceIconSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
      'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" '
      'stroke-linecap="round" stroke-linejoin="round" class="lucide lucide-folders-icon lucide-folders">'
      '<path d="M20 5a2 2 0 0 1 2 2v7a2 2 0 0 1-2 2H9a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h2.5a1.5 1.5 0 0 1 1.2.6l.6.8a1.5 1.5 0 0 0 1.2.6z"/>'
      '<path d="M3 8.268a2 2 0 0 0-1 1.738V19a2 2 0 0 0 2 2h11a2 2 0 0 0 1.732-1"/>'
      '</svg>';

  static const String _normalChatIconSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
      'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" '
      'stroke-linecap="round" stroke-linejoin="round">'
      '<path d="M16 10a2 2 0 0 1-2 2H6.828a2 2 0 0 0-1.414.586l-2.202 2.202A.71.71 0 0 1 2 14.286V4a2 2 0 0 1 2-2h10a2 2 0 0 1 2 2z"/>'
      '<path d="M20 9a2 2 0 0 1 2 2v10.286a.71.71 0 0 1-1.212.502l-2.202-2.202A2 2 0 0 0 17.172 19H10a2 2 0 0 1-2-2v-1"/>'
      '</svg>';

  double _dragDelta = 0;

  void _handleDragEnd({double velocity = 0}) {
    final intent = _dragDelta + velocity * 0.015;
    final shouldSwitch = _dragDelta.abs() > 14 || velocity.abs() > 250;
    if (shouldSwitch) {
      final currentIndex = ChatSurfaceMode.values.indexOf(widget.activeMode);
      final delta = intent > 0 ? 1 : -1;
      final targetIndex = (currentIndex + delta).clamp(
        0,
        ChatSurfaceMode.values.length - 1,
      );
      widget.onChanged(ChatSurfaceMode.values[targetIndex]);
    }
    _dragDelta = 0;
  }

  @override
  Widget build(BuildContext context) {
    final alignment = switch (widget.activeMode) {
      ChatSurfaceMode.workspace => Alignment.centerLeft,
      ChatSurfaceMode.normal => Alignment.center,
      ChatSurfaceMode.openclaw => Alignment.centerRight,
    };
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragUpdate: (details) {
        _dragDelta += details.delta.dx;
        widget.onInteracted?.call();
      },
      onHorizontalDragEnd: (details) {
        widget.onInteracted?.call();
        _handleDragEnd(velocity: details.primaryVelocity ?? 0);
      },
      onTapUp: (details) {
        widget.onInteracted?.call();
        final box = context.findRenderObject() as RenderBox?;
        if (box == null || !box.hasSize) return;
        final local = box.globalToLocal(details.globalPosition);
        final segmentWidth = box.size.width / ChatSurfaceMode.values.length;
        final targetIndex = (local.dx / segmentWidth).floor().clamp(
          0,
          ChatSurfaceMode.values.length - 1,
        );
        widget.onChanged(ChatSurfaceMode.values[targetIndex]);
      },
      child: Container(
        height: 32,
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 280),
              curve: Curves.easeOutCubic,
              alignment: alignment,
              child: FractionallySizedBox(
                widthFactor: 1 / 3,
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF2DA5F0), Color(0xFF1930D9)],
                    ),
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x291930D9),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: _buildModeIcon(
                    isSelected: widget.activeMode == ChatSurfaceMode.workspace,
                    child: SvgPicture.string(
                      _workspaceIconSvg,
                      width: 16,
                      height: 16,
                    ),
                  ),
                ),
                Expanded(
                  child: _buildModeIcon(
                    isSelected: widget.activeMode == ChatSurfaceMode.normal,
                    child: SvgPicture.string(
                      _normalChatIconSvg,
                      width: 16,
                      height: 16,
                    ),
                  ),
                ),
                Expanded(
                  child: _buildModeIcon(
                    isSelected: widget.activeMode == ChatSurfaceMode.openclaw,
                    child: SvgPicture.asset(
                      'assets/home/openclaw.svg',
                      width: 16,
                      height: 16,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeIcon({required bool isSelected, required Widget child}) {
    final color = isSelected ? Colors.white : const Color(0xFF617390);
    return Center(
      child: AnimatedScale(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        scale: isSelected ? 1 : 0.95,
        child: ColorFiltered(
          colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
          child: child,
        ),
      ),
    );
  }
}

/// 消息列表
class ChatMessageList extends StatelessWidget {
  final List<ChatMessageModel> messages;
  final ScrollController scrollController;
  final Future<void> Function() onBeforeTaskExecute;
  final void Function(String taskId)? onCancelTask;
  final void Function(List<String> requiredPermissionIds)? onRequestAuthorize;

  const ChatMessageList({
    super.key,
    required this.messages,
    required this.scrollController,
    required this.onBeforeTaskExecute,
    this.onCancelTask,
    this.onRequestAuthorize,
  });

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) {
      return GestureDetector(
        onVerticalDragUpdate: (_) {},
        behavior: HitTestBehavior.opaque,
        child: const Center(
          child: Text(
            '有什么可以帮助你的？',
            style: TextStyle(color: Color(0xFF999999), fontSize: 14),
          ),
        ),
      );
    }

    return Align(
      alignment: Alignment.topCenter,
      child: ListView.builder(
        controller: scrollController,
        reverse: true,
        shrinkWrap: true,
        physics: const ClampingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
        itemCount: messages.length,
        itemBuilder: (context, index) {
          final message = messages[index];
          final isLastMessage = index == 0;
          final isOldestMessage = index == messages.length - 1;
          final needBottomPadding = isLastMessage && messages.length > 1;
          final needTopPadding = isOldestMessage && message.user != 1;
          return Padding(
            padding: EdgeInsets.only(
              top: needTopPadding ? 24.0 : 0.0,
              bottom: needBottomPadding ? 40.0 : 0.0,
            ),
            child: MessageBubble(
              message: message,
              key: ValueKey(message.dbId ?? message.contentId ?? message.id),
              onBeforeTaskExecute: onBeforeTaskExecute,
              onCancelTask: onCancelTask,
              enableThinkingCollapse: true,
              parentScrollController: scrollController,
              onRequestAuthorize: onRequestAuthorize,
            ),
          );
        },
      ),
    );
  }
}

/// VLM 用户输入提示
class VlmInfoPrompt extends StatelessWidget {
  final String question;
  final TextEditingController controller;
  final bool isSubmitting;
  final VoidCallback onSubmit;
  final VoidCallback onDismiss;

  const VlmInfoPrompt({
    super.key,
    required this.question,
    required this.controller,
    required this.isSubmitting,
    required this.onSubmit,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFE8F2FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF4F83FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '需要你的确认',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF1D3E7B),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            question,
            style: const TextStyle(fontSize: 13, color: Color(0xFF1D3E7B)),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            maxLines: 2,
            decoration: const InputDecoration(
              hintText: '可选：补充你的操作说明，默认发送"已完成操作，继续执行"',
              isDense: true,
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: isSubmitting ? null : onDismiss,
                  child: const Text('稍后再说'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton(
                  onPressed: isSubmitting ? null : onSubmit,
                  child: Text(isSubmitting ? '发送中...' : '继续执行'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// 聊天输入区域包装器
class ChatInputWrapper extends StatelessWidget {
  final GlobalKey<ChatInputAreaState> inputAreaKey;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool isProcessing;
  final Future<void> Function({String? text}) onSendMessage;
  final VoidCallback onCancelTask;
  final void Function(bool) onPopupVisibilityChanged;
  final bool? openClawEnabled;
  final ValueChanged<bool>? onToggleOpenClaw;
  final VoidCallback? onLongPressOpenClaw;
  final bool useLargeComposerStyle;
  final bool useAttachmentPickerForPlus;
  final Future<void> Function()? onPickAttachment;
  final List<ChatInputAttachment> attachments;
  final ValueChanged<String>? onRemoveAttachment;
  final Widget? topBanner;
  final String? selectedModelOverrideId;
  final VoidCallback? onClearSelectedModelOverride;

  const ChatInputWrapper({
    super.key,
    required this.inputAreaKey,
    required this.controller,
    required this.focusNode,
    required this.isProcessing,
    required this.onSendMessage,
    required this.onCancelTask,
    required this.onPopupVisibilityChanged,
    this.openClawEnabled,
    this.onToggleOpenClaw,
    this.onLongPressOpenClaw,
    this.useLargeComposerStyle = false,
    this.useAttachmentPickerForPlus = false,
    this.onPickAttachment,
    this.attachments = const [],
    this.onRemoveAttachment,
    this.topBanner,
    this.selectedModelOverrideId,
    this.onClearSelectedModelOverride,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (topBanner != null) ...[topBanner!, const SizedBox(height: 8)],
          ChatInputArea(
            key: inputAreaKey,
            controller: controller,
            focusNode: focusNode,
            isProcessing: isProcessing,
            onSendMessage: onSendMessage,
            onCancelTask: onCancelTask,
            onPopupVisibilityChanged: onPopupVisibilityChanged,
            openClawEnabled: openClawEnabled,
            onToggleOpenClaw: onToggleOpenClaw,
            onLongPressOpenClaw: onLongPressOpenClaw,
            useLargeComposerStyle: useLargeComposerStyle,
            useAttachmentPickerForPlus: useAttachmentPickerForPlus,
            onPickAttachment: onPickAttachment,
            attachments: attachments,
            onRemoveAttachment: onRemoveAttachment,
            selectedModelOverrideId: selectedModelOverrideId,
            onClearSelectedModelOverride: onClearSelectedModelOverride,
          ),
        ],
      ),
    );
  }
}
