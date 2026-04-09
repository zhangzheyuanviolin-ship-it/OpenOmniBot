import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ui/core/router/go_router_manager.dart';
import 'package:ui/features/home/widgets/conversation_slidable.dart';
import 'package:ui/models/conversation_model.dart';
import 'package:ui/models/conversation_thread_target.dart';
import 'package:ui/services/assists_core_service.dart';
import 'package:ui/services/conversation_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/theme/theme_context.dart';
import 'package:ui/utils/cache_util.dart';
import 'package:ui/utils/ui.dart';

const String _kDrawerMemoryIconSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
    'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" '
    'stroke-linecap="round" stroke-linejoin="round" '
    'class="lucide lucide-brain-icon lucide-brain">'
    '<path d="M12 18V5"/>'
    '<path d="M15 13a4.17 4.17 0 0 1-3-4 4.17 4.17 0 0 1-3 4"/>'
    '<path d="M17.598 6.5A3 3 0 1 0 12 5a3 3 0 1 0-5.598 1.5"/>'
    '<path d="M17.997 5.125a4 4 0 0 1 2.526 5.77"/>'
    '<path d="M18 18a4 4 0 0 0 2-7.464"/>'
    '<path d="M19.967 17.483A4 4 0 1 1 12 18a4 4 0 1 1-7.967-.517"/>'
    '<path d="M6 18a4 4 0 0 1-2-7.464"/>'
    '<path d="M6.003 5.125a4 4 0 0 0-2.526 5.77"/>'
    '</svg>';

const String _kDrawerSkillStoreIconSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
    'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" '
    'stroke-linecap="round" stroke-linejoin="round" '
    'class="lucide lucide-container-icon lucide-container">'
    '<path d="M22 7.7c0-.6-.4-1.2-.8-1.5l-6.3-3.9a1.72 1.72 0 0 0-1.7 0l-10.3 '
    '6c-.5.2-.9.8-.9 1.4v6.6c0 .5.4 1.2.8 1.5l6.3 3.9a1.72 1.72 0 0 0 1.7 0'
    'l10.3-6c.5-.3.9-1 .9-1.5Z"/>'
    '<path d="M10 21.9V14L2.1 9.1"/>'
    '<path d="m10 14 11.9-6.9"/>'
    '<path d="M14 19.8v-8.1"/>'
    '<path d="M18 17.5V9.4"/>'
    '</svg>';

const String _kDrawerTaskHistoryIconSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" '
    'viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" '
    'stroke-linecap="round" stroke-linejoin="round" '
    'class="lucide lucide-history-icon lucide-history">'
    '<path d="M3 12a9 9 0 1 0 9-9 9.75 9.75 0 0 0-6.74 2.74L3 8"/>'
    '<path d="M3 3v5h5"/>'
    '<path d="M12 7v5l4 2"/>'
    '</svg>';

/// 首页侧边栏
class HomeDrawer extends ConsumerStatefulWidget {
  const HomeDrawer({
    super.key,
    this.memoryCount,
    this.newConversationMode = ConversationMode.normal,
    this.embedded = false,
    this.closeOnNavigate = true,
    this.onThreadTargetSelected,
  });

  final int? memoryCount;
  final ConversationMode newConversationMode;
  final bool embedded;
  final bool closeOnNavigate;
  final ValueChanged<ConversationThreadTarget>? onThreadTargetSelected;

  @override
  ConsumerState<HomeDrawer> createState() => HomeDrawerState();
}

class HomeDrawerState extends ConsumerState<HomeDrawer> {
  static const double _conversationActionIconSize = 18;
  static const BorderRadius _drawerTrailingActionRadius = BorderRadius.only(
    topRight: Radius.circular(4),
    bottomRight: Radius.circular(4),
  );

  List<ConversationModel> conversations = [];
  final Set<String> _busyConversationKeys = <String>{};
  bool isLoadingConversations = true;
  StreamSubscription<Map<String, dynamic>>?
  _conversationListChangedSubscription;

