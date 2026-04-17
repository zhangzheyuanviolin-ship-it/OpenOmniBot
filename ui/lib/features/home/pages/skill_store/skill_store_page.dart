import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ui/features/home/widgets/home_drawer_search_field.dart';
import 'package:ui/l10n/l10n.dart';
import 'package:ui/models/agent_skill_item.dart';
import 'package:ui/services/agent_skill_store_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';

const String _kBuiltinSkillBadgeCheckSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
    'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" '
    'stroke-linecap="round" stroke-linejoin="round" '
    'class="lucide lucide-badge-check-icon lucide-badge-check">'
    '<path d="M3.85 8.62a4 4 0 0 1 4.78-4.77 4 4 0 0 1 6.74 0 '
    '4 4 0 0 1 4.78 4.78 4 4 0 0 1 0 6.74 4 4 0 0 1-4.77 4.78 '
    '4 4 0 0 1-6.75 0 4 4 0 0 1-4.78-4.77 4 4 0 0 1 0-6.76Z"/>'
    '<path d="m9 12 2 2 4-4"/></svg>';

class SkillStorePage extends StatefulWidget {
  const SkillStorePage({super.key});

  @override
  State<SkillStorePage> createState() => _SkillStorePageState();
}

class _SkillStorePageState extends State<SkillStorePage> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  bool _loading = true;
  final Set<String> _busyIds = <String>{};
  List<AgentSkillItem> _skills = [];

  String get _searchQuery => _searchController.text.trim();

  List<AgentSkillItem> get _visibleSkills {
    final query = _searchQuery.toLowerCase();
    if (query.isEmpty) {
      return _skills;
    }

    return _skills
        .where((skill) {
          return skill.name.toLowerCase().contains(query) ||
              skill.description.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_handleSearchChanged);
    _searchFocusNode.addListener(_handleSearchFocusChanged);
    _loadSkills();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_handleSearchChanged)
      ..dispose();
    _searchFocusNode
      ..removeListener(_handleSearchFocusChanged)
      ..dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _handleSearchFocusChanged() {
    if (!mounted) return;
    setState(() {});
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
      showToast(
        enabled
            ? context.l10n.skillEnabledMsg(item.name)
            : context.l10n.skillDisabledMsg(item.name),
      );
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
      showToast(
        context.l10n.skillInstalledMsg(item.name),
        type: ToastType.success,
      );
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
      if (!mounted) return;
      if (!deleted) {
        showToast(context.l10n.skillDeleteFailed, type: ToastType.error);
        return;
      }
      await _loadSkills();
      if (!mounted) return;
      showToast(context.l10n.skillDeleted, type: ToastType.success);
    } catch (_) {
      if (!mounted) return;
      showToast(context.l10n.skillDeleteFailed, type: ToastType.error);
    } finally {
      _setBusy(item.id, false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    final visibleSkills = _visibleSkills;
    final listChildren = <Widget>[
      HomeDrawerSearchField(
        controller: _searchController,
        focusNode: _searchFocusNode,
        isSearching: false,
        textColor: context.isDarkTheme ? palette.textPrimary : AppColors.text,
        hintText: context.trLegacy('搜索技能名称或描述'),
      ),
      const SizedBox(height: 12),
    ];

    if (visibleSkills.isEmpty) {
      listChildren.add(_buildSearchEmpty());
    } else {
      for (var index = 0; index < visibleSkills.length; index++) {
        if (index > 0) {
          listChildren.add(const SizedBox(height: 12));
        }
        listChildren.add(_buildSkillCard(visibleSkills[index]));
      }
    }

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
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: listChildren,
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
                    _buildSkillTitle(item),
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

  Widget _buildSkillTitle(AgentSkillItem item) {
    final palette = context.omniPalette;
    final titleStyle = TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      color: context.isDarkTheme ? palette.textPrimary : AppColors.text,
    );

    if (!item.isBuiltin) {
      return Text(item.name, style: titleStyle);
    }

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: item.name, style: titleStyle),
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Tooltip(
                message: context.l10n.skillBuiltin,
                child: SvgPicture.string(
                  _kBuiltinSkillBadgeCheckSvg,
                  width: 18,
                  height: 18,
                  colorFilter: ColorFilter.mode(
                    palette.accentPrimary,
                    BlendMode.srcIn,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchEmpty() {
    final palette = context.omniPalette;
    return Padding(
      padding: const EdgeInsets.only(top: 120),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 48,
            color: context.isDarkTheme
                ? palette.textTertiary
                : AppColors.text50,
          ),
          const SizedBox(height: 12),
          Text(
            context.trLegacy('未找到匹配的技能'),
            style: TextStyle(
              fontSize: 16,
              color: context.isDarkTheme
                  ? palette.textSecondary
                  : AppColors.text70,
            ),
          ),
        ],
      ),
    );
  }
}
