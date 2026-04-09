import 'package:flutter/material.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/widgets/common_app_bar.dart';
import 'package:ui/widgets/theme_mode_setting_card.dart';

class ThemeColorPage extends StatelessWidget {
  const ThemeColorPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final palette = context.omniPalette;

    return Scaffold(
      backgroundColor: palette.pageBackground,
      appBar: const CommonAppBar(title: '主题模式', primary: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [const ThemeModeSettingCard()],
      ),
    );
  }
}
