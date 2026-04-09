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
