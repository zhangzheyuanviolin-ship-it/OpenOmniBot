import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui/services/assists_core_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';

class UtgDashboardPage extends StatefulWidget {
  const UtgDashboardPage({super.key});

  @override
  State<UtgDashboardPage> createState() => _UtgDashboardPageState();
}

class _UtgDashboardPageState extends State<UtgDashboardPage> {
  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _startCommandController = TextEditingController();
  final TextEditingController _workingDirectoryController =
      TextEditingController();
  final TextEditingController _cloudBaseUrlController = TextEditingController();
  final TextEditingController _cloudPathIdController = TextEditingController();
  final TextEditingController _pathSearchController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _loadingPaths = false;
  bool _loadingRunLogs = false;
  bool _downloadingCloudPath = false;
  bool _utgEnabled = true;
  bool _providerAutoStartEnabled = true;
  bool _fallbackToVlmOnFailureEnabled = true;
  bool _runLogRecordingEnabled = true;
  String? _runningPathId;
  String? _deletingPathId;
  String? _uploadingPathId;
  String? _expandedPathId;
  String? _viewingPathId;
  String? _importingRunId;
  String? _providerControlAction;
  String? _highlightedPathId;
  final Map<String, Map<String, dynamic>> _pathBundleCache = {};
  final Map<String, String> _pathBundleErrorById = {};
  final Set<String> _expandedStepKeys = <String>{};
  final Set<String> _expandedSequenceKeys = <String>{};

  UtgBridgeConfig? _config;
  UtgPathsSnapshot? _pathsSnapshot;
  UtgRunLogsSnapshot? _runLogsSnapshot;
  String? _pathsError;
  String? _runLogsError;

  @override
  void initState() {
    super.initState();
    _refreshAll();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _startCommandController.dispose();
    _workingDirectoryController.dispose();
    _cloudBaseUrlController.dispose();
    _cloudPathIdController.dispose();
    _pathSearchController.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    setState(() => _loading = true);
    try {
      final config = await AssistsMessageService.getUtgBridgeConfig();
      if (!mounted) return;
      _applyConfig(config);
      await _loadPaths(baseUrl: config.omnicloudBaseUrl, silent: true);
      await _loadRunLogs(baseUrl: config.omnicloudBaseUrl, silent: true);
    } on PlatformException catch (e) {
      showToast(e.message ?? '加载 UTG 配置失败', type: ToastType.error);
    } catch (e) {
      showToast('加载 UTG 配置失败', type: ToastType.error);
      debugPrint('Load UTG config failed: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _applyConfig(UtgBridgeConfig config) {
    _config = config;
    _utgEnabled = config.utgEnabled;
    _providerAutoStartEnabled = config.providerAutoStartEnabled;
    _fallbackToVlmOnFailureEnabled = config.fallbackToVlmOnFailureEnabled;
    _runLogRecordingEnabled = config.runLogRecordingEnabled;
    _baseUrlController.text = config.omnicloudBaseUrl;
    _startCommandController.text = config.providerStartCommand;
    _workingDirectoryController.text = config.providerWorkingDirectory ?? '';
    if (_cloudBaseUrlController.text.trim().isEmpty) {
      _cloudBaseUrlController.text = config.omnicloudBaseUrl;
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _saveConfig() async {
    setState(() => _saving = true);
    try {
      final saved = await AssistsMessageService.saveUtgBridgeConfig(
        utgEnabled: _utgEnabled,
        providerAutoStartEnabled: _providerAutoStartEnabled,
        fallbackToVlmOnFailureEnabled: _fallbackToVlmOnFailureEnabled,
        runLogRecordingEnabled: _runLogRecordingEnabled,
        omnicloudBaseUrl: _baseUrlController.text.trim(),
        providerStartCommand: _startCommandController.text.trim(),
        providerWorkingDirectory: _workingDirectoryController.text.trim(),
      );
      if (!mounted) return;
      _applyConfig(saved);
      await _loadPaths(baseUrl: saved.omnicloudBaseUrl, silent: true);
      await _loadRunLogs(baseUrl: saved.omnicloudBaseUrl, silent: true);
      showToast('UTG 配置已保存', type: ToastType.success);
    } on PlatformException catch (e) {
      showToast(e.message ?? '保存 UTG 配置失败', type: ToastType.error);
    } catch (e) {
      showToast('保存 UTG 配置失败', type: ToastType.error);
      debugPrint('Save UTG config failed: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _loadPaths({String? baseUrl, bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loadingPaths = true;
        _pathsError = null;
      });
    } else {
      _loadingPaths = true;
      _pathsError = null;
    }
    try {
      final snapshot = await AssistsMessageService.getUtgPaths(
        baseUrl: baseUrl,
      );
      if (!mounted) return;
      setState(() {
        _pathsSnapshot = snapshot;
        _pathsError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pathsSnapshot = null;
        _pathsError = e.toString();
      });
      if (!silent) {
        showToast('加载 UTG paths 失败', type: ToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _loadingPaths = false);
      } else {
        _loadingPaths = false;
      }
    }
  }

  Future<void> _loadRunLogs({String? baseUrl, bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loadingRunLogs = true;
        _runLogsError = null;
      });
    } else {
      _loadingRunLogs = true;
      _runLogsError = null;
    }
    try {
      final snapshot = await AssistsMessageService.getUtgRunLogs(
        baseUrl: baseUrl,
      );
      if (!mounted) return;
      setState(() {
        _runLogsSnapshot = snapshot;
        _runLogsError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _runLogsSnapshot = null;
        _runLogsError = e.toString();
      });
      if (!silent) {
        showToast('加载 UTG run_logs 失败', type: ToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _loadingRunLogs = false);
      } else {
        _loadingRunLogs = false;
      }
    }
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: child,
    );
  }

