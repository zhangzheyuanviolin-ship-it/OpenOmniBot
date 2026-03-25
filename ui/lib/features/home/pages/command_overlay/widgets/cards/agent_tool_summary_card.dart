import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:ui/core/router/go_router_manager.dart';
import 'package:ui/features/home/pages/command_overlay/widgets/cards/terminal_output_utils.dart';
import 'package:ui/services/omnibot_resource_service.dart';
import 'package:ui/theme/app_colors.dart';

const Color _interruptedStatusColor = Color(0xFFFFAA2C);
const ValueKey<String> _toolCardTapTargetKey = ValueKey<String>(
  'agent_tool_summary_card_tap_target',
);
const ValueKey<String> _toolCardDetailsKey = ValueKey<String>(
  'agent_tool_summary_card_details',
);
const ValueKey<String> _toolCardDetailScrollViewKey = ValueKey<String>(
  'agent_tool_summary_detail_scroll_view',
);
const ValueKey<String> _toolCardTerminalBlockKey = ValueKey<String>(
  'agent_tool_summary_terminal_block',
);

class AgentToolSummaryCard extends StatefulWidget {
  final Map<String, dynamic> cardData;
  final ScrollController? parentScrollController;

  const AgentToolSummaryCard({
    super.key,
    required this.cardData,
    this.parentScrollController,
  });

  @override
  State<AgentToolSummaryCard> createState() => _AgentToolSummaryCardState();
}

class _AgentToolSummaryCardState extends State<AgentToolSummaryCard> {
  bool _expanded = false;
  bool _terminalAutoExpandSuppressed = false;
  static const double _messageFontSize = 14;
  static const double _detailFontSize = 12;
  static const double _detailMaxHeight = 260;
  final ScrollController _detailScrollController = ScrollController();
  bool _stickToBottom = true;

