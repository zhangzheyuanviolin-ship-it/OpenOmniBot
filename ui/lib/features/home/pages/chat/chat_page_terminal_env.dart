part of 'chat_page.dart';

mixin _ChatPageTerminalEnvMixin on _ChatPageStateBase {
  @override
  Future<void> _loadTerminalEnvironmentVariables() async {
    final variables = ChatTerminalEnvironmentService.loadVariables();
    if (!mounted) {
      _terminalEnvironmentVariables = variables;
      return;
    }
    setState(() {
      _terminalEnvironmentVariables = variables;
    });
  }

  @override
  Future<void> _updateTerminalEnvironmentVariables(
    List<ChatTerminalEnvironmentVariable> variables,
  ) async {
    final normalized = ChatTerminalEnvironmentService.normalizeVariables(
      variables,
    );
    try {
      await ChatTerminalEnvironmentService.saveVariables(normalized);
      if (!mounted) {
        _terminalEnvironmentVariables = normalized;
        return;
      }
      setState(() {
        _terminalEnvironmentVariables = normalized;
      });
    } catch (error) {
      if (mounted) {
        showToast('保存环境变量失败: $error', type: ToastType.error);
      }
    }
  }

  @override
  Future<void> _openTerminalEnvironmentEditor(
    BuildContext anchorContext,
  ) async {
    if (_activeMode != ChatPageMode.normal) {
      return;
    }
    _cancelNormalSurfaceModelReveal();
    if (_showSlashCommandPanel ||
        _showModelMentionPanel ||
        _openClawPanelExpanded) {
      setState(() {
        _showSlashCommandPanel = false;
        _showModelMentionPanel = false;
        _openClawPanelExpanded = false;
      });
    }
    _inputFocusNode.unfocus();
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    final anchorBox = anchorContext.findRenderObject() as RenderBox?;
    if (overlay == null || anchorBox == null || !anchorBox.hasSize) {
      return;
    }
    final topLeft = anchorBox.localToGlobal(Offset.zero, ancestor: overlay);
    final bottomRight = anchorBox.localToGlobal(
      anchorBox.size.bottomRight(Offset.zero),
      ancestor: overlay,
    );
    final anchorRect = Rect.fromPoints(topLeft, bottomRight);
    final popupWidth = (overlay.size.width - 32).clamp(220.0, 340.0).toDouble();
    const popupMaxHeight = 360.0;
    final position = PopupMenuAnchorPosition.fromAnchorRect(
      anchorRect: anchorRect,
      overlaySize: overlay.size,
      estimatedMenuHeight: popupMaxHeight,
      reservedBottom: MediaQuery.of(context).viewInsets.bottom,
    );
    await showMenu<String>(
      context: context,
      color: Colors.white,
      elevation: 8,
      constraints: BoxConstraints(minWidth: popupWidth, maxWidth: popupWidth),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      position: position,
      items: [
        _TerminalEnvironmentEditorPopupEntry(
          width: popupWidth,
          estimatedHeight: popupMaxHeight,
          initialVariables: _terminalEnvironmentVariables,
          onChanged: _updateTerminalEnvironmentVariables,
        ),
      ],
    );
  }

  @override
  Map<String, String>? _buildAgentTerminalEnvironmentPayload() {
    final environment = ChatTerminalEnvironmentService.buildEnvironmentMap(
      _terminalEnvironmentVariables,
    );
    return environment.isEmpty ? null : environment;
  }
}

class _TerminalEnvironmentEditorPopupEntry extends PopupMenuEntry<String> {
  const _TerminalEnvironmentEditorPopupEntry({
    required this.width,
    required this.estimatedHeight,
    required this.initialVariables,
    required this.onChanged,
  });

  final double width;
  final double estimatedHeight;
  final List<ChatTerminalEnvironmentVariable> initialVariables;
  final Future<void> Function(List<ChatTerminalEnvironmentVariable>) onChanged;

  @override
  double get height => estimatedHeight;

  @override
  bool represents(String? value) => false;

  @override
  State<_TerminalEnvironmentEditorPopupEntry> createState() =>
      _TerminalEnvironmentEditorPopupEntryState();
}

