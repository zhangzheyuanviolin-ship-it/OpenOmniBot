import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/theme/theme_context.dart';

const String _kHomeShortcutMemoryIconSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
    'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" '
    'stroke-linecap="round" stroke-linejoin="round">'
    '<path d="M12 18V5"/>'
    '<path d="M15 13a4.17 4.17 0 0 1-3-4 4.17 4.17 0 0 1-3 4"/>'
    '<path d="M17.598 6.5A3 3 0 1 0 12 5a3 3 0 1 0-5.598 1.5"/>'
    '<path d="M17.997 5.125a4 4 0 0 1 2.526 5.77"/>'
    '<path d="M18 18a4 4 0 0 0 2-7.464"/>'
    '<path d="M19.967 17.483A4 4 0 1 1 12 18a4 4 0 1 1-7.967-.517"/>'
    '<path d="M6 18a4 4 0 0 1-2-7.464"/>'
    '<path d="M6.003 5.125a4 4 0 0 0-2.526 5.77"/>'
    '</svg>';

const String _kHomeShortcutSkillStoreIconSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
    'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" '
    'stroke-linecap="round" stroke-linejoin="round">'
    '<path d="M22 7.7c0-.6-.4-1.2-.8-1.5l-6.3-3.9a1.72 1.72 0 0 0-1.7 0l-10.3 '
    '6c-.5.2-.9.8-.9 1.4v6.6c0 .5.4 1.2.8 1.5l6.3 3.9a1.72 1.72 0 0 0 1.7 0'
    'l10.3-6c.5-.3.9-1 .9-1.5Z"/>'
    '<path d="M10 21.9V14L2.1 9.1"/>'
    '<path d="m10 14 11.9-6.9"/>'
    '<path d="M14 19.8v-8.1"/>'
    '<path d="M18 17.5V9.4"/>'
    '</svg>';

const String _kHomeShortcutTaskHistoryIconSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
    'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" '
    'stroke-linecap="round" stroke-linejoin="round">'
    '<path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/>'
    '<path d="M3 3v5h5"/>'
    '<path d="M12 7v5l4 2"/>'
    '</svg>';

enum HomeShortcutDestination {
  settings,
  memoryCenter,
  skillStore,
  executionHistory,
  scheduledTasks,
}

class HomeShortcutSpec {
  const HomeShortcutSpec({
    required this.destination,
    required this.label,
    required this.route,
    this.assetPath,
    this.svgString,
  }) : assert(assetPath != null || svgString != null);

  final HomeShortcutDestination destination;
  final String label;
  final String route;
  final String? assetPath;
  final String? svgString;
}

const List<HomeShortcutSpec> kHomeFooterShortcutSpecs = [
  HomeShortcutSpec(
    destination: HomeShortcutDestination.settings,
    label: '设置',
    route: '/home/settings',
    assetPath: 'assets/home/setting_icon.svg',
  ),
  HomeShortcutSpec(
    destination: HomeShortcutDestination.memoryCenter,
    label: '记忆中心',
    route: '/memory/memory_center_page',
    svgString: _kHomeShortcutMemoryIconSvg,
  ),
  HomeShortcutSpec(
    destination: HomeShortcutDestination.skillStore,
    label: '技能仓库',
    route: '/home/skill_store',
    svgString: _kHomeShortcutSkillStoreIconSvg,
  ),
  HomeShortcutSpec(
    destination: HomeShortcutDestination.executionHistory,
    label: '任务记录',
    route: '/task/execution_history',
    svgString: _kHomeShortcutTaskHistoryIconSvg,
  ),
  HomeShortcutSpec(
    destination: HomeShortcutDestination.scheduledTasks,
    label: '定时',
    route: '/task/scheduled_tasks',
    assetPath: 'assets/common/schedule_icon.svg',
  ),
];

List<HomeShortcutSpec> buildIosChatMenuShortcutSpecs() {
  return kHomeFooterShortcutSpecs
      .where((spec) => spec.destination != HomeShortcutDestination.settings)
      .toList(growable: false);
}

Widget buildHomeShortcutIcon(
  BuildContext context,
  HomeShortcutSpec spec, {
  double size = 18,
  Color? color,
}) {
  final resolvedColor =
      color ??
      (context.isDarkTheme ? context.omniPalette.textPrimary : AppColors.text);
  if (spec.assetPath != null) {
    return SvgPicture.asset(
      spec.assetPath!,
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(resolvedColor, BlendMode.srcIn),
    );
  }
  return SvgPicture.string(
    spec.svgString!,
    width: size,
    height: size,
    colorFilter: ColorFilter.mode(resolvedColor, BlendMode.srcIn),
  );
}
