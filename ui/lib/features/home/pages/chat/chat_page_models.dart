import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

enum ChatIslandDisplayLayer {
  mode('mode'),
  model('model'),
  tools('tools');

  const ChatIslandDisplayLayer(this.wireName);

  final String wireName;

  static ChatIslandDisplayLayer fromWireName(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    for (final layer in ChatIslandDisplayLayer.values) {
      if (layer.wireName == normalized) {
        return layer;
      }
    }
    return ChatIslandDisplayLayer.mode;
  }
}

class ChatBrowserSessionSnapshot {
  const ChatBrowserSessionSnapshot({
    required this.available,
    required this.workspaceId,
    required this.activeTabId,
    required this.currentUrl,
    required this.title,
    this.userAgentProfile,
  });

  final bool available;
  final String workspaceId;
  final int? activeTabId;
  final String currentUrl;
  final String title;
  final String? userAgentProfile;

  bool matchesWorkspace(String? candidateWorkspaceId) {
    final normalizedCandidate = candidateWorkspaceId?.trim() ?? '';
    if (normalizedCandidate.isEmpty) {
      return false;
    }
    return workspaceId.trim() == normalizedCandidate;
  }

  ChatBrowserSessionSnapshot copyWith({
    bool? available,
    String? workspaceId,
    int? activeTabId,
    String? currentUrl,
    String? title,
    String? userAgentProfile,
  }) {
    return ChatBrowserSessionSnapshot(
      available: available ?? this.available,
      workspaceId: workspaceId ?? this.workspaceId,
      activeTabId: activeTabId ?? this.activeTabId,
      currentUrl: currentUrl ?? this.currentUrl,
      title: title ?? this.title,
      userAgentProfile: userAgentProfile ?? this.userAgentProfile,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'available': available,
      'workspaceId': workspaceId,
      'activeTabId': activeTabId,
      'currentUrl': currentUrl,
      'title': title,
      'userAgentProfile': userAgentProfile,
    };
  }

  factory ChatBrowserSessionSnapshot.fromMap(Map<dynamic, dynamic> raw) {
    final activeTabIdRaw = raw['activeTabId'];
    final activeTabId = activeTabIdRaw is num
        ? activeTabIdRaw.toInt()
        : int.tryParse(activeTabIdRaw?.toString() ?? '');
    return ChatBrowserSessionSnapshot(
      available: raw['available'] == true,
      workspaceId: (raw['workspaceId'] ?? '').toString(),
      activeTabId: activeTabId,
      currentUrl: (raw['currentUrl'] ?? '').toString(),
      title: (raw['title'] ?? '').toString(),
      userAgentProfile: raw['userAgentProfile']?.toString(),
    );
  }

  factory ChatBrowserSessionSnapshot.fromBrowserToolPayload({
    required Map<String, dynamic> payload,
    required String workspaceId,
  }) {
    final activeTabIdRaw = payload['activeTabId'] ?? payload['tabId'];
    final activeTabId = activeTabIdRaw is num
        ? activeTabIdRaw.toInt()
        : int.tryParse(activeTabIdRaw?.toString() ?? '');
    final currentUrl =
        (payload['currentUrl'] ?? payload['finalUrl'] ?? payload['url'] ?? '')
            .toString();
    final title = (payload['pageTitle'] ?? payload['title'] ?? '').toString();
    return ChatBrowserSessionSnapshot(
      available: true,
      workspaceId: workspaceId,
      activeTabId: activeTabId,
      currentUrl: currentUrl,
      title: title,
      userAgentProfile: payload['userAgentProfile']?.toString(),
    );
  }

  static ChatBrowserSessionSnapshot? tryParseBrowserToolJson({
    required String rawJson,
    required String workspaceId,
  }) {
    final text = rawJson.trim();
    if (text.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        return null;
      }
      final payload = decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      return ChatBrowserSessionSnapshot.fromBrowserToolPayload(
        payload: payload,
        workspaceId: workspaceId,
      );
    } catch (_) {
      return null;
    }
  }
}

