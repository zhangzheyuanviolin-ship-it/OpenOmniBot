import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ui/features/my/pages/my/widgets/setting_section.dart';
import 'package:ui/features/my/pages/my/widgets/setting_tile.dart';
import 'package:ui/widgets/common_app_bar.dart';

enum ThemeOption { system, light, dark }

class ThemeColorPage extends StatefulWidget {
  const ThemeColorPage({Key? key}) : super(key: key);

  @override
  State<ThemeColorPage> createState() => _ThemeColorPageState();
}

class _ThemeColorPageState extends State<ThemeColorPage> {
  ThemeOption _selected = ThemeOption.system;

  @override
  void initState() {
    super.initState();
    _loadSelected();
  }

  Future<void> _loadSelected() async {
    final prefs = await SharedPreferences.getInstance();
    final str = prefs.getString('theme_option') ?? 'system';
    setState(() {
      switch (str) {
        case 'light':
          _selected = ThemeOption.light;
          break;
        case 'dark':
          _selected = ThemeOption.dark;
          break;
        default:
          _selected = ThemeOption.system;
      }
    });
  }

  Future<void> _saveSelected(ThemeOption option) async {
    final prefs = await SharedPreferences.getInstance();
    final val = option == ThemeOption.light
        ? 'light'
        : option == ThemeOption.dark
            ? 'dark'
            : 'system';
    await prefs.setString('theme_option', val);
    // TODO: 这里可以调用你的主题切换逻辑，如 Provider/Bloc/ThemeService 等
  }

  void _onSelect(ThemeOption option) {
    if (_selected == option) return;
    setState(() => _selected = option);
    _saveSelected(option);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = const Color(0xFFF7F7F7);

    return Scaffold(
      backgroundColor: bg,
      appBar: CommonAppBar(
        title: '主题色彩',
        primary: true,
        onBackPressed: () => Navigator.of(context).maybePop(),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          SettingSection(children: [
            SettingTile(
              title: '跟随系统',
              trailing: _selected == ThemeOption.system
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () => _onSelect(ThemeOption.system),
              showChevron: false,
            ),
            SettingTile(
              title: '浅色模式',
              trailing: _selected == ThemeOption.light
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () => _onSelect(ThemeOption.light),
              showChevron: false,
            ),
            SettingTile(
              title: '深色模式',
              trailing: _selected == ThemeOption.dark
                  ? const Icon(Icons.check, color: Colors.green)
                  : null,
              onTap: () => _onSelect(ThemeOption.dark),
              showChevron: false,
            ),
          ]),
        ],
      ),
    );
  }
}