  Map<String, String> _getGreetingByTime() {
    final hour = DateTime.now().hour;

    if (hour >= 2 && hour < 6) {
      final greetings = [
        {'title': '凌晨啦', 'subtitle': '还没休息吗？'},
        {'title': '天还没亮', 'subtitle': '早起的你辛苦啦～'},
        {'title': '深夜的时光很静', 'subtitle': '但也要记得给身体留些休息呀～'},
      ];
      return greetings[DateTime.now().minute % greetings.length];
    }

    if (hour >= 6 && hour < 8) {
      final greetings = [
        {'title': '早安！', 'subtitle': '开启元气一天'},
        {'title': '早呀！', 'subtitle': '新的一天开始啦'},
      ];
      return greetings[DateTime.now().minute % greetings.length];
    }

    if (hour >= 8 && hour < 12) {
      final greetings = [
        {'title': '上午好！', 'subtitle': '再忙也别忘了活动下肩膀'},
        {'title': '上午的效率超棒！', 'subtitle': '继续加油'},
      ];
      return greetings[DateTime.now().minute % greetings.length];
    }

    if (hour >= 12 && hour < 14) {
      final greetings = [
        {'title': '午饭时间到！', 'subtitle': '好好吃饭，别凑合'},
        {'title': '午安～', 'subtitle': '吃完记得歇会儿'},
        {'title': '午餐不知道吃什么？', 'subtitle': '让小万帮你推荐吧！'},
      ];
      return greetings[DateTime.now().minute % greetings.length];
    }

    if (hour >= 14 && hour < 18) {
      final greetings = [
        {'title': '喝杯茶提提神', 'subtitle': '剩下的任务也能轻松搞定～'},
        {'title': '工作间隙看看窗外', 'subtitle': '让眼睛歇一歇～'},
      ];
      return greetings[DateTime.now().minute % greetings.length];
    }

    if (hour >= 18 && hour < 20) {
      final greetings = [
        {'title': '回家路上慢点', 'subtitle': '今晚好好放松～'},
        {'title': '傍晚了', 'subtitle': '吹来的晚风很舒服呀！～'},
        {'title': '忙了一天', 'subtitle': '吃顿好的犒劳自己～'},
      ];
      return greetings[DateTime.now().minute % greetings.length];
    }

    if (hour >= 20 && hour < 22) {
      final greetings = [
        {'title': '晚上好！', 'subtitle': '享受属于自己的时光吧～'},
        {'title': '夜色渐浓', 'subtitle': '准备下早点休息啦～'},
        {'title': '该休息了', 'subtitle': '让小万帮你定个闹钟吧！'},
      ];
      return greetings[DateTime.now().minute % greetings.length];
    }

    final greetings = [
      {'title': '放下手机早点睡', 'subtitle': '明天才能元气满满～'},
      {'title': '深夜了', 'subtitle': '好好和今天说晚安～'},
    ];
    return greetings[DateTime.now().minute % greetings.length];
  }

  @override
  void initState() {
    super.initState();
    _conversationListChangedSubscription = AssistsMessageService
        .conversationListChangedStream
        .listen((_) {
          unawaited(_loadConversations());
        });
    _loadConversations();
  }

  @override
  void dispose() {
    _conversationListChangedSubscription?.cancel();
    super.dispose();
  }

  void reloadConversations() {
    _loadConversations();
  }

  Future<void> _loadConversations() async {
    debugPrint('[HomeDrawer] 开始加载聊天记录...');
    setState(() {
      isLoadingConversations = true;
    });

    try {
      final loadedConversations =
          await ConversationService.getAllConversations();
      debugPrint('[HomeDrawer] 加载到 ${loadedConversations.length} 条聊天记录');
      if (!mounted) return;
      setState(() {
        conversations = loadedConversations;
        isLoadingConversations = false;
      });
    } catch (e) {
      debugPrint('[HomeDrawer] 加载聊天记录出错: $e');
      if (!mounted) return;
      setState(() {
        isLoadingConversations = false;
      });
    }
  }

  bool get _shouldCloseOnNavigate => widget.closeOnNavigate && !widget.embedded;

  Color get _drawerBackgroundColor {
    if (!context.isDarkTheme) {
      return AppColors.background;
    }
    return context.omniPalette.pageBackground;
  }

  Color get _drawerTextColor {
    if (!context.isDarkTheme) {
      return AppColors.text;
    }
    return context.omniPalette.textPrimary;
  }

  Color get _drawerSecondaryTextColor {
    if (!context.isDarkTheme) {
      return AppColors.text.withValues(alpha: 0.4);
    }
    return context.omniPalette.textSecondary;
  }

