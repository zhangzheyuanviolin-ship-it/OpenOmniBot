import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui/l10n/l10n.dart';
import 'package:ui/services/app_state_service.dart';
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
  final TextEditingController _cloudFunctionIdController =
      TextEditingController();
  final TextEditingController _functionSearchController =
      TextEditingController();

  bool _loading = true;
  bool _saving = false;
  bool _loadingFunctions = false;
  bool _loadingRunLogs = false;
  bool _downloadingCloudFunction = false;
  bool _utgEnabled = true;
  bool _providerAutoStartEnabled = true;
  String? _runningFunctionId;
  String? _deletingFunctionId;
  String? _distillingFunctionId;
  String? _uploadingFunctionId;
  String? _expandedFunctionId;
  String? _expandedRunId;
  String? _viewingFunctionId;
  String? _importingRunId;
  String? _providerControlAction;
  String? _highlightedFunctionId;
  bool _runLogsExpanded = false;
  String _runLogFilter = 'all';
  final Map<String, Map<String, dynamic>> _functionBundleCache = {};
  final Map<String, String> _functionBundleErrorById = {};
  final Map<String, UtgRunLogDetail> _runLogDetailCache = {};
  final Map<String, String> _runLogDetailErrorById = {};
  final Set<String> _loadingRunLogDetailIds = <String>{};
  final Set<String> _expandedStepKeys = <String>{};
  final Set<String> _expandedFunctionKeys = <String>{};

  UtgBridgeConfig? _config;
  UtgFunctionsSnapshot? _functionsSnapshot;
  UtgRunLogsSnapshot? _runLogsSnapshot;
  String? _functionsError;
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
    _cloudFunctionIdController.dispose();
    _functionSearchController.dispose();
    super.dispose();
  }

  Future<void> _refreshAll() async {
    setState(() => _loading = true);
    try {
      final config = await AssistsMessageService.getUtgBridgeConfig();
      if (!mounted) return;
      _applyConfig(config);
      await Future.wait([
        _loadFunctions(baseUrl: config.resolvedOmniflowBaseUrl, silent: true),
        _loadRunLogs(baseUrl: config.resolvedOmniflowBaseUrl, silent: true),
      ]);
    } on PlatformException catch (e) {
      showToast(e.message ?? '加载 OmniFlow 配置失败', type: ToastType.error);
    } catch (e) {
      showToast('加载 OmniFlow 配置失败', type: ToastType.error);
      debugPrint('Load OmniFlow config failed: $e');
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
    _baseUrlController.text = config.omniflowBaseUrl;
    _startCommandController.text = config.providerStartCommand;
    _workingDirectoryController.text = config.providerWorkingDirectory ?? '';
    if (_cloudBaseUrlController.text.trim().isEmpty) {
      _cloudBaseUrlController.text = config.omniflowBaseUrl;
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
        omniflowBaseUrl: _baseUrlController.text.trim(),
        providerStartCommand: _startCommandController.text.trim(),
        providerWorkingDirectory: _workingDirectoryController.text.trim(),
      );
      if (!mounted) return;
      _applyConfig(saved);
      await Future.wait([
        _loadFunctions(baseUrl: saved.resolvedOmniflowBaseUrl, silent: true),
        _loadRunLogs(baseUrl: saved.resolvedOmniflowBaseUrl, silent: true),
      ]);
      showToast('OmniFlow 配置已保存', type: ToastType.success);
    } on PlatformException catch (e) {
      showToast(e.message ?? '保存 OmniFlow 配置失败', type: ToastType.error);
    } catch (e) {
      showToast('保存 OmniFlow 配置失败', type: ToastType.error);
      debugPrint('Save OmniFlow config failed: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _loadFunctions({String? baseUrl, bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loadingFunctions = true;
        _functionsError = null;
      });
    } else {
      _loadingFunctions = true;
      _functionsError = null;
    }
    try {
      final snapshot = await AssistsMessageService.getUtgFunctions(
        baseUrl: baseUrl,
      );
      if (!mounted) return;
      setState(() {
        _functionsSnapshot = snapshot;
        _functionsError = null;
      });
    } catch (e) {
      final errorText = e.toString().replaceFirst('Exception: ', '');
      if (!mounted) return;
      setState(() {
        _functionsSnapshot = null;
        _functionsError = errorText;
      });
      if (!silent) {
        showToast('加载 OmniFlow 资产失败：$errorText', type: ToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _loadingFunctions = false);
      } else {
        _loadingFunctions = false;
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
        final activeRunIds = snapshot.runs.map((run) => run.runId).toSet();
        _runLogDetailCache.removeWhere(
          (runId, _) => !activeRunIds.contains(runId),
        );
        _runLogDetailErrorById.removeWhere(
          (runId, _) => !activeRunIds.contains(runId),
        );
        _loadingRunLogDetailIds.removeWhere(
          (runId) => !activeRunIds.contains(runId),
        );
      });
    } catch (e) {
      final errorText = e.toString().replaceFirst('Exception: ', '');
      if (!mounted) return;
      setState(() {
        _runLogsSnapshot = null;
        _runLogsError = errorText;
      });
      if (!silent) {
        showToast('加载 OmniFlow run_logs 失败：$errorText', type: ToastType.error);
      }
    } finally {
      if (mounted) {
        setState(() => _loadingRunLogs = false);
      } else {
        _loadingRunLogs = false;
      }
    }
  }

  Future<void> _ensureRunLogDetail(UtgRunLogSummary run) async {
    final runId = run.runId.trim();
    if (runId.isEmpty ||
        _runLogDetailCache.containsKey(runId) ||
        _loadingRunLogDetailIds.contains(runId)) {
      return;
    }
    setState(() {
      _loadingRunLogDetailIds.add(runId);
      _runLogDetailErrorById.remove(runId);
    });
    try {
      final detail = await AssistsMessageService.getUtgRunLogDetail(
        runId: runId,
        baseUrl: _config?.resolvedOmniflowBaseUrl,
      );
      if (!mounted) return;
      setState(() {
        _runLogDetailCache[runId] = detail;
        _runLogDetailErrorById.remove(runId);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _runLogDetailErrorById[runId] = e.toString().replaceFirst(
          'Exception: ',
          '',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingRunLogDetailIds.remove(runId);
        });
      } else {
        _loadingRunLogDetailIds.remove(runId);
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

  Widget _buildPill(
    String text, {
    Color backgroundColor = const Color(0xFFF2F5FA),
    Color textColor = AppColors.text70,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: textColor,
        ),
      ),
    );
  }

  Widget _buildRunStatusPill(bool success) {
    return _buildPill(
      success ? 'success' : 'failed',
      backgroundColor: success
          ? const Color(0xFFE8F7EE)
          : const Color(0xFFFDECEC),
      textColor: success ? const Color(0xFF117A37) : const Color(0xFFB42318),
    );
  }

  List<UtgRunLogSummary> _filteredRunLogs() {
    final allRuns = _runLogsSnapshot?.runs ?? const <UtgRunLogSummary>[];
    switch (_runLogFilter) {
      case 'success':
        return allRuns.where((run) => run.success).toList();
      case 'failed':
        return allRuns.where((run) => !run.success).toList();
      default:
        return allRuns;
    }
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

  Widget _buildFunctionCard(UtgFunctionSummary function) {
    final description = function.description.trim().isEmpty
        ? '无描述'
        : function.description;
    final running = _runningFunctionId == function.functionId;
    final deleting = _deletingFunctionId == function.functionId;
    final distilling = _distillingFunctionId == function.functionId;
    final uploading = _uploadingFunctionId == function.functionId;
    final viewing = _viewingFunctionId == function.functionId;
    final expanded = _expandedFunctionId == function.functionId;
    final highlighted = _highlightedFunctionId == function.functionId;
    final isTemporary = _isTemporaryFunction(function);
    final isReady = _isReadyFunction(function);
    final bundle = _functionBundleCache[function.functionId];
    final bundleError = _functionBundleErrorById[function.functionId];
    final lastRun = function.lastRun;
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
            function.functionId,
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
              _buildPill(
                _assetKindLabel(function),
                backgroundColor: isTemporary
                    ? const Color(0xFFFFF4E5)
                    : isReady
                    ? const Color(0xFFE8F7EE)
                    : const Color(0xFFF2F5FA),
                textColor: isTemporary
                    ? const Color(0xFFB54708)
                    : isReady
                    ? const Color(0xFF117A37)
                    : AppColors.text70,
              ),
              if (function.appName.trim().isNotEmpty)
                _buildPill(function.appName),
              _buildPill(_syncStatusLabel(function.syncStatus)),
              if (hasLastRun)
                _buildPill(
                  lastRunSuccess ? '最近成功' : '最近失败',
                  backgroundColor: lastRunSuccess
                      ? const Color(0xFFE8F7EE)
                      : const Color(0xFFFDECEC),
                  textColor: lastRunSuccess
                      ? const Color(0xFF117A37)
                      : const Color(0xFFB42318),
                ),
              _buildPill('${function.stepCount} steps'),
              _buildPill('parameters ${function.parameterNames.length}'),
              if (function.parameterNames.isEmpty) _buildPill('无参数'),
              if (function.parameterNames.isNotEmpty) _buildPill('需填写参数'),
              ...function.parameterNames.map(
                (parameter) => _buildPill(parameter),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildInfoRow(
            'app',
            [
              function.appName,
              function.packageName,
            ].where((e) => e.trim().isNotEmpty).join(' · '),
          ),
          if (function.parameterExamples.isNotEmpty) ...[
            const SizedBox(height: 10),
            const Text(
              'parameter 示例',
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
              children: function.parameterExamples.entries
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
                      _runningFunctionId != null ||
                          _deletingFunctionId != null ||
                          _distillingFunctionId != null ||
                          _uploadingFunctionId != null ||
                          _viewingFunctionId != null
                      ? null
                      : () => _viewFunctionBundle(function),
                  icon: viewing
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.account_tree_outlined),
                  label: Text(viewing ? '加载中...' : '查看资产'),
                ),
                OutlinedButton.icon(
                  onPressed:
                      _runningFunctionId != null ||
                          _deletingFunctionId != null ||
                          _distillingFunctionId != null ||
                          _uploadingFunctionId != null ||
                          _viewingFunctionId != null
                      ? null
                      : () => _deleteFunctionFromDashboard(function),
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
                      isTemporary ||
                          _runningFunctionId != null ||
                          _deletingFunctionId != null ||
                          _distillingFunctionId != null ||
                          _uploadingFunctionId != null ||
                          _viewingFunctionId != null
                      ? null
                      : () => _uploadFunctionToCloud(function),
                  icon: uploading
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.cloud_upload_outlined),
                  label: Text(
                    isTemporary ? '仅资产区可上传' : (uploading ? '上传中...' : '上传云端'),
                  ),
                ),
                if (isTemporary)
                  OutlinedButton.icon(
                    onPressed:
                        _runningFunctionId != null ||
                            _deletingFunctionId != null ||
                            _distillingFunctionId != null ||
                            _uploadingFunctionId != null ||
                            _viewingFunctionId != null
                        ? null
                        : () => _distillFunctionFromDashboard(function),
                    icon: distilling
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.auto_awesome_outlined),
                    label: Text(distilling ? '沉淀中...' : '沉淀资产'),
                  ),
                FilledButton.icon(
                  onPressed:
                      _runningFunctionId != null ||
                          _deletingFunctionId != null ||
                          _distillingFunctionId != null ||
                          _uploadingFunctionId != null ||
                          _viewingFunctionId != null
                      ? null
                      : () => _runFunctionFromDashboard(function),
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
              _buildFunctionBundleView(function, bundle),
          ],
        ],
      ),
    );
  }

  Widget _buildFunctionBundleView(
    UtgFunctionSummary function,
    Map<String, dynamic> payload,
  ) {
    final graph =
        (payload['graph'] as Map<String, dynamic>?) ??
        const <String, dynamic>{};
    final functions =
        (graph['functions'] as List<dynamic>?) ?? const <dynamic>[];
    final nodes = (graph['nodes'] as List<dynamic>?) ?? const <dynamic>[];
    final functionPayload = functions.isNotEmpty && functions.first is Map
        ? Map<String, dynamic>.from(functions.first as Map)
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
    final steps =
        (functionPayload['steps'] as Map<dynamic, dynamic>?) ?? const {};
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
      final functions =
          (node['functions'] as Map<dynamic, dynamic>?) ?? const {};
      final functionNames =
          (step['functions'] as List<dynamic>?) ?? const <dynamic>[];
      for (final functionNameRaw in functionNames) {
        final functionName = functionNameRaw.toString();
        final functionPayload = functions[functionName] is Map
            ? Map<String, dynamic>.from(functions[functionName] as Map)
            : const <String, dynamic>{};
        final actions =
            (functionPayload['actions'] as List<dynamic>?) ?? const <dynamic>[];
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
              const Text('资产详情', style: TextStyle(fontWeight: FontWeight.w700)),
              const Spacer(),
              OutlinedButton(
                onPressed: () => _copyText(
                  '资产 JSON',
                  const JsonEncoder.withIndent('  ').convert(payload),
                ),
                child: const Text('复制 JSON'),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: () {
                  setState(() {
                    if (_expandedFunctionId == function.functionId) {
                      _expandedFunctionId = null;
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
          if (function.parameterNames.isNotEmpty) ...[
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: function.parameterNames.map(_buildPill).toList(),
            ),
            const SizedBox(height: 12),
          ],
          if (stepEntries.isEmpty)
            const Text('这条资产暂时没有步骤。', style: TextStyle(color: AppColors.text70))
          else
            ...stepEntries.map((entry) {
              final nodeId = entry.key;
              final stepKey = '${function.functionId}::$nodeId';
              final stepExpanded = _expandedStepKeys.contains(stepKey);
              final step = entry.value is Map
                  ? Map<String, dynamic>.from(entry.value as Map)
                  : const <String, dynamic>{};
              final node = nodeById[nodeId] ?? const <String, dynamic>{};
              final repr = (node['repr'] as Map<dynamic, dynamic>?) ?? const {};
              final functions =
                  (node['functions'] as Map<dynamic, dynamic>?) ?? const {};
              final functionNames =
                  (step['functions'] as List<dynamic>?) ?? const <dynamic>[];
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
                          _buildPill('${functionNames.length} functions'),
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
                        functionNames.map((e) => e.toString()).join(' · '),
                        style: const TextStyle(
                          color: AppColors.text70,
                          fontSize: 12,
                          height: 1.5,
                        ),
                      )
                    else
                      ...functionNames.map((functionNameRaw) {
                        final functionName = functionNameRaw.toString();
                        final functionKey = '$stepKey::$functionName';
                        final functionExpanded = _expandedFunctionKeys.contains(
                          functionKey,
                        );
                        final functionPayload = functions[functionName] is Map
                            ? Map<String, dynamic>.from(
                                functions[functionName] as Map,
                              )
                            : const <String, dynamic>{};
                        final actions =
                            (functionPayload['actions'] as List<dynamic>?) ??
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
                                    if (functionExpanded) {
                                      _expandedFunctionKeys.remove(functionKey);
                                    } else {
                                      _expandedFunctionKeys.add(functionKey);
                                    }
                                  });
                                },
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        functionName,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    _buildPill('${actions.length} actions'),
                                    const SizedBox(width: 8),
                                    Icon(
                                      functionExpanded
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                      color: AppColors.text70,
                                    ),
                                  ],
                                ),
                              ),
                              if ((functionPayload['description'] ?? '')
                                  .toString()
                                  .trim()
                                  .isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  (functionPayload['description'] ?? '')
                                      .toString(),
                                  style: const TextStyle(
                                    color: AppColors.text70,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              if (!functionExpanded)
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
    final expanded = _expandedRunId == run.runId;
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
          if (run.operationDescription.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              run.operationDescription.trim(),
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black87,
                height: 1.5,
              ),
            ),
          ],
          if (run.selectorLabel.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              run.selectorReason.trim().isNotEmpty
                  ? 'selected_by: ${run.selectorLabel} · ${run.selectorReason}'
                  : 'selected_by: ${run.selectorLabel}',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.text70,
                height: 1.5,
              ),
            ),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildRunStatusPill(run.success),
              _buildPill('${run.stepCount} steps'),
              _buildPill(compileLabel),
              _buildPill(routeLabel),
              if (run.compileFunctionId.trim().isNotEmpty)
                _buildPill('compile fn ${run.compileFunctionId}'),
              if (run.actFunctionId.trim().isNotEmpty)
                _buildPill('execute fn ${run.actFunctionId}'),
            ],
          ),
          _buildInfoRow('started_at', run.startedAt),
          _buildInfoRow('done_reason', run.doneReason),
          if (run.errorMessage.trim().isNotEmpty)
            _buildInfoRow('error', run.errorMessage),
          if (run.finalPackageName.trim().isNotEmpty)
            _buildInfoRow('final_package', run.finalPackageName),
          const SizedBox(height: 12),
          Row(
            children: [
              OutlinedButton(
                onPressed: () async {
                  if (expanded) {
                    setState(() {
                      _expandedRunId = null;
                    });
                    return;
                  }
                  setState(() {
                    _expandedRunId = run.runId;
                  });
                  await _ensureRunLogDetail(run);
                },
                child: Text(expanded ? '收起详情' : '查看详情'),
              ),
            ],
          ),
          if (expanded) ...[
            const SizedBox(height: 12),
            _buildRunLogDetailView(run),
          ],
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
                      : const Icon(Icons.psychology_alt_outlined),
                  label: Text(importing ? '记忆中...' : '记忆'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRunLogDetailView(UtgRunLogSummary run) {
    final runId = run.runId.trim();
    final detail = _runLogDetailCache[runId];
    final loading = _loadingRunLogDetailIds.contains(runId);
    final errorText = _runLogDetailErrorById[runId];
    final raw = detail?.runLog ?? const <String, dynamic>{};
    final view =
        (detail?.rawJson['view'] as Map<dynamic, dynamic>?) ??
        const <dynamic, dynamic>{};
    final viewSteps = (view['steps'] as List<dynamic>?) ?? const <dynamic>[];
    final summary = (view['summary'] ?? '').toString().trim();
    final emptyMessage = (view['empty_message'] ?? '').toString().trim().isEmpty
        ? 'provider 当前没有返回可展示的 step。'
        : (view['empty_message'] ?? '').toString().trim();
    final finalPackage = (view['final_package'] ?? '').toString().trim().isEmpty
        ? 'unknown'
        : (view['final_package'] ?? '').toString().trim();
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
                'Run Log 详情',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              OutlinedButton(
                onPressed: view.isEmpty
                    ? null
                    : () => _copyText(
                        'provider view json',
                        const JsonEncoder.withIndent('  ').convert(view),
                      ),
                child: const Text('复制 View JSON'),
              ),
            ],
          ),
          if (loading) ...[
            const SizedBox(height: 12),
            const Row(
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text(
                  '正在加载 run_log 详情...',
                  style: TextStyle(color: AppColors.text70),
                ),
              ],
            ),
          ] else if (errorText != null && errorText.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'run_log 详情加载失败：$errorText',
              style: const TextStyle(color: Color(0xFFB42318), height: 1.6),
            ),
          ] else if (raw.isEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              '当前没有拿到完整 run_log 详情。',
              style: TextStyle(color: AppColors.text70, height: 1.6),
            ),
          ] else ...[
            if (summary.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                summary,
                style: const TextStyle(
                  fontSize: 13,
                  color: Colors.black87,
                  height: 1.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (viewSteps.isEmpty)
              Text(
                emptyMessage,
                style: const TextStyle(color: AppColors.text70, height: 1.6),
              )
            else
              ...viewSteps.asMap().entries.map((entry) {
                final step = entry.value is Map
                    ? Map<String, dynamic>.from(entry.value as Map)
                    : const <String, dynamic>{};
                final actions =
                    (step['actions'] as List<dynamic>?)
                        ?.map((item) => item.toString().trim())
                        .where((item) => item.isNotEmpty)
                        .toList() ??
                    const <String>[];
                final stepSuccess = step['success'] != false;
                final operationDescription =
                    ((step['title'] ?? '').toString()).trim().isEmpty
                    ? 'Step ${entry.key + 1}'
                    : (step['title'] ?? '').toString().trim();
                final selectorLabel = ((step['selected_by'] ?? '').toString())
                    .trim();
                final selectorReason = ((step['why'] ?? '').toString()).trim();
                final resultMessage = ((step['result'] ?? '').toString())
                    .trim();
                final resultThought = ((step['thought'] ?? '').toString())
                    .trim();
                final resultTextSummary = ((step['summary'] ?? '').toString())
                    .trim();
                final errorText = ((step['error'] ?? '').toString()).trim();
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFE4E8EE)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Step ${entry.key + 1} · $operationDescription',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildRunStatusPill(stepSuccess),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (selectorLabel.isNotEmpty)
                        Text(
                          'selected_by: $selectorLabel',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.text70,
                            height: 1.5,
                          ),
                        ),
                      if (selectorReason.isNotEmpty)
                        Text(
                          'why: $selectorReason',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.text70,
                            height: 1.5,
                          ),
                        ),
                      ...actions.asMap().entries.map(
                        (actionEntry) => Text(
                          'action ${actionEntry.key + 1}: ${actionEntry.value}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.text70,
                            height: 1.5,
                          ),
                        ),
                      ),
                      if (resultMessage.isNotEmpty)
                        Text(
                          'result: $resultMessage',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.text70,
                            height: 1.5,
                          ),
                        ),
                      if (resultThought.isNotEmpty)
                        Text(
                          'thought: $resultThought',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.text70,
                            height: 1.5,
                          ),
                        ),
                      if (resultTextSummary.isNotEmpty)
                        Text(
                          'summary: $resultTextSummary',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.text70,
                            height: 1.5,
                          ),
                        ),
                      if (errorText.isNotEmpty)
                        Text(
                          'error: $errorText',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFFB42318),
                            height: 1.5,
                          ),
                        ),
                    ],
                  ),
                );
              }),
            const SizedBox(height: 8),
            Text(
              'final package: $finalPackage',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.text70,
                height: 1.5,
              ),
            ),
          ],
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
        return 'click';
      case 'click_node':
        return 'click_node';
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
    final params = (rawAction['params'] as Map<dynamic, dynamic>?) ?? const {};
    final packageName =
        (rawAction['packageName'] ??
                rawAction['package_name'] ??
                params['packageName'] ??
                params['package_name'] ??
                '')
            .toString()
            .trim();
    final textValue = (rawAction['text'] ?? params['text'] ?? '')
        .toString()
        .trim();
    final keyValue = (rawAction['key'] ?? params['key'] ?? '')
        .toString()
        .trim();
    final directionValue = (rawAction['direction'] ?? params['direction'] ?? '')
        .toString()
        .trim();
    final xValue = rawAction['x'] ?? params['x'];
    final yValue = rawAction['y'] ?? params['y'];
    final targetDescription =
        (rawAction['targetDescription'] ??
                rawAction['target_description'] ??
                params['targetDescription'] ??
                params['target_description'] ??
                '')
            .toString()
            .trim();
    if (actionType == 'click') {
      if (xValue != null && yValue != null) {
        return 'click ($xValue, $yValue)';
      }
      if (targetDescription.isNotEmpty) {
        return 'click $targetDescription';
      }
      return 'click';
    }
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

  bool _isTemporaryFunction(UtgFunctionSummary function) {
    return function.assetState.trim().toLowerCase() == 'temporary';
  }

  bool _isReadyFunction(UtgFunctionSummary function) {
    return function.assetState.trim().toLowerCase() == 'ready';
  }

  String _assetKindLabel(UtgFunctionSummary function) {
    if (_isTemporaryFunction(function)) {
      return '临时区';
    }
    if (_isReadyFunction(function)) {
      return '资产区';
    }
    return function.assetState.trim().isEmpty
        ? '未分区'
        : function.assetState.trim();
  }

  Future<void> _controlProvider(String action) async {
    try {
      setState(() => _providerControlAction = action);
      final result = await AssistsMessageService.controlUtgProvider(
        action: action,
      );
      if (!mounted) return;
      _applyConfig(result.config);
      await _loadFunctions(
        baseUrl: result.config.resolvedOmniflowBaseUrl,
        silent: true,
      );
      await _loadRunLogs(
        baseUrl: result.config.resolvedOmniflowBaseUrl,
        silent: true,
      );
      if (!mounted) return;
      showToast(
        result.success
            ? 'provider $action 成功'
            : 'provider $action 失败：${result.message}',
        type: result.success ? ToastType.success : ToastType.error,
      );
    } catch (e) {
      final errorText = e.toString().replaceFirst('Exception: ', '');
      if (!mounted) return;
      showToast('provider $action 失败：$errorText', type: ToastType.error);
      debugPrint('Control provider failed: $e');
    } finally {
      if (mounted) {
        setState(() => _providerControlAction = null);
      }
    }
  }

  Future<void> _importRunLog(UtgRunLogSummary run) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('记忆到 OmniFlow'),
          content: const Text(
            '是否确定将这次执行记录记忆到 OmniFlow 临时区？\n\n记忆后可在下方 OmniFlow 资产列表继续沉淀为可 compile 资产。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    if (!mounted || confirmed != true) {
      return;
    }
    var loadingShown = false;
    try {
      setState(() => _importingRunId = run.runId);
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return const AlertDialog(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
                SizedBox(width: 12),
                Expanded(child: Text('正在整理执行记录并写入 OmniFlow 临时区...')),
              ],
            ),
          );
        },
      );
      loadingShown = true;
      final result = await AssistsMessageService.importUtgRunLog(
        runId: run.runId,
        baseUrl: _baseUrlController.text.trim(),
      );
      if (!mounted) return;
      if (loadingShown) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingShown = false;
      }
      await _loadFunctions(
        baseUrl: _baseUrlController.text.trim(),
        silent: true,
      );
      await _loadRunLogs(baseUrl: _baseUrlController.text.trim(), silent: true);
      if (!mounted) return;
      if (!result.success) {
        showToast(
          result.errorMessage ?? '该 run_log 不能记忆到 OmniFlow',
          type: ToastType.error,
        );
        return;
      }
      final targetFunctionId = result.createdFunctionId.trim();
      if (targetFunctionId.isNotEmpty) {
        setState(() {
          _highlightedFunctionId = targetFunctionId;
          _functionSearchController.text = targetFunctionId;
        });
        final matchedFunctions =
            _functionsSnapshot?.functions ?? const <UtgFunctionSummary>[];
        for (final function in matchedFunctions) {
          if (function.functionId == targetFunctionId) {
            await _viewFunctionBundle(function);
            break;
          }
        }
        if (!mounted) return;
      }
      final zoneLabel = result.assetState.trim().isEmpty
          ? '临时区'
          : result.assetState.trim();
      showToast(
        targetFunctionId.isEmpty
            ? '已记忆到 OmniFlow $zoneLabel'
            : '已记忆到 OmniFlow $zoneLabel：$targetFunctionId',
        type: ToastType.success,
      );
    } catch (e) {
      if (mounted && loadingShown) {
        Navigator.of(context, rootNavigator: true).pop();
        loadingShown = false;
      }
      if (!mounted) return;
      showToast('记忆到 OmniFlow 失败', type: ToastType.error);
      debugPrint('Convert run log to OmniFlow failed: $e');
    } finally {
      if (mounted) {
        setState(() => _importingRunId = null);
      }
    }
  }

  Future<Map<String, String>?> _confirmFunctionRun(
    UtgFunctionSummary function,
    UtgBridgeExecutionContext executionContext,
  ) async {
    final controllers = {
      for (final parameter in function.parameterNames)
        parameter: TextEditingController(
          text: function.parameterExamples[parameter] ?? '',
        ),
    };
    try {
      return await showDialog<Map<String, String>>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title: const Text('执行 OmniFlow 资产'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  SelectableText('function_id: ${function.functionId}'),
                  const SizedBox(height: 8),
                  Text(
                    function.description.trim().isEmpty
                        ? '无描述'
                        : function.description,
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
                    const Text('此资产无需填写参数。')
                  else
                    ...controllers.entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: TextField(
                          controller: entry.value,
                          decoration: InputDecoration(
                            labelText: entry.key,
                            hintText:
                                function.parameterExamples[entry.key] ?? '',
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

  Future<void> _uploadFunctionToCloud(UtgFunctionSummary function) async {
    final cloudBaseUrl = _cloudBaseUrlController.text.trim();
    if (cloudBaseUrl.isEmpty) {
      showToast('请先填写云端 Base URL', type: ToastType.error);
      return;
    }
    try {
      setState(() => _uploadingFunctionId = function.functionId);
      final result = await AssistsMessageService.uploadCloudUtgFunction(
        functionId: function.functionId,
        cloudBaseUrl: cloudBaseUrl,
        baseUrl: _baseUrlController.text.trim(),
      );
      if (!mounted) return;
      if (!result.success) {
        showToast(result.errorMessage ?? '上传云端资产失败', type: ToastType.error);
        return;
      }
      showToast('已上传到云端：${function.functionId}', type: ToastType.success);
    } catch (e) {
      if (!mounted) return;
      showToast('上传云端资产失败', type: ToastType.error);
      debugPrint('Upload cloud trajectory failed: $e');
    } finally {
      if (mounted) {
        setState(() => _uploadingFunctionId = null);
      }
    }
  }

  Future<void> _viewFunctionBundle(UtgFunctionSummary function) async {
    if (_expandedFunctionId == function.functionId) {
      setState(() {
        _expandedFunctionId = null;
        _functionBundleErrorById.remove(function.functionId);
      });
      return;
    }
    if (_functionBundleCache.containsKey(function.functionId)) {
      setState(() {
        _expandedFunctionId = function.functionId;
        _functionBundleErrorById.remove(function.functionId);
      });
      return;
    }
    try {
      setState(() => _viewingFunctionId = function.functionId);
      final payload = await AssistsMessageService.getUtgFunctionBundle(
        functionId: function.functionId,
        baseUrl: _baseUrlController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _functionBundleCache[function.functionId] = payload;
        _functionBundleErrorById.remove(function.functionId);
        _expandedFunctionId = function.functionId;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _functionBundleErrorById[function.functionId] = '加载资产详情失败：$e';
        _expandedFunctionId = function.functionId;
      });
      showToast('加载资产详情失败', type: ToastType.error);
      debugPrint('Load OmniFlow trajectory bundle failed: $e');
    } finally {
      if (mounted) {
        setState(() => _viewingFunctionId = null);
      }
    }
  }

  Future<void> _runFunctionFromDashboard(UtgFunctionSummary function) async {
    try {
      final executionContext =
          await AssistsMessageService.getUtgBridgeExecutionContext();
      if (!mounted) return;
      final arguments = await _confirmFunctionRun(function, executionContext);
      if (!mounted || arguments == null) {
        return;
      }
      setState(() => _runningFunctionId = function.functionId);
      final result = await AssistsMessageService.runUtgFunction(
        functionId: function.functionId,
        arguments: arguments,
        baseUrl: _baseUrlController.text.trim(),
      );
      if (!mounted) return;
      await _loadFunctions(
        baseUrl: _baseUrlController.text.trim(),
        silent: true,
      );
      await _loadRunLogs(baseUrl: _baseUrlController.text.trim(), silent: true);
      if (!mounted) return;
      showToast(
        result.success
            ? '已通过 OmniFlow 执行 ${function.functionId}'
            : (result.errorMessage?.trim().isNotEmpty == true
                  ? 'OmniFlow 执行失败：${result.errorMessage}'
                  : 'OmniFlow 执行失败：${function.functionId}'),
        type: result.success ? ToastType.success : ToastType.error,
      );
      await AppStateService.navigateBackToChat();
    } on PlatformException catch (e) {
      if (!mounted) return;
      showToast(e.message ?? '获取 OmniFlow bridge 失败', type: ToastType.error);
    } catch (e) {
      if (!mounted) return;
      showToast('执行 OmniFlow 资产失败', type: ToastType.error);
      debugPrint('Run OmniFlow trajectory failed: $e');
    } finally {
      if (mounted) {
        setState(() => _runningFunctionId = null);
      }
    }
  }

  Future<void> _distillFunctionFromDashboard(
    UtgFunctionSummary function,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('沉淀为资产'),
          content: Text(
            '确认将 ${function.functionId} 从 OmniFlow 临时区沉淀到资产区？\n\n沉淀后会生成一个新的 ready function，原 raw replay function 会继续保留。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('确定'),
            ),
          ],
        );
      },
    );
    if (!mounted || confirmed != true) {
      return;
    }
    try {
      setState(() => _distillingFunctionId = function.functionId);
      final result = await AssistsMessageService.distillUtgFunction(
        functionId: function.functionId,
        baseUrl: _baseUrlController.text.trim(),
      );
      if (!mounted) return;
      await _loadFunctions(
        baseUrl: _baseUrlController.text.trim(),
        silent: true,
      );
      await _loadRunLogs(baseUrl: _baseUrlController.text.trim(), silent: true);
      if (!mounted) return;
      if (!result.success) {
        showToast(result.errorMessage ?? '沉淀资产失败', type: ToastType.error);
        return;
      }
      final createdFunctionId = result.createdFunctionId.trim();
      setState(() {
        _highlightedFunctionId = createdFunctionId.isEmpty
            ? function.functionId
            : createdFunctionId;
        if (createdFunctionId.isNotEmpty) {
          _functionSearchController.text = createdFunctionId;
        }
      });
      showToast(
        createdFunctionId.isEmpty ? '已完成沉淀' : '已沉淀到资产区：$createdFunctionId',
        type: ToastType.success,
      );
    } catch (e) {
      if (!mounted) return;
      showToast('沉淀资产失败', type: ToastType.error);
      debugPrint('Distill OmniFlow trajectory failed: $e');
    } finally {
      if (mounted) {
        setState(() => _distillingFunctionId = null);
      }
    }
  }

  Future<void> _deleteFunctionFromDashboard(UtgFunctionSummary function) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('删除 OmniFlow 资产'),
          content: SelectableText(
            '确认删除 function_id=${function.functionId}？\n\n删除后会直接从当前本地 provider 的 OmniFlow store 移除。',
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
      setState(() => _deletingFunctionId = function.functionId);
      final result = await AssistsMessageService.deleteUtgFunction(
        functionId: function.functionId,
        baseUrl: _baseUrlController.text.trim(),
      );
      if (!mounted) return;
      if (!result.success) {
        showToast(
          result.errorMessage ?? '删除失败：${function.functionId}',
          type: ToastType.error,
        );
        return;
      }
      await _loadFunctions(
        baseUrl: _baseUrlController.text.trim(),
        silent: true,
      );
      if (!mounted) return;
      setState(() {
        if (_highlightedFunctionId == function.functionId) {
          _highlightedFunctionId = null;
        }
        if (_expandedFunctionId == function.functionId) {
          _expandedFunctionId = null;
        }
        _functionBundleCache.remove(function.functionId);
        _functionBundleErrorById.remove(function.functionId);
      });
      showToast('已删除 ${function.functionId}', type: ToastType.success);
    } catch (e) {
      if (!mounted) return;
      showToast('删除 OmniFlow 资产失败', type: ToastType.error);
      debugPrint('Delete OmniFlow trajectory failed: $e');
    } finally {
      if (mounted) {
        setState(() => _deletingFunctionId = null);
      }
    }
  }

  Future<void> _downloadCloudFunction() async {
    final cloudBaseUrl = _cloudBaseUrlController.text.trim();
    final functionId = _cloudFunctionIdController.text.trim();
    if (cloudBaseUrl.isEmpty) {
      showToast('请填写云端 Base URL', type: ToastType.error);
      return;
    }
    try {
      setState(() => _downloadingCloudFunction = true);
      final result = await AssistsMessageService.downloadCloudUtgFunction(
        functionId: functionId,
        cloudBaseUrl: cloudBaseUrl,
        baseUrl: _baseUrlController.text.trim(),
      );
      if (!mounted) return;
      if (!result.success) {
        showToast(result.errorMessage ?? '下载云端资产失败', type: ToastType.error);
        return;
      }
      await _loadFunctions(
        baseUrl: _baseUrlController.text.trim(),
        silent: true,
      );
      if (!mounted) return;
      final importedCount = result.count;
      if (functionId.isEmpty) {
        showToast(
          importedCount > 0 ? '已下载全部云端资产：$importedCount 条' : '云端资产已同步，无新增条目',
          type: ToastType.success,
        );
      } else {
        showToast('已下载云端资产：$functionId', type: ToastType.success);
      }
    } catch (e) {
      if (!mounted) return;
      showToast('下载云端资产失败', type: ToastType.error);
      debugPrint('Download cloud trajectory failed: $e');
    } finally {
      if (mounted) {
        setState(() => _downloadingCloudFunction = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _config;
    final allFunctions =
        _functionsSnapshot?.functions ?? const <UtgFunctionSummary>[];
    final allRuns = _runLogsSnapshot?.runs ?? const <UtgRunLogSummary>[];
    final filteredRuns = _filteredRunLogs();
    final searchQuery = _functionSearchController.text.trim().toLowerCase();
    final filteredFunctions = searchQuery.isEmpty
        ? allFunctions
        : allFunctions.where((function) {
            final haystack = <String>[
              function.functionId,
              function.description,
              function.assetKind,
              function.assetState,
              function.derivedFromRawFunctionId,
              function.startNodeId,
              function.endNodeId,
              function.startNodeDescription,
              function.endNodeDescription,
              ...function.parameterNames,
            ].join(' ').toLowerCase();
            return haystack.contains(searchQuery);
          }).toList();
    final temporaryFunctions = filteredFunctions
        .where(_isTemporaryFunction)
        .toList();
    final readyFunctions = filteredFunctions.where(_isReadyFunction).toList();
    final unknownFunctions = filteredFunctions
        .where(
          (function) =>
              !_isTemporaryFunction(function) && !_isReadyFunction(function),
        )
        .toList();

    Map<String, List<UtgFunctionSummary>> groupByApp(
      List<UtgFunctionSummary> functions,
    ) {
      final grouped = <String, List<UtgFunctionSummary>>{};
      for (final function in functions) {
        final groupName = function.groupName.trim().isEmpty
            ? 'unknown_app'
            : function.groupName.trim();
        grouped
            .putIfAbsent(groupName, () => <UtgFunctionSummary>[])
            .add(function);
      }
      return grouped;
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: CommonAppBar(
        title: context.l10n.omniflowSkillPanelTitle,
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
                    child: Text(
                      context.l10n.omniflowSkillPanelDesc,
                      style: const TextStyle(
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
                          'OmniFlow 设置',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          value: _utgEnabled,
                          title: const Text(
                            '启用 `vlm_task` 前置 OmniFlow pre-hook',
                          ),
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
                        const SizedBox(height: 8),
                        _buildInputField(
                          controller: _baseUrlController,
                          label: 'OmniFlow Base URL',
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
                          hint: '/data/local/tmp/omnibot/omniflow',
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
                          'provider run_log',
                          config?.providerRunLogPath ?? '',
                        ),
                        _buildInfoRow(
                          'canonical run_log',
                          config?.canonicalRunLogPath ?? '',
                        ),
                        _buildInfoRow(
                          'auto-start command',
                          config == null
                              ? ''
                              : (config.providerStartCommandConfigured
                                    ? 'configured'
                                    : 'not configured'),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFFF7E8),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: const Color(0xFFFFD89B)),
                          ),
                          child: const Text(
                            '当前页的启动/重启/停止按钮只控制手机内 provider。若你现在使用的是 Mac + adb reverse 调试模式，请在开发机运行 bash scripts/start_oob_utg_host_bridge.sh <serial>，然后这里再点刷新资产。',
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.5,
                              color: Color(0xFF8A5A00),
                            ),
                          ),
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
                                  : () => _loadFunctions(
                                      baseUrl: _baseUrlController.text.trim(),
                                    ),
                              icon: const Icon(Icons.sync_outlined),
                              label: const Text('刷新资产'),
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
                          '下载云端资产',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          '本地 provider 会从另一台 OmniFlow provider 拉取单条 `/functions/{id}/bundle`，或在 id 留空时先拉 `/functions` 再全量同步。',
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
                          controller: _cloudFunctionIdController,
                          label: '云端 function_id（可留空）',
                          hint: '例如 global-open-settings；留空表示下载全部',
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerRight,
                          child: FilledButton.icon(
                            onPressed: _downloadingCloudFunction || _saving
                                ? null
                                : _downloadCloudFunction,
                            icon: _downloadingCloudFunction
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.cloud_download_outlined),
                            label: Text(
                              _downloadingCloudFunction ? '下载中...' : '下载云端资产',
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // RunLog 部分已移至轨迹页面
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        context.l10n.omniflowSkillList,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_loadingFunctions)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        _buildPill('${allFunctions.length}'),
                      if (searchQuery.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        _buildPill('筛选 ${filteredFunctions.length}'),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildCard(
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _functionSearchController,
                            onChanged: (_) => setState(() {}),
                            decoration: InputDecoration(
                              labelText: context.l10n.omniflowSkillSearch,
                              hintText: context.l10n.omniflowSkillSearchHint,
                              prefixIcon: const Icon(Icons.search_outlined),
                              suffixIcon: searchQuery.isEmpty
                                  ? null
                                  : IconButton(
                                      onPressed: () {
                                        setState(() {
                                          _functionSearchController.clear();
                                          _highlightedFunctionId = null;
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
                  if (_functionsError != null)
                    _buildCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'OmniFlow 资产列表加载失败',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _functionsError!,
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.text70,
                              height: 1.6,
                            ),
                          ),
                        ],
                      ),
                    )
                  else if (allFunctions.isEmpty)
                    _buildCard(
                      child: const Text(
                        '当前 provider 没有返回可展示的 OmniFlow 资产。确认 OmniFlow provider 已启动、Base URL 正确，并且 provider 能访问到临时区或资产区数据。',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.text70,
                          height: 1.7,
                        ),
                      ),
                    )
                  else if (filteredFunctions.isEmpty)
                    _buildCard(
                      child: Text(
                        '没有匹配到资产：${_functionSearchController.text.trim()}',
                        style: const TextStyle(
                          fontSize: 13,
                          color: AppColors.text70,
                          height: 1.7,
                        ),
                      ),
                    )
                  else ...[
                    if (temporaryFunctions.isNotEmpty) ...[
                      _buildCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    '临时区 Raw Replay',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                _buildPill(
                                  '${temporaryFunctions.length}',
                                  backgroundColor: const Color(0xFFFFF4E5),
                                  textColor: const Color(0xFFB54708),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '这里保存原始回放记忆，可直接回放，但默认不参与 compile；需要手动“沉淀资产”后才会进入资产区。',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.text70,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...(() {
                        final groupedFunctions = groupByApp(temporaryFunctions);
                        final groupKeys = groupedFunctions.keys.toList()
                          ..sort();
                        return groupKeys.expand((groupName) {
                          final functionsInGroup =
                              groupedFunctions[groupName] ??
                              const <UtgFunctionSummary>[];
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
                                  _buildPill('${functionsInGroup.length}'),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...functionsInGroup.map(
                              (function) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildFunctionCard(function),
                              ),
                            ),
                          ];
                        });
                      })(),
                    ],
                    if (readyFunctions.isNotEmpty) ...[
                      _buildCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Expanded(
                                  child: Text(
                                    '资产区 Ready 资产',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                _buildPill(
                                  '${readyFunctions.length}',
                                  backgroundColor: const Color(0xFFE8F7EE),
                                  textColor: const Color(0xFF117A37),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              '这里的 function 资产已经完成沉淀，可复用、可 compile，也可以继续上传或同步。',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.text70,
                                height: 1.6,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      ...(() {
                        final groupedFunctions = groupByApp(readyFunctions);
                        final groupKeys = groupedFunctions.keys.toList()
                          ..sort();
                        return groupKeys.expand((groupName) {
                          final functionsInGroup =
                              groupedFunctions[groupName] ??
                              const <UtgFunctionSummary>[];
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
                                  _buildPill('${functionsInGroup.length}'),
                                ],
                              ),
                            ),
                            const SizedBox(height: 8),
                            ...functionsInGroup.map(
                              (function) => Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: _buildFunctionCard(function),
                              ),
                            ),
                          ];
                        });
                      })(),
                    ],
                    // 未分区资产已隐藏
                  ],
                ],
              ),
            ),
    );
  }
}
