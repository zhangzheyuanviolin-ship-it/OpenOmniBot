import 'dart:ui';

import 'package:ui/services/storage_service.dart';

typedef _TextRewriter = String Function(RegExpMatch match);

class LegacyTextLocalizer {
  static Locale? _activeLocale;

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
    '当前平台暂不支持浏览器工具视图':
        'Browser tool view is not supported on this platform yet',
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
    '本地图片不存在，请重新选择': 'The local image no longer exists. Please choose it again',
    '尚未选择本地图片': 'No local image selected yet',
    '正在自动保存…': 'Saving changes…',
    '更改会自动保存': 'Changes are saved automatically',
    '正在调用内嵌 Alpine 终端执行命令': 'Running a command in the embedded Alpine terminal',
    '正在执行内嵌 Alpine 终端命令': 'Executing a command in the embedded Alpine terminal',
    '终端输出更新中': 'Updating terminal output',
    '🎉Hi，我是小万，我会做很多事，让我展示给你下！':
        '🎉Hi, I\'m Omnibot. I can do many things, let me show you!',
    '换一换': 'Shuffle',
    '小万正在思考...': 'Omnibot is thinking...',
    '总结中': 'Summarizing',
    '总结如下': 'Summary',
    '全选': 'Select all',
    '复制': 'Copy',
    '取消': 'Cancel',
    '确认': 'Confirm',
    '确定': 'OK',
    '请稍候...': 'Please wait...',
    '保存': 'Save',
    '未设置模型': 'No model set',
    '发现新版本': 'New version available',
    '打开终端': 'Open terminal',
    '管理终端环境变量': 'Manage terminal environment variables',
    '打开当前会话浏览器': 'Open browser for current session',
    '当前会话还没有可用的浏览器会话': 'No browser session available',
    '纯聊天': 'Chat Only',
    '普通': 'Normal',
    '今天': 'Today',
    '昨天': 'Yesterday',
    '执行中': 'Executing',
    '执行成功': 'Succeeded',
    '执行失败': 'Failed',
    '已取消': 'Cancelled',
    '等待执行': 'Pending',
    '已暂停': 'Paused',
    '系统': 'System',
    '总结': 'Summary',
    '未知': 'Unknown',
    '识图': 'Image Recognition',
    '未知类型': 'Unknown type',
    '正在回复...': 'Replying...',
    '永不': 'Never',
    '每日': 'Daily',
    '每周': 'Weekly',
    '每月': 'Monthly',
    '每年': 'Yearly',
    '时间': 'Time',
    '日期': 'Date',
    '重复': 'Repeat',
    '任务选项': 'Task options',
    '请选择一个任务': 'Please select a task',
    '请选择你想执行的任务': 'Please select a task to execute',
    '请选择一个应用程序': 'Please select an application',
    '未设置': 'Not set',
    '已过期': 'Expired',
    '即将执行': 'Starting soon',
    '执行': 'Execute',
    '任务': 'Task',
    '好，我来帮你完成': 'OK, I\'ll help you complete it',
    '用户操作': 'User action',
    '短期记忆': 'Short-term Memory',
    '长期记忆': 'Long-term Memory',
    '删除': 'Delete',
    '全部': 'All',
    '删除成功': 'Deleted',
    '删除失败': 'Failed to delete',
    '保存失败': 'Save failed',
    '修改失败': 'Modify failed',
    '修改成功': 'Modified successfully',
    '桌面': 'Desktop',
    '内存中': 'Local Memory',
    '云内存中': 'Cloud Memory',
    '记忆中心': 'Memory Center',
    '技能仓库': 'Skill Store',
    '轨迹': 'Trajectory',
    '聊天记录': 'Chat History',
    '归档对话': 'Archived Conversations',
    '执行历史': 'Execution History',
    '本地模型': 'Local Models',
    '新增': 'Add',
    '安装': 'Install',
    '未安装': 'Not installed',
    '已安装': 'Installed',
    '已禁用': 'Disabled',
    '启用中': 'Enabled',
    '内置': 'Built-in',
    '用户': 'User',
    '保存成功': 'Saved successfully',
    '记忆': 'Memory',
    '记忆能力': 'Memory Capability',
    '文档内容': 'Document Content',
    '权限说明': 'Permission Notes',
    '授权应用': 'Authorized Apps',
    '编辑': 'Edit',
    '创建': 'Create',
    '任务名称': 'Task Name',
    '启动命令': 'Start Command',
    '工作目录': 'Working Directory',
    '应用权限授权': 'App Permission Authorization',
    '存储占用': 'Storage Usage',
    '清理': 'Clean',
    '重新分析': 'Reanalyze',
    '加载失败': 'Failed to load',
    '场景映射': 'Scene Mapping',
    '已安装模型': 'Installed Models',
    '自启动任务': 'Boot Tasks',
    '暂无': 'None',
    '暂无记忆': 'No memories',
    '暂无执行记录': 'No execution records',
    '暂无执行历史': 'No execution history',
    '暂无可配置场景': 'No configurable scenes',
    '暂无已接入的技能': 'No skills available',
    '暂无归档对话': 'No archived conversations',
    '暂无聊天记录': 'No conversations yet',
    '还没有短期记忆': 'No short-term memory yet',
    '还没有可用的本地模型': 'No local models available',
    '确定删除吗？': 'Are you sure you want to delete?',
    '删除后该内容将不可找回': 'This action cannot be undone',
    '立即整理一次': 'Rollup now',
    '夜间记忆整理（22:00）': 'Nightly Memory Rollup (22:00)',
    '陪伴权限管理': 'Companion Permission Management',
    '最近执行': 'Last executed',
    '暂无总结内容': 'No summary content',
    '检查更新失败': 'Failed to check for updates',
    '已是最新版': 'Already up to date',
    '检查 GitHub Release 获取最新版本': 'Checking GitHub Release for the latest version',
    '检查中...': 'Checking...',
    '查看新版本': 'View new version',
    '检查更新': 'Check for updates',
    '请求日志': 'Request logs',
    '保存中...': 'Saving...',
    '未选择文件': 'No file selected',
    '远程地址': 'Remote URL',
    '后台运行权限': 'Background run permission',
    '应用列表读取': 'Installed apps access',
    '无障碍辅助权限': 'Accessibility permission',
    '已开启': 'Enabled',
    '去开启': 'Enable',
    '清除缓存': 'Clear cache',
  };

  static final List<(RegExp, _TextRewriter)>
  _regexEn = <(RegExp, _TextRewriter)>[
    (RegExp(r'^MCP 已开启：(.+)$'), (match) => 'MCP enabled: ${match.group(1)!}'),
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
      (match) =>
          'Enable these permissions before running tasks: ${match.group(1)!}',
    ),
    (
      RegExp(r'^执行任务前需要先开启权限$'),
      (_) => 'Permissions must be enabled before running tasks',
    ),
    (RegExp(r'^用户: (.+)\n$'), (match) => 'User: ${match.group(1)!}\n'),
  ];

  static void setResolvedLocale(Locale locale) {
    _activeLocale = locale;
  }

  static void clearResolvedLocale() {
    _activeLocale = null;
  }

  static Locale get _resolvedLocale {
    final activeLocale = _activeLocale;
    if (activeLocale != null) {
      return activeLocale;
    }
    try {
      return StorageService.getResolvedLocale();
    } catch (_) {
      return PlatformDispatcher.instance.locale;
    }
  }

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
