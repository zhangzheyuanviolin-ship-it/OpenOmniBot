import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../../../../models/chat_message_model.dart';
import '../../../../../widgets/streaming_text.dart';
import 'thinking_dots_indicator.dart';
import 'cards/card_widget_factory.dart';
import 'package:flutter_svg/flutter_svg.dart';

export 'package:ui/widgets/streaming_text.dart'
    show kThinkingText, kSummarizingText, kSummaryCompleteText;

/// 消息气泡组件
///
/// 根据消息类型渲染不同样式的气泡
/// - 用户消息：右侧深色气泡
/// - AI消息：左侧浅色气泡，使用StreamingText组件渲染流式内容
/// - 卡片消息（预留）：自定义卡片组件
class MessageBubble extends StatelessWidget {
  final ChatMessageModel message;

  /// 任务执行前的回调，用于保存聊天上下文
  final OnBeforeTaskExecute? onBeforeTaskExecute;

  /// 取消任务回调，参数为 taskId
  final void Function(String taskId)? onCancelTask;

  /// 是否允许深度思考卡片折叠
  final bool enableThinkingCollapse;

  /// 外层消息列表滚动控制器，用于卡片内嵌滚动与父列表联动
  final ScrollController? parentScrollController;
  final OnRequestAuthorize? onRequestAuthorize;
  final void Function(ChatMessageModel message, LongPressStartDetails details)?
  onUserMessageLongPressStart;

  const MessageBubble({
    super.key,
    required this.message,
    this.onBeforeTaskExecute,
    this.onCancelTask,
    this.enableThinkingCollapse = false,
    this.parentScrollController,
    this.onRequestAuthorize,
    this.onUserMessageLongPressStart,
  });

