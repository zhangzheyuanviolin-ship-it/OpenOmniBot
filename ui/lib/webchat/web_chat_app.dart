// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:html' as html;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:ui/models/chat_message_model.dart';
import 'package:ui/models/conversation_model.dart';
import 'package:ui/webchat/web_backends.dart';

enum _ShellSection { chat, workspace, browser }

class WebChatApp extends StatelessWidget {
  const WebChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Omnibot Web Chat',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF2E6AE6),
          brightness: Brightness.light,
        ),
        scaffoldBackgroundColor: const Color(0xFFF4F7FC),
        fontFamily: 'PingFang SC',
      ),
      home: const _WebChatHome(),
    );
  }
}

class _PendingAttachment {
  const _PendingAttachment({
    required this.name,
    required this.mimeType,
    required this.size,
    required this.dataUrl,
    required this.isImage,
  });

  final String name;
  final String mimeType;
  final int size;
  final String dataUrl;
  final bool isImage;

  Map<String, dynamic> toPayload() {
    return <String, dynamic>{
      'fileName': name,
      'mimeType': mimeType,
      'size': size,
      'dataUrl': dataUrl,
      'isImage': isImage,
    };
  }
}

class _WebChatHome extends StatefulWidget {
  const _WebChatHome();

  @override
  State<_WebChatHome> createState() => _WebChatHomeState();
}

class _WebChatHomeState extends State<_WebChatHome> {
  final WebChatHttpClient _client = WebChatHttpClient();
  final WebRunStreamBackend _events = WebRunStreamBackend();
  final TextEditingController _tokenController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();
  final TextEditingController _workspaceEditorController =
      TextEditingController();
  final TextEditingController _browserUrlController = TextEditingController();
  final ScrollController _chatScrollController = ScrollController();

  StreamSubscription<WebChatEvent>? _eventsSubscription;

  bool _booting = true;
  bool _authenticated = false;
  bool _loadingConversations = false;
  bool _sendingMessage = false;
  bool _workspaceBusy = false;
  bool _browserBusy = false;
  bool _archivedOnly = false;
  bool _workspaceDirty = false;
  String? _error;
  String? _workspaceCurrentPath;
  String? _workspaceSelectedFilePath;
  String? _activeClarifyTaskId;
  int _browserFrameSeed = 0;
  _ShellSection _mobileSection = _ShellSection.chat;

  List<ConversationModel> _conversations = <ConversationModel>[];
  ConversationModel? _selectedConversation;
  List<ChatMessageModel> _messages = <ChatMessageModel>[];
  final Map<String, ChatMessageModel> _ephemeralThinkingCards =
      <String, ChatMessageModel>{};
  final List<_PendingAttachment> _pendingAttachments = <_PendingAttachment>[];
  List<Map<String, dynamic>> _workspaceItems = <Map<String, dynamic>>[];
  Map<String, dynamic>? _workspaceInfo;
  Map<String, dynamic>? _browserSnapshot;

  @override
  void initState() {
    super.initState();
    _workspaceEditorController.addListener(() {
      if (_workspaceSelectedFilePath != null) {
        setState(() {
          _workspaceDirty = true;
        });
      }
    });
    _tryBootstrapFromSavedToken();
  }

  @override
  void dispose() {
    _eventsSubscription?.cancel();
    _events.dispose();
    _client.dispose();
    _tokenController.dispose();
    _messageController.dispose();
    _workspaceEditorController.dispose();
    _browserUrlController.dispose();
    _chatScrollController.dispose();
    super.dispose();
  }

  Future<void> _tryBootstrapFromSavedToken() async {
    final queryToken = Uri.base.queryParameters['token']?.trim();
    final savedToken = html.window.localStorage['omnibot_webchat_token']
        ?.trim();
    final token =
        (queryToken?.isNotEmpty == true ? queryToken : savedToken) ?? '';
    if (token.isEmpty) {
      setState(() {
        _booting = false;
      });
      return;
    }
    _tokenController.text = token;
    await _bootstrap(token);
  }

