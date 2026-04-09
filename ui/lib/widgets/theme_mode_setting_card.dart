import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui/theme/app_theme_controller.dart';
import 'package:ui/theme/app_theme_mode.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/widgets/settings_section_title.dart';

class ThemeModeSettingCard extends ConsumerWidget {
  const ThemeModeSettingCard({
    super.key,
    this.title = '主题模式',
    this.subtitle = '切换浅色、深色或跟随系统外观',
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appThemeModeProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionTitle(
          label: title,
          subtitle: subtitle,
          bottomPadding: 10,
        ),
        _ThemeModeSlider(
          value: mode,
          onChanged: (nextMode) {
            ref.read(appThemeModeProvider.notifier).setThemeMode(nextMode);
          },
        ),
      ],
    );
  }
}

class _ThemeModeSlider extends StatelessWidget {
  const _ThemeModeSlider({required this.value, required this.onChanged});

  final AppThemeMode value;
  final ValueChanged<AppThemeMode> onChanged;

  static const List<_ThemeModeOption> _options = <_ThemeModeOption>[
    _ThemeModeOption(AppThemeMode.light, '浅色', Icons.light_mode_rounded),
    _ThemeModeOption(AppThemeMode.dark, '深色', Icons.dark_mode_rounded),
    _ThemeModeOption(AppThemeMode.system, '系统', Icons.brightness_auto_rounded),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    final selectedIndex = _options.indexWhere((option) => option.mode == value);
    final isDark = context.isDarkTheme;
    const controlHeight = 44.0;
    const outerPadding = 3.0;

    return Container(
      key: const ValueKey('theme-mode-slider'),
      height: controlHeight,
      decoration: BoxDecoration(
        color: palette.segmentTrack,
        borderRadius: BorderRadius.circular(controlHeight / 2),
        boxShadow: [
          BoxShadow(
            color: palette.shadowColor.withValues(alpha: isDark ? 0.12 : 0.06),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(controlHeight / 2),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final thumbWidth =
                (constraints.maxWidth - outerPadding * 2) / _options.length;
            return Stack(
              children: [
                AnimatedPositioned(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  left: outerPadding + thumbWidth * selectedIndex,
                  top: outerPadding,
                  bottom: outerPadding,
                  width: thumbWidth,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.segmentThumb,
                        borderRadius: BorderRadius.circular(controlHeight / 2),
                        boxShadow: [
                          BoxShadow(
                            color: palette.shadowColor.withValues(
                              alpha: isDark ? 0.20 : 0.10,
                            ),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Row(
                  children: _options
                      .map((option) {
                        final selected = option.mode == value;
                        final foreground = selected
                            ? palette.textPrimary
                            : palette.textSecondary;
                        return Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              key: ValueKey(
                                'theme-mode-option-${option.mode.name}',
                              ),
                              borderRadius: BorderRadius.circular(
                                controlHeight / 2,
                              ),
                              onTap: () => onChanged(option.mode),
                              child: Center(
                                child: AnimatedScale(
                                  duration: const Duration(milliseconds: 180),
                                  curve: Curves.easeOutCubic,
                                  scale: selected ? 1.0 : 0.97,
                                  child: AnimatedDefaultTextStyle(
                                    duration: const Duration(milliseconds: 180),
                                    curve: Curves.easeOutCubic,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: selected
                                          ? FontWeight.w700
                                          : FontWeight.w600,
                                      color: foreground,
                                      letterSpacing: selected ? 0.1 : 0,
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        AnimatedContainer(
                                          duration: const Duration(
                                            milliseconds: 180,
                                          ),
                                          curve: Curves.easeOutCubic,
                                          padding: const EdgeInsets.all(3),
                                          decoration: BoxDecoration(
                                            color: selected
                                                ? palette.accentPrimary
                                                      .withValues(
                                                        alpha: isDark
                                                            ? 0.18
                                                            : 0.10,
                                                      )
                                                : Colors.transparent,
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                          ),
                                          child: Icon(
                                            option.icon,
                                            size: 14,
                                            color: selected
                                                ? palette.accentPrimary
                                                : palette.textTertiary,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(option.label),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ThemeModeOption {
  const _ThemeModeOption(this.mode, this.label, this.icon);

  final AppThemeMode mode;
  final String label;
  final IconData icon;
}
