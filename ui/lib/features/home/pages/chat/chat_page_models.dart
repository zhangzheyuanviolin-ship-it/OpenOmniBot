import 'dart:collection';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:ui/models/chat_message_model.dart';

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

enum ChatMessageListMutationKind { none, content, structure }

class ChatMessageListItemNotifier extends ValueNotifier<ChatMessageModel> {
  ChatMessageListItemNotifier(super.value);

  void update(ChatMessageModel message) {
    value = message;
  }
}

class ObservableChatMessageList extends ChangeNotifier
    with ListMixin<ChatMessageModel> {
  static const String _kAgentToolSummaryCardType = 'agent_tool_summary';

  final List<ChatMessageModel> _messages = <ChatMessageModel>[];
  final List<ChatMessageListItemNotifier> _messageNotifiers =
      <ChatMessageListItemNotifier>[];

  bool _isDisposed = false;
  int _structureRevision = 0;
  int _lastMutationRevision = 0;
  bool _lastMutationAffectsPageChrome = false;
  ChatMessageListMutationKind _lastMutationKind =
      ChatMessageListMutationKind.none;

  int get structureRevision => _structureRevision;
  int get lastMutationRevision => _lastMutationRevision;
  bool get lastMutationAffectsPageChrome => _lastMutationAffectsPageChrome;
  ChatMessageListMutationKind get lastMutationKind => _lastMutationKind;

  ValueListenable<ChatMessageModel> listenableAt(int index) {
    return _messageNotifiers[index];
  }

  @override
  void addListener(VoidCallback listener) {
    if (_isDisposed) {
      return;
    }
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    if (_isDisposed) {
      return;
    }
    super.removeListener(listener);
  }

  void replaceAllMessages(Iterable<ChatMessageModel> messages) {
    final nextMessages = List<ChatMessageModel>.from(messages);
    final affectsPageChrome =
        _batchAffectsPageChrome(_messages) ||
        _batchAffectsPageChrome(nextMessages);
    _disposeMessageNotifiers(_messageNotifiers);
    _messages
      ..clear()
      ..addAll(nextMessages);
    _messageNotifiers
      ..clear()
      ..addAll(nextMessages.map(ChatMessageListItemNotifier.new));
    _recordStructureMutation(affectsPageChrome: affectsPageChrome);
    notifyListeners();
  }

  @override
  int get length => _messages.length;

  @override
  set length(int newLength) {
    RangeError.checkNotNegative(newLength, 'newLength');
    if (newLength == _messages.length) {
      return;
    }
    if (newLength > _messages.length) {
      throw UnsupportedError(
        'Expanding the message list length is unsupported',
      );
    }
    final removedMessages = _messages.sublist(newLength);
    final removedNotifiers = _messageNotifiers.sublist(newLength);
    _messages.removeRange(newLength, _messages.length);
    _messageNotifiers.removeRange(newLength, _messageNotifiers.length);
    _disposeMessageNotifiers(removedNotifiers);
    _recordStructureMutation(
      affectsPageChrome: _batchAffectsPageChrome(removedMessages),
    );
    notifyListeners();
  }

  @override
  ChatMessageModel operator [](int index) => _messages[index];

  @override
  void operator []=(int index, ChatMessageModel value) {
    final previous = _messages[index];
    _messages[index] = value;
    _messageNotifiers[index].update(value);
    _recordContentMutation(
      affectsPageChrome:
          _messageAffectsPageChrome(previous) ||
          _messageAffectsPageChrome(value),
    );
  }

  @override
  void add(ChatMessageModel value) {
    insert(length, value);
  }

  @override
  void addAll(Iterable<ChatMessageModel> iterable) {
    final nextMessages = List<ChatMessageModel>.from(iterable);
    if (nextMessages.isEmpty) {
      return;
    }
    _messages.addAll(nextMessages);
    _messageNotifiers.addAll(nextMessages.map(ChatMessageListItemNotifier.new));
    _recordStructureMutation(
      affectsPageChrome: _batchAffectsPageChrome(nextMessages),
    );
    notifyListeners();
  }

  @override
  void clear() {
    if (_messages.isEmpty) {
      return;
    }
    final removedMessages = List<ChatMessageModel>.from(_messages);
    _messages.clear();
    _disposeMessageNotifiers(_messageNotifiers);
    _messageNotifiers.clear();
    _recordStructureMutation(
      affectsPageChrome: _batchAffectsPageChrome(removedMessages),
    );
    notifyListeners();
  }

  @override
  void insert(int index, ChatMessageModel element) {
    _messages.insert(index, element);
    _messageNotifiers.insert(index, ChatMessageListItemNotifier(element));
    _recordStructureMutation(
      affectsPageChrome: _messageAffectsPageChrome(element),
    );
    notifyListeners();
  }

  @override
  void insertAll(int index, Iterable<ChatMessageModel> iterable) {
    final nextMessages = List<ChatMessageModel>.from(iterable);
    if (nextMessages.isEmpty) {
      return;
    }
    _messages.insertAll(index, nextMessages);
    _messageNotifiers.insertAll(
      index,
      nextMessages.map(ChatMessageListItemNotifier.new),
    );
    _recordStructureMutation(
      affectsPageChrome: _batchAffectsPageChrome(nextMessages),
    );
    notifyListeners();
  }

  @override
  ChatMessageModel removeAt(int index) {
    final removedMessage = _messages.removeAt(index);
    final removedNotifier = _messageNotifiers.removeAt(index);
    removedNotifier.dispose();
    _recordStructureMutation(
      affectsPageChrome: _messageAffectsPageChrome(removedMessage),
    );
    notifyListeners();
    return removedMessage;
  }

  @override
  void removeRange(int start, int end) {
    if (start == end) {
      return;
    }
    final removedMessages = _messages.sublist(start, end);
    final removedNotifiers = _messageNotifiers.sublist(start, end);
    _messages.removeRange(start, end);
    _messageNotifiers.removeRange(start, end);
    _disposeMessageNotifiers(removedNotifiers);
    _recordStructureMutation(
      affectsPageChrome: _batchAffectsPageChrome(removedMessages),
    );
    notifyListeners();
  }

  @override
  void removeWhere(bool Function(ChatMessageModel element) test) {
    final removedMessages = <ChatMessageModel>[];
    final removedNotifiers = <ChatMessageListItemNotifier>[];
    for (var index = _messages.length - 1; index >= 0; index--) {
      final message = _messages[index];
      if (!test(message)) {
        continue;
      }
      removedMessages.add(message);
      removedNotifiers.add(_messageNotifiers[index]);
      _messages.removeAt(index);
      _messageNotifiers.removeAt(index);
    }
    if (removedMessages.isEmpty) {
      return;
    }
    _disposeMessageNotifiers(removedNotifiers);
    _recordStructureMutation(
      affectsPageChrome: _batchAffectsPageChrome(removedMessages),
    );
    notifyListeners();
  }

  @override
  void dispose() {
    if (_isDisposed) {
      return;
    }
    _isDisposed = true;
    _disposeMessageNotifiers(_messageNotifiers);
    _messageNotifiers.clear();
    _messages.clear();
    super.dispose();
  }

  void _recordContentMutation({required bool affectsPageChrome}) {
    _lastMutationRevision += 1;
    _lastMutationAffectsPageChrome = affectsPageChrome;
    _lastMutationKind = ChatMessageListMutationKind.content;
  }

  void _recordStructureMutation({required bool affectsPageChrome}) {
    _structureRevision += 1;
    _lastMutationRevision += 1;
    _lastMutationAffectsPageChrome = affectsPageChrome;
    _lastMutationKind = ChatMessageListMutationKind.structure;
  }

  bool _batchAffectsPageChrome(Iterable<ChatMessageModel> messages) {
    for (final message in messages) {
      if (_messageAffectsPageChrome(message)) {
        return true;
      }
    }
    return false;
  }

  bool _messageAffectsPageChrome(ChatMessageModel message) {
    if (message.type != 2) {
      return false;
    }
    return (message.cardData?['type'] ?? '').toString() ==
        _kAgentToolSummaryCardType;
  }

  void _disposeMessageNotifiers(
    Iterable<ChatMessageListItemNotifier> notifiers,
  ) {
    for (final notifier in notifiers) {
      notifier.dispose();
    }
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