  Future<void> _bootstrap(String token) async {
    setState(() {
      _booting = true;
      _error = null;
    });
    try {
      await _client.bootstrapSession(token);
      html.window.localStorage['omnibot_webchat_token'] = token;
      final bootstrap = await _client.bootstrap();
      final workspace = Map<String, dynamic>.from(
        (bootstrap['workspace'] as Map?) ?? const <String, dynamic>{},
      );
      final browser = Map<String, dynamic>.from(
        (bootstrap['browser'] as Map?) ?? const <String, dynamic>{},
      );
      _workspaceInfo = Map<String, dynamic>.from(
        (workspace['workspace'] as Map?) ?? const <String, dynamic>{},
      );
      _workspaceCurrentPath =
          (workspace['root'] as Map?)?['path']?.toString() ??
          _workspaceInfo?['rootPath']?.toString();
      _workspaceItems =
          ((workspace['root'] as Map?)?['items'] as List?)
              ?.whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList() ??
          <Map<String, dynamic>>[];
      _browserSnapshot = browser;
      _browserUrlController.text = (browser['currentUrl'] ?? '').toString();
      await _loadConversations(preserveSelection: false);
      _connectEvents();
      setState(() {
        _authenticated = true;
        _booting = false;
      });
    } catch (error) {
      setState(() {
        _error = error.toString();
        _authenticated = false;
        _booting = false;
      });
    }
  }

  void _connectEvents() {
    _eventsSubscription?.cancel();
    _eventsSubscription = _events.connect().listen(_handleEvent);
  }

  Future<void> _loadConversations({required bool preserveSelection}) async {
    setState(() {
      _loadingConversations = true;
    });
    final conversations = await _client.listConversations(
      includeArchived: true,
      archivedOnly: _archivedOnly,
    );
    ConversationModel? nextSelection;
    if (preserveSelection && _selectedConversation != null) {
      for (final conversation in conversations) {
        if (conversation.id == _selectedConversation!.id &&
            conversation.mode == _selectedConversation!.mode) {
          nextSelection = conversation;
          break;
        }
      }
    }
    nextSelection ??= conversations.isNotEmpty ? conversations.first : null;
    setState(() {
      _conversations = conversations;
      _selectedConversation = nextSelection;
      _loadingConversations = false;
    });
    if (nextSelection != null) {
      await _selectConversation(nextSelection);
    } else {
      setState(() {
        _messages = <ChatMessageModel>[];
      });
    }
  }

  Future<void> _selectConversation(ConversationModel conversation) async {
    final messages = await _client.getMessages(
      conversation.id,
      mode: conversation.mode,
    );
    if (!mounted) return;
    setState(() {
      _selectedConversation = conversation;
      _messages = messages;
    });
  }

  Future<void> _createConversation() async {
    final conversation = await _client.createConversation(
      title: '新对话',
      mode: ConversationMode.normal,
    );
    setState(() {
      _archivedOnly = false;
      _selectedConversation = conversation;
    });
    await _loadConversations(preserveSelection: true);
  }

