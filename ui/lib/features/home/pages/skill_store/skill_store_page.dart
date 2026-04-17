import 'package:flutter/material.dart';
import 'package:ui/l10n/l10n.dart';
import 'package:ui/models/agent_skill_item.dart';
import 'package:ui/services/agent_skill_store_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';

class SkillStorePage extends StatefulWidget {
  const SkillStorePage({super.key});

  @override
  State<SkillStorePage> createState() => _SkillStorePageState();
}

class _SkillStorePageState extends State<SkillStorePage> {
  bool _loading = true;
  final Set<String> _busyIds = <String>{};
  List<AgentSkillItem> _skills = [];

  @override
  void initState() {
    super.initState();
    _loadSkills();
  }

  Future<void> _loadSkills() async {
    setState(() => _loading = true);
    try {
      final skills = await AgentSkillStoreService.listSkills();
      if (!mounted) return;
      setState(() {
        _skills = skills;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
      showToast(context.l10n.skillLoadFailed, type: ToastType.error);
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

  Future<void> _toggleSkill(AgentSkillItem item, bool enabled) async {
    _setBusy(item.id, true);
    try {
      final updated = await AgentSkillStoreService.setEnabled(
        skillId: item.id,
        enabled: enabled,
      );
      if (!mounted) return;
      if (updated == null) {
        showToast(context.l10n.skillToggleFailed, type: ToastType.error);
        return;
      }
      setState(() {
        _skills = _skills
            .map((skill) => skill.id == item.id ? updated : skill)
            .toList();
      });
      showToast(enabled ? context.l10n.skillEnabledMsg(item.name) : context.l10n.skillDisabledMsg(item.name));
    } catch (_) {
      showToast(context.l10n.skillToggleFailed, type: ToastType.error);
    } finally {
      _setBusy(item.id, false);
    }
  }

  Future<void> _installBuiltinSkill(AgentSkillItem item) async {
    _setBusy(item.id, true);
    try {
      final installed = await AgentSkillStoreService.installBuiltinSkill(
        skillId: item.id,
      );
      if (!mounted) return;
      if (installed == null) {
        showToast(context.l10n.skillInstallFailed, type: ToastType.error);
        return;
      }
      setState(() {
        _skills = _skills
            .map((skill) => skill.id == item.id ? installed : skill)
            .toList();
        _skills.sort((a, b) {
          if (a.installed != b.installed) {
            return a.installed ? -1 : 1;
          }
          if (a.isBuiltin != b.isBuiltin) {
            return a.isBuiltin ? -1 : 1;
          }
          return a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      });
      showToast(context.l10n.skillInstalledMsg(item.name), type: ToastType.success);
    } catch (_) {
      showToast(context.l10n.skillInstallFailed, type: ToastType.error);
    } finally {
      _setBusy(item.id, false);
    }
  }

  Future<void> _deleteSkill(AgentSkillItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.l10n.skillDeleteTitle),
        content: Text(context.l10n.skillDeleteConfirmMsg(item.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(context.trLegacy('取消')),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: AppColors.alertRed),
            child: Text(context.l10n.skillDelete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    _setBusy(item.id, true);
    try {
      final deleted = await AgentSkillStoreService.deleteSkill(
        skillId: item.id,
      );
      if (!mounted || !deleted) {
        showToast(context.l10n.skillDeleteFailed, type: ToastType.error);
        return;
      }
      await _loadSkills();
      if (!mounted) return;
      showToast(context.l10n.skillDeleted, type: ToastType.success);
    } catch (_) {
      showToast(context.l10n.skillDeleteFailed, type: ToastType.error);
    } finally {
      _setBusy(item.id, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    return Scaffold(
      backgroundColor: context.isDarkTheme
          ? palette.pageBackground
          : AppColors.background,
      appBar: CommonAppBar(title: context.l10n.skillStoreTitle, primary: true),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _skills.isEmpty
          ? _buildEmpty()
          : RefreshIndicator(
              onRefresh: _loadSkills,
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemBuilder: (context, index) =>
                    _buildSkillCard(_skills[index]),
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemCount: _skills.length,
              ),
            ),
    );
  }

  Widget _buildEmpty() {
    final palette = context.omniPalette;
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const SizedBox(height: 120),
        Icon(
          Icons.extension_outlined,
          size: 48,
          color: context.isDarkTheme ? palette.textTertiary : AppColors.text50,
        ),
        const SizedBox(height: 12),
        Center(
          child: Text(
            context.l10n.skillEmpty,
            style: TextStyle(
              fontSize: 16,
              color: context.isDarkTheme
                  ? palette.textSecondary
                  : AppColors.text70,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSkillCard(AgentSkillItem item) {
    final palette = context.omniPalette;
    final busy = _busyIds.contains(item.id);
    final description = item.description.trim().isEmpty
        ? context.l10n.skillNoDescription
        : item.description;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: context.isDarkTheme ? palette.surfacePrimary : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: context.isDarkTheme
            ? Border.all(color: palette.borderSubtle)
            : null,
        boxShadow: context.isDarkTheme
            ? [
                BoxShadow(
                  color: palette.shadowColor.withValues(alpha: 0.18),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ]
            : [AppColors.boxShadow],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.name,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: context.isDarkTheme
                            ? palette.textPrimary
                            : AppColors.text,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.5,
                        color: context.isDarkTheme
                            ? palette.textSecondary
                            : AppColors.text70,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (busy)
                const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                )
              else if (item.installed)
                Switch(
                  value: item.enabled,
                  onChanged: (value) => _toggleSkill(item, value),
                )
              else
                FilledButton.tonal(
                  onPressed: item.isBuiltin
                      ? () => _installBuiltinSkill(item)
                      : null,
                  child: Text(context.l10n.skillInstall),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildChip(item.isBuiltin ? context.l10n.skillBuiltin : context.l10n.skillUser),
              _buildChip(item.installed ? context.l10n.skillInstalled : context.l10n.skillNotInstalled),
              if (item.installed) _buildChip(item.enabled ? context.l10n.skillEnabled : context.l10n.skillDisabled),
              ...item.capabilities.map(_buildChip),
            ],
          ),
          if (!item.installed && item.isBuiltin) ...[
            const SizedBox(height: 12),
            Text(
              context.l10n.skillBuiltinRemovedDesc,
              style: TextStyle(
                fontSize: 12,
                color: context.isDarkTheme
                    ? palette.textTertiary
                    : AppColors.text50,
                height: 1.5,
              ),
            ),
          ],
          if (item.installed) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Text(
                    item.shellSkillFilePath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.isDarkTheme
                          ? palette.textTertiary
                          : AppColors.text50,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                TextButton(
                  onPressed: busy ? null : () => _deleteSkill(item),
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.alertRed,
                  ),
                  child: Text(context.l10n.skillDelete),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildChip(String label) {
    final palette = context.omniPalette;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: context.isDarkTheme
            ? palette.surfaceSecondary
            : const Color(0xFFF4F7FD),
        borderRadius: BorderRadius.circular(999),
        border: context.isDarkTheme
            ? Border.all(color: palette.borderSubtle)
            : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: context.isDarkTheme ? palette.textSecondary : AppColors.text70,
        ),
      ),
    );
  }
}
