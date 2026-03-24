import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import '../../../../../models/chat_message_model.dart';
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
  final void Function(BuildContext context, Offset globalPosition)?
  onModelLongPressStart;
  final ValueChanged<Offset>? onModelLongPressMove;
  final ValueChanged<Offset>? onModelLongPressEnd;
  final VoidCallback? onModelLongPressCancel;
  final VoidCallback? onModelLabelTap;
  final bool isModelSelectorActive;
  final bool isQuickModelPickerActive;
  final TextEditingController? modelSearchController;
  final FocusNode? modelSearchFocusNode;
  final VoidCallback? onCloseModelSelector;
  final Widget? modelSelectorPanel;
  final Key? modelSelectorSurfaceKey;
  final TextEditingController? quickModelSearchController;
  final FocusNode? quickModelSearchFocusNode;
  final VoidCallback? onCloseQuickModelPicker;
  final Key? quickModelPickerSurfaceKey;
  final String? quickModelSearchHint;
  final bool isCompanionModeEnabled;
  final bool isCompanionToggleLoading;

  const ChatAppBar({
    super.key,
    required this.onMenuTap,
    required this.onCompanionTap,
    required this.activeMode,
    required this.onModeChanged,
    this.activeModelId,
    this.onModelLongPressStart,
    this.onModelLongPressMove,
    this.onModelLongPressEnd,
    this.onModelLongPressCancel,
    this.onModelLabelTap,
    this.isModelSelectorActive = false,
    this.isQuickModelPickerActive = false,
    this.modelSearchController,
    this.modelSearchFocusNode,
    this.onCloseModelSelector,
    this.modelSelectorPanel,
    this.modelSelectorSurfaceKey,
    this.quickModelSearchController,
    this.quickModelSearchFocusNode,
    this.onCloseQuickModelPicker,
    this.quickModelPickerSurfaceKey,
    this.quickModelSearchHint,
    this.isCompanionModeEnabled = false,
    this.isCompanionToggleLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconTint = Colors.grey[800]!;
    final modelLabel = activeMode == ChatSurfaceMode.normal
        ? (activeModelId ?? '').trim()
        : '';

    if (isQuickModelPickerActive) {
      final controller = quickModelSearchController;
      final focusNode = quickModelSearchFocusNode;
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            key: quickModelPickerSurfaceKey,
            constraints: const BoxConstraints(maxWidth: 272),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: const Color(0xFFDCE7F7)),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x140F172A),
                    blurRadius: 16,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: onCloseQuickModelPicker,
                    child: const SizedBox(
                      width: 28,
                      height: 28,
                      child: Icon(
                        Icons.arrow_back_ios_new_rounded,
                        size: 16,
                        color: Color(0xFF617390),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.search_rounded,
                    size: 18,
                    color: Color(0xFF9AA4B6),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      autofocus: false,
                      scrollPadding: EdgeInsets.zero,
                      style: const TextStyle(
                        fontSize: 14,
                        color: Color(0xFF1F2937),
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: quickModelSearchHint ?? '搜索模型 ID',
                        hintStyle: const TextStyle(
                          fontSize: 14,
                          color: Color(0xFF9AA4B6),
                          fontWeight: FontWeight.w500,
                        ),
                        border: InputBorder.none,
                        focusedBorder: InputBorder.none,
                        enabledBorder: InputBorder.none,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ),
                  if ((controller?.text ?? '').isNotEmpty)
                    GestureDetector(
                      onTap: controller?.clear,
                      child: const SizedBox(
                        width: 28,
                        height: 28,
                        child: Icon(
                          Icons.close_rounded,
                          size: 18,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (isModelSelectorActive) {
      final controller = modelSearchController;
      final focusNode = modelSearchFocusNode;
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            key: modelSelectorSurfaceKey,
            constraints: const BoxConstraints(maxWidth: 240),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFDCE7F7)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x140F172A),
                        blurRadius: 16,
                        offset: Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: onCloseModelSelector,
                        child: const SizedBox(
                          width: 28,
                          height: 28,
                          child: Icon(
                            Icons.arrow_back_ios_new_rounded,
                            size: 16,
                            color: Color(0xFF617390),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.search_rounded,
                        size: 18,
                        color: Color(0xFF9AA4B6),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          focusNode: focusNode,
                          autofocus: false,
                          scrollPadding: EdgeInsets.zero,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Color(0xFF1F2937),
                            fontWeight: FontWeight.w500,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            hintText: '搜索模型 ID',
                            hintStyle: TextStyle(
                              fontSize: 14,
                              color: Color(0xFF9AA4B6),
                              fontWeight: FontWeight.w500,
                            ),
                            border: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      if ((controller?.text ?? '').isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            controller?.clear();
                            focusNode?.requestFocus();
                          },
                          child: const SizedBox(
                            width: 28,
                            height: 28,
                            child: Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (modelSelectorPanel != null) ...[
                  const SizedBox(height: 10),
                  modelSelectorPanel!,
                ],
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
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
                    child: ChatModeSlider(
                      activeMode: activeMode,
                      onChanged: onModeChanged,
                      onModelLongPressStart: onModelLongPressStart,
                      onModelLongPressMove: onModelLongPressMove,
                      onModelLongPressEnd: onModelLongPressEnd,
                      onModelLongPressCancel: onModelLongPressCancel,
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
          if (modelLabel.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onModelLabelTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 240),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          modelLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 12,
                            color: onModelLabelTap == null
                                ? const Color(0xFF9DA9BB)
                                : const Color(0xFF7C8CA5),
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ),
                      if (onModelLabelTap != null) ...[
                        const SizedBox(width: 4),
                        const Icon(
                          Icons.expand_more_rounded,
                          size: 14,
                          color: Color(0xFF9DA9BB),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class ChatModeSlider extends StatefulWidget {
  final ChatSurfaceMode activeMode;
  final ValueChanged<ChatSurfaceMode> onChanged;
  final void Function(BuildContext context, Offset globalPosition)?
  onModelLongPressStart;
  final ValueChanged<Offset>? onModelLongPressMove;
  final ValueChanged<Offset>? onModelLongPressEnd;
  final VoidCallback? onModelLongPressCancel;

  const ChatModeSlider({
    super.key,
    required this.activeMode,
    required this.onChanged,
    this.onModelLongPressStart,
    this.onModelLongPressMove,
    this.onModelLongPressEnd,
    this.onModelLongPressCancel,
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
      },
      onHorizontalDragEnd: (details) {
        _handleDragEnd(velocity: details.primaryVelocity ?? 0);
      },
      onLongPressStart: widget.onModelLongPressStart == null
          ? null
          : (details) {
              HapticFeedback.mediumImpact();
              widget.onModelLongPressStart?.call(
                context,
                details.globalPosition,
              );
            },
      onLongPressMoveUpdate: widget.onModelLongPressMove == null
          ? null
          : (details) {
              widget.onModelLongPressMove?.call(details.globalPosition);
            },
      onLongPressEnd: widget.onModelLongPressEnd == null
          ? null
          : (details) {
              widget.onModelLongPressEnd?.call(details.globalPosition);
            },
      onLongPressCancel: widget.onModelLongPressCancel,
      onTapUp: (details) {
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
          if (topBanner != null) ...[
            topBanner!,
            const SizedBox(height: 8),
          ],
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