String chatConversationWorkspaceId(int? conversationId) {
  return conversationId == null
      ? 'conversation_default'
      : 'conversation_$conversationId';
}

class HdPadPaneLayout {
  const HdPadPaneLayout({
    required this.leftWidth,
    required this.centerWidth,
    required this.rightWidth,
  });

  final double leftWidth;
  final double centerWidth;
  final double rightWidth;
}

class HdPadPaneLayoutResolver {
  const HdPadPaneLayoutResolver();

  static const double dividerHitWidth = 12;
  static const double defaultLeftWidth = 260;
  static const double minLeftWidth = 220;
  static const double maxLeftWidth = 360;
  static const double defaultRightWidth = 300;
  static const double minRightWidth = 240;
  static const double maxRightWidth = 420;
  static const double minCenterWidth = 320;

  HdPadPaneLayout resolve(
    double totalWidth, {
    double? preferredLeftWidth,
    double? preferredRightWidth,
    bool collapseLeftPane = false,
  }) {
    final dividerCount = collapseLeftPane ? 1 : 2;
    final availableWidth = math.max(
      0,
      totalWidth - dividerHitWidth * dividerCount,
    );

    var leftWidth = collapseLeftPane
        ? 0.0
        : (preferredLeftWidth ?? defaultLeftWidth).clamp(
            minLeftWidth,
            maxLeftWidth,
          );
    var rightWidth = (preferredRightWidth ?? defaultRightWidth).clamp(
      minRightWidth,
      maxRightWidth,
    );

    if (!collapseLeftPane) {
      final maxLeftBySpace = math.max(
        minLeftWidth,
        availableWidth - rightWidth - minCenterWidth,
      );
      leftWidth = leftWidth.clamp(minLeftWidth, maxLeftBySpace);
    }

    final maxRightBySpace = math.max(
      minRightWidth,
      availableWidth - leftWidth - minCenterWidth,
    );
    rightWidth = rightWidth.clamp(minRightWidth, maxRightBySpace);

    var centerWidth = availableWidth - leftWidth - rightWidth;
    if (centerWidth < minCenterWidth) {
      final rightFlexible = rightWidth - minRightWidth;
      if (rightFlexible > 0) {
        final delta = math.min(minCenterWidth - centerWidth, rightFlexible);
        rightWidth -= delta;
        centerWidth += delta;
      }
    }
    if (!collapseLeftPane && centerWidth < minCenterWidth) {
      final leftFlexible = leftWidth - minLeftWidth;
      if (leftFlexible > 0) {
        final delta = math.min(minCenterWidth - centerWidth, leftFlexible);
        leftWidth -= delta;
        centerWidth += delta;
      }
    }

    return HdPadPaneLayout(
      leftWidth: leftWidth,
      centerWidth: centerWidth,
      rightWidth: centerWidth.isNegative ? 0 : rightWidth,
    );
  }
}

class ChatPaneOverlayAnchorGeometry {
  const ChatPaneOverlayAnchorGeometry({
    required this.rect,
    required this.bottom,
  });

  final Rect rect;
  final double bottom;
}

ChatPaneOverlayAnchorGeometry resolveChatPaneOverlayAnchorGeometry({
  required Size viewportSize,
  double horizontalInset = 24,
  required double bottomSpacing,
  required double anchorHeight,
}) {
  final resolvedWidth = math.max(0.0, viewportSize.width - horizontalInset * 2);
  final resolvedBottom = bottomSpacing
      .clamp(0.0, viewportSize.height)
      .toDouble();
  final resolvedHeight = anchorHeight.isFinite
      ? math.max(0.0, anchorHeight)
      : 0.0;
  final top = (viewportSize.height - resolvedBottom)
      .clamp(0.0, viewportSize.height)
      .toDouble();
  return ChatPaneOverlayAnchorGeometry(
    rect: Rect.fromLTWH(horizontalInset, top, resolvedWidth, resolvedHeight),
    bottom: resolvedBottom,
  );
}
