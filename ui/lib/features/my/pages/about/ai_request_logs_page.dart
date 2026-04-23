import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui/l10n/legacy_text_localizer.dart';
import 'package:ui/services/ai_request_log_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/theme/app_text_styles.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';

class AiRequestLogsPage extends StatefulWidget {
  const AiRequestLogsPage({super.key});

  @override
  State<AiRequestLogsPage> createState() => _AiRequestLogsPageState();
}

class _AiRequestLogsPageState extends State<AiRequestLogsPage> {
  List<AiRequestLogEntry> _logs = const [];
  bool _isLoading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  Future<void> _loadLogs() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });
    try {
      final logs = await AiRequestLogService.listRecent(limit: 10);
      if (!mounted) return;
      setState(() {
        _logs = logs;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _copyJson(String label, String content) async {
    await Clipboard.setData(ClipboardData(text: content));
    if (!mounted) return;
    showToast(
      LegacyTextLocalizer.localize('$label已复制'),
      type: ToastType.success,
    );
  }

  String _formatDateTime(DateTime value) {
    String pad(int number) => number.toString().padLeft(2, '0');
    return '${value.year}-${pad(value.month)}-${pad(value.day)} '
        '${pad(value.hour)}:${pad(value.minute)}:${pad(value.second)}';
  }

  String _buildSummary(AiRequestLogEntry log) {
    final statusText = log.statusCode == null ? '' : 'HTTP ${log.statusCode}';
    final streamText = LegacyTextLocalizer.localize(
      log.stream ? '流式' : '非流式',
    );
    final protocolText = log.protocolType == 'anthropic'
        ? 'Anthropic'
        : 'OpenAI';
    return [
      protocolText,
      streamText,
      statusText,
    ].where((item) => item.isNotEmpty).join(' · ');
  }

  Widget _buildJsonBlock({
    required BuildContext context,
    required String title,
    required String content,
  }) {
    final palette = context.omniPalette;
    final jsonText = content.trim().isEmpty ? '<empty>' : content;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.isDarkTheme
            ? const Color(0xFF11151B)
            : const Color(0xFFF6F8FC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: context.isDarkTheme
              ? const Color(0xFF1B2432)
              : const Color(0xFFE1E8F2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontFamily: AppTextStyles.fontFamily,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: context.isDarkTheme
                        ? palette.textPrimary
                        : AppColors.text,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => _copyJson(title, jsonText),
                child: Text(LegacyTextLocalizer.localize('复制')),
              ),
            ],
          ),
          SelectableText(
            jsonText,
            style: TextStyle(
              fontFamily: 'monospace',
              fontSize: 12,
              height: 1.5,
              color: context.isDarkTheme
                  ? palette.textSecondary
                  : AppColors.text70,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final palette = context.omniPalette;
    if (_isLoading && _logs.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_errorMessage.isNotEmpty && _logs.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                LegacyTextLocalizer.localize('加载请求日志失败'),
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: context.isDarkTheme
                      ? palette.textPrimary
                      : AppColors.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 13,
                  color: context.isDarkTheme
                      ? palette.textSecondary
                      : AppColors.text70,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _loadLogs,
                child: Text(LegacyTextLocalizer.localize('重试')),
              ),
            ],
          ),
        ),
      );
    }
    if (_logs.isEmpty) {
      return Center(
        child: Text(
          LegacyTextLocalizer.localize('最近还没有 AI 请求日志'),
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 14,
            color: context.isDarkTheme
                ? palette.textSecondary
                : AppColors.text70,
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadLogs,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _logs.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final log = _logs[index];
          return Container(
            decoration: BoxDecoration(
              color: context.isDarkTheme
                  ? const Color(0xFF12161C)
                  : Colors.white,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: context.isDarkTheme
                    ? const Color(0xFF1B2432)
                    : const Color(0xFFE6ECF5),
              ),
              boxShadow: context.isDarkTheme
                  ? null
                  : const [
                      BoxShadow(
                        color: Color(0x0F16324F),
                        blurRadius: 18,
                        offset: Offset(0, 6),
                      ),
                    ],
            ),
            child: ExpansionTile(
              tilePadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 4,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              title: Text(
                log.model.isEmpty
                    ? (log.label.isEmpty
                          ? LegacyTextLocalizer.localize('AI 请求')
                          : log.label)
                    : log.model,
                style: TextStyle(
                  fontFamily: AppTextStyles.fontFamily,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: context.isDarkTheme
                      ? palette.textPrimary
                      : AppColors.text,
                ),
              ),
              subtitle: Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatDateTime(log.createdAt),
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 12,
                        color: context.isDarkTheme
                            ? palette.textSecondary
                            : AppColors.text70,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _buildSummary(log),
                      style: TextStyle(
                        fontFamily: AppTextStyles.fontFamily,
                        fontSize: 12,
                        color: log.success
                            ? const Color(0xFF1E8E5A)
                            : const Color(0xFFD93025),
                      ),
                    ),
                  ],
                ),
              ),
              children: [
                _buildInfoRow(
                  context,
                  LegacyTextLocalizer.localize('请求地址'),
                  log.url,
                ),
                _buildInfoRow(
                  context,
                  LegacyTextLocalizer.localize('请求方法'),
                  log.method,
                ),
                if (log.errorMessage.trim().isNotEmpty)
                  _buildInfoRow(
                    context,
                    LegacyTextLocalizer.localize('错误信息'),
                    log.errorMessage,
                  ),
                _buildJsonBlock(
                  context: context,
                  title: LegacyTextLocalizer.localize('请求 JSON'),
                  content: log.requestJson,
                ),
                _buildJsonBlock(
                  context: context,
                  title: LegacyTextLocalizer.localize('响应 JSON'),
                  content: log.responseJson,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    final palette = context.omniPalette;
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: RichText(
        text: TextSpan(
          style: TextStyle(
            fontFamily: AppTextStyles.fontFamily,
            fontSize: 13,
            height: 1.5,
            color: context.isDarkTheme
                ? palette.textSecondary
                : AppColors.text70,
          ),
          children: [
            TextSpan(
              text: '$label：',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: context.isDarkTheme
                    ? palette.textPrimary
                    : AppColors.text,
              ),
            ),
            TextSpan(text: value.trim().isEmpty ? '-' : value),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    return Scaffold(
      backgroundColor: palette.pageBackground,
      appBar: CommonAppBar(
        title: LegacyTextLocalizer.localize('请求日志'),
        primary: true,
        actions: [
          IconButton(
            onPressed: _loadLogs,
            icon: const Icon(Icons.refresh),
            tooltip: LegacyTextLocalizer.localize('刷新'),
          ),
        ],
      ),
      body: _buildContent(context),
    );
  }
}