  Widget _buildPill(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F5FA),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: AppColors.text70,
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    final display = value.trim().isEmpty ? '未设置' : value.trim();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.text70,
            ),
          ),
          const SizedBox(height: 4),
          SelectableText(
            display,
            style: const TextStyle(fontSize: 13, color: Colors.black87),
          ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    String? hint,
    int minLines = 1,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      enabled: !_saving,
      minLines: minLines,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Widget _buildPathCard(UtgPathSummary path) {
    final description = path.description.trim().isEmpty
        ? '无描述'
        : path.description;
    final running = _runningPathId == path.pathId;
    final deleting = _deletingPathId == path.pathId;
    final uploading = _uploadingPathId == path.pathId;
    final viewing = _viewingPathId == path.pathId;
    final expanded = _expandedPathId == path.pathId;
    final highlighted = _highlightedPathId == path.pathId;
    final bundle = _pathBundleCache[path.pathId];
    final bundleError = _pathBundleErrorById[path.pathId];
    final lastRun = path.lastRun;
    final lastRunSuccess = lastRun['success'] == true;
    final hasLastRun = lastRun.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: highlighted ? const Color(0xFFFFFBF0) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlighted ? const Color(0xFFF59E0B) : Colors.transparent,
          width: highlighted ? 1.5 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x11000000),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            path.pathId,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.text70,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (highlighted) _buildPill('新导入'),
              if (path.appName.trim().isNotEmpty) _buildPill(path.appName),
              _buildPill(_syncStatusLabel(path.syncStatus)),
              if (hasLastRun) _buildPill(lastRunSuccess ? '最近成功' : '最近失败'),
              _buildPill('${path.stepCount} steps'),
              _buildPill('slots ${path.slotNames.length}'),
              if (path.slotNames.isEmpty) _buildPill('无 slots'),
              if (path.slotNames.isNotEmpty) _buildPill('需填写 slots'),
              ...path.slotNames.map((slot) => _buildPill(slot)),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            'app',
            [
              path.appName,
              path.packageName,
            ].where((e) => e.trim().isNotEmpty).join(' · '),
          ),
          _buildInfoRow(
            'start node',
            [
              path.startNodeId,
              path.startNodeDescription,
            ].where((e) => e.trim().isNotEmpty).join(' · '),
          ),
          _buildInfoRow(
            'end node',
            [
              path.endNodeId,
              path.endNodeDescription,
            ].where((e) => e.trim().isNotEmpty).join(' · '),
          ),
          _buildInfoRow(
            'source',
            [
              path.source,
              path.syncOrigin,
            ].where((e) => e.trim().isNotEmpty).join(' · '),
          ),
          _buildInfoRow(
            'time',
            [
              if (path.createdAt.trim().isNotEmpty) 'created ${path.createdAt}',
              if (path.updatedAt.trim().isNotEmpty) 'updated ${path.updatedAt}',
              if (path.lastSyncedAt.trim().isNotEmpty)
                'synced ${path.lastSyncedAt}',
            ].join(' | '),
          ),
          _buildInfoRow(
            'recent run',
            hasLastRun
                ? [
                    (lastRun['success'] == true) ? 'success' : 'failed',
                    (lastRun['goal'] ?? '').toString(),
                    (lastRun['started_at'] ?? '').toString(),
                    (lastRun['error_code'] ?? '').toString(),
                  ].where((e) => e.trim().isNotEmpty).join(' · ')
                : '暂无执行记录',
          ),
          _buildInfoRow(
            'run stats',
            'total ${path.runCount} · success ${path.successCount} · fail ${path.failCount}',
          ),
          if (path.cloudBaseUrl.trim().isNotEmpty)
            _buildInfoRow('cloud', path.cloudBaseUrl),
          if (path.slotExamples.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'slot 示例',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: AppColors.text70,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: path.slotExamples.entries
                  .map((entry) => _buildPill('${entry.key}=${entry.value}'))
                  .toList(),
            ),
          ],
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed:
                      _runningPathId != null ||
                          _deletingPathId != null ||
                          _uploadingPathId != null ||
                          _viewingPathId != null
                      ? null
                      : () => _viewPathBundle(path),
                  icon: viewing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.account_tree_outlined),
                  label: Text(viewing ? '加载中...' : '查看 Path'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _runningPathId != null ||
                          _deletingPathId != null ||
                          _uploadingPathId != null ||
                          _viewingPathId != null
                      ? null
                      : () => _deletePathFromDashboard(path),
                  icon: deleting
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
                  label: Text(deleting ? '删除中...' : '删除'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _runningPathId != null ||
                          _deletingPathId != null ||
                          _uploadingPathId != null ||
                          _viewingPathId != null
                      ? null
                      : () => _uploadPathToCloud(path),
                  icon: uploading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(uploading ? '上传中...' : '上传云端'),
                ),
                FilledButton.icon(
                  onPressed:
                      _runningPathId != null ||
                          _deletingPathId != null ||
                          _uploadingPathId != null ||
                          _viewingPathId != null
                      ? null
                      : () => _runPathFromDashboard(path),
                  icon: running
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.play_arrow_outlined),
                  label: Text(running ? '执行中...' : '执行'),
                ),
              ],
            ),
          ),
          if (expanded || viewing || bundleError != null) ...[
            const SizedBox(height: 16),
            if (viewing)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: LinearProgressIndicator(minHeight: 3),
              ),
            if (bundleError != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF4F4),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  bundleError,
                  style: const TextStyle(color: Color(0xFFB42318), height: 1.5),
                ),
              )
            else if (bundle != null)
              _buildPathBundleView(path, bundle),
          ],
        ],
      ),
    );
  }

  Widget _buildPathBundleView(
    UtgPathSummary path,
    Map<String, dynamic> payload,
  ) {
    final graph =
        (payload['graph'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final paths = (graph['paths'] as List<dynamic>?) ?? const <dynamic>[];
    final nodes = (graph['nodes'] as List<dynamic>?) ?? const <dynamic>[];
    final pathPayload = paths.isNotEmpty && paths.first is Map
        ? Map<String, dynamic>.from(paths.first as Map)
        : const <String, dynamic>{};
    final nodeById = <String, Map<String, dynamic>>{};
    for (final raw in nodes) {
      if (raw is! Map) continue;
      final node = Map<String, dynamic>.from(raw);
      final nodeId = (node['id'] ?? '').toString();
      if (nodeId.isNotEmpty) {
        nodeById[nodeId] = node;
      }
    }
    final stepEntries = <MapEntry<String, dynamic>>[];
    final steps = (pathPayload['steps'] as Map<dynamic, dynamic>?) ?? const {};
    for (final entry in steps.entries) {
      stepEntries.add(MapEntry(entry.key.toString(), entry.value));
    }
    stepEntries.sort((a, b) {
      final av = a.value is Map ? (a.value as Map)['index'] : null;
      final bv = b.value is Map ? (b.value as Map)['index'] : null;
      final ai = av is num ? av.toInt() : 0;
      final bi = bv is num ? bv.toInt() : 0;
      return ai.compareTo(bi);
    });
    final previewParts = <String>[];
    for (final entry in stepEntries) {
      final nodeId = entry.key;
      final step = entry.value is Map
          ? Map<String, dynamic>.from(entry.value as Map)
          : const <String, dynamic>{};
      final node = nodeById[nodeId] ?? const <String, dynamic>{};
      final sequences =
          (node['sequences'] as Map<dynamic, dynamic>?) ?? const {};
      final sequenceNames =
          (step['sequences'] as List<dynamic>?) ?? const <dynamic>[];
      for (final sequenceNameRaw in sequenceNames) {
        final sequenceName = sequenceNameRaw.toString();
        final sequence = sequences[sequenceName] is Map
            ? Map<String, dynamic>.from(sequences[sequenceName] as Map)
            : const <String, dynamic>{};
        final actions =
            (sequence['actions'] as List<dynamic>?) ?? const <dynamic>[];
        for (final item in actions) {
          final rawAction = item is Map
              ? Map<String, dynamic>.from(item)
              : <String, dynamic>{'value': item};
          previewParts.add(_buildActionPreviewText(rawAction));
        }
      }
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                'Path 详情',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: () => _copyText(
                  'path json',
                  const JsonEncoder.withIndent('  ').convert(payload),
                ),
                child: const Text('复制 JSON'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    if (_expandedPathId == path.pathId) {
                      _expandedPathId = null;
                    }
                  });
                },
                child: const Text('收起'),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            previewParts.isEmpty
                ? '执行预览：无动作'
                : '执行预览：${previewParts.join(' -> ')}',
            style: const TextStyle(
              color: AppColors.text70,
              fontSize: 12,
              height: 1.6,
            ),
          ),
          const SizedBox(height: 8),
          if (path.slotNames.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: path.slotNames.map(_buildPill).toList(),
            ),
            const SizedBox(height: 12),
          ],
          if (stepEntries.isEmpty)
            const Text(
              '这个 path 暂时没有 steps。',
              style: TextStyle(color: AppColors.text70),
            )
          else
            ...stepEntries.map((entry) {
              final nodeId = entry.key;
              final stepKey = '${path.pathId}::$nodeId';
              final stepExpanded = _expandedStepKeys.contains(stepKey);
              final step = entry.value is Map
                  ? Map<String, dynamic>.from(entry.value as Map)
                  : const <String, dynamic>{};
              final node = nodeById[nodeId] ?? const <String, dynamic>{};
              final repr = (node['repr'] as Map<dynamic, dynamic>?) ?? const {};
              final sequences =
                  (node['sequences'] as Map<dynamic, dynamic>?) ?? const {};
              final sequenceNames =
                  (step['sequences'] as List<dynamic>?) ?? const <dynamic>[];
              final stepIndex = step['index'] is num
                  ? (step['index'] as num).toInt()
                  : 0;
              final nodeDescription = (repr['description'] ?? '')
                  .toString()
                  .trim();
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE4E8EE)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    InkWell(
                      onTap: () {
                        setState(() {
                          if (stepExpanded) {
                            _expandedStepKeys.remove(stepKey);
                          } else {
                            _expandedStepKeys.add(stepKey);
                          }
                        });
                      },
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Step ${stepIndex + 1} · $nodeId',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          _buildPill('${sequenceNames.length} sequences'),
                          const SizedBox(width: 8),
                          Icon(
                            stepExpanded
                                ? Icons.expand_less
                                : Icons.expand_more,
                            color: AppColors.text70,
                          ),
                        ],
                      ),
                    ),
                    if (nodeDescription.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        nodeDescription,
                        style: const TextStyle(color: AppColors.text70),
                      ),
                    ],
                    const SizedBox(height: 8),
                    if (!stepExpanded)
                      Text(
                        sequenceNames.map((e) => e.toString()).join(' · '),
                        style: const TextStyle(
                          color: AppColors.text70,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      )
                    else
                      ...sequenceNames.map((sequenceNameRaw) {
                        final sequenceName = sequenceNameRaw.toString();
                        final sequenceKey = '$stepKey::$sequenceName';
                        final sequenceExpanded = _expandedSequenceKeys.contains(
                          sequenceKey,
                        );
                        final sequence = sequences[sequenceName] is Map
                            ? Map<String, dynamic>.from(
                                sequences[sequenceName] as Map,
                              )
                            : const <String, dynamic>{};
                        final actions =
                            (sequence['actions'] as List<dynamic>?) ??
                            const <dynamic>[];
                        return Container(
                          width: double.infinity,
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF7F9FC),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    if (sequenceExpanded) {
                                      _expandedSequenceKeys.remove(sequenceKey);
                                    } else {
                                      _expandedSequenceKeys.add(sequenceKey);
                                    }
                                  });
                                },
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        sequenceName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    _buildPill('${actions.length} actions'),
                                    const SizedBox(width: 8),
                                    Icon(
                                      sequenceExpanded
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                      color: AppColors.text70,
                                    ),
                                  ],
                                ),
                              ),
                              if ((sequence['description'] ?? '')
                                  .toString()
                                  .trim()
                                  .isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  (sequence['description'] ?? '').toString(),
                                  style: const TextStyle(
                                    color: AppColors.text70,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              if (!sequenceExpanded)
                                Text(
                                  actions
                                      .map((item) {
                                        final rawAction = item is Map
                                            ? Map<String, dynamic>.from(item)
                                            : <String, dynamic>{'value': item};
                                        return _actionDisplayName(
                                          (rawAction['type'] ?? '').toString(),
                                        );
                                      })
                                      .join(' -> '),
                                  style: const TextStyle(
                                    color: AppColors.text70,
                                    fontSize: 12,
                                    height: 1.5,
                                  ),
                                )
                              else if (actions.isEmpty)
                                const Text(
                                  '无动作',
                                  style: TextStyle(color: AppColors.text70),
                                )
                              else
                                ...actions.asMap().entries.map((actionEntry) {
                                  final rawAction = actionEntry.value is Map
                                      ? Map<String, dynamic>.from(
                                          actionEntry.value as Map,
                                        )
                                      : <String, dynamic>{
                                          'value': actionEntry.value,
                                        };
                                  final actionType = (rawAction['type'] ?? '')
                                      .toString()
                                      .trim();
                                  final summaryParts = <String>[];
                                  final packageName =
                                      (rawAction['packageName'] ??
                                              rawAction['package_name'] ??
                                              '')
                                          .toString()
                                          .trim();
                                  final textValue = (rawAction['text'] ?? '')
                                      .toString()
                                      .trim();
                                  final keyValue = (rawAction['key'] ?? '')
                                      .toString()
                                      .trim();
                                  final directionValue =
                                      (rawAction['direction'] ?? '')
                                          .toString()
                                          .trim();
                                  final xValue = rawAction['x'];
                                  final yValue = rawAction['y'];
                                  final durationValue =
                                      rawAction['duration_ms'];
                                  final timeValue = rawAction['time_s'];
                                  if (packageName.isNotEmpty) {
                                    summaryParts.add('package=$packageName');
                                  }
                                  if (textValue.isNotEmpty) {
                                    summaryParts.add('text=$textValue');
                                  }
                                  if (keyValue.isNotEmpty) {
                                    summaryParts.add('key=$keyValue');
                                  }
                                  if (xValue != null || yValue != null) {
                                    summaryParts.add('pos=($xValue, $yValue)');
                                  }
                                  if (directionValue.isNotEmpty) {
                                    summaryParts.add(
                                      'direction=$directionValue',
                                    );
                                  }
                                  if (durationValue != null) {
                                    summaryParts.add(
                                      'duration_ms=$durationValue',
                                    );
                                  }
                                  if (timeValue != null) {
                                    summaryParts.add('time_s=$timeValue');
                                  }
                                  if (summaryParts.isEmpty) {
                                    for (final entry in rawAction.entries) {
                                      if (entry.key == 'type') continue;
                                      summaryParts.add(
                                        '${entry.key}=${entry.value}',
                                      );
                                    }
                                  }
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 8),
                                    child: Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: Colors.white,
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: const Color(0xFFE9EDF3),
                                        ),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  '${actionEntry.key + 1}. ${_actionDisplayName(actionType)}',
                                                  style: const TextStyle(
                                                    fontSize: 13,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              TextButton(
                                                onPressed: () => _copyText(
                                                  'action json',
                                                  const JsonEncoder.withIndent(
                                                    '  ',
                                                  ).convert(rawAction),
                                                ),
                                                child: const Text('复制 JSON'),
                                              ),
                                            ],
                                          ),
                                          if (summaryParts.isNotEmpty) ...[
                                            const SizedBox(height: 4),
                                            Text(
                                              summaryParts.join(' · '),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                color: AppColors.text70,
                                                height: 1.5,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                }),
                            ],
                          ),
                        );
                      }),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildRunLogCard(UtgRunLogSummary run) {
    final importing = _importingRunId == run.runId;
    final compileLabel = run.compileStatus.trim().isEmpty
        ? 'compile unknown'
        : 'compile ${run.compileStatus}';
    final routeLabel = run.toolName.trim().isEmpty ? '无 tool' : run.toolName;
    return _buildCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            run.goal.trim().isEmpty ? run.runId : run.goal,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          SelectableText(
            run.runId,
            style: const TextStyle(fontSize: 12, color: AppColors.text70),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildPill(run.success ? 'success' : 'failed'),
              _buildPill('${run.stepCount} steps'),
              _buildPill(compileLabel),
              _buildPill(routeLabel),
              if (run.compilePathId.trim().isNotEmpty)
                _buildPill('hit ${run.compilePathId}'),
              if (run.actPathId.trim().isNotEmpty)
                _buildPill('act ${run.actPathId}'),
            ],
          ),
          _buildInfoRow('started_at', run.startedAt),
          _buildInfoRow('done_reason', run.doneReason),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: () => _copyText('run_id', run.runId),
                  child: const Text('复制 run_id'),
                ),
                FilledButton.icon(
                  onPressed: importing ? null : () => _importRunLog(run),
                  icon: importing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.save_alt_outlined),
                  label: Text(importing ? '保存中...' : '保存为 Path'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _copyText(String label, String value) async {
    if (value.trim().isEmpty) {
      showToast('$label 为空', type: ToastType.error);
      return;
    }
    final copied = await AssistsMessageService.copyToClipboard(value);
    if (!mounted) return;
    showToast(
      copied ? '$label 已复制' : '$label 复制失败',
      type: copied ? ToastType.success : ToastType.error,
    );
  }

  String _actionDisplayName(String actionType) {
    switch (actionType.trim()) {
      case 'open_app':
        return '打开应用';
      case 'click':
        return '点击';
      case 'click_node':
        return '点击节点';
      case 'long_press':
        return '长按';
      case 'input_text':
        return '输入文本';
      case 'swipe':
        return '滑动';
      case 'press_key':
        return '按键';
      case 'wait':
        return '等待';
      case 'finished':
        return '结束';
      default:
        return actionType.trim().isEmpty ? '动作' : actionType.trim();
    }
  }

  String _buildActionPreviewText(Map<String, dynamic> rawAction) {
    final actionType = (rawAction['type'] ?? '').toString().trim();
    final label = _actionDisplayName(actionType);
    final packageName =
        (rawAction['packageName'] ?? rawAction['package_name'] ?? '')
            .toString()
            .trim();
    final textValue = (rawAction['text'] ?? '').toString().trim();
    final keyValue = (rawAction['key'] ?? '').toString().trim();
    final directionValue = (rawAction['direction'] ?? '').toString().trim();
    if (packageName.isNotEmpty) {
      return '$label($packageName)';
    }
    if (textValue.isNotEmpty) {
      return '$label($textValue)';
    }
    if (keyValue.isNotEmpty) {
      return '$label($keyValue)';
    }
    if (directionValue.isNotEmpty) {
      return '$label($directionValue)';
    }
    return label;
  }

  String _syncStatusLabel(String syncStatus) {
    switch (syncStatus.trim()) {
      case 'downloaded_from_cloud':
        return '来自云端';
      case 'uploaded_to_cloud':
        return '已上传云端';
      case 'imported_bundle':
        return '已导入 bundle';
      case 'local_only':
        return '仅本地';
      default:
        return syncStatus.trim().isEmpty ? '同步未知' : syncStatus.trim();
    }
  }

  Future<void> _controlProvider(String action) async {
    try {
      setState(() => _providerControlAction = action);
      final result = await AssistsMessageService.controlUtgProvider(
        action: action,
      );
      if (!mounted) return;
      _applyConfig(result.config);
      await _loadPaths(baseUrl: result.config.omnicloudBaseUrl, silent: true);
      await _loadRunLogs(baseUrl: result.config.omnicloudBaseUrl, silent: true);
      if (!mounted) return;
      showToast(
        result.success ? 'provider ${action} 成功' : 'provider ${action} 失败',
        type: result.success ? ToastType.success : ToastType.error,
      );
    } catch (e) {
      if (!mounted) return;
      showToast('provider ${action} 失败', type: ToastType.error);
      debugPrint('Control provider failed: $e');
    } finally {
      if (mounted) {
        setState(() => _providerControlAction = null);
      }
    }
  }

  Future<void> _importRunLog(UtgRunLogSummary run) async {
    try {
      setState(() => _importingRunId = run.runId);
      var result = await AssistsMessageService.importUtgRunLog(
        runId: run.runId,
        baseUrl: _baseUrlController.text.trim(),
      );
      if (!mounted) return;
      if (result.requiresConfirmation) {
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (dialogContext) {
            final preview = result.previewPaths.isEmpty
                ? null
                : result.previewPaths.first;
            return AlertDialog(
              title: const Text('保存 run_log 为 Path'),
              content: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SelectableText('run_id: ${run.runId}'),
                    const SizedBox(height: 8),
                    if (preview != null) ...[
                      SelectableText('path_id: ${preview.pathId}'),
                      const SizedBox(height: 6),
                      Text(
                        preview.description.trim().isEmpty
                            ? '无描述'
                            : preview.description,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'steps ${preview.stepCount} · slots ${preview.slotNames.length}',
                      ),
                      if (preview.slotExamples.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: preview.slotExamples.entries
                              .map(
                                (entry) =>
                                    _buildPill('${entry.key}=${entry.value}'),
                              )
                              .toList(),
                        ),
                      ],
                    ],
                    if (result.pendingNotes.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      SelectableText(
                        const JsonEncoder.withIndent(
                          '  ',
                        ).convert(result.pendingNotes),
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('确认保存'),
                ),
              ],
            );
          },
        );
        if (!mounted) return;
        if (confirmed != true) {
          return;
        }
        result = await AssistsMessageService.importUtgRunLog(
          runId: run.runId,
          confirm: true,
          baseUrl: _baseUrlController.text.trim(),
        );
        if (!mounted) return;
      }
      await _loadPaths(baseUrl: _baseUrlController.text.trim(), silent: true);
      await _loadRunLogs(baseUrl: _baseUrlController.text.trim(), silent: true);
      if (!mounted) return;
      if (!result.success) {
        showToast(
          result.errorMessage ?? result.pendingReason ?? '该 run_log 不能保存为 path',
          type: ToastType.error,
        );
        return;
      }
      final targetPathId = result.createdPathIds.isEmpty
          ? null
          : result.createdPathIds.first;
      if (targetPathId != null && targetPathId.trim().isNotEmpty) {
        setState(() {
          _highlightedPathId = targetPathId;
          _pathSearchController.text = targetPathId;
        });
        final matchedPaths = _pathsSnapshot?.paths ?? const <UtgPathSummary>[];
        for (final path in matchedPaths) {
          if (path.pathId == targetPathId) {
            await _viewPathBundle(path);
            break;
          }
        }
        if (!mounted) return;
      }
      final createdPathText = result.createdPathIds.isEmpty
          ? ''
          : '：${result.createdPathIds.join(', ')}';
      showToast('已保存为 path$createdPathText', type: ToastType.success);
    } catch (e) {
      if (!mounted) return;
      showToast('保存 run_log 为 path 失败', type: ToastType.error);
      debugPrint('Import run log failed: $e');
    } finally {
      if (mounted) {
        setState(() => _importingRunId = null);
      }
    }
  }

  Future<Map<String, String>?> _confirmPathRun(
    UtgPathSummary path,
    UtgBridgeExecutionContext executionContext,
  ) async {
    final controllers = {
      for (final slot in path.slotNames)
        slot: TextEditingController(text: path.slotExamples[slot] ?? ''),
    };
    try {
      return await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('执行 UTG Path'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SelectableText('path_id: ${path.pathId}'),
                  const SizedBox(height: 8),
                  Text(
                    path.description.trim().isEmpty ? '无描述' : path.description,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    executionContext.providerHealthy
                        ? 'provider health: ok'
                        : 'provider health: ${executionContext.providerMessage}',
                    style: TextStyle(
                      color: executionContext.providerHealthy
                          ? Colors.green.shade700
                          : Colors.red.shade700,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  SelectableText(
                    'bridge: ${executionContext.bridgeBaseUrl}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.text70,
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (controllers.isEmpty)
                    const Text('此 path 无需填写 slots。')
                  else
                    ...controllers.entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextField(
                          controller: entry.value,
                          decoration: InputDecoration(
                            labelText: entry.key,
                            hintText: path.slotExamples[entry.key] ?? '',
                            border: const OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  Navigator.of(dialogContext).pop({
                    for (final entry in controllers.entries)
                      entry.key: entry.value.text.trim(),
                  });
                },
                child: const Text('执行'),
              ),
            ],
          );
        },
      );
    } finally {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    }
  }

  Future<void> _uploadPathToCloud(UtgPathSummary path) async {
    final cloudBaseUrl = _cloudBaseUrlController.text.trim();
    if (cloudBaseUrl.isEmpty) {
      showToast('请先填写云端 Base URL', type: ToastType.error);
      return;
    }
    try {
      setState(() => _uploadingPathId = path.pathId);
      final result = await AssistsMessageService.uploadCloudUtgPath(
        pathId: path.pathId,
        cloudBaseUrl: cloudBaseUrl,
        baseUrl: _baseUrlController.text.trim(),
      );
      if (!mounted) return;
      if (!result.success) {
        showToast(result.errorMessage ?? '上传云端 path 失败', type: ToastType.error);
        return;
      }
      showToast('已上传到云端：${path.pathId}', type: ToastType.success);
    } catch (e) {
      if (!mounted) return;
      showToast('上传云端 path 失败', type: ToastType.error);
      debugPrint('Upload cloud path failed: $e');
    } finally {
      if (mounted) {
        setState(() => _uploadingPathId = null);
      }
    }
  }

  Future<void> _viewPathBundle(UtgPathSummary path) async {
    if (_expandedPathId == path.pathId) {
      setState(() {
        _expandedPathId = null;
        _pathBundleErrorById.remove(path.pathId);
      });
      return;
    }
    if (_pathBundleCache.containsKey(path.pathId)) {
      setState(() {
        _expandedPathId = path.pathId;
        _pathBundleErrorById.remove(path.pathId);
      });
      return;
    }
    try {
      setState(() => _viewingPathId = path.pathId);
      final payload = await AssistsMessageService.getUtgPathBundle(
        pathId: path.pathId,
        baseUrl: _baseUrlController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _pathBundleCache[path.pathId] = payload;
        _pathBundleErrorById.remove(path.pathId);
        _expandedPathId = path.pathId;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _pathBundleErrorById[path.pathId] = '加载 path 详情失败：$e';
        _expandedPathId = path.pathId;
      });
      showToast('加载 path 详情失败', type: ToastType.error);
      debugPrint('Load UTG path bundle failed: $e');
    } finally {
      if (mounted) {
        setState(() => _viewingPathId = null);
      }
    }
  }

  Future<void> _showRunResult(UtgManualRunResult result) async {
    final terminalSummary = result.terminalState.isEmpty
        ? '无 terminal verify 结果'
        : const JsonEncoder.withIndent('  ').convert(result.terminalState);
    final rawJson = const JsonEncoder.withIndent('  ').convert(result.rawJson);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(result.success ? 'UTG 执行成功' : 'UTG 执行失败'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SelectableText('goal: ${result.goal}'),
                const SizedBox(height: 8),
                SelectableText('path_id: ${result.pathId}'),
                const SizedBox(height: 8),
                if ((result.errorCode ?? '').isNotEmpty)
                  SelectableText('error_code: ${result.errorCode}'),
                if ((result.errorMessage ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  SelectableText('error_message: ${result.errorMessage}'),
                ],
                const SizedBox(height: 12),
                const Text(
                  'terminal verify',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  terminalSummary,
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                const Text(
                  'run logs',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  'canonical: ${result.canonicalRunLogPath}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 6),
                SelectableText(
                  'provider: ${result.providerRunLogPath}',
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton(
                      onPressed: () => _copyText(
                        'canonical run log',
                        result.canonicalRunLogPath,
                      ),
                      child: const Text('复制 canonical'),
                    ),
                    OutlinedButton(
                      onPressed: () => _copyText(
                        'provider run log',
                        result.providerRunLogPath,
                      ),
                      child: const Text('复制 provider'),
                    ),
                    OutlinedButton(
                      onPressed: () => _copyText('结果 JSON', rawJson),
                      child: const Text('复制 JSON'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('关闭'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _runPathFromDashboard(UtgPathSummary path) async {
    try {
      final executionContext =
          await AssistsMessageService.getUtgBridgeExecutionContext();
      if (!mounted) return;
      final slots = await _confirmPathRun(path, executionContext);
      if (!mounted || slots == null) {
        return;
      }
      setState(() => _runningPathId = path.pathId);
      final result = await AssistsMessageService.runUtgPath(
        pathId: path.pathId,
        slots: slots,
        baseUrl: _baseUrlController.text.trim(),
      );
      if (!mounted) return;
      await _showRunResult(result);
      if (!mounted) return;
      showToast(
        result.success
            ? '已通过 UTG 执行 ${path.pathId}'
            : 'UTG 执行失败：${path.pathId}',
        type: result.success ? ToastType.success : ToastType.error,
      );
    } on PlatformException catch (e) {
      if (!mounted) return;
      showToast(e.message ?? '获取 UTG bridge 失败', type: ToastType.error);
    } catch (e) {
      if (!mounted) return;
      showToast('执行 UTG path 失败', type: ToastType.error);
      debugPrint('Run UTG path failed: $e');
    } finally {
      if (mounted) {
        setState(() => _runningPathId = null);
      }
    }
  }

  Future<void> _deletePathFromDashboard(UtgPathSummary path) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('删除 UTG Path'),
          content: SelectableText(
            '确认删除 path_id=${path.pathId}？\n\n删除后会直接从当前本地 provider 的 UTG store 移除。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (shouldDelete != true || !mounted) {
      return;
    }
    try {
      setState(() => _deletingPathId = path.pathId);
      final result = await AssistsMessageService.deleteUtgPath(
        pathId: path.pathId,
        baseUrl: _baseUrlController.text.trim(),
      );
      if (!mounted) return;
      if (!result.success) {
        showToast(
          result.errorMessage ?? '删除失败：${path.pathId}',
          type: ToastType.error,
        );
        return;
      }
      await _loadPaths(baseUrl: _baseUrlController.text.trim(), silent: true);
      if (!mounted) return;
      setState(() {
        if (_highlightedPathId == path.pathId) {
          _highlightedPathId = null;
        }
        if (_expandedPathId == path.pathId) {
          _expandedPathId = null;
        }
        _pathBundleCache.remove(path.pathId);
        _pathBundleErrorById.remove(path.pathId);
      });
      showToast('已删除 ${path.pathId}', type: ToastType.success);
    } catch (e) {
      if (!mounted) return;
      showToast('删除 UTG path 失败', type: ToastType.error);
      debugPrint('Delete UTG path failed: $e');
    } finally {
      if (mounted) {
        setState(() => _deletingPathId = null);
      }
    }
  }

  Future<void> _downloadCloudPath() async {
    final cloudBaseUrl = _cloudBaseUrlController.text.trim();
    final pathId = _cloudPathIdController.text.trim();
    if (cloudBaseUrl.isEmpty || pathId.isEmpty) {
      showToast('请填写云端 Base URL 和 path_id', type: ToastType.error);
      return;
    }
    try {
      setState(() => _downloadingCloudPath = true);
      final result = await AssistsMessageService.downloadCloudUtgPath(
        pathId: pathId,
        cloudBaseUrl: cloudBaseUrl,
        baseUrl: _baseUrlController.text.trim(),
      );
      if (!mounted) return;
      if (!result.success) {
        showToast(result.errorMessage ?? '下载云端 path 失败', type: ToastType.error);
        return;
      }
      await _loadPaths(baseUrl: _baseUrlController.text.trim(), silent: true);
      if (!mounted) return;
      showToast('已下载云端 path：$pathId', type: ToastType.success);
    } catch (e) {
      if (!mounted) return;
      showToast('下载云端 path 失败', type: ToastType.error);
      debugPrint('Download cloud path failed: $e');
    } finally {
      if (mounted) {
        setState(() => _downloadingCloudPath = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final allPaths = _pathsSnapshot?.paths ?? const <UtgPathSummary>[];
    final searchQuery = _pathSearchController.text.trim().toLowerCase();
    final filteredPaths = searchQuery.isEmpty
        ? allPaths
        : allPaths.where((path) {
            final haystack = <String>[
              path.pathId,
              path.description,
              path.startNodeId,
              path.endNodeId,
              path.startNodeDescription,
              path.endNodeDescription,
              ...path.slotNames,
            ].join(' ').toLowerCase();
            return haystack.contains(searchQuery);
          }).toList();
    final groupedPaths = <String, List<UtgPathSummary>>{};
    for (final path in filteredPaths) {
      final groupName = path.groupName.trim().isEmpty
          ? 'unknown_app'
          : path.groupName.trim();
      groupedPaths.putIfAbsent(groupName, () => <UtgPathSummary>[]).add(path);
    }
    final groupKeys = groupedPaths.keys.toList()..sort();
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CommonAppBar(
        title: 'UTG',
        primary: true,
        actions: [
          IconButton(
            onPressed: _loading ? null : _refreshAll,
            icon: const Icon(Icons.refresh_outlined),
            tooltip: '刷新',
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshAll,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildCard(
                    child: const Text(
                      '这里统一处理 OmniCloud UTG provider 设置，并展示当前 provider 暴露出来的全部 UTG paths。'
                      ' `vlm_task` 的 compile-first pre-hook 也由这里控制。',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.text70,
                        height: 1.7,
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'UTG 设置',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _utgEnabled,
                          title: const Text('启用 `vlm_task` 前置 UTG pre-hook'),
                          onChanged: _saving
                              ? null
                              : (value) => setState(() => _utgEnabled = value),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _providerAutoStartEnabled,
                          title: const Text('打开 OOB 时自动拉起 provider'),
                          onChanged: _saving
                              ? null
                              : (value) => setState(
                                  () => _providerAutoStartEnabled = value,
                                ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _fallbackToVlmOnFailureEnabled,
                          title: const Text('UTG 失败时自动回退到 VLM'),
                          onChanged: _saving
                              ? null
                              : (value) => setState(
                                  () => _fallbackToVlmOnFailureEnabled = value,
                                ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _runLogRecordingEnabled,
                          title: const Text('持续记录 UTG run_log'),
                          onChanged: _saving
                              ? null
                              : (value) => setState(
                                  () => _runLogRecordingEnabled = value,
                                ),
                        ),
                        const SizedBox(height: 8),
                        _buildInputField(
                          controller: _baseUrlController,
                          label: 'OmniCloud Base URL',
                          hint: 'http://127.0.0.1:19070',
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(
                          controller: _startCommandController,
                          label: 'Provider Start Command',
                          minLines: 2,
                          maxLines: 3,
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(
                          controller: _workingDirectoryController,
                          label: 'Working Directory',
                          hint: '/data/data/com.termux/files/home/OmniCloud',
                        ),
                        const SizedBox(height: 8),
                        _buildInfoRow(
                          'provider health',
                          config == null
                              ? ''
                              : (config.providerHealthy
                                    ? (config.providerHealthStatus.isEmpty
                                          ? 'ok'
                                          : config.providerHealthStatus)
                                    : 'unreachable'),
                        ),
                        _buildInfoRow(
                          'sidecar run_log',
                          config?.runLogPath ?? '',
                        ),
                        _buildInfoRow(
                          'provider run_log',
                          config?.providerRunLogPath ?? '',
                        ),
                        _buildInfoRow(
                          'canonical run_log',
                          config?.canonicalRunLogPath ?? '',
                        ),
                        _buildInfoRow(
                          'provider stdout',
                          config?.providerStdoutPath ?? '',
                        ),
                        const SizedBox(height: 16),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed:
                                  _saving || _providerControlAction != null
                                  ? null
                                  : () => _loadPaths(
                                      baseUrl: _baseUrlController.text.trim(),
                                    ),
                              icon: const Icon(Icons.sync_outlined),
                              label: const Text('刷新 paths'),
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  _saving || _providerControlAction != null
                                  ? null
                                  : () => _loadRunLogs(
                                      baseUrl: _baseUrlController.text.trim(),
                                    ),
                              icon: const Icon(Icons.receipt_long_outlined),
                              label: const Text('刷新 run_log'),
                            ),
                            FilledButton.icon(
                              onPressed:
                                  _saving || _providerControlAction != null
                                  ? null
                                  : () => _controlProvider('start'),
                              icon: _providerControlAction == 'start'
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.play_circle_outline),
                              label: Text(
                                _providerControlAction == 'start'
                                    ? '启动中...'
                                    : '启动 provider',
                              ),
                            ),
                            FilledButton.icon(
                              onPressed:
                                  _saving || _providerControlAction != null
                                  ? null
                                  : () => _controlProvider('restart'),
                              icon: _providerControlAction == 'restart'
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.restart_alt_outlined),
                              label: Text(
                                _providerControlAction == 'restart'
                                    ? '重启中...'
                                    : '重启 provider',
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed:
                                  _saving || _providerControlAction != null
                                  ? null
                                  : () => _controlProvider('stop'),
                              icon: _providerControlAction == 'stop'
                                  ? const SizedBox(
                                      width: 14,
                                      height: 14,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.stop_circle_outlined),
                              label: Text(
                                _providerControlAction == 'stop'
                                    ? '停止中...'
                                    : '停止 provider',
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: _saving ? null : _saveConfig,
                              child: Text(_saving ? '保存中...' : '保存设置'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  _buildCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          '下载云端 Path',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '本地 provider 会从另一台 OmniCloud provider 拉取 `/paths/{path_id}/bundle`，再 merge 到当前手机上的本地 UTG store。',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.text70,
                            height: 1.6,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(
                          controller: _cloudBaseUrlController,
                          label: '云端 Base URL',
                          hint: '例如 http://192.168.1.10:19070',
                        ),
                        const SizedBox(height: 12),
                        _buildInputField(
                          controller: _cloudPathIdController,
                          label: '云端 path_id',
                          hint: '例如 global-open-settings',
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: _downloadingCloudPath || _saving
                                ? null
                                : _downloadCloudPath,
                            icon: _downloadingCloudPath
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.cloud_download_outlined),
                            label: Text(
                              _downloadingCloudPath ? '下载中...' : '下载云端 Path',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text(
                        '最近 Run Logs',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_loadingRunLogs)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        _buildPill('${_runLogsSnapshot?.count ?? 0}'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_runLogsError != null)
                    _buildCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'UTG run_log 列表加载失败',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _runLogsError!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.text70,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if ((_runLogsSnapshot?.runs ??
                          const <UtgRunLogSummary>[])
                      .isEmpty)
                    _buildCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '当前没有可导入的 run_log',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'OmniCloud 目前还没有记录到 canonical run(goal) 日志，先执行一次 `vlm_task` 或手动运行 path。',
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.text70,
                              height: 1.7,
                            ),
                          ),
                          if ((_runLogsSnapshot?.runLogPath ?? '')
                              .trim()
                              .isNotEmpty) ...[
                            const SizedBox(height: 10),
                            _buildInfoRow(
                              'canonical run_log',
                              _runLogsSnapshot?.runLogPath ?? '',
                            ),
                          ],
                        ],
                      ),
                    )
                  else
                    ..._runLogsSnapshot!.runs.map(
                      (run) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildRunLogCard(run),
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text(
                        '已有 UTG Paths',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_loadingPaths)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        _buildPill('${allPaths.length}'),
                      if (searchQuery.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _buildPill('筛选 ${filteredPaths.length}'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _pathSearchController,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: '搜索 path',
                              hintText: '按 path_id、描述、slot、node 过滤',
                              prefixIcon: const Icon(Icons.search_outlined),
                              suffixIcon: searchQuery.isEmpty
                                  ? null
                                  : IconButton(
                                      onPressed: () {
                                        setState(() {
                                          _pathSearchController.clear();
                                          _highlightedPathId = null;
                                        });
                                      },
                                      icon: const Icon(Icons.close_outlined),
                                      tooltip: '清空搜索',
                                    ),
                              border: const OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_pathsError != null)
                    _buildCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'UTG path 列表加载失败',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _pathsError!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.text70,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (allPaths.isEmpty)
                    _buildCard(
                      child: const Text(
                        '当前 provider 没有返回可展示的 UTG path。确认 OmniCloud 已启动、Base URL 正确，并且 provider 能访问到 UTG store。',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.text70,
                          height: 1.7,
                        ),
                      ),
                    )
                  else if (filteredPaths.isEmpty)
                    _buildCard(
                      child: Text(
                        '没有匹配到 path：${_pathSearchController.text.trim()}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.text70,
                          height: 1.7,
                        ),
                      ),
                    )
                  else
                    ...groupKeys.expand((groupName) {
                      final paths =
                          groupedPaths[groupName] ?? const <UtgPathSummary>[];
                      return [
                        _buildCard(
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  groupName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              _buildPill('${paths.length}'),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        ...paths.map(
                          (path) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildPathCard(path),
                          ),
                        ),
                      ];
                    }),
                ],
              ),
            ),
    );
  }
}