  void _maybeCloseDrawer() {
    if (!_shouldCloseOnNavigate || !Navigator.of(context).canPop()) {
      return;
    }
    Navigator.pop(context);
  }

  void _openThreadTarget(ConversationThreadTarget target) {
    if (widget.embedded && widget.onThreadTargetSelected != null) {
      widget.onThreadTargetSelected!(target);
      return;
    }
    _maybeCloseDrawer();
    GoRouterManager.pushReplacement('/home/chat', extra: target);
  }

  void _navigateTo(String route) {
    _maybeCloseDrawer();
    GoRouterManager.push(route);
  }

  void _openNewConversation() {
    _openThreadTarget(
      ConversationThreadTarget.newConversation(
        mode: widget.newConversationMode,
        requestKey: DateTime.now().microsecondsSinceEpoch.toString(),
      ),
    );
  }

  Future<void> _triggerDeleteHaptic() async {
    try {
      final enabled = await CacheUtil.getBool(
        'app_vibrate',
        defaultValue: true,
      );
      if (!enabled) {
        return;
      }
      await HapticFeedback.mediumImpact();
    } catch (error) {
      debugPrint('[HomeDrawer] failed to trigger delete haptic: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final backgroundColor = _drawerBackgroundColor;
    final content = ColoredBox(
      color: backgroundColor,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            _buildUserHeader(),
            const SizedBox(height: 20),
            Expanded(child: _buildConversationSection()),
            const SizedBox(height: 12),
            _buildFooterShortcutBar(),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (widget.embedded) {
      return content;
    }
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.8,
      backgroundColor: backgroundColor,
      child: content,
    );
  }

  Widget _buildUserHeader() {
    final greeting = _getGreetingByTime();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            greeting['title'] ?? '你好！',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: _drawerTextColor,
              height: 1.5,
            ),
          ),
          Text(
            greeting['subtitle'] ?? '欢迎使用小万',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: _drawerTextColor,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConversationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _buildSectionActionButton(
                iconPath: 'assets/home/archive_icon.svg',
                tooltip: '归档对话',
                onTap: () => _navigateTo('/home/archived_conversations'),
              ),
              const SizedBox(width: 10),
              _buildSectionActionButton(
                iconPath: 'assets/home/chat_add_icon.svg',
                tooltip: '新对话',
                onTap: _openNewConversation,
                isPrimary: true,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: isLoadingConversations
                ? Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          _drawerTextColor,
                        ),
                      ),
                    ),
                  )
                : conversations.isEmpty
                ? _buildEmptyConversation()
                : SlidableAutoCloseBehavior(
                    child: ListView(
                      padding: EdgeInsets.zero,
                      children: _buildConversationTimelineChildren(),
                    ),
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyConversation() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '暂无聊天记录',
              style: TextStyle(fontSize: 14, color: _drawerSecondaryTextColor),
            ),
            const SizedBox(height: 12),
            GestureDetector(
              onTap: _openNewConversation,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: context.omniPalette.accentPrimary,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '开始对话',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildConversationTimelineChildren() {
    final sections = _buildConversationSections();
    final children = <Widget>[];
    for (int sectionIndex = 0; sectionIndex < sections.length; sectionIndex++) {
      final section = sections[sectionIndex];
      if (sectionIndex > 0) {
        children.add(const SizedBox(height: 14));
      }
      children.add(_buildConversationSectionHeader(section.label));
      children.add(const SizedBox(height: 4));
      for (
        int itemIndex = 0;
        itemIndex < section.conversations.length;
        itemIndex++
      ) {
        children.add(
          _buildSwipeConversationItem(
            section.conversations[itemIndex],
            showDivider: itemIndex != section.conversations.length - 1,
          ),
        );
      }
    }
    return children;
  }

  List<_ConversationSection> _buildConversationSections() {
    final sections = <_ConversationSection>[];
    for (final conversation in conversations) {
      final label = conversation.timeDisplay;
      if (sections.isEmpty || sections.last.label != label) {
        sections.add(
          _ConversationSection(
            label: label,
            conversations: <ConversationModel>[conversation],
          ),
        );
      } else {
        sections.last.conversations.add(conversation);
      }
    }
    return sections;
  }

  Widget _buildConversationSectionHeader(String label) {
    final palette = context.omniPalette;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
      child: Row(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.6,
              color: palette.textTertiary,
              fontFamily: 'PingFang SC',
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 1,
              color: palette.borderSubtle.withValues(
                alpha: context.isDarkTheme ? 0.56 : 0.8,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionActionButton({
    required String iconPath,
    required String tooltip,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    final palette = context.omniPalette;
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: isPrimary
                ? context.omniPalette.accentPrimary
                : context.isDarkTheme
                ? palette.surfaceSecondary
                : Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              if (!isPrimary && !context.isDarkTheme)
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
            ],
          ),
          padding: const EdgeInsets.all(8),
          child: SvgPicture.asset(
            iconPath,
            width: 16,
            height: 16,
            colorFilter: ColorFilter.mode(
              isPrimary
                  ? Theme.of(context).colorScheme.onPrimary
                  : _drawerTextColor,
              BlendMode.srcIn,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooterShortcutBar() {
    final items = <_DrawerShortcutAction>[
      _DrawerShortcutAction(
        label: '设置',
        assetPath: 'assets/home/setting_icon.svg',
        onTap: () => _navigateTo('/home/settings'),
      ),
      _DrawerShortcutAction(
        label: '记忆中心',
        svgString: _kDrawerMemoryIconSvg,
        onTap: () => _navigateTo('/memory/memory_center_page'),
      ),
      _DrawerShortcutAction(
        label: '技能仓库',
        svgString: _kDrawerSkillStoreIconSvg,
        onTap: () => _navigateTo('/home/skill_store'),
      ),
      _DrawerShortcutAction(
        label: '任务记录',
        svgString: _kDrawerTaskHistoryIconSvg,
        onTap: () => _navigateTo('/task/execution_history'),
      ),
      _DrawerShortcutAction(
        label: '定时',
        assetPath: 'assets/common/schedule_icon.svg',
        onTap: () => _navigateTo('/task/scheduled_tasks'),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: items
            .map((item) => Expanded(child: _buildFooterShortcutButton(item)))
            .toList(growable: false),
      ),
    );
  }

  Widget _buildFooterShortcutButton(_DrawerShortcutAction item) {
    final palette = context.omniPalette;
    final circleColor = context.isDarkTheme
        ? palette.surfaceSecondary
        : Colors.white;
    final iconColor = context.isDarkTheme
        ? palette.textPrimary
        : AppColors.text;
    final icon = item.assetPath != null
        ? SvgPicture.asset(
            item.assetPath!,
            width: 18,
            height: 18,
            colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
          )
        : SvgPicture.string(
            item.svgString!,
            width: 18,
            height: 18,
            colorFilter: ColorFilter.mode(iconColor, BlendMode.srcIn),
          );

    return Tooltip(
      message: item.label,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: item.onTap,
          borderRadius: BorderRadius.circular(24),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Center(
              child: Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: circleColor,
                  shape: BoxShape.circle,
                  boxShadow: context.isDarkTheme
                      ? const []
                      : [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 10,
                            offset: const Offset(0, 3),
                          ),
                        ],
                ),
                alignment: Alignment.center,
                child: icon,
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _openConversationFromDrawer(ConversationModel conversation) {
    if (_busyConversationKeys.contains(conversation.threadKey)) {
      return;
    }
    _openThreadTarget(
      ConversationThreadTarget.existing(
        conversationId: conversation.id,
        mode: conversation.mode,
      ),
    );
  }

  Future<void> _deleteConversation(ConversationModel conversation) async {
    if (_busyConversationKeys.contains(conversation.threadKey)) {
      return;
    }

    final originalIndex = conversations.indexWhere(
      (item) => item.id == conversation.id,
    );
    if (originalIndex < 0) {
      return;
    }

    setState(() {
      _busyConversationKeys.add(conversation.threadKey);
      conversations = List<ConversationModel>.from(conversations)
        ..removeAt(originalIndex);
    });

    final deleted = await ConversationService.deleteConversation(
      conversation.id,
      mode: conversation.mode,
    );
    if (!mounted) {
      return;
    }
    if (deleted) {
      unawaited(_triggerDeleteHaptic());
    }

    setState(() {
      _busyConversationKeys.remove(conversation.threadKey);
      if (!deleted) {
        final restoredIndex = originalIndex <= conversations.length
            ? originalIndex
            : conversations.length;
        conversations = List<ConversationModel>.from(conversations)
          ..insert(restoredIndex, conversation);
      }
    });

    showToast(
      deleted ? '已删除' : '删除失败',
      type: deleted ? ToastType.success : ToastType.error,
    );
  }

  Future<void> _archiveConversation(ConversationModel conversation) async {
    if (_busyConversationKeys.contains(conversation.threadKey)) {
      return;
    }

    final originalIndex = conversations.indexWhere(
      (item) => item.id == conversation.id,
    );
    if (originalIndex < 0) {
      return;
    }

    setState(() {
      _busyConversationKeys.add(conversation.threadKey);
      conversations = List<ConversationModel>.from(conversations)
        ..removeAt(originalIndex);
    });

    final archived = await ConversationService.archiveConversation(
      conversation,
    );
    if (!mounted) {
      return;
    }

    setState(() {
      _busyConversationKeys.remove(conversation.threadKey);
      if (!archived) {
        final restoredIndex = originalIndex <= conversations.length
            ? originalIndex
            : conversations.length;
        conversations = List<ConversationModel>.from(conversations)
          ..insert(restoredIndex, conversation);
      }
    });

    showToast(
      archived ? '已归档' : '归档失败',
      type: archived ? ToastType.success : ToastType.error,
    );
  }

  List<ConversationSlideAction> _buildDrawerActions(
    ConversationModel conversation,
  ) {
    return [
      ConversationSlideAction(
        onPressed: () => _deleteConversation(conversation),
        backgroundColor: AppColors.alertRed,
        child: Center(
          child: SvgPicture.asset(
            'assets/memory/memory_delete.svg',
            width: _conversationActionIconSize,
            height: _conversationActionIconSize,
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          ),
        ),
      ),
      ConversationSlideAction(
        onPressed: () => _archiveConversation(conversation),
        backgroundColor: context.isDarkTheme
            ? Color.lerp(
                context.omniPalette.surfaceElevated,
                context.omniPalette.accentPrimary,
                0.3,
              )!
            : AppColors.buttonPrimary,
        borderRadius: _drawerTrailingActionRadius,
        child: Center(
          child: SvgPicture.asset(
            'assets/home/archive_icon.svg',
            width: _conversationActionIconSize,
            height: _conversationActionIconSize,
            colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
          ),
        ),
      ),
    ];
  }

  String _resolveConversationTitle(ConversationModel conversation) {
    final title = conversation.title.trim();
    if (title.isNotEmpty) {
      return title;
    }
    final summary = (conversation.summary ?? '').trim();
    return summary.isNotEmpty ? summary : '未命名对话';
  }

  Widget _buildSwipeConversationItem(
    ConversationModel conversation, {
    required bool showDivider,
  }) {
    final isBusy = _busyConversationKeys.contains(conversation.threadKey);
    final title = _resolveConversationTitle(conversation);

    return ConversationSlidable(
      itemKey: conversation.threadKey,
      groupTag: 'home-drawer-conversations',
      isBusy: isBusy,
      actions: _buildDrawerActions(conversation),
      onDismissed: () => _deleteConversation(conversation),
      onFullSwipe: () => _archiveConversation(conversation),
      child: Column(
        children: [
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _openConversationFromDrawer(conversation),
              borderRadius: BorderRadius.circular(14),
              splashColor: context.omniPalette.accentPrimary.withValues(
                alpha: 0.08,
              ),
              highlightColor: Colors.transparent,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(4, 9, 2, 9),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: _drawerTextColor,
                          height: 1.35,
                          fontFamily: 'PingFang SC',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (showDivider) const SizedBox(height: 2),
        ],
      ),
    );
  }
}

class _DrawerShortcutAction {
  const _DrawerShortcutAction({
    required this.label,
    required this.onTap,
    this.assetPath,
    this.svgString,
  }) : assert(
         assetPath != null || svgString != null,
         'assetPath or svgString is required',
       );

  final String label;
  final VoidCallback onTap;
  final String? assetPath;
  final String? svgString;
}

class _ConversationSection {
  _ConversationSection({required this.label, required this.conversations});

  final String label;
  final List<ConversationModel> conversations;
}