class _TerminalEnvironmentEditorPopupEntryState
    extends State<_TerminalEnvironmentEditorPopupEntry> {
  final TextEditingController _keyController = TextEditingController();
  final TextEditingController _valueController = TextEditingController();
  late List<ChatTerminalEnvironmentVariable> _variables;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _variables = List<ChatTerminalEnvironmentVariable>.from(
      widget.initialVariables,
    );
  }

  @override
  void dispose() {
    _keyController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  void _handleAdd() {
    final key = _keyController.text.trim();
    final value = _valueController.text;
    if (key.isEmpty) {
      setState(() {
        _errorText = '变量名不能为空';
      });
      return;
    }
    if (!ChatTerminalEnvironmentService.isValidKey(key)) {
      setState(() {
        _errorText = '变量名仅支持字母、数字和下划线，且不能以数字开头';
      });
      return;
    }
    final next = ChatTerminalEnvironmentService.normalizeVariables([
      ..._variables.where((item) => item.normalizedKey != key),
      ChatTerminalEnvironmentVariable(key: key, value: value),
    ]);
    setState(() {
      _variables = next;
      _errorText = null;
      _keyController.clear();
      _valueController.clear();
    });
    unawaited(widget.onChanged(next));
  }

  void _handleDelete(ChatTerminalEnvironmentVariable item) {
    final next = _variables
        .where((candidate) => candidate.normalizedKey != item.normalizedKey)
        .toList(growable: false);
    setState(() {
      _variables = next;
      _errorText = null;
    });
    unawaited(widget.onChanged(next));
  }

  Widget _buildVariableRow(ChatTerminalEnvironmentVariable item) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 2),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFD),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.normalizedKey,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF1F2937),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    item.value.isEmpty ? '(空字符串)' : item.value,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: () {
                _handleDelete(item);
              },
              borderRadius: BorderRadius.circular(999),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(
                  Icons.delete_outline_rounded,
                  size: 18,
                  color: Color(0xFF8FA1BC),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAddForm() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 2),
          TextField(
            controller: _keyController,
            autofocus: false,
            scrollPadding: EdgeInsets.zero,
            textInputAction: TextInputAction.next,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF1F2937),
              fontWeight: FontWeight.w500,
            ),
            decoration: const InputDecoration(
              isDense: true,
              hintText: '变量名，例如 OPENAI_API_KEY',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            onSubmitted: (_) {
              _handleAdd();
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _valueController,
            autofocus: false,
            scrollPadding: EdgeInsets.zero,
            textInputAction: TextInputAction.done,
            style: const TextStyle(
              fontSize: 13,
              color: Color(0xFF1F2937),
              fontWeight: FontWeight.w500,
            ),
            decoration: const InputDecoration(
              isDense: true,
              hintText: '变量值，允许为空',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
            ),
            onSubmitted: (_) {
              _handleAdd();
            },
          ),
          if (_errorText != null) ...[
            const SizedBox(height: 8),
            Text(
              _errorText!,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFFD93025),
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton.tonalIcon(
              onPressed: _handleAdd,
              icon: const Icon(Icons.add_rounded, size: 16),
              label: const Text('添加'),
              style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact,
                foregroundColor: const Color(0xFF1930D9),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final dynamicMaxHeight =
        (mediaQuery.size.height - mediaQuery.viewInsets.bottom - 96)
            .clamp(220.0, widget.estimatedHeight)
            .toDouble();
    return SizedBox(
      width: widget.width,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: dynamicMaxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
              child: Row(
                children: [
                  const Icon(
                    Icons.tune_rounded,
                    size: 16,
                    color: Color(0xFF617390),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '终端环境变量',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Color(0xFF1F2937),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    '${_variables.length}',
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFF8FA1BC),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (_variables.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Text(
                  '还没有环境变量',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              )
            else
              Flexible(
                child: Scrollbar(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(bottom: 8),
                    itemCount: _variables.length,
                    itemBuilder: (context, index) {
                      return _buildVariableRow(_variables[index]);
                    },
                  ),
                ),
              ),
            const Divider(height: 1, color: Color(0xFFE5EDF8)),
            _buildAddForm(),
          ],
        ),
      ),
    );
  }
}
