import 'package:flutter/material.dart';
import 'package:ui/services/agent_avatar_service.dart';
import 'package:ui/theme/theme_context.dart';

Future<int?> showAgentAvatarPicker(BuildContext context) {
  return showDialog<int>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.28),
    builder: (context) => const _AgentAvatarPickerDialog(),
  );
}

class AgentAvatarButton extends StatefulWidget {
  const AgentAvatarButton({
    super.key,
    this.size = 28,
    this.tooltip = '修改 Agent 头像',
    this.showEditBadge = false,
    this.showCompletedBadge = false,
    this.onChanged,
  });

  final double size;
  final String tooltip;
  final bool showEditBadge;
  final bool showCompletedBadge;
  final ValueChanged<int>? onChanged;

  @override
  State<AgentAvatarButton> createState() => _AgentAvatarButtonState();
}

class _AgentAvatarButtonState extends State<AgentAvatarButton> {
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    AgentAvatarService.ensureLoaded();
  }

  Future<void> _openPicker() async {
    final selectedIndex = await showAgentAvatarPicker(context);
    if (selectedIndex == null || !mounted) {
      return;
    }
    widget.onChanged?.call(selectedIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _openPicker,
        onTapDown: (_) => setState(() => _isPressed = true),
        onTapCancel: () => setState(() => _isPressed = false),
        onTapUp: (_) => setState(() => _isPressed = false),
        child: AnimatedScale(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          scale: _isPressed ? 0.94 : 1,
          child: ValueListenableBuilder<int>(
            valueListenable: AgentAvatarService.avatarIndexNotifier,
            builder: (context, avatarIndex, _) {
              return AgentAvatarCircle(
                avatarIndex: avatarIndex,
                size: widget.size,
                showEditBadge: widget.showEditBadge,
                showCompletedBadge: widget.showCompletedBadge,
              );
            },
          ),
        ),
      ),
    );
  }
}

class AgentAvatarCircle extends StatelessWidget {
  const AgentAvatarCircle({
    super.key,
    this.avatarIndex,
    this.size = 28,
    this.showEditBadge = false,
    this.showCompletedBadge = false,
  });

  final int? avatarIndex;
  final double size;
  final bool showEditBadge;
  final bool showCompletedBadge;

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    final badgeSize = (size * 0.38).clamp(10.0, 16.0).toDouble();
    final badgeIconSize = (badgeSize * 0.64).clamp(7.0, 11.0).toDouble();
    final asset = AgentAvatarService.assetForIndex(avatarIndex);
    final badgeIcon = showCompletedBadge
        ? Icons.check_rounded
        : showEditBadge
        ? Icons.edit_rounded
        : null;
    final badgeColor = showCompletedBadge
        ? const Color(0xFF23B26D)
        : palette.accentPrimary;

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            foregroundDecoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: context.isDarkTheme
                    ? palette.borderStrong
                    : const Color(0xFFFFFFFF),
                width: 1.5,
              ),
            ),
            child: ClipOval(
              child: Image.asset(
                asset,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) {
                  return ColoredBox(
                    color: palette.surfaceElevated,
                    child: Icon(
                      Icons.smart_toy_outlined,
                      size: size * 0.54,
                      color: palette.textSecondary,
                    ),
                  );
                },
              ),
            ),
          ),
          if (badgeIcon != null)
            Positioned(
              right: -1,
              bottom: -1,
              child: Container(
                width: badgeSize,
                height: badgeSize,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.surfacePrimary, width: 1),
                ),
                child: Icon(
                  badgeIcon,
                  size: badgeIconSize,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AgentAvatarPickerDialog extends StatelessWidget {
  const _AgentAvatarPickerDialog();

  Future<void> _selectAvatar(BuildContext context, int avatarIndex) async {
    final selectedIndex = await AgentAvatarService.setAvatarIndex(avatarIndex);
    if (!context.mounted) {
      return;
    }
    Navigator.of(context).pop(selectedIndex);
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    final isDark = context.isDarkTheme;
    final surfaceColor = isDark ? palette.surfacePrimary : Colors.white;
    final secondaryTextColor = isDark
        ? palette.textSecondary
        : const Color(0xFF64748B);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 36),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 326),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? palette.borderSubtle : const Color(0xFFE2EAF4),
            ),
            boxShadow: [
              BoxShadow(
                color: palette.shadowColor.withValues(
                  alpha: isDark ? 0.36 : 0.16,
                ),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    ValueListenableBuilder<int>(
                      valueListenable: AgentAvatarService.avatarIndexNotifier,
                      builder: (context, avatarIndex, _) {
                        return AgentAvatarCircle(
                          avatarIndex: avatarIndex,
                          size: 42,
                        );
                      },
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Agent 头像',
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w700,
                              fontFamily: 'PingFang SC',
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '用于聊天思考状态与场景入口',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: secondaryTextColor,
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              fontFamily: 'PingFang SC',
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: '关闭',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => Navigator.of(context).pop(),
                      icon: Icon(
                        Icons.close_rounded,
                        size: 20,
                        color: palette.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                ValueListenableBuilder<int>(
                  valueListenable: AgentAvatarService.avatarIndexNotifier,
                  builder: (context, selectedIndex, _) {
                    return GridView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: AgentAvatarService.presetAvatars.length,
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                          ),
                      itemBuilder: (context, index) {
                        final selected = selectedIndex == index;
                        return _AgentAvatarPickerItem(
                          avatarIndex: index,
                          selected: selected,
                          onTap: () => _selectAvatar(context, index),
                        );
                      },
                    );
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentAvatarPickerItem extends StatelessWidget {
  const _AgentAvatarPickerItem({
    required this.avatarIndex,
    required this.selected,
    required this.onTap,
  });

  final int avatarIndex;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    final selectedColor = context.isDarkTheme
        ? palette.accentPrimary
        : const Color(0xFF2C7FEB);

    return Material(
      color: selected
          ? selectedColor.withValues(alpha: context.isDarkTheme ? 0.14 : 0.08)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? selectedColor : palette.borderSubtle,
              width: selected ? 1.6 : 1,
            ),
          ),
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              AgentAvatarCircle(avatarIndex: avatarIndex, size: 56),
              if (selected)
                Positioned(
                  right: -3,
                  bottom: -3,
                  child: Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: selectedColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: palette.surfacePrimary,
                        width: 1.2,
                      ),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 12,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
