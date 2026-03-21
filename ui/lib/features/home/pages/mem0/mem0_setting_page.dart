import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/svg.dart';
import 'package:ui/core/router/go_router_manager.dart';
import 'package:ui/models/mem0_config.dart';
import 'package:ui/services/mem0_config_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';

class Mem0SettingPage extends StatefulWidget {
  const Mem0SettingPage({super.key});

  @override
  State<Mem0SettingPage> createState() => _Mem0SettingPageState();
}

class _Mem0SettingPageState extends State<Mem0SettingPage> {
  static const String _defaultAgentId = 'omnibot-unified-agent';

  final TextEditingController _baseUrlController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _agentIdController = TextEditingController(
    text: _defaultAgentId,
  );

  bool _loading = true;
  bool _saving = false;
  bool _obscureApiKey = true;
  String? _source;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _agentIdController.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    setState(() => _loading = true);
    try {
      final config = await Mem0ConfigService.getConfig();
      if (!mounted) return;
      _applyConfig(config);
    } on PlatformException catch (e) {
      showToast(e.message ?? '加载 Mem0 配置失败', type: ToastType.error);
    } catch (_) {
      showToast('加载 Mem0 配置失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _applyConfig(Mem0Config config) {
    setState(() {
      _baseUrlController.text = config.baseUrl;
      _apiKeyController.text = config.apiKey;
      _agentIdController.text = config.agentId.isNotEmpty
          ? config.agentId
          : _defaultAgentId;
      _source = config.source;
    });
  }

  Future<void> _saveConfig() async {
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    final agentId = _agentIdController.text.trim().isEmpty
        ? _defaultAgentId
        : _agentIdController.text.trim();

    if (baseUrl.isEmpty) {
      showToast('请填写 Base URL', type: ToastType.error);
      return;
    }

    setState(() => _saving = true);
    try {
      final saved = await Mem0ConfigService.saveConfig(
        Mem0Config(
          baseUrl: baseUrl,
          apiKey: apiKey,
          agentId: agentId,
          configured: apiKey.isNotEmpty,
        ),
      );
      if (!mounted) return;
      _applyConfig(saved);
      showToast(
        apiKey.isEmpty ? '已保存，当前会按无记忆模式运行' : 'Mem0 配置已保存',
        type: ToastType.success,
      );
    } on PlatformException catch (e) {
      showToast(e.message ?? '保存失败', type: ToastType.error);
    } catch (_) {
      showToast('保存失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _clearConfig() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清空 Mem0 配置'),
        content: const Text('确认清空当前可见的 Mem0 配置吗？清空后统一 Agent 会自动降级为无记忆模式。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('清空'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _saving = true);
    try {
      await Mem0ConfigService.clearConfig();
      if (!mounted) return;
      _applyConfig(
        const Mem0Config(
          baseUrl: '',
          apiKey: '',
          agentId: _defaultAgentId,
          configured: false,
        ),
      );
      showToast('已清空 Mem0 配置');
    } on PlatformException catch (e) {
      showToast(e.message ?? '清空失败', type: ToastType.error);
    } catch (_) {
      showToast('清空失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CommonAppBar(title: 'Mem0 云记忆', primary: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '统一 Agent 开启且 API Key 非空时，当前记忆空间会先自动检索 Mem0，再进入 Agent 推理。未配置时会自动降级为无记忆模式。',
                        style: TextStyle(
                          fontSize: 13,
                          color: AppColors.text70,
                          height: 1.6,
                        ),
                      ),
                      if ((_source ?? '').isNotEmpty) ...[
                        const SizedBox(height: 10),
                        _buildTag(
                          _source == 'global' ? '当前使用全局配置' : '当前使用当前空间配置',
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                _buildCard(
                  child: Column(
                    children: [
                      _InputField(
                        controller: _baseUrlController,
                        label: 'Base URL',
                        hint: 'https://api.mem0.ai/v1',
                      ),
                      const SizedBox(height: 12),
                      _InputField(
                        controller: _apiKeyController,
                        label: 'API Key',
                        hint: 'Bearer Token',
                        obscureText: _obscureApiKey,
                        suffixIcon: IconButton(
                          onPressed: () {
                            setState(() {
                              _obscureApiKey = !_obscureApiKey;
                            });
                          },
                          icon: Icon(
                            _obscureApiKey
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      _InputField(
                        controller: _agentIdController,
                        label: 'Agent ID',
                        hint: _defaultAgentId,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _saveConfig,
                    child: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('保存配置'),
                  ),
                ),
                const SizedBox(height: 12),
                TextButton(
                  onPressed: _saving ? null : _clearConfig,
                  child: const Text('清空当前配置'),
                ),
              ],
            ),
    );
  }

  Widget _buildCard({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [AppColors.boxShadow],
      ),
      child: child,
    );
  }

  Widget _buildTag(String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.primaryBlue.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, color: AppColors.primaryBlue),
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;
  final bool obscureText;
  final Widget? suffixIcon;

  const _InputField({
    required this.controller,
    required this.label,
    this.hint,
    this.obscureText = false,
    this.suffixIcon,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscureText,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        suffixIcon: suffixIcon,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
