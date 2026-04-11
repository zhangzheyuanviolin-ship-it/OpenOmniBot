import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui/core/router/go_router_manager.dart';
import 'package:ui/services/assists_core_service.dart';
import 'package:ui/services/workspace_memory_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';
import 'package:ui/widgets/settings_section_title.dart';

class WorkspaceMemorySettingPage extends StatefulWidget {
  const WorkspaceMemorySettingPage({super.key});

  @override
  State<WorkspaceMemorySettingPage> createState() =>
      _WorkspaceMemorySettingPageState();
}

class _WorkspaceMemorySettingPageState
    extends State<WorkspaceMemorySettingPage> {
  final TextEditingController _soulController = TextEditingController();
  final TextEditingController _chatController = TextEditingController();
  final TextEditingController _memoryController = TextEditingController();

  bool _loading = true;
  bool _savingSoul = false;
  bool _savingChat = false;
  bool _savingMemory = false;
  bool _embeddingEnabled = true;
  bool _rollupEnabled = true;
  WorkspaceMemoryEmbeddingConfig? _embeddingConfig;
  WorkspaceMemoryRollupStatus? _rollupStatus;
  StreamSubscription<AgentAiConfigChangedEvent>? _configChangedSubscription;

  @override
  void initState() {
    super.initState();
    _loadAll();
    _configChangedSubscription = AssistsMessageService
        .agentAiConfigChangedStream
        .listen((event) {
          if (event.source != 'file' || !mounted) {
            return;
          }
          if (event.path.endsWith('/SOUL.md')) {
            unawaited(_refreshSoulDocument());
            return;
          }
          if (event.path.endsWith('/CHAT.md')) {
            unawaited(_refreshChatDocument());
            return;
          }
          unawaited(_refreshCapabilityState());
        });
  }

  @override
  void dispose() {
    _configChangedSubscription?.cancel();
    _soulController.dispose();
    _chatController.dispose();
    _memoryController.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        WorkspaceMemoryService.getSoul(),
        WorkspaceMemoryService.getChatPrompt(),
        WorkspaceMemoryService.getLongMemory(),
        WorkspaceMemoryService.getEmbeddingConfig(),
        WorkspaceMemoryService.getRollupStatus(),
      ]);
      if (!mounted) return;
      final soul = results[0] as String;
      final chatPrompt = results[1] as String;
      final memory = results[2] as String;
      final embedding = results[3] as WorkspaceMemoryEmbeddingConfig;
      final rollup = results[4] as WorkspaceMemoryRollupStatus;
      setState(() {
        _soulController.text = soul;
        _chatController.text = chatPrompt;
        _memoryController.text = memory;
        _embeddingConfig = embedding;
        _rollupStatus = rollup;
        _embeddingEnabled = embedding.enabled;
        _rollupEnabled = rollup.enabled;
      });
    } catch (e) {
      showToast('加载 workspace 记忆配置失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _refreshCapabilityState() async {
    try {
      final results = await Future.wait([
        WorkspaceMemoryService.getEmbeddingConfig(),
        WorkspaceMemoryService.getRollupStatus(),
      ]);
      if (!mounted) return;
      final embedding = results[0] as WorkspaceMemoryEmbeddingConfig;
      final rollup = results[1] as WorkspaceMemoryRollupStatus;
      setState(() {
        _embeddingConfig = embedding;
        _rollupStatus = rollup;
        _embeddingEnabled = embedding.enabled;
        _rollupEnabled = rollup.enabled;
      });
    } catch (_) {
      // Keep current UI state when passive refresh fails.
    }
  }

  Future<void> _refreshSoulDocument() async {
    try {
      final soul = await WorkspaceMemoryService.getSoul();
      if (!mounted) return;
      _soulController.text = soul;
    } catch (_) {
      // Keep current UI state when passive refresh fails.
    }
  }

  Future<void> _refreshChatDocument() async {
    try {
      final chatPrompt = await WorkspaceMemoryService.getChatPrompt();
      if (!mounted) return;
      _chatController.text = chatPrompt;
    } catch (_) {
      // Keep current UI state when passive refresh fails.
    }
  }

  Future<void> _saveSoul() async {
    setState(() => _savingSoul = true);
    try {
      final saved = await WorkspaceMemoryService.saveSoul(_soulController.text);
      if (!mounted) return;
      _soulController.text = saved;
      showToast('SOUL.md 已保存', type: ToastType.success);
    } catch (e) {
      showToast('SOUL.md 保存失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _savingSoul = false);
      }
    }
  }

  Future<void> _saveChatPrompt() async {
    setState(() => _savingChat = true);
    try {
      final saved = await WorkspaceMemoryService.saveChatPrompt(
        _chatController.text,
      );
      if (!mounted) return;
      _chatController.text = saved;
      showToast('CHAT.md 已保存', type: ToastType.success);
    } catch (e) {
      showToast('CHAT.md 保存失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _savingChat = false);
      }
    }
  }

  Future<void> _saveMemory() async {
    setState(() => _savingMemory = true);
    try {
      final saved = await WorkspaceMemoryService.saveLongMemory(
        _memoryController.text,
      );
      if (!mounted) return;
      _memoryController.text = saved;
      showToast('MEMORY.md 已保存', type: ToastType.success);
    } catch (e) {
      showToast('MEMORY.md 保存失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _savingMemory = false);
      }
    }
  }

  Future<void> _toggleEmbedding(bool enabled) async {
    setState(() => _embeddingEnabled = enabled);
    try {
      final config = await WorkspaceMemoryService.saveEmbeddingConfig(
        enabled: enabled,
      );
      if (!mounted) return;
      setState(() => _embeddingConfig = config);
    } catch (e) {
      if (!mounted) return;
      setState(() => _embeddingEnabled = !enabled);
      showToast('记忆嵌入开关更新失败', type: ToastType.error);
    }
  }

  Future<void> _toggleRollup(bool enabled) async {
    setState(() => _rollupEnabled = enabled);
    try {
      final status = await WorkspaceMemoryService.saveRollupEnabled(enabled);
      if (!mounted) return;
      setState(() => _rollupStatus = status);
    } catch (e) {
      if (!mounted) return;
      setState(() => _rollupEnabled = !enabled);
      showToast('夜间整理开关更新失败', type: ToastType.error);
    }
  }

  Future<void> _runRollupNow() async {
    try {
      final result = await WorkspaceMemoryService.runRollupNow();
      if (!mounted) return;
      showToast((result?['summary'] ?? '整理完成').toString());
      await _loadAll();
    } on PlatformException catch (e) {
      final message = e.message?.trim();
      final errorText = (message == null || message.isEmpty)
          ? '立即整理失败'
          : '立即整理失败：$message';
      showToast(errorText, type: ToastType.error);
    } catch (e) {
      showToast('立即整理失败：$e', type: ToastType.error);
    }
  }

  String _formatTime(int? millis) {
    if (millis == null || millis <= 0) return '暂无';
    final date = DateTime.fromMillisecondsSinceEpoch(millis);
    return '${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    return Scaffold(
      backgroundColor: context.isDarkTheme
          ? palette.pageBackground
          : AppColors.background,
      appBar: const CommonAppBar(title: 'Workspace 记忆', primary: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 28),
              children: [
                const SettingsSectionTitle(label: '记忆能力'),
                _buildSwitchCard(
                  title: '记忆嵌入检索',
                  subtitle: _embeddingConfig?.configured == true
                      ? '已配置，可使用向量检索'
                      : '未配置，将自动降级为词法检索',
                  value: _embeddingEnabled,
                  onChanged: _toggleEmbedding,
                  footer: TextButton(
                    onPressed: () {
                      GoRouterManager.push('/home/scene_model_setting');
                    },
                    child: const Text('去场景模型配置记忆嵌入模型'),
                  ),
                ),
                const Divider(height: 24),
                _buildSwitchCard(
                  title: '夜间记忆整理（22:00）',
                  subtitle:
                      '最近运行：${_formatTime(_rollupStatus?.lastRunAtMillis)}\n下次运行：${_formatTime(_rollupStatus?.nextRunAtMillis)}',
                  value: _rollupEnabled,
                  onChanged: _toggleRollup,
                  footer: Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton(
                      onPressed: _runRollupNow,
                      child: const Text('立即整理一次'),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const SettingsSectionTitle(label: '文档内容'),
                _buildEditorCard(
                  title: 'SOUL.md（Agent 灵魂）',
                  controller: _soulController,
                  saving: _savingSoul,
                  onSave: _saveSoul,
                ),
                const Divider(height: 24),
                _buildEditorCard(
                  title: 'CHAT.md（纯聊天系统提示词）',
                  controller: _chatController,
                  saving: _savingChat,
                  onSave: _saveChatPrompt,
                ),
                const Divider(height: 24),
                _buildEditorCard(
                  title: 'MEMORY.md（长期记忆）',
                  controller: _memoryController,
                  saving: _savingMemory,
                  onSave: _saveMemory,
                ),
              ],
            ),
    );
  }

  Widget _buildSwitchCard({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Widget? footer,
  }) {
    final palette = context.omniPalette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: context.isDarkTheme
                        ? palette.textPrimary
                        : AppColors.text,
                  ),
                ),
              ),
              Switch(value: value, onChanged: onChanged),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: context.isDarkTheme
                  ? palette.textSecondary
                  : AppColors.text70,
            ),
          ),
          if (footer != null) ...[const SizedBox(height: 8), footer],
        ],
      ),
    );
  }

  Widget _buildEditorCard({
    required String title,
    required TextEditingController controller,
    required bool saving,
    required Future<void> Function() onSave,
  }) {
    final palette = context.omniPalette;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: context.isDarkTheme ? palette.textPrimary : AppColors.text,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            maxLines: 12,
            minLines: 8,
            decoration: InputDecoration(
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton(
              onPressed: saving ? null : onSave,
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ),
        ],
      ),
    );
  }
}
