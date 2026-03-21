import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui/models/remote_mcp_server.dart';
import 'package:ui/services/remote_mcp_config_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';

class RemoteMcpServersPage extends StatefulWidget {
  const RemoteMcpServersPage({super.key});

  @override
  State<RemoteMcpServersPage> createState() => _RemoteMcpServersPageState();
}

class _RemoteMcpServersPageState extends State<RemoteMcpServersPage> {
  bool _loading = true;
  final Set<String> _busyIds = {};
  List<RemoteMcpServer> _servers = [];

  @override
  void initState() {
    super.initState();
    _loadServers();
  }

  Future<void> _loadServers() async {
    setState(() => _loading = true);
    try {
      final servers = await RemoteMcpConfigService.listServers();
      if (!mounted) return;
      setState(() {
        _servers = servers;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast('加载 MCP 工具失败', type: ToastType.error);
    }
  }

  Future<void> _toggleServer(RemoteMcpServer server, bool enabled) async {
    _setBusy(server.id, true);
    try {
      final updated = await RemoteMcpConfigService.setServerEnabled(
        server.id,
        enabled,
      );
      if (!mounted) return;
      setState(() {
        _servers = _servers.map((item) {
          if (item.id != server.id) return item;
          return updated ?? item.copyWith(enabled: enabled);
        }).toList();
      });
    } catch (e) {
      showToast('切换失败', type: ToastType.error);
    } finally {
      _setBusy(server.id, false);
    }
  }

  Future<void> _refreshTools(RemoteMcpServer server) async {
    _setBusy(server.id, true);
    try {
      final updated = await RemoteMcpConfigService.refreshServerTools(
        server.id,
      );
      if (!mounted) return;
      setState(() {
        _servers = _servers.map((item) {
          if (item.id != server.id) return item;
          return updated ?? item;
        }).toList();
      });
      showToast('工具列表已刷新');
    } on PlatformException catch (e) {
      showToast(e.message ?? '刷新失败', type: ToastType.error);
    } catch (_) {
      showToast('刷新失败', type: ToastType.error);
    } finally {
      _setBusy(server.id, false);
    }
  }

  Future<void> _deleteServer(RemoteMcpServer server) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除 MCP 服务'),
        content: Text('确认删除“${server.name}”？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    _setBusy(server.id, true);
    try {
      await RemoteMcpConfigService.deleteServer(server.id);
      if (!mounted) return;
      setState(() {
        _servers.removeWhere((item) => item.id == server.id);
      });
      showToast('已删除');
    } catch (e) {
      showToast('删除失败', type: ToastType.error);
    } finally {
      _setBusy(server.id, false);
    }
  }

  Future<void> _showServerEditor({RemoteMcpServer? server}) async {
    final nameController = TextEditingController(text: server?.name ?? '');
    final endpointController = TextEditingController(
      text: server?.endpointUrl ?? '',
    );
    final tokenController = TextEditingController(
      text: server?.bearerToken ?? '',
    );
    bool enabled = server?.enabled ?? true;

    final saved = await showModalBottomSheet<RemoteMcpServer>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    server == null ? '添加 MCP 服务' : '编辑 MCP 服务',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _InputField(controller: nameController, label: '名称'),
                  const SizedBox(height: 12),
                  _InputField(
                    controller: endpointController,
                    label: 'Endpoint URL',
                    hint: 'https://example.com/mcp',
                  ),
                  const SizedBox(height: 12),
                  _InputField(
                    controller: tokenController,
                    label: 'Bearer Token（可选）',
                  ),
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: enabled,
                    onChanged: (value) => setModalState(() => enabled = value),
                    title: const Text('启用'),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        final name = nameController.text.trim();
                        final endpoint = endpointController.text.trim();
                        if (name.isEmpty || endpoint.isEmpty) {
                          showToast('请填写名称和地址', type: ToastType.error);
                          return;
                        }
                        Navigator.of(context).pop(
                          (server ??
                                  const RemoteMcpServer(
                                    id: '',
                                    name: '',
                                    endpointUrl: '',
                                    bearerToken: '',
                                    enabled: true,
                                    lastHealth: 'unknown',
                                    toolCount: 0,
                                  ))
                              .copyWith(
                                name: name,
                                endpointUrl: endpoint,
                                bearerToken: tokenController.text.trim(),
                                enabled: enabled,
                              ),
                        );
                      },
                      child: const Text('保存'),
                    ),
                  ),
                ],
              );
            },
          ),
        );
      },
    );

    if (saved == null) return;
    try {
      final result = await RemoteMcpConfigService.upsertServer(saved);
      if (result == null || !mounted) return;
      setState(() {
        final index = _servers.indexWhere((item) => item.id == result.id);
        if (index == -1) {
          _servers = [result, ..._servers];
        } else {
          _servers[index] = result;
        }
      });
      showToast('已保存');
    } catch (e) {
      showToast('保存失败', type: ToastType.error);
    }
  }

  void _setBusy(String id, bool busy) {
    if (!mounted) return;
    setState(() {
      if (busy) {
        _busyIds.add(id);
      } else {
        _busyIds.remove(id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CommonAppBar(title: 'MCP 工具', primary: true),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _showServerEditor(),
        child: const Icon(Icons.add),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _servers.isEmpty
          ? _buildEmpty()
          : RefreshIndicator(
              onRefresh: _loadServers,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemBuilder: (context, index) =>
                    _buildServerCard(_servers[index]),
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemCount: _servers.length,
              ),
            ),
    );
  }

  Widget _buildEmpty() {
    return ListView(
      padding: const EdgeInsets.all(24),
      children: const [
        SizedBox(height: 120),
        Icon(Icons.extension, size: 48, color: AppColors.text50),
        SizedBox(height: 12),
        Center(
          child: Text(
            '暂无远端 MCP 服务',
            style: TextStyle(fontSize: 16, color: AppColors.text70),
          ),
        ),
      ],
    );
  }

  Widget _buildServerCard(RemoteMcpServer server) {
    final busy = _busyIds.contains(server.id);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [AppColors.boxShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      server.name,
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      server.endpointUrl,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.text50,
                      ),
                    ),
                  ],
                ),
              ),
              Switch(
                value: server.enabled,
                onChanged: busy
                    ? null
                    : (value) => _toggleServer(server, value),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(label: _healthLabel(server.lastHealth)),
              _MetaChip(label: '工具 ${server.toolCount}'),
              if ((server.lastError ?? '').isNotEmpty)
                _MetaChip(
                  label: server.lastError!,
                  color: AppColors.alertRed.withValues(alpha: 0.08),
                  textColor: AppColors.alertRed,
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              TextButton(
                onPressed: busy ? null : () => _refreshTools(server),
                child: const Text('刷新工具'),
              ),
              TextButton(
                onPressed: busy
                    ? null
                    : () => _showServerEditor(server: server),
                child: const Text('编辑'),
              ),
              const Spacer(),
              TextButton(
                onPressed: busy ? null : () => _deleteServer(server),
                child: const Text('删除'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _healthLabel(String health) {
    switch (health) {
      case 'healthy':
        return '连接正常';
      case 'error':
        return '连接异常';
      default:
        return '状态未知';
    }
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String? hint;

  const _InputField({required this.controller, required this.label, this.hint});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final Color? color;
  final Color? textColor;

  const _MetaChip({required this.label, this.color, this.textColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color ?? AppColors.background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 12, color: textColor ?? AppColors.text70),
      ),
    );
  }
}