  // Key for header to maintain position during expand/collapse
  final GlobalKey _headerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _expanded = _isTerminalRunning(widget.cardData);
    _detailScrollController.addListener(_handleDetailScroll);
    if (_expanded) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _stickToBottom = true;
        _scheduleAutoScroll(force: true);
      });
    }
  }

  @override
  void dispose() {
    _detailScrollController.removeListener(_handleDetailScroll);
    _detailScrollController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant AgentToolSummaryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final parentScrollPosition = _resolveParentScrollPosition();
    final wasRunning = _isTerminalRunning(oldWidget.cardData);
    final isRunning = _isTerminalRunning(widget.cardData);
    final isFinished = _isTerminalFinished(widget.cardData);

    if (!wasRunning && isRunning && !_terminalAutoExpandSuppressed) {
      _setExpandedState(
        true,
        parentScrollPosition: parentScrollPosition,
        forceAutoScroll: true,
      );
    } else if (wasRunning && isFinished) {
      _terminalAutoExpandSuppressed = false;
      _setExpandedState(
        false,
        parentScrollPosition: parentScrollPosition,
      );
    } else if (!isRunning && isFinished) {
      _terminalAutoExpandSuppressed = false;
    }

    final oldOutput = _resolveTerminalOutput(oldWidget.cardData);
    final newOutput = _resolveTerminalOutput(widget.cardData);
    if (_expanded && newOutput != oldOutput) {
      _scheduleAutoScroll();
    }
  }

  @override
  Widget build(BuildContext context) {
    final parentScrollPosition = _resolveParentScrollPosition();
    final status = (widget.cardData['status'] ?? 'running').toString();
    final displayName = (widget.cardData['displayName'] ?? '工具调用').toString();
    final toolType = (widget.cardData['toolType'] ?? 'builtin').toString();
    final isTerminal = toolType == 'terminal';
    final serverName = widget.cardData['serverName']?.toString();
    final summary = (widget.cardData['summary'] ?? '').toString();
    final argsJson = (widget.cardData['argsJson'] ?? '').toString();
    final rawResultJson = (widget.cardData['rawResultJson'] ?? '').toString();
    final resultPreviewJson = (widget.cardData['resultPreviewJson'] ?? '')
        .toString();
    final terminalOutput = _resolveTerminalOutput(widget.cardData);
    final terminalStreamState = (widget.cardData['terminalStreamState'] ?? '')
        .toString();
    final workspaceId = widget.cardData['workspaceId']?.toString();
    final artifacts = _normalizeMapList(widget.cardData['artifacts']);
    final actions = _normalizeMapList(widget.cardData['actions']);
    final detailResultJson = rawResultJson.isNotEmpty
        ? rawResultJson
        : resultPreviewJson;
    final statusColor = _resolvedStatusColor(status);
    const userMessageBackground = AppColors.buttonSmall;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DecoratedBox(
          key: _headerKey,
          decoration: BoxDecoration(
            color: userMessageBackground,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              key: _toolCardTapTargetKey,
              borderRadius: BorderRadius.circular(12),
              onTap: _handleToggleExpanded,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 56),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      _StatusIcon(status: status, toolType: toolType),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _buildTitle(displayName, toolType, serverName),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.text,
                            fontSize: _messageFontSize,
                            fontFamily: 'PingFang SC',
                            fontWeight: FontWeight.w400,
                            height: 1.43,
                            letterSpacing: 0.33,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _StatusBadge(
                        label: _resolvedStatusLabel(status, toolType),
                        color: statusColor,
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                        color: AppColors.text50,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topLeft,
          child: _expanded
              ? Padding(
                  key: _toolCardDetailsKey,
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Container(
                    width: double.infinity,
                    decoration: const BoxDecoration(
                      border: Border(
                        left: BorderSide(color: AppColors.text10, width: 1),
                      ),
                    ),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(
                        maxHeight: _detailMaxHeight,
                      ),
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (notification) =>
                            _forwardScrollToParent(
                              notification,
                              parentScrollPosition,
                            ),
                        child: SingleChildScrollView(
                          key: _toolCardDetailScrollViewKey,
                          controller: _detailScrollController,
                          physics: const ClampingScrollPhysics(),
                          child: Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (summary.isNotEmpty)
                                  _DetailBlock(title: '摘要', content: summary),
                                if (argsJson.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  _DetailBlock(
                                    title: '参数',
                                    content: isTerminal
                                        ? _formatTerminalArgs(argsJson)
                                        : _formatJson(argsJson),
                                    monospace: true,
                                  ),
                                ],
                                if (isTerminal) ...[
                                  const SizedBox(height: 10),
                                  _TerminalOutputBlock(
                                    content: terminalOutput,
                                    streamState: terminalStreamState,
                                  ),
                                ] else if (detailResultJson.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  _DetailBlock(
                                    title: rawResultJson.isNotEmpty
                                        ? '原始结果'
                                        : '结果摘要',
                                    content: _formatJson(detailResultJson),
                                    monospace: true,
                                  ),
                                ],
                                if (artifacts.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  _ArtifactBlock(
                                    artifacts: artifacts,
                                    onPreview: _handleArtifactPreview,
                                    onSave: _handleArtifactSave,
                                  ),
                                ],
                                if ((workspaceId?.isNotEmpty ?? false) ||
                                    actions.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  _ActionBlock(
                                    workspaceId: workspaceId,
                                    actions: actions,
                                    onOpenWorkspace: _handleOpenWorkspace,
                                    onRunAction: _handleAction,
                                  ),
                                ],
                                if (widget.cardData['showScheduleAction'] ==
                                    true) ...[
                                  const SizedBox(height: 10),
                                  TextButton(
                                    onPressed: () => GoRouterManager.push(
                                      '/task/scheduled_tasks',
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppColors.primaryBlue,
                                      textStyle: const TextStyle(
                                        fontSize: _detailFontSize,
                                        fontFamily: 'PingFang SC',
                                        fontWeight: FontWeight.w400,
                                        height: 1.50,
                                        letterSpacing: 0.33,
                                      ),
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(0, 32),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text('查看定时任务'),
                                  ),
                                ],
                                if (widget.cardData['showAlarmAction'] ==
                                    true) ...[
                                  const SizedBox(height: 10),
                                  TextButton(
                                    onPressed: () => GoRouterManager.push(
                                      '/task/scheduled_tasks',
                                      queryParams: const {'tab': 'alarm'},
                                    ),
                                    style: TextButton.styleFrom(
                                      foregroundColor: AppColors.primaryBlue,
                                      textStyle: const TextStyle(
                                        fontSize: _detailFontSize,
                                        fontFamily: 'PingFang SC',
                                        fontWeight: FontWeight.w400,
                                        height: 1.50,
                                        letterSpacing: 0.33,
                                      ),
                                      padding: EdgeInsets.zero,
                                      minimumSize: const Size(0, 32),
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: const Text('查看闹钟列表'),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  String _buildTitle(String displayName, String toolType, String? serverName) {
    if (toolType == 'mcp' && serverName?.isNotEmpty == true) {
      return '$displayName · $serverName';
    }
    return displayName;
  }

  String _statusLabel(String status, String toolType) {
    switch (status) {
      case 'success':
        return '成功';
      case 'error':
        return '失败';
      default:
        if (toolType == 'mcp') return '响应中';
        if (toolType == 'memory') return '处理中';
        if (toolType == 'terminal') return '运行中';
        if (toolType == 'browser') return '浏览中';
        return '执行中';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'success':
        return const Color(0xFF2F8F4E);
      case 'error':
        return AppColors.alertRed;
      default:
        return AppColors.primaryBlue;
    }
  }

  String _resolvedStatusLabel(String status, String toolType) {
    if (status == 'interrupted') {
      return '\u4E2D\u65AD';
    }
    return _statusLabel(status, toolType);
  }

  Color _resolvedStatusColor(String status) {
    if (status == 'interrupted') {
      return _interruptedStatusColor;
    }
    return _statusColor(status);
  }

  String _formatJson(String value) {
    final text = value.trim();
    if (text.isEmpty) return text;
    try {
      final decoded = jsonDecode(text);
      return const JsonEncoder.withIndent('  ').convert(decoded);
    } catch (_) {
      return text;
    }
  }

  String _formatTerminalArgs(String value) {
    final args = TerminalOutputUtils.decodeJsonMap(value);
    if (args.isEmpty) {
      return _formatJson(value);
    }

    final lines = <String>[];
    final command = (args['command'] ?? '').toString();
    if (command.isNotEmpty) {
      lines.add('command: $command');
    }
    final executionMode = (args['executionMode'] ?? 'proot').toString();
    if (executionMode.isNotEmpty) {
      lines.add('mode: $executionMode');
    }
    final prootDistro = (args['prootDistro'] ?? '').toString();
    if (prootDistro.isNotEmpty) {
      lines.add('proot: $prootDistro');
    }
    final workingDirectory = (args['workingDirectory'] ?? '').toString();
    if (workingDirectory.isNotEmpty) {
      lines.add('cwd: $workingDirectory');
    }
    final timeoutSeconds = args['timeoutSeconds']?.toString() ?? '';
    if (timeoutSeconds.isNotEmpty) {
      lines.add('timeout: ${timeoutSeconds}s');
    }
    return lines.join('\n');
  }

  ScrollPosition? _resolveParentScrollPosition() {
    return widget.parentScrollController?.hasClients == true
        ? widget.parentScrollController!.position
        : Scrollable.maybeOf(context)?.position;
  }

  bool _isTerminalCard(Map<String, dynamic> cardData) {
    return (cardData['toolType'] ?? 'builtin').toString() == 'terminal';
  }

  bool _isTerminalRunning(Map<String, dynamic> cardData) {
    if (!_isTerminalCard(cardData)) {
      return false;
    }

    final streamState = (cardData['terminalStreamState'] ?? '').toString();
    if (streamState == 'starting' || streamState == 'running') {
      return true;
    }

    final status = (cardData['status'] ?? 'running').toString();
    return status == 'running';
  }

  bool _isTerminalFinished(Map<String, dynamic> cardData) {
    if (!_isTerminalCard(cardData)) {
      return false;
    }

    final streamState = (cardData['terminalStreamState'] ?? '').toString();
    if (streamState == 'completed' ||
        streamState == 'fallback' ||
        streamState == 'error') {
      return true;
    }

    final status = (cardData['status'] ?? 'running').toString();
    return status == 'success' ||
        status == 'error' ||
        status == 'interrupted';
  }

  void _handleToggleExpanded() {
    final parentScrollPosition = _resolveParentScrollPosition();
    final nextExpanded = !_expanded;
    final isLiveTerminal = _isTerminalRunning(widget.cardData);
    final shouldFollowTerminalTail = _isTerminalCard(widget.cardData);

    if (isLiveTerminal) {
      _terminalAutoExpandSuppressed = !nextExpanded;
    }

    _setExpandedState(
      nextExpanded,
      parentScrollPosition: parentScrollPosition,
      scrollToTop: nextExpanded && !shouldFollowTerminalTail,
      forceAutoScroll: nextExpanded && shouldFollowTerminalTail,
    );
  }

  void _setExpandedState(
    bool nextExpanded, {
    ScrollPosition? parentScrollPosition,
    bool scrollToTop = false,
    bool forceAutoScroll = false,
  }) {
    if (_expanded == nextExpanded) {
      if (nextExpanded && forceAutoScroll) {
        _stickToBottom = true;
        _scheduleAutoScroll(force: true);
      }
      return;
    }

    final headerRenderBox =
        _headerKey.currentContext?.findRenderObject() as RenderBox?;
    final headerPositionBefore = headerRenderBox?.localToGlobal(Offset.zero).dy;

    setState(() => _expanded = nextExpanded);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      final headerRenderBoxAfter =
          _headerKey.currentContext?.findRenderObject() as RenderBox?;
      final headerPositionAfter = headerRenderBoxAfter
          ?.localToGlobal(Offset.zero)
          .dy;

      if (parentScrollPosition != null &&
          headerPositionBefore != null &&
          headerPositionAfter != null) {
        final delta = headerPositionAfter - headerPositionBefore;
        if (delta.abs() > 0.5) {
          final newScrollPosition = (parentScrollPosition.pixels - delta).clamp(
            parentScrollPosition.minScrollExtent,
            parentScrollPosition.maxScrollExtent,
          );
          parentScrollPosition.jumpTo(newScrollPosition);
        }
      }

      if (!nextExpanded) {
        return;
      }

      if (scrollToTop) {
        _scrollDetailToTop();
        return;
      }

      _stickToBottom = true;
      _scheduleAutoScroll(force: forceAutoScroll);
    });
  }

  void _scrollDetailToTop() {
    if (!_detailScrollController.hasClients) {
      return;
    }
    _detailScrollController.jumpTo(
      _detailScrollController.position.minScrollExtent,
    );
    _stickToBottom = false;
  }

  String _resolveTerminalOutput(Map<String, dynamic> cardData) {
    return TerminalOutputUtils.buildDisplayOutput(
      terminalOutput: (cardData['terminalOutput'] ?? '').toString(),
      rawResultJson: (cardData['rawResultJson'] ?? '').toString(),
      resultPreviewJson: (cardData['resultPreviewJson'] ?? '').toString(),
    );
  }

  List<Map<String, dynamic>> _normalizeMapList(dynamic raw) {
    return (raw as List? ?? const [])
        .whereType<Map>()
        .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
        .toList();
  }

  void _handleArtifactPreview(Map<String, dynamic> artifact) {
    final uri = artifact['uri']?.toString();
    final path = artifact['androidPath']?.toString();
    final title = (artifact['title'] ?? artifact['fileName'] ?? '文件')
        .toString();
    final previewKind = artifact['previewKind']?.toString();
    final mimeType = artifact['mimeType']?.toString();
    final shellPath = artifact['workspacePath']?.toString();
    if (path != null && path.isNotEmpty) {
      OmnibotResourceService.openFilePath(
        path,
        uri: uri,
        title: title,
        previewKind: previewKind,
        mimeType: mimeType,
        shellPath: shellPath,
      );
      return;
    }
    if (uri != null && uri.isNotEmpty) {
      OmnibotResourceService.openUri(uri);
    }
  }

  void _handleArtifactSave(Map<String, dynamic> artifact) {
    final path = artifact['androidPath']?.toString();
    if (path == null || path.isEmpty) return;
    OmnibotResourceService.saveToLocal(
      sourcePath: path,
      fileName: (artifact['fileName'] ?? artifact['title'] ?? 'artifact')
          .toString(),
      mimeType: (artifact['mimeType'] ?? 'application/octet-stream').toString(),
    );
  }

  void _handleOpenWorkspace(String? workspaceId) {
    if (workspaceId == null || workspaceId.isEmpty) return;
    OmnibotResourceService.openWorkspace(workspaceId: workspaceId);
  }

  void _handleAction(Map<String, dynamic> action) {
    final type = action['type']?.toString() ?? '';
    final target = action['target']?.toString();
    final payload = (action['payload'] as Map?)?.map(
      (key, value) => MapEntry(key.toString(), value),
    );
    if (type == 'workspace') {
      OmnibotResourceService.openWorkspace(
        workspaceId: payload?['workspaceId']?.toString(),
        absolutePath: payload?['workspacePath']?.toString(),
        shellPath: payload?['workspaceShellPath']?.toString(),
        uri: target,
      );
      return;
    }
    if (target != null && target.startsWith('omnibot://')) {
      OmnibotResourceService.openUri(target);
    }
  }

  void _handleDetailScroll() {
    if (!_detailScrollController.hasClients) {
      return;
    }
    final position = _detailScrollController.position;
    _stickToBottom = (position.maxScrollExtent - position.pixels) <= 48;
  }

  void _scheduleAutoScroll({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_expanded || !_detailScrollController.hasClients) {
        return;
      }
      if (!force && !_stickToBottom) {
        return;
      }
      final position = _detailScrollController.position;
      _detailScrollController.animateTo(
        position.maxScrollExtent,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
      );
    });
  }

  bool _forwardScrollToParent(
    ScrollNotification notification,
    ScrollPosition? parentPosition,
  ) {
    if (parentPosition == null || !parentPosition.hasPixels) {
      return false;
    }

    final pointerDelta = _resolvePointerDelta(notification);
    if (pointerDelta == null || pointerDelta.abs() < 0.5) {
      return false;
    }

    final parentDelta = _pointerDeltaToScrollDelta(
      pointerDelta,
      parentPosition.axisDirection,
    );
    if (parentDelta.abs() < 0.5) {
      return false;
    }

    final current = parentPosition.pixels;
    final min = parentPosition.minScrollExtent;
    final max = parentPosition.maxScrollExtent;
    final next = (current + parentDelta).clamp(min, max).toDouble();

    if ((next - current).abs() < 0.5) {
      return false;
    }

    parentPosition.jumpTo(next);
    return true;
  }

  double? _resolvePointerDelta(ScrollNotification notification) {
    final dragDelta = switch (notification) {
      OverscrollNotification(:final dragDetails?) => _primaryDelta(
        dragDetails.delta,
        notification.metrics.axis,
      ),
      _ => null,
    };
    if (dragDelta != null) {
      return dragDelta;
    }

    final scrollDelta = switch (notification) {
      OverscrollNotification(:final overscroll) => overscroll,
      _ => null,
    };
    if (scrollDelta == null || scrollDelta.abs() < 0.5) {
      return null;
    }

    return _scrollDeltaToPointerDelta(
      scrollDelta,
      notification.metrics.axisDirection,
    );
  }

  double _primaryDelta(Offset offset, Axis axis) {
    return axis == Axis.vertical ? offset.dy : offset.dx;
  }

  double _scrollDeltaToPointerDelta(
    double scrollDelta,
    AxisDirection axisDirection,
  ) {
    return switch (axisDirection) {
      AxisDirection.down || AxisDirection.right => -scrollDelta,
      AxisDirection.up || AxisDirection.left => scrollDelta,
    };
  }

  double _pointerDeltaToScrollDelta(
    double pointerDelta,
    AxisDirection axisDirection,
  ) {
    return switch (axisDirection) {
      AxisDirection.down || AxisDirection.right => -pointerDelta,
      AxisDirection.up || AxisDirection.left => pointerDelta,
    };
  }
}

class _StatusIcon extends StatelessWidget {
  final String status;
  final String toolType;

  const _StatusIcon({required this.status, required this.toolType});

  @override
  Widget build(BuildContext context) {
    final color = _resolvedStatusColor(status);
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Center(
        child: status == 'running'
            ? SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              )
            : Icon(
                _resolvedStatusIcon(status, toolType),
                size: 16,
                color: color,
              ),
      ),
    );
  }

  static IconData _resolvedStatusIcon(String status, String toolType) {
    if (status == 'interrupted') {
      return Icons.stop_circle_outlined;
    }
    return _statusIcon(status, toolType);
  }

  static Color _resolvedStatusColor(String status) {
    if (status == 'interrupted') {
      return _interruptedStatusColor;
    }
    return _statusColor(status);
  }

  static IconData _statusIcon(String status, String toolType) {
    if (status == 'error') return Icons.error_outline;
    if (toolType == 'schedule') return Icons.alarm_on_outlined;
    if (toolType == 'alarm') return Icons.alarm_outlined;
    if (toolType == 'calendar') return Icons.calendar_month_outlined;
    if (toolType == 'memory') return Icons.psychology_alt_outlined;
    if (toolType == 'subagent') return Icons.hub_outlined;
    if (toolType == 'mcp') return Icons.extension_outlined;
    if (toolType == 'terminal') return Icons.terminal_outlined;
    if (toolType == 'browser') return Icons.language_outlined;
    return Icons.check_circle_outline;
  }

  static Color _statusColor(String status) {
    switch (status) {
      case 'success':
        return const Color(0xFF2F8F4E);
      case 'error':
        return AppColors.alertRed;
      default:
        return AppColors.primaryBlue;
    }
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusBadge({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: _AgentToolSummaryCardState._messageFontSize,
          fontFamily: 'PingFang SC',
          fontWeight: FontWeight.w600,
          height: 1.43,
          letterSpacing: 0.33,
        ),
      ),
    );
  }
}

class _DetailBlock extends StatelessWidget {
  final String title;
  final String content;
  final bool monospace;

  const _DetailBlock({
    required this.title,
    required this.content,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: AppColors.text50,
            fontSize: _AgentToolSummaryCardState._detailFontSize,
            fontFamily: 'PingFang SC',
            fontWeight: FontWeight.w500,
            height: 1.50,
            letterSpacing: 0.33,
          ),
        ),
        const SizedBox(height: 6),
        SelectableText(
          content,
          style: TextStyle(
            color: AppColors.text50,
            fontSize: _AgentToolSummaryCardState._detailFontSize,
            fontFamily: monospace ? 'monospace' : 'PingFang SC',
            fontWeight: FontWeight.w400,
            height: 1.50,
            letterSpacing: monospace ? null : 0.33,
          ),
        ),
      ],
    );
  }
}

