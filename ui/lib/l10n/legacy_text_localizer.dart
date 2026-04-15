import 'dart:ui';

import 'package:ui/services/storage_service.dart';

typedef _TextRewriter = String Function(RegExpMatch match);

class LegacyTextLocalizer {
  static final Map<String, String> _exactEn = <String, String>{
    '设置': 'Settings',
    '外观设置': 'Appearance',
    '主题模式': 'Theme Mode',
    '本机服务': 'Local Service',
    '地址': 'Address',
    'Token': 'Token',
    '未生成': 'Not generated',
    '复制地址': 'Copy Address',
    '复制 Token': 'Copy Token',
    '刷新 Token': 'Refresh Token',
    '加载中...': 'Loading...',
    '模型与记忆': 'Models & Memory',
    '服务与环境': 'Services & Environment',
    '体验与外观': 'Experience & Appearance',
    '权限与信息': 'Permissions & Info',
    '模型提供商': 'Model Providers',
    '场景模型配置': 'Scene Model Config',
    '本地模型服务': 'Local Model Service',
    'Workspace 记忆配置': 'Workspace Memory',
    'MCP 工具': 'MCP Tools',
    'Alpine 环境': 'Alpine Environment',
    '后台隐藏': 'Hide from Recents',
    '闹钟设置': 'Alarm Settings',
    '振动反馈': 'Vibration Feedback',
    '任务完成后自动回聊天': 'Return to Chat After Tasks',
    '陪伴权限授权': 'Companion App Permissions',
    '关于小万': 'About Omnibot',
    '背景来源': 'Background Source',
    '效果预览': 'Preview',
    '效果调整': 'Adjustments',
    '聊天': 'Chat',
    '工作区': 'Workspace',
    '启用背景图': 'Enable background image',
    '本地图片': 'Local Image',
    '图片直链': 'Image URL',
    '选择图片': 'Choose Image',
    '重新选择': 'Choose Again',
    '背景柔化': 'Background Blur',
    '蒙版强度': 'Overlay Strength',
    '蒙版明暗': 'Overlay Brightness',
    '聊天文本大小': 'Chat Text Size',
    '聊天文本颜色': 'Chat Text Color',
    '自动': 'Auto',
    '自定义色号': 'Custom Color',
    '关闭浏览器窗口': 'Close browser window',
    '当前平台暂不支持浏览器工具视图': 'Browser tool view is not supported on this platform yet',
    '无障碍权限': 'Accessibility',
    '悬浮窗权限': 'Overlay',
    '应用列表读取权限': 'Installed Apps Access',
    '公共文件访问': 'Public Storage Access',
    '正在调用工具': 'Calling tool',
    '暂时无法生成回复，请重试。': "I can't generate a reply right now. Please try again.",
    '[只显示最近的部分终端输出]\n': '[Only the most recent terminal output is shown]\n',
    '搜索全部对话': 'Search',
    '清空搜索': 'Clear search',
    '抱歉，刚刚网络开小差了。再发一次试试？':
        'Sorry, the network stumbled just now. Please try sending it again.',
    '小万忙不过来了，等会儿再试试吧':
        'Omnibot is busy right now. Please try again in a moment.',
    '设置后台隐藏失败': 'Failed to update hide-from-recents',
    '设置失败': 'Failed to save settings',
    'MCP 已关闭': 'MCP disabled',
    'MCP 开关失败': 'Failed to toggle MCP',
    '已复制访问地址': 'Address copied',
    '已复制 Token': 'Token copied',
    '已刷新 Token': 'Token refreshed',
    '刷新 Token 失败': 'Failed to refresh token',
    '请求应用列表权限失败': 'Failed to request installed apps permission',
    '请输入有效的 http(s) 图片直链': 'Enter a valid http(s) image URL',
    '请输入 #RRGGBB 或 #AARRGGBB': 'Enter #RRGGBB or #AARRGGBB',
    '色号格式不正确': 'Invalid color code',
    '请先选择本地图片': 'Select a local image first',
    '本地图片不存在，请重新选择':
        'The local image no longer exists. Please choose it again',
    '尚未选择本地图片': 'No local image selected yet',
    '正在自动保存…': 'Saving changes…',
    '更改会自动保存': 'Changes are saved automatically',
    '正在调用内嵌 Alpine 终端执行命令':
        'Running a command in the embedded Alpine terminal',
    '正在执行内嵌 Alpine 终端命令':
        'Executing a command in the embedded Alpine terminal',
    '终端输出更新中': 'Updating terminal output',
  };

  static final List<(RegExp, _TextRewriter)> _regexEn = <(RegExp, _TextRewriter)>[
    (
      RegExp(r'^MCP 已开启：(.+)$'),
      (match) => 'MCP enabled: ${match.group(1)!}',
    ),
    (
      RegExp(r'^任务完成后将自动返回聊天$'),
      (_) => 'The app will return to chat after tasks finish',
    ),
    (
      RegExp(r'^任务完成后将停留在当前页面$'),
      (_) => 'The app will stay on the current page after tasks finish',
    ),
    (
      RegExp(r'^选择图片失败：(.+)$'),
      (match) => 'Failed to pick image: ${match.group(1)!}',
    ),
    (
      RegExp(r'^自动保存失败：(.+)$'),
      (match) => 'Auto-save failed: ${match.group(1)!}',
    ),
    (
      RegExp(r'^暂时无法生成回复，请重试。(.*)$'),
      (match) {
        final extra = match.group(1)?.trim() ?? '';
        if (extra.isEmpty) {
          return "I can't generate a reply right now. Please try again.";
        }
        return "I can't generate a reply right now. Please try again. $extra";
      },
    ),
    (
      RegExp(r'^执行任务前，请先开启：(.+)$'),
      (match) => 'Enable these permissions before running tasks: ${match.group(1)!}',
    ),
    (
      RegExp(r'^执行任务前需要先开启权限$'),
      (_) => 'Permissions must be enabled before running tasks',
    ),
    (
      RegExp(r'^用户: (.+)\n$'),
      (match) => 'User: ${match.group(1)!}\n',
    ),
  ];

  static Locale get _resolvedLocale => StorageService.getResolvedLocale();

  static bool get isEnglish => _resolvedLocale.languageCode == 'en';

  static String localize(String text, {Locale? locale}) {
    final targetLocale = locale ?? _resolvedLocale;
    if (targetLocale.languageCode != 'en') {
      return text;
    }
    final exact = _exactEn[text];
    if (exact != null) {
      return exact;
    }
    for (final (pattern, rewrite) in _regexEn) {
      final match = pattern.firstMatch(text);
      if (match != null) {
        return rewrite(match);
      }
    }
    return text;
  }
}
