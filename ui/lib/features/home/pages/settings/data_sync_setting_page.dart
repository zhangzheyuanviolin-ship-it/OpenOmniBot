import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:ui/services/data_sync_service.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';

class DataSyncSettingPage extends StatefulWidget {
  const DataSyncSettingPage({super.key});

  @override
  State<DataSyncSettingPage> createState() => _DataSyncSettingPageState();
}

class _DataSyncSettingPageState extends State<DataSyncSettingPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _supabaseUrlController;
  late final TextEditingController _anonKeyController;
  late final TextEditingController _namespaceController;
  late final TextEditingController _syncSecretController;
  late final TextEditingController _s3EndpointController;
  late final TextEditingController _regionController;
  late final TextEditingController _bucketController;
  late final TextEditingController _accessKeyController;
  late final TextEditingController _secretKeyController;
  late final TextEditingController _sessionTokenController;

  bool _enabled = false;
  bool _forcePathStyle = true;
  bool _loading = true;
  bool _busy = false;
  DataSyncStatus _status = const DataSyncStatus();
  Timer? _pollTimer;

  bool get _isEnglish => Localizations.localeOf(context).languageCode == 'en';

  @override
  void initState() {
    super.initState();
    _supabaseUrlController = TextEditingController();
    _anonKeyController = TextEditingController();
    _namespaceController = TextEditingController();
    _syncSecretController = TextEditingController();
    _s3EndpointController = TextEditingController();
    _regionController = TextEditingController();
    _bucketController = TextEditingController();
    _accessKeyController = TextEditingController();
    _secretKeyController = TextEditingController();
    _sessionTokenController = TextEditingController();
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _supabaseUrlController.dispose();
    _anonKeyController.dispose();
    _namespaceController.dispose();
    _syncSecretController.dispose();
    _s3EndpointController.dispose();
    _regionController.dispose();
    _bucketController.dispose();
    _accessKeyController.dispose();
    _secretKeyController.dispose();
    _sessionTokenController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
    });
    try {
      final results = await Future.wait([
        DataSyncService.getConfig(),
        DataSyncService.getStatus(),
      ]);
      final config = results[0] as DataSyncConfig;
      final status = results[1] as DataSyncStatus;
      _applyConfig(config);
      if (!mounted) return;
      setState(() {
        _status = status;
        _loading = false;
      });
      _ensurePolling(status);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
      });
      showToast(error.toString(), type: ToastType.error);
    }
  }

  void _applyConfig(DataSyncConfig config) {
    _enabled = config.enabled;
    _forcePathStyle = config.forcePathStyle;
    _supabaseUrlController.text = config.supabaseUrl;
    _anonKeyController.text = config.anonKey;
    _namespaceController.text = config.namespace;
    _syncSecretController.text = config.syncSecret;
    _s3EndpointController.text = config.s3Endpoint;
    _regionController.text = config.region;
    _bucketController.text = config.bucket;
    _accessKeyController.text = config.accessKey;
    _secretKeyController.text = config.secretKey;
    _sessionTokenController.text = config.sessionToken;
  }

  DataSyncConfig _buildConfig() {
    return DataSyncConfig(
      enabled: _enabled,
      supabaseUrl: _supabaseUrlController.text.trim(),
      anonKey: _anonKeyController.text.trim(),
      namespace: _namespaceController.text.trim(),
      syncSecret: _syncSecretController.text.trim(),
      s3Endpoint: _s3EndpointController.text.trim(),
      region: _regionController.text.trim(),
      bucket: _bucketController.text.trim(),
      accessKey: _accessKeyController.text.trim(),
      secretKey: _secretKeyController.text.trim(),
      sessionToken: _sessionTokenController.text.trim(),
      forcePathStyle: _forcePathStyle,
      deviceId: _status.deviceId,
    );
  }

  Future<void> _saveConfig() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    await _guardBusy(() async {
      final saved = await DataSyncService.saveConfig(_buildConfig());
      _applyConfig(saved);
      final status = await DataSyncService.getStatus();
      if (!mounted) return;
      setState(() {
        _enabled = saved.enabled;
        _status = status;
      });
      showToast(_t('配置已保存', 'Sync config saved'));
    });
  }

  Future<void> _toggleEnabled(bool value) async {
    if (value) {
      if (!_formKey.currentState!.validate()) {
        return;
      }
      await _saveConfig();
    }
    await _guardBusy(() async {
      final status = await DataSyncService.setEnabled(value);
      if (!mounted) return;
      setState(() {
        _enabled = value;
        _status = status;
      });
      _ensurePolling(status);
      showToast(
        value ? _t('数据同步已启用', 'Data sync enabled') : _t('数据同步已停用', 'Data sync disabled'),
      );
    });
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    await _guardBusy(() async {
      final result = await DataSyncService.testConnection(_buildConfig());
      showToast(result['message']?.toString() ?? _t('连接成功', 'Connection succeeded'));
    });
  }

  Future<void> _syncNow() async {
    await _guardBusy(() async {
      final status = await DataSyncService.syncNow();
      if (!mounted) return;
      setState(() {
        _status = status;
      });
      _ensurePolling(status);
      showToast(_t('已开始同步', 'Sync started'));
    });
  }

  Future<void> _reindex() async {
    await _guardBusy(() async {
      final status = await DataSyncService.reindexLocalSnapshot();
      if (!mounted) return;
      setState(() {
        _status = status;
      });
      showToast(_t('本地索引已重建', 'Local snapshot index rebuilt'));
    });
  }

  Future<void> _exportPairing() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    await _saveConfig();
    final passphrase = await _askPassphrase(
      title: _t('导出配对二维码', 'Export pairing QR'),
      subtitle: _t('请输入一次性口令，用于加密导出的配对配置', 'Enter a one-time passphrase to encrypt the exported pairing payload'),
    );
    if (passphrase == null || passphrase.isEmpty) return;
    await _guardBusy(() async {
      final payload = await DataSyncService.exportPairingPayload(passphrase);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(_t('配对二维码', 'Pairing QR')),
            content: SizedBox(
              width: 280,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  QrImageView(
                    data: payload.encodedPayload,
                    version: QrVersions.auto,
                    size: 220,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _t(
                      '请在新设备上扫描二维码，并输入同一一次性口令。',
                      'Scan this code on the new device and enter the same one-time passphrase.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: payload.encodedPayload),
                      );
                      if (!context.mounted) return;
                      showToast(_t('已复制导入串', 'Pairing payload copied'));
                    },
                    child: Text(_t('复制导入串', 'Copy payload')),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(_t('关闭', 'Close')),
              ),
            ],
          );
        },
      );
    });
  }

  Future<void> _importPairing() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: Text(_t('扫描二维码', 'Scan QR code')),
              onTap: () => Navigator.of(context).pop('scan'),
            ),
            ListTile(
              leading: const Icon(Icons.paste),
              title: Text(_t('粘贴导入串', 'Paste payload')),
              onTap: () => Navigator.of(context).pop('paste'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    String? encodedPayload;
    if (action == 'scan') {
      encodedPayload = await Navigator.of(context).push<String>(
        MaterialPageRoute(builder: (_) => const _DataSyncQrScannerPage()),
      );
    } else {
      encodedPayload = await _askTextInput(
        title: _t('导入配对配置', 'Import pairing payload'),
        hint: _t('请粘贴配对导入串', 'Paste the encrypted pairing payload'),
      );
    }
    if (encodedPayload == null || encodedPayload.trim().isEmpty || !mounted) return;
    final passphrase = await _askPassphrase(
      title: _t('输入一次性口令', 'Enter one-time passphrase'),
      subtitle: _t('请输入导出时设置的加密口令', 'Enter the passphrase used when exporting the payload'),
    );
    if (passphrase == null || passphrase.isEmpty) return;
    await _guardBusy(() async {
      final status = await DataSyncService.importPairingPayload(
        encodedPayload: encodedPayload!.trim(),
        passphrase: passphrase,
      );
      if (!mounted) return;
      setState(() {
        _enabled = true;
        _status = status;
      });
      _ensurePolling(status);
      showToast(
        _t('配对配置已导入，正在执行首次全量同步', 'Pairing imported, starting the first full sync'),
      );
    });
  }

  Future<void> _showConflicts() async {
    await _guardBusy(() async {
      final conflicts = await DataSyncService.listConflicts();
      if (!mounted) return;
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          return SafeArea(
            child: SizedBox(
              height: MediaQuery.of(context).size.height * 0.72,
              child: Column(
                children: [
                  ListTile(
                    title: Text(_t('冲突与失败记录', 'Conflicts and failures')),
                    subtitle: Text(
                      conflicts.isEmpty
                          ? _t('当前没有未处理冲突', 'No unresolved conflicts')
                          : _t('共 ${conflicts.length} 条记录', '${conflicts.length} records'),
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: conflicts.isEmpty
                        ? Center(
                            child: Text(_t('暂无冲突', 'No conflicts')),
                          )
                        : ListView.separated(
                            itemCount: conflicts.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final item = conflicts[index];
                              return ListTile(
                                title: Text(item.relativePath),
                                subtitle: Text(
                                  item.conflictCopyPath.isEmpty
                                      ? item.remoteHash
                                      : '${_t('保留副本', 'Conflict copy')}: ${item.conflictCopyPath}',
                                ),
                                trailing: item.status == 'open'
                                    ? TextButton(
                                        onPressed: () async {
                                          await DataSyncService.ackConflict(item.id);
                                          if (!context.mounted) return;
                                          Navigator.of(context).pop();
                                          _showConflicts();
                                        },
                                        child: Text(_t('已知悉', 'Acknowledge')),
                                      )
                                    : Text(_t('已处理', 'Handled')),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    });
  }

  Future<void> _refreshStatus() async {
    try {
      final status = await DataSyncService.getStatus();
      if (!mounted) return;
      setState(() {
        _status = status;
      });
      _ensurePolling(status);
    } catch (_) {}
  }

  void _ensurePolling(DataSyncStatus status) {
    if (!status.isSyncing) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    _pollTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
      _refreshStatus();
    });
  }

  Future<void> _guardBusy(Future<void> Function() action) async {
    if (_busy) return;
    setState(() {
      _busy = true;
    });
    try {
      await action();
    } on PlatformException catch (error) {
      showToast(error.message ?? error.code, type: ToastType.error);
    } catch (error) {
      showToast(error.toString(), type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<String?> _askPassphrase({
    required String title,
    required String subtitle,
  }) {
    return _askTextInput(
      title: title,
      hint: subtitle,
      obscureText: true,
    );
  }

  Future<String?> _askTextInput({
    required String title,
    required String hint,
    bool obscureText = false,
  }) async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(title),
          content: TextField(
            controller: controller,
            obscureText: obscureText,
            autofocus: true,
            decoration: InputDecoration(hintText: hint),
            minLines: obscureText ? 1 : 3,
            maxLines: obscureText ? 1 : 6,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(_t('取消', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: Text(_t('确定', 'OK')),
            ),
          ],
        );
      },
    );
  }

  String _statusText() {
    if (_loading) return _t('加载中…', 'Loading…');
    switch (_status.state) {
      case 'syncing':
        return _status.progress.detail.isNotEmpty
            ? _status.progress.detail
            : _t('同步进行中', 'Sync in progress');
      case 'success':
        return _status.lastMessage.isNotEmpty
            ? _status.lastMessage
            : _t('最近一次同步成功', 'Last sync succeeded');
      case 'error':
        return _status.lastError.isNotEmpty
            ? _status.lastError
            : _t('同步失败', 'Sync failed');
      case 'disabled':
        return _t('同步未启用', 'Sync disabled');
      default:
        return _status.lastMessage.isNotEmpty
            ? _status.lastMessage
            : _t('等待同步', 'Idle');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    return Scaffold(
      backgroundColor: palette.pageBackground,
      appBar: CommonAppBar(
        title: _t('数据同步', 'Data Sync'),
        primary: true,
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    _buildStatusCard(context),
                    const SizedBox(height: 16),
                    _buildSectionTitle(_t('同步配置', 'Sync Config')),
                    _buildField(
                      controller: _supabaseUrlController,
                      label: 'Supabase URL',
                      hint: 'https://your-project.supabase.co',
                    ),
                    _buildField(
                      controller: _anonKeyController,
                      label: 'anon key',
                      obscureText: true,
                    ),
                    _buildField(
                      controller: _namespaceController,
                      label: 'sync namespace',
                    ),
                    _buildField(
                      controller: _syncSecretController,
                      label: 'sync secret',
                      obscureText: true,
                    ),
                    _buildField(
                      controller: _s3EndpointController,
                      label: 'S3 endpoint',
                      hint: 'https://s3.example.com',
                    ),
                    _buildField(
                      controller: _regionController,
                      label: 'region',
                    ),
                    _buildField(
                      controller: _bucketController,
                      label: 'bucket',
                    ),
                    _buildField(
                      controller: _accessKeyController,
                      label: 'access key',
                      obscureText: true,
                    ),
                    _buildField(
                      controller: _secretKeyController,
                      label: 'secret key',
                      obscureText: true,
                    ),
                    _buildField(
                      controller: _sessionTokenController,
                      label: _t('session token（可选）', 'session token (optional)'),
                      required: false,
                      obscureText: true,
                    ),
                    SwitchListTile.adaptive(
                      value: _forcePathStyle,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('path-style'),
                      subtitle: Text(
                        _t('兼容 MinIO / R2 等 S3-compatible 存储', 'Use path-style URLs for MinIO / R2 and other S3-compatible storage'),
                      ),
                      onChanged: _busy
                          ? null
                          : (value) {
                              setState(() {
                                _forcePathStyle = value;
                              });
                            },
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile.adaptive(
                      value: _enabled,
                      contentPadding: EdgeInsets.zero,
                      title: Text(_t('启用数据同步', 'Enable data sync')),
                      subtitle: Text(
                        _t('采用本地优先 + 快照差异 + 幂等 push/pull，同步聊天、workspace、附件与跨设备设置。', 'Use local-first sync with snapshot diff and idempotent push/pull for chats, workspace, attachments, and cross-device settings.'),
                      ),
                      onChanged: _busy ? null : _toggleEnabled,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        FilledButton.icon(
                          onPressed: _busy ? null : _saveConfig,
                          icon: const Icon(Icons.save_outlined),
                          label: Text(_t('保存配置', 'Save Config')),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _testConnection,
                          icon: const Icon(Icons.cloud_done_outlined),
                          label: Text(_t('连接测试', 'Test Connection')),
                        ),
                        OutlinedButton.icon(
                          onPressed: (!_enabled || _busy) ? null : _syncNow,
                          icon: const Icon(Icons.sync),
                          label: Text(_t('立即同步', 'Sync Now')),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _reindex,
                          icon: const Icon(Icons.manage_search_outlined),
                          label: Text(_t('重建本地索引', 'Reindex')),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _exportPairing,
                          icon: const Icon(Icons.qr_code_2),
                          label: Text(_t('导出配对二维码', 'Export QR')),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _importPairing,
                          icon: const Icon(Icons.qr_code_scanner),
                          label: Text(_t('导入配对二维码', 'Import QR')),
                        ),
                        OutlinedButton.icon(
                          onPressed: _busy ? null : _showConflicts,
                          icon: const Icon(Icons.warning_amber_outlined),
                          label: Text(_t('查看冲突/失败', 'View Conflicts')),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    Text(
                      _t(
                        '同步范围：聊天、workspace、附件、用户记录、跨设备配置。\n不同步：闹钟/定时任务、权限、隐藏最近任务、本机服务状态、本地模型/缓存/日志、App 更新状态、同步凭据自身。',
                        'Synced: chats, workspace, attachments, user records, and cross-device settings.\nNot synced: alarms/tasks, permissions, hide-from-recents, local service state, local models/cache/logs, app update state, and sync credentials.',
                      ),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: palette.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildStatusCard(BuildContext context) {
    final theme = Theme.of(context);
    final percent = _status.progress.percent.clamp(0, 100);
    final double? progressValue = _status.isSyncing
        ? percent.toDouble() / 100.0
        : null;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _t('同步状态', 'Sync Status'),
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Chip(
                  label: Text(
                    _status.state.toUpperCase(),
                    style: theme.textTheme.labelSmall,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(_statusText(), style: theme.textTheme.bodyMedium),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: progressValue),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _InfoPill(
                  label: _t('命名空间', 'Namespace'),
                  value: _status.namespace.isEmpty ? '-' : _status.namespace,
                ),
                _InfoPill(
                  label: _t('设备', 'Device'),
                  value: _status.deviceId.isEmpty ? '-' : _status.deviceId,
                ),
                _InfoPill(
                  label: _t('待推送', 'Pending'),
                  value: '${_status.pendingOutboxCount}',
                ),
                _InfoPill(
                  label: _t('冲突', 'Conflicts'),
                  value: '${_status.openConflictCount}',
                ),
                _InfoPill(
                  label: 'Cursor',
                  value: '${_status.remoteCursor}',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium,
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    String? hint,
    bool obscureText = false,
    bool required = true,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextFormField(
        controller: controller,
        obscureText: obscureText,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
        validator: required
            ? (value) {
                if ((value ?? '').trim().isEmpty) {
                  return _t('必填', 'Required');
                }
                return null;
              }
            : null,
      ),
    );
  }

  String _t(String zh, String en) => _isEnglish ? en : zh;
}

class _InfoPill extends StatelessWidget {
  const _InfoPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 2),
          Text(value, style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}

class _DataSyncQrScannerPage extends StatefulWidget {
  const _DataSyncQrScannerPage();

  @override
  State<_DataSyncQrScannerPage> createState() => _DataSyncQrScannerPageState();
}

class _DataSyncQrScannerPageState extends State<_DataSyncQrScannerPage> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) {
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    return Scaffold(
      appBar: CommonAppBar(
        title: isEnglish ? 'Scan Pairing QR' : '扫描配对二维码',
        primary: true,
      ),
      body: MobileScanner(
        onDetect: (capture) {
          if (_handled) return;
          final code = capture.barcodes
              .map((item) => item.rawValue?.trim() ?? '')
              .firstWhere(
                (item) => item.isNotEmpty,
                orElse: () => '',
              );
          if (code.isEmpty) return;
          _handled = true;
          Navigator.of(context).pop(code);
        },
      ),
    );
  }
}