class _ArtifactBlock extends StatelessWidget {
  final List<Map<String, dynamic>> artifacts;
  final void Function(Map<String, dynamic> artifact) onPreview;
  final void Function(Map<String, dynamic> artifact) onSave;

  const _ArtifactBlock({
    required this.artifacts,
    required this.onPreview,
    required this.onSave,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '产物',
          style: TextStyle(
            color: AppColors.text50,
            fontSize: _AgentToolSummaryCardState._detailFontSize,
            fontFamily: 'PingFang SC',
            fontWeight: FontWeight.w500,
            height: 1.50,
            letterSpacing: 0.33,
          ),
        ),
        const SizedBox(height: 8),
        Column(
          children: artifacts.map((artifact) {
            final title =
                (artifact['title'] ?? artifact['fileName'] ?? 'artifact')
                    .toString();
            final shellPath = (artifact['workspacePath'] ?? '').toString();
            final meta = <String>[
              if ((artifact['mimeType'] ?? '').toString().isNotEmpty)
                artifact['mimeType'].toString(),
              if ((artifact['size'] ?? '').toString().isNotEmpty)
                '${artifact['size']} bytes',
            ].join(' · ');
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FB),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: AppColors.text,
                    ),
                  ),
                  if (meta.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      meta,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.text50,
                      ),
                    ),
                  ],
                  if (shellPath.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      shellPath,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.text50,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: () => onPreview(artifact),
                        child: const Text('预览'),
                      ),
                      TextButton(
                        onPressed: () => onSave(artifact),
                        child: const Text('保存'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _ActionBlock extends StatelessWidget {
  final String? workspaceId;
  final List<Map<String, dynamic>> actions;
  final void Function(String? workspaceId) onOpenWorkspace;
  final void Function(Map<String, dynamic> action) onRunAction;

  const _ActionBlock({
    required this.workspaceId,
    required this.actions,
    required this.onOpenWorkspace,
    required this.onRunAction,
  });

  @override
  Widget build(BuildContext context) {
    final buttons = <Widget>[];
    if (workspaceId?.isNotEmpty == true) {
      buttons.add(
        TextButton(
          onPressed: () => onOpenWorkspace(workspaceId),
          child: const Text('打开工作区'),
        ),
      );
    }
    for (final action in actions) {
      final label = action['label']?.toString();
      if (label == null || label.isEmpty) continue;
      buttons.add(
        TextButton(onPressed: () => onRunAction(action), child: Text(label)),
      );
    }
    if (buttons.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(spacing: 8, children: buttons);
  }
}

class _TerminalOutputBlock extends StatelessWidget {
  final String content;
  final String streamState;

  const _TerminalOutputBlock({
    required this.content,
    required this.streamState,
  });

  @override
  Widget build(BuildContext context) {
    const labelStyle = TextStyle(
      color: AppColors.text50,
      fontSize: _AgentToolSummaryCardState._detailFontSize,
      fontFamily: 'PingFang SC',
      fontWeight: FontWeight.w500,
      height: 1.50,
      letterSpacing: 0.33,
    );
    const terminalTextStyle = TextStyle(
      color: Color(0xFFE5E7EB),
      fontSize: _AgentToolSummaryCardState._detailFontSize,
      fontFamily: 'monospace',
      fontWeight: FontWeight.w400,
      height: 1.55,
    );

    final statusLabel = switch (streamState) {
      'starting' => '准备中',
      'running' => '实时中',
      'fallback' => '回退展示',
      'error' => '异常',
      _ => '最终结果',
    };
    final placeholder = switch (streamState) {
      'starting' => '正在准备实时终端输出...',
      'running' => '等待终端输出...',
      'fallback' => '未采集到实时输出，将展示最终终端结果。',
      _ => '暂无终端输出',
    };

    return Column(
      key: _toolCardTerminalBlockKey,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('终端输出', style: labelStyle),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF0F172A).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                statusLabel,
                style: labelStyle.copyWith(
                  color: AppColors.text,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0B1220),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0x1FFFFFFF)),
          ),
          child: content.isNotEmpty
              ? SelectableText.rich(
                  AnsiTextSpanBuilder.build(content, terminalTextStyle),
                )
              : Text(
                  placeholder,
                  style: terminalTextStyle.copyWith(
                    color: const Color(0xFFE5E7EB).withValues(alpha: 0.65),
                  ),
                ),
        ),
      ],
    );
  }
}
