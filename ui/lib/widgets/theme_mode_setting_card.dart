import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ui/theme/app_theme_controller.dart';
import 'package:ui/theme/app_theme_mode.dart';
import 'package:ui/widgets/omni_segmented_slider.dart';
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
        OmniSegmentedSlider<AppThemeMode>(
          key: const ValueKey('theme-mode-slider'),
          value: mode,
          keyPrefix: 'theme-mode-option',
          options: const [
            OmniSegmentedOption<AppThemeMode>(
              value: AppThemeMode.light,
              label: '浅色',
              icon: Icons.light_mode_rounded,
              id: 'light',
            ),
            OmniSegmentedOption<AppThemeMode>(
              value: AppThemeMode.dark,
              label: '深色',
              icon: Icons.dark_mode_rounded,
              id: 'dark',
            ),
            OmniSegmentedOption<AppThemeMode>(
              value: AppThemeMode.system,
              label: '系统',
              icon: Icons.brightness_auto_rounded,
              id: 'system',
            ),
          ],
          onChanged: (nextMode) {
            ref.read(appThemeModeProvider.notifier).setThemeMode(nextMode);
          },
        ),
      ],
    );
  }
}