  Future<void> _sendMessage({
    String? overrideText,
    List<_PendingAttachment>? overrideAttachments,
  }) async {
    final text = (overrideText ?? _messageController.text).trim();
    final attachments = overrideAttachments ?? _pendingAttachments;
    if (text.isEmpty && attachments.isEmpty) {
      return;
    }
    setState(() {
      _sendingMessage = true;
      _error = null;
    });
    try {
      var conversation = _selectedConversation;
      if (conversation == null) {
        conversation = await _client.createConversation(
          title: text.isEmpty ? '新对话' : text,
          mode: ConversationMode.normal,
        );
        setState(() {
          _selectedConversation = conversation;
        });
        await _loadConversations(preserveSelection: true);
      }
      await _client.startRun(
        conversation.id,
        userMessage: text,
        mode: conversation.mode,
        attachments: attachments.map((item) => item.toPayload()).toList(),
      );
      if (overrideText == null) {
        _messageController.clear();
      }
      if (overrideAttachments == null) {
        _pendingAttachments.clear();
      }
      setState(() {
        _sendingMessage = false;
      });
    } catch (error) {
      setState(() {
        _sendingMessage = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      type: FileType.any,
    );
    if (result == null) {
      return;
    }
    final attachments = result.files.where((file) => file.bytes != null).map((
      file,
    ) {
      final mimeType = file.extension == null
          ? 'application/octet-stream'
          : _mimeTypeForExtension(file.extension!);
      final bytes = file.bytes!;
      final dataUrl =
          'data:$mimeType;base64,${base64Encode(Uint8List.fromList(bytes))}';
      return _PendingAttachment(
        name: file.name,
        mimeType: mimeType,
        size: bytes.length,
        dataUrl: dataUrl,
        isImage: mimeType.startsWith('image/'),
      );
    }).toList();
    setState(() {
      _pendingAttachments.addAll(attachments);
    });
  }

  Future<void> _updateArchiveState(bool archived) async {
    final conversation = _selectedConversation;
    if (conversation == null) return;
    final updated = await _client.updateConversation(
      conversation.copyWith(isArchived: archived),
    );
    setState(() {
      _selectedConversation = updated;
    });
    await _loadConversations(preserveSelection: true);
  }

  Future<void> _deleteSelectedConversation() async {
    final conversation = _selectedConversation;
    if (conversation == null) return;
    await _client.deleteConversation(conversation.id);
    _ephemeralThinkingCards.remove(_conversationKey(conversation));
    await _loadConversations(preserveSelection: false);
  }

  Future<void> _reloadWorkspace({String? path}) async {
    final payload = await _client.list(path: path ?? _workspaceCurrentPath);
    setState(() {
      _workspaceCurrentPath = (payload['path'] ?? _workspaceCurrentPath ?? '')
          .toString();
      _workspaceItems = ((payload['items'] as List?) ?? const <dynamic>[])
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    });
  }

  Future<void> _openWorkspaceEntry(Map<String, dynamic> entry) async {
    final isDirectory = entry['isDirectory'] == true;
    final path = (entry['path'] ?? '').toString();
    if (path.isEmpty) {
      return;
    }
    if (isDirectory) {
      await _reloadWorkspace(path: path);
      return;
    }
    setState(() {
      _workspaceBusy = true;
      _workspaceSelectedFilePath = path;
      _workspaceDirty = false;
    });
    try {
      final payload = await _client.readFile(path);
      if (!mounted) return;
      setState(() {
        _workspaceSelectedFilePath = path;
        _workspaceEditorController.text = (payload['content'] ?? '').toString();
        _workspaceDirty = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _workspaceBusy = false;
        });
      }
    }
  }

  Future<void> _saveWorkspaceFile() async {
    final path = _workspaceSelectedFilePath;
    if (path == null) return;
    setState(() {
      _workspaceBusy = true;
    });
    try {
      await _client.writeFile(path, _workspaceEditorController.text);
      await _reloadWorkspace();
      if (!mounted) return;
      setState(() {
        _workspaceDirty = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _workspaceBusy = false;
        });
      }
    }
  }

  Future<void> _navigateBrowser() async {
    final url = _browserUrlController.text.trim();
    if (url.isEmpty) return;
    await _runBrowserAction(<String, dynamic>{
      'action': 'navigate',
      'url': url,
      'tool_title': 'Web Chat Navigate',
    });
  }

  Future<void> _runBrowserAction(Map<String, dynamic> payload) async {
    setState(() {
      _browserBusy = true;
    });
    try {
      final result = await _client.action(payload);
      final snapshot = Map<String, dynamic>.from(
        (result['snapshot'] as Map?) ?? const <String, dynamic>{},
      );
      if (!mounted) return;
      setState(() {
        _browserSnapshot = snapshot;
        _browserUrlController.text = (snapshot['currentUrl'] ?? '').toString();
        _browserFrameSeed++;
      });
    } finally {
      if (mounted) {
        setState(() {
          _browserBusy = false;
        });
      }
    }
  }

  void _handleEvent(WebChatEvent event) {
    final data = event.data;
    switch (event.event) {
      case 'conversation_created':
      case 'conversation_updated':
      case 'conversation_deleted':
        unawaited(_loadConversations(preserveSelection: true));
        break;
      case 'messages_replaced':
        final key = _conversationKeyFromPayload(data);
        if (key != null && _selectedConversation != null) {
          if (key == _conversationKey(_selectedConversation!)) {
            final messages = ((data['messages'] as List?) ?? const <dynamic>[])
                .whereType<Map>()
                .map(
                  (item) => ChatMessageModel.fromJson(
                    Map<String, dynamic>.from(item.cast<String, dynamic>()),
                  ),
                )
                .toList();
            setState(() {
              _messages = messages;
            });
          }
        }
        break;
      case 'agent_thinking_start':
      case 'agent_thinking_update':
      case 'agent_complete':
      case 'agent_error':
        _applyThinkingEvent(event);
        break;
      case 'browser_snapshot_updated':
        final snapshot = Map<String, dynamic>.from(
          (data['snapshot'] as Map?) ?? const <String, dynamic>{},
        );
        setState(() {
          _browserSnapshot = snapshot;
          _browserUrlController.text = (snapshot['currentUrl'] ?? '')
              .toString();
          _browserFrameSeed++;
        });
        break;
      case 'workspace_changed':
        if (_workspaceCurrentPath != null) {
          unawaited(_reloadWorkspace());
        }
        break;
      case 'agent_clarify_required':
        setState(() {
          _activeClarifyTaskId = data['taskId']?.toString();
        });
        break;
    }
  }

