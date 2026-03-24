import 'dart:convert';

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