  @override
  Widget build(BuildContext context) {
    // user: 1=用户, 2=AI, 3=系统
    final isUserMessage = message.user == 1;
    final isCardMessage = message.type == 2; // 卡片消息

    // 卡片消息特殊布局：撑满整个聊天框宽度
    if (isCardMessage) {
      return Container(
        margin: const EdgeInsets.only(top: 8, bottom: 0),
        child: _buildMessageContent(context, isUserMessage),
      );
    }

    return Container(
      margin: EdgeInsets.only(
        top: isUserMessage ? 24 : 8,
        bottom: isUserMessage ? 16 : 0,
        right: isUserMessage ? 0 : 18.34,
      ),
      child: Row(
        mainAxisAlignment: isUserMessage
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          isUserMessage
              ? Flexible(child: _buildMessageContent(context, isUserMessage))
              : Expanded(child: _buildMessageContent(context, isUserMessage)),
        ],
      ),
    );
  }

  /// 构建消息内容
  Widget _buildMessageContent(BuildContext context, bool isUserMessage) {
    // 根据消息类型渲染不同内容
    // type: 1=普通消息, 2=卡片消息
    switch (message.type) {
      case 1: // 普通消息
        return _buildTextMessage(context, isUserMessage);

      case 2: // 卡片消息
        return _buildCardMessage(context);

      default:
        return _buildTextMessage(context, isUserMessage);
    }
  }

  /// 构建文本消息
  Widget _buildTextMessage(BuildContext context, bool isUserMessage) {
    final text = message.text ?? '';
    final attachments = _extractAttachments();

    if (isUserMessage) {
      // 用户消息：整块气泡长按触发快捷操作。
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPressStart: onUserMessageLongPressStart == null
            ? null
            : (details) => onUserMessageLongPressStart!(message, details),
        child: Container(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          decoration: ShapeDecoration(
            color: const Color(0xCCF1F8FF), // rgba(241,248,255,0.8)
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (text.isNotEmpty) _buildUserText(text),
              if (attachments.isNotEmpty) ...[
                if (text.isNotEmpty) const SizedBox(height: 8),
                _buildUserAttachmentList(attachments),
              ],
            ],
          ),
        ),
      );
    }

    if (attachments.isEmpty) {
      // AI消息：简单文本样式，无背景
      return _buildAiText(text);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (text.isNotEmpty) _buildAiText(text),
        if (text.isNotEmpty) const SizedBox(height: 8),
        _buildUserAttachmentList(attachments),
      ],
    );
  }

  List<Map<String, dynamic>> _extractAttachments() {
    final raw = message.content?['attachments'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  Widget _buildUserAttachmentList(List<Map<String, dynamic>> attachments) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: attachments.map(_buildAttachmentItem).toList(),
    );
  }

  Widget _buildAttachmentItem(Map<String, dynamic> item) {
    if (_isImageAttachment(item)) {
      return _buildImageAttachmentTile(item);
    }
    return _buildFileAttachmentChip(item);
  }

  Widget _buildImageAttachmentTile(Map<String, dynamic> item) {
    return Container(
      width: 84,
      height: 84,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFD0DEFA), width: 1),
      ),
      child: _buildAttachmentImageWidget(item),
    );
  }

  Widget _buildAttachmentImageWidget(Map<String, dynamic> item) {
    final dataUrl = (item['dataUrl'] as String? ?? '').trim();
    if (dataUrl.startsWith('data:')) {
      final bytes = _decodeDataUrlBytes(dataUrl);
      if (bytes != null) {
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildImageFallback(),
        );
      }
    }

    final url = (item['url'] as String? ?? '').trim();
    if (url.startsWith('http://') || url.startsWith('https://')) {
      return Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildImageFallback(),
      );
    }
    if (url.startsWith('data:')) {
      final bytes = _decodeDataUrlBytes(url);
      if (bytes != null) {
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => _buildImageFallback(),
        );
      }
    }

    final path = (item['path'] as String? ?? '').trim();
    if (path.isNotEmpty && !path.startsWith('http')) {
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildImageFallback(),
      );
    }
    return _buildImageFallback();
  }

  Widget _buildImageFallback() {
    return const Center(
      child: Icon(
        Icons.image_not_supported_outlined,
        size: 20,
        color: Color(0xFF6A83AA),
      ),
    );
  }

  Widget _buildFileAttachmentChip(Map<String, dynamic> item) {
    final displayName = _resolveAttachmentDisplayName(item);
    final sizeText = _formatAttachmentSize(item['size']);

    return Container(
      constraints: const BoxConstraints(maxWidth: 220, minHeight: 40),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFE4EEFF),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFD0DEFA), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.insert_drive_file_outlined,
            size: 15,
            color: Color(0xFF375EAF),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              sizeText.isEmpty ? displayName : '$displayName\n$sizeText',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Color(0xFF35517A),
                fontSize: 12,
                fontWeight: FontWeight.w500,
                height: 1.25,
              ),
            ),
          ),
        ],
      ),
    );
  }

  bool _isImageAttachment(Map<String, dynamic> item) {
    final explicit = item['isImage'];
    if (explicit is bool && explicit) return true;
    final mimeType = (item['mimeType'] as String? ?? '').trim().toLowerCase();
    if (mimeType.startsWith('image/')) return true;
    final path = (item['path'] as String? ?? '').toLowerCase();
    final url = (item['url'] as String? ?? '').toLowerCase();
    final dataUrl = (item['dataUrl'] as String? ?? '').toLowerCase();
    return _looksLikeImage(path) ||
        _looksLikeImage(url) ||
        dataUrl.startsWith('data:image/');
  }

  bool _looksLikeImage(String value) {
    if (value.isEmpty) return false;
    final pure = value.split('?').first;
    return pure.endsWith('.png') ||
        pure.endsWith('.jpg') ||
        pure.endsWith('.jpeg') ||
        pure.endsWith('.gif') ||
        pure.endsWith('.webp') ||
        pure.endsWith('.bmp') ||
        pure.endsWith('.heic') ||
        pure.endsWith('.heif');
  }

  String _resolveAttachmentDisplayName(Map<String, dynamic> item) {
    final name = (item['name'] as String? ?? '').trim();
    if (name.isNotEmpty) return name;
    final fileName = (item['fileName'] as String? ?? '').trim();
    if (fileName.isNotEmpty) return fileName;
    final path = (item['path'] as String? ?? '').trim();
    if (path.isNotEmpty) {
      final normalizedPath = path.replaceAll('\\', '/');
      return normalizedPath.split('/').last;
    }
    final url = (item['url'] as String? ?? '').trim();
    if (url.isNotEmpty) {
      final normalizedUrl = url.split('?').first;
      final segments = normalizedUrl.split('/');
      if (segments.isNotEmpty && segments.last.isNotEmpty) {
        return segments.last;
      }
    }
    return '附件';
  }

  Uint8List? _decodeDataUrlBytes(String value) {
    final comma = value.indexOf(',');
    if (comma < 0 || comma + 1 >= value.length) return null;
    final base64Part = value.substring(comma + 1);
    try {
      return base64Decode(base64Part);
    } catch (_) {
      return null;
    }
  }

  String _formatAttachmentSize(dynamic rawSize) {
    final int? size = rawSize is int
        ? rawSize
        : (rawSize is String ? int.tryParse(rawSize) : null);
    if (size == null || size <= 0) return '';
    if (size < 1024) return '${size}B';
    if (size < 1024 * 1024) return '${(size / 1024).toStringAsFixed(1)}KB';
    return '${(size / (1024 * 1024)).toStringAsFixed(1)}MB';
  }

  /// 构建用户文本（不使用流式效果）
  Widget _buildUserText(String text) {
    return Text(
      text,
      style: const TextStyle(
        color: Color(0xFF353E53), // #353E53
        fontSize: 14,
        fontFamily: 'PingFang SC',
        fontWeight: FontWeight.w400,
        height: 1.43,
        letterSpacing: 0.33,
      ),
      textAlign: TextAlign.left,
    );
  }

  /// 构建AI文本（使用StreamingText组件）
  Widget _buildAiText(String text) {
    // 如果是 loading 状态，显示浮动三个点动画（左对齐，与回复文本位置一致）
    if (message.isLoading) {
      return const Align(
        alignment: Alignment.centerLeft,
        child: ThinkingDotsIndicator(),
      );
    }

    // 如果是总结中状态，显示"总结中"提示
    if (message.isSummarizing) {
      return _buildSummarizingIndicator();
    }

    // 如果有内容且之前是总结状态（通过taskId判断），显示"总结如下"前缀
    final bool isSummaryContent =
        message.id.startsWith('vlm-summary-') ||
        message.id.startsWith('task-summary-');

    if (isSummaryContent && text.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryCompleteHeader(),
          const SizedBox(height: 8),
          StreamingText(
            enableMarkdown: true,
            fullText: text,
            selectable: true,
            style: const TextStyle(
              fontSize: 14,
              color: Color(0xFF353E53), // #353E53
              height: 1.57,
            ),
          ),
        ],
      );
    }

    return StreamingText(
      enableMarkdown: true,
      fullText: text,
      selectable: true,
      style: const TextStyle(
        fontSize: 14,
        color: Color(0xFF353E53), // #353E53
        height: 1.57,
      ),
    );
  }

  /// 构建"总结中"指示器
  Widget _buildSummarizingIndicator() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          'assets/common/summary_loading.svg',
          width: 16,
          height: 16,
          colorFilter: const ColorFilter.mode(
            Color(0xFF4F83FF),
            BlendMode.srcIn,
          ),
        ),
        const SizedBox(width: 6),
        const Text(
          kSummarizingText,
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF4F83FF),
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(width: 8),
        const ThinkingDotsIndicator(
          dotColor: Color(0xFF4F83FF),
          dotSize: 6.0,
          spacing: 3.0,
        ),
      ],
    );
  }

  /// 构建"总结如下"标题
  Widget _buildSummaryCompleteHeader() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          'assets/common/summary_complete.svg',
          width: 16,
          height: 16,
          colorFilter: const ColorFilter.mode(
            Color(0xFF52C41A),
            BlendMode.srcIn,
          ),
        ),
        const SizedBox(width: 6),
        const Text(
          kSummaryCompleteText,
          style: TextStyle(
            fontSize: 14,
            color: Color(0xFF52C41A),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  /// 构建卡片消息
  Widget _buildCardMessage(BuildContext context) {
    final cardData = message.cardData ?? {};

    // 卡片消息撑满聊天框宽度，减去头像和间距的宽度
    return SizedBox(
      width: double.infinity,
      child: CardWidgetFactory.createCard(
        cardData,
        onBeforeTaskExecute: onBeforeTaskExecute,
        onRequestAuthorize: onRequestAuthorize,
        onCancelTask: onCancelTask,
        enableThinkingCollapse: enableThinkingCollapse,
        parentScrollController: parentScrollController,
      ),
    );
  }
}