  void _applyThinkingEvent(WebChatEvent event) {
    final key = _conversationKeyFromPayload(event.data);
    final taskId = event.data['taskId']?.toString();
    if (key == null || taskId == null || taskId.isEmpty) {
      return;
    }
    final existing = _ephemeralThinkingCards[key];
    final existingCardData = Map<String, dynamic>.from(
      existing?.cardData ?? const <String, dynamic>{},
    );
    final cardData = <String, dynamic>{
      ...existingCardData,
      'type': 'deep_thinking',
      'taskID': taskId,
      'startTime':
          existingCardData['startTime'] ??
          event.data['timestamp'] ??
          DateTime.now().millisecondsSinceEpoch,
      'thinkingContent': existingCardData['thinkingContent'] ?? '',
      'isCollapsible': true,
    };
    if (event.event == 'agent_thinking_update') {
      cardData['thinkingContent'] = (event.data['thinking'] ?? '').toString();
      cardData['isLoading'] = true;
      cardData['stage'] = 1;
    } else if (event.event == 'agent_thinking_start') {
      cardData['isLoading'] = true;
      cardData['stage'] = 1;
    } else if (event.event == 'agent_complete') {
      cardData['isLoading'] = false;
      cardData['stage'] = 4;
      _activeClarifyTaskId = null;
    } else if (event.event == 'agent_error') {
      cardData['isLoading'] = false;
      cardData['stage'] = 5;
      _activeClarifyTaskId = null;
    }
    _ephemeralThinkingCards[key] =
        ChatMessageModel.cardMessage(cardData, id: '$taskId-thinking').copyWith(
          createAt: DateTime.fromMillisecondsSinceEpoch(
            (event.data['timestamp'] as num?)?.toInt() ??
                DateTime.now().millisecondsSinceEpoch,
          ),
        );
    if (_selectedConversation != null &&
        key == _conversationKey(_selectedConversation!)) {
      setState(() {});
    }
  }

  String? _conversationKeyFromPayload(Map<String, dynamic> payload) {
    final conversationId = (payload['conversationId'] as num?)?.toInt();
    final rawMode =
        payload['conversationMode'] as String? ?? payload['mode'] as String?;
    if (conversationId == null) {
      return null;
    }
    return '${ConversationMode.fromStorageValue(rawMode).storageValue}:$conversationId';
  }

  String _conversationKey(ConversationModel conversation) {
    return '${conversation.mode.storageValue}:${conversation.id}';
  }

  List<ChatMessageModel> get _displayMessages {
    final conversation = _selectedConversation;
    if (conversation == null) {
      return _messages.reversed.toList();
    }
    final merged = <ChatMessageModel>[
      ..._messages,
      if (_ephemeralThinkingCards.containsKey(_conversationKey(conversation)))
        _ephemeralThinkingCards[_conversationKey(conversation)]!,
    ];
    merged.sort((a, b) => a.createAt.compareTo(b.createAt));
    return merged;
  }

