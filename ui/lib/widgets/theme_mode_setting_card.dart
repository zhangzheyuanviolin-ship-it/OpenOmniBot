import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui/theme/app_theme_controller.dart';
import 'package:ui/theme/app_theme_mode.dart';
import 'package:ui/theme/theme_context.dart';

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
    final palette = context.omniPalette;
    final mode = ref.watch(appThemeModeProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: palette.surfacePrimary,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: palette.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: palette.shadowColor.withValues(
              alpha: context.isDarkTheme ? 0.52 : 0.10,
            ),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: palette.textSecondary,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 14),
          _ThemeModeSlider(
            value: mode,
            onChanged: (nextMode) {
              ref.read(appThemeModeProvider.notifier).setThemeMode(nextMode);
            },
          ),
        ],
      ),
    );
  }
}

class _ThemeModeSlider extends StatelessWidget {
  const _ThemeModeSlider({required this.value, required this.onChanged});

  final AppThemeMode value;
  final ValueChanged<AppThemeMode> onChanged;

  static const List<(AppThemeMode, String)> _options = <(AppThemeMode, String)>[
    (AppThemeMode.light, '浅色'),
    (AppThemeMode.dark, '深色'),
    (AppThemeMode.system, '系统'),
  ];

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;
    final selectedIndex = _options.indexWhere((option) => option.$1 == value);

    return Container(
      key: const ValueKey('theme-mode-slider'),
      height: 52,
      decoration: BoxDecoration(
        color: palette.segmentTrack,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.borderSubtle),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const outerPadding = 4.0;
          final thumbWidth = (constraints.maxWidth - outerPadding * 2) / 3;
          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOutCubic,
                left: outerPadding + thumbWidth * selectedIndex,
                top: outerPadding,
                bottom: outerPadding,
                width: thumbWidth,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.segmentThumb,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: palette.borderStrong),
                    boxShadow: [
                      BoxShadow(
                        color: palette.shadowColor.withValues(
                          alpha: context.isDarkTheme ? 0.48 : 0.12,
                        ),
                        blurRadius: 18,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: _options
                    .map((option) {
                      final selected = option.$1 == value;
                      return Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            key: ValueKey(
                              'theme-mode-option-${option.$1.name}',
                            ),
                            borderRadius: BorderRadius.circular(14),
                            onTap: () => onChanged(option.$1),
                            child: Center(
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 180),
                                curve: Curves.easeInOutCubic,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: selected
                                      ? palette.textPrimary
                                      : palette.textSecondary,
                                ),
                                child: Text(option.$2),
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
    );
  }
}