  @override
  Widget build(BuildContext context) {
    if (_booting) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (!_authenticated) {
      return _buildLogin(context);
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isDesktop = constraints.maxWidth >= 980;
        if (!isDesktop) {
          return _buildMobileShell(context);
        }
        return _buildDesktopShell(context);
      },
    );
  }

  Widget _buildLogin(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(28),
            ),
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Omnibot Web Chat',
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    '输入本机 MCP Server Token 以换取 Web Chat 会话 Cookie。',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: _tokenController,
                    decoration: const InputDecoration(
                      labelText: 'Server Token',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () => _bootstrap(_tokenController.text.trim()),
                    child: const Text('连接'),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: const TextStyle(color: Colors.red)),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopShell(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            SizedBox(width: 320, child: _buildConversationSidebar(context)),
            Expanded(child: _buildChatPane(context)),
            SizedBox(width: 360, child: _buildSidePanels(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildMobileShell(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          _selectedConversation?.title ?? 'Omnibot Web Chat',
          overflow: TextOverflow.ellipsis,
        ),
      ),
      body: SafeArea(
        child: switch (_mobileSection) {
          _ShellSection.chat => Column(
            children: [
              SizedBox(height: 164, child: _buildConversationSidebar(context)),
              Expanded(child: _buildChatPane(context)),
            ],
          ),
          _ShellSection.workspace => _buildWorkspacePanel(context),
          _ShellSection.browser => _buildBrowserPanel(context),
        },
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _mobileSection.index,
        onDestinationSelected: (index) {
          setState(() {
            _mobileSection = _ShellSection.values[index];
          });
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            label: '聊天',
          ),
          NavigationDestination(
            icon: Icon(Icons.folder_outlined),
            label: '工作区',
          ),
          NavigationDestination(
            icon: Icon(Icons.language_outlined),
            label: '浏览器',
          ),
        ],
      ),
    );
  }

  Widget _buildConversationSidebar(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        border: Border(
          right: BorderSide(color: Color(0xFFE3EAF7)),
          bottom: BorderSide(color: Color(0xFFE3EAF7)),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment<bool>(value: false, label: Text('进行中')),
                      ButtonSegment<bool>(value: true, label: Text('归档')),
                    ],
                    selected: <bool>{_archivedOnly},
                    onSelectionChanged: (selection) {
                      setState(() {
                        _archivedOnly = selection.first;
                      });
                      unawaited(_loadConversations(preserveSelection: false));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _createConversation,
                  icon: const Icon(Icons.add),
                  label: const Text('新建'),
                ),
              ],
            ),
          ),
          if (_loadingConversations)
            const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView.builder(
              itemCount: _conversations.length,
              itemBuilder: (context, index) {
                final conversation = _conversations[index];
                final selected =
                    _selectedConversation?.threadKey == conversation.threadKey;
                return ListTile(
                  selected: selected,
                  title: Text(
                    conversation.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    conversation.summary?.isNotEmpty == true
                        ? conversation.summary!
                        : conversation.lastMessage?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (value) {
                      switch (value) {
                        case 'archive':
                          unawaited(
                            _client
                                .updateConversation(
                                  conversation.copyWith(isArchived: true),
                                )
                                .then(
                                  (_) => _loadConversations(
                                    preserveSelection: true,
                                  ),
                                ),
                          );
                          break;
                        case 'unarchive':
                          unawaited(
                            _client
                                .updateConversation(
                                  conversation.copyWith(isArchived: false),
                                )
                                .then(
                                  (_) => _loadConversations(
                                    preserveSelection: true,
                                  ),
                                ),
                          );
                          break;
                        case 'delete':
                          unawaited(
                            _client
                                .deleteConversation(conversation.id)
                                .then(
                                  (_) => _loadConversations(
                                    preserveSelection: false,
                                  ),
                                ),
                          );
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<String>(
                        value: conversation.isArchived
                            ? 'unarchive'
                            : 'archive',
                        child: Text(conversation.isArchived ? '取消归档' : '归档'),
                      ),
                      const PopupMenuItem<String>(
                        value: 'delete',
                        child: Text('删除'),
                      ),
                    ],
                  ),
                  onTap: () => unawaited(_selectConversation(conversation)),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatPane(BuildContext context) {
    return Column(
      children: [
        Container(
          height: 64,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE3EAF7))),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _selectedConversation?.title ?? '选择一个对话开始聊天',
                  style: Theme.of(context).textTheme.titleMedium,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (_selectedConversation != null) ...[
                IconButton(
                  tooltip: _selectedConversation!.isArchived ? '取消归档' : '归档',
                  onPressed: () =>
                      _updateArchiveState(!_selectedConversation!.isArchived),
                  icon: Icon(
                    _selectedConversation!.isArchived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                  ),
                ),
                IconButton(
                  tooltip: '删除',
                  onPressed: _deleteSelectedConversation,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ],
          ),
        ),
        if (_error != null)
          Container(
            width: double.infinity,
            color: const Color(0xFFFFF0F0),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Text(
              _error!,
              style: const TextStyle(color: Color(0xFFB42318)),
            ),
          ),
        Expanded(
          child: ListView.builder(
            controller: _chatScrollController,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
            itemCount: _displayMessages.length,
            itemBuilder: (context, index) {
              final message = _displayMessages[index];
              return _buildMessageBubble(context, message);
            },
          ),
        ),
        if (_activeClarifyTaskId != null)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            child: OutlinedButton.icon(
              onPressed: () async {
                final text = _messageController.text.trim();
                if (text.isEmpty) {
                  return;
                }
                await _client.clarifyTask(_activeClarifyTaskId!, text);
                _messageController.clear();
                setState(() {
                  _activeClarifyTaskId = null;
                });
              },
              icon: const Icon(Icons.help_outline),
              label: const Text('将输入内容作为澄清回复发送'),
            ),
          ),
        Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFE3EAF7))),
            color: Colors.white,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_pendingAttachments.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _pendingAttachments.map((attachment) {
                    return InputChip(
                      label: Text(attachment.name),
                      onDeleted: () {
                        setState(() {
                          _pendingAttachments.remove(attachment);
                        });
                      },
                    );
                  }).toList(),
                ),
              if (_pendingAttachments.isNotEmpty) const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: _pickAttachments,
                    icon: const Icon(Icons.attach_file),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      minLines: 1,
                      maxLines: 6,
                      decoration: const InputDecoration(
                        hintText: '直接和 Agent 对话...',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _sendingMessage ? null : _sendMessage,
                    child: _sendingMessage
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('发送'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSidePanels(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const Material(
            color: Colors.white,
            child: TabBar(
              tabs: [
                Tab(text: '工作区'),
                Tab(text: '浏览器'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildWorkspacePanel(context),
                _buildBrowserPanel(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWorkspacePanel(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE3EAF7))),
            color: Colors.white,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _workspaceCurrentPath ?? '工作区',
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                onPressed: () => _reloadWorkspace(),
                icon: const Icon(Icons.refresh),
              ),
              if (_workspaceSelectedFilePath != null)
                FilledButton(
                  onPressed: _workspaceBusy || !_workspaceDirty
                      ? null
                      : _saveWorkspaceFile,
                  child: const Text('保存'),
                ),
            ],
          ),
        ),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 180,
                child: ListView.builder(
                  itemCount: _workspaceItems.length,
                  itemBuilder: (context, index) {
                    final entry = _workspaceItems[index];
                    final isDirectory = entry['isDirectory'] == true;
                    final path = (entry['path'] ?? '').toString();
                    final selected = path == _workspaceSelectedFilePath;
                    return ListTile(
                      dense: true,
                      selected: selected,
                      leading: Icon(
                        isDirectory
                            ? Icons.folder_outlined
                            : Icons.description_outlined,
                        size: 18,
                      ),
                      title: Text(
                        (entry['name'] ?? '').toString(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => unawaited(_openWorkspaceEntry(entry)),
                    );
                  },
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _workspaceSelectedFilePath == null
                    ? const Center(child: Text('选择一个文件开始查看或编辑'))
                    : Padding(
                        padding: const EdgeInsets.all(12),
                        child: TextField(
                          controller: _workspaceEditorController,
                          expands: true,
                          maxLines: null,
                          minLines: null,
                          decoration: InputDecoration(
                            labelText: _workspaceSelectedFilePath,
                            border: const OutlineInputBorder(),
                            alignLabelWithHint: true,
                          ),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBrowserPanel(BuildContext context) {
    final snapshot = _browserSnapshot ?? const <String, dynamic>{};
    final available = snapshot['available'] == true;
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE3EAF7))),
            color: Colors.white,
          ),
          child: Column(
            children: [
              TextField(
                controller: _browserUrlController,
                decoration: const InputDecoration(
                  hintText: '输入网址并远程导航',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _navigateBrowser(),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  FilledButton(
                    onPressed: _browserBusy ? null : _navigateBrowser,
                    child: const Text('打开'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _browserBusy
                        ? null
                        : () => _runBrowserAction(<String, dynamic>{
                            'action': 'scroll',
                            'direction': 'up',
                            'amount': 420,
                            'tool_title': 'Web Chat Scroll Up',
                          }),
                    child: const Text('上滑'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: _browserBusy
                        ? null
                        : () => _runBrowserAction(<String, dynamic>{
                            'action': 'scroll',
                            'direction': 'down',
                            'amount': 420,
                            'tool_title': 'Web Chat Scroll Down',
                          }),
                    child: const Text('下滑'),
                  ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('当前页面', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 6),
              Text(
                (snapshot['title'] ?? '暂无会话').toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                (snapshot['currentUrl'] ?? '').toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
        Expanded(
          child: Center(
            child: available
                ? Padding(
                    padding: const EdgeInsets.all(12),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        _client.frameUrl(seed: _browserFrameSeed),
                        fit: BoxFit.contain,
                        errorBuilder: (_, __, ___) =>
                            const Center(child: Text('浏览器画面暂不可用')),
                      ),
                    ),
                  )
                : const Text('当前没有可镜像的浏览器会话'),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageBubble(BuildContext context, ChatMessageModel message) {
    if (message.type == 2) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: _buildCard(message.cardData ?? const <String, dynamic>{}),
      );
    }
    final isUser = message.user == 1;
    final attachments = _extractAttachments(message);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 6),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isUser ? const Color(0xFFDDEBFF) : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: isUser ? const Color(0xFFBBD4FF) : const Color(0xFFE3EAF7),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if ((message.text ?? '').isNotEmpty)
                SelectableText(
                  message.text!,
                  style: const TextStyle(height: 1.55),
                ),
              if (attachments.isNotEmpty) ...[
                if ((message.text ?? '').isNotEmpty) const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: attachments.map(_buildAttachmentChip).toList(),
                ),
              ],
              if (isUser && (message.text ?? '').isNotEmpty) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () => _sendMessage(overrideText: message.text),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('重试'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(Map<String, dynamic> cardData) {
    final type = (cardData['type'] ?? '').toString();
    switch (type) {
      case 'deep_thinking':
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FBFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFD6E4FA)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.psychology_alt_outlined, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    '思考中',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  if (cardData['isLoading'] == true)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SelectableText(
                (cardData['thinkingContent'] ?? '').toString().trim().isEmpty
                    ? '正在生成思考内容...'
                    : (cardData['thinkingContent'] ?? '').toString(),
                style: const TextStyle(color: Color(0xFF55657F), height: 1.55),
              ),
            ],
          ),
        );
      case 'agent_tool_summary':
        final status = (cardData['status'] ?? 'running').toString();
        final color = switch (status) {
          'success' => const Color(0xFF1E9C53),
          'error' => const Color(0xFFC73E1D),
          'interrupted' => const Color(0xFFF0A429),
          _ => const Color(0xFF2E6AE6),
        };
        return Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.auto_awesome_outlined, size: 16, color: color),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    (cardData['summary'] ??
                            cardData['toolTitle'] ??
                            cardData['displayName'] ??
                            '正在调用工具')
                        .toString(),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        );
      default:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFE3EAF7)),
          ),
          child: SelectableText(jsonEncode(cardData)),
        );
    }
  }

  List<Map<String, dynamic>> _extractAttachments(ChatMessageModel message) {
    final raw = message.content?['attachments'];
    if (raw is! List) {
      return const <Map<String, dynamic>>[];
    }
    return raw
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item.cast<String, dynamic>()))
        .toList();
  }

  Widget _buildAttachmentChip(Map<String, dynamic> item) {
    final dataUrl = (item['dataUrl'] ?? '').toString();
    final fileName = (item['fileName'] ?? item['name'] ?? item['path'] ?? '附件')
        .toString();
    final mimeType = (item['mimeType'] ?? '').toString();
    if (dataUrl.startsWith('data:image/')) {
      final bytes = _bytesFromDataUrl(dataUrl);
      if (bytes != null) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(bytes, width: 92, height: 92, fit: BoxFit.cover),
        );
      }
    }
    return Chip(
      avatar: Icon(
        mimeType.startsWith('image/')
            ? Icons.image_outlined
            : Icons.insert_drive_file_outlined,
        size: 18,
      ),
      label: Text(fileName, overflow: TextOverflow.ellipsis),
    );
  }

  Uint8List? _bytesFromDataUrl(String dataUrl) {
    final marker = dataUrl.indexOf(',');
    if (marker < 0) return null;
    return Uint8List.fromList(base64Decode(dataUrl.substring(marker + 1)));
  }

  String _mimeTypeForExtension(String extension) {
    switch (extension.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'md':
        return 'text/markdown';
      case 'json':
        return 'application/json';
      case 'txt':
      case 'log':
        return 'text/plain';
      default:
        return 'application/octet-stream';
    }
  }
}
