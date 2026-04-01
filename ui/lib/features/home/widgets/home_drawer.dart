import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_slidable/flutter_slidable.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ui/core/router/go_router_manager.dart';
import 'package:ui/features/home/widgets/conversation_mode_badge.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/utils/cache_util.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/models/conversation_model.dart';
import 'package:ui/models/conversation_thread_target.dart';
import 'package:ui/services/conversation_service.dart';
import 'package:ui/features/memory/services/mem0_memory_service.dart';

/// 首页侧边栏
class HomeDrawer extends ConsumerStatefulWidget {
  const HomeDrawer({
    super.key,
    this.memoryCount,
    this.newConversationMode = ConversationMode.normal,
  });

  final int? memoryCount;
  final ConversationMode newConversationMode;

  @override
  ConsumerState<HomeDrawer> createState() => HomeDrawerState();
}

class HomeDrawerState extends ConsumerState<HomeDrawer> {
  static const double _conversationDeleteExtentRatio = 0.24;
  static const double _conversationDeleteIconSize = 18;
  int _localMemoryCount = 0;
  int _cloudMemoryCount = 0;
  List<ConversationModel> conversations = [];
  final Set<String> _deletingConversationKeys = <String>{};
  bool isLoadingConversations = true;
  static const BorderRadius _drawerDeleteActionRadius = BorderRadius.only(
    topRight: Radius.circular(4),
    bottomRight: Radius.circular(4),
  );

  int get _totalMemoryCount => _localMemoryCount + _cloudMemoryCount;

  /// 根据时间段获取问候语
  Map<String, String> _getGreetingByTime() {
    final hour = DateTime.now().hour;

    // 02:00 - 06:00: 深夜未眠 / 凌晨早起
    if (hour >= 2 && hour < 6) {
      final greetings = [
        {'title': '凌晨啦', 'subtitle': '还没休息吗？'},
        {'title': '天还没亮', 'subtitle': '早起的你辛苦啦～'},
        {'title': '深夜的时光很静', 'subtitle': '但也要记得给身体留些休息呀～'},
      ];
      return greetings[DateTime.now().minute % greetings.length];
    }

    // 06:00 - 08:00: 清晨通勤 / 准备早餐
    if (hour >= 6 && hour < 8) {
      final greetings = [
        {'title': '早安！', 'subtitle': '开启元气一天'},
        {'title': '早呀！', 'subtitle': '新的一天开始啦'},
      ];
      return greetings[DateTime.now().minute % greetings.length];
    }

    // 08:00 - 12:00: 工作 / 学习时段
    if (hour >= 8 && hour < 12) {
      final greetings = [
        {'title': '上午好！', 'subtitle': '再忙也别忘了活动下肩膀'},
        {'title': '上午的效率超棒！', 'subtitle': '继续加油'},
      ];
      return greetings[DateTime.now().minute % greetings.length];
    }

    // 12:00 - 14:00: 午餐 / 午休时段
    if (hour >= 12 && hour < 14) {
      final greetings = [
        {'title': '午饭时间到！', 'subtitle': '好好吃饭，别凑合'},
        {'title': '午安～', 'subtitle': '吃完记得歇会儿'},
        {'title': '午餐不知道吃什么？', 'subtitle': '让小万帮你推荐吧！'},
      ];
      return greetings[DateTime.now().minute % greetings.length];
    }

    // 14:00 - 18:00: 下午工作 / 学习 / 接娃
    if (hour >= 14 && hour < 18) {
      final greetings = [
        {'title': '喝杯茶提提神', 'subtitle': '剩下的任务也能轻松搞定～'},
        {'title': '工作间隙看看窗外', 'subtitle': '让眼睛歇一歇～'},
      ];
      return greetings[DateTime.now().minute % greetings.length];
    }

    // 18:00 - 20:00: 下班 / 放学 / 准备晚餐
    if (hour >= 18 && hour < 20) {
      final greetings = [
        {'title': '回家路上慢点', 'subtitle': '今晚好好放松～'},
        {'title': '傍晚了', 'subtitle': '吹来的晚风很舒服呀！～'},
        {'title': '忙了一天', 'subtitle': '吃顿好的犒劳自己～'},
      ];
      return greetings[DateTime.now().minute % greetings.length];
    }

    // 20:00 - 22:00: 休闲放松 / 陪伴家人
    if (hour >= 20 && hour < 22) {
      final greetings = [
        {'title': '晚上好！', 'subtitle': '享受属于自己的时光吧～'},
        {'title': '夜色渐浓', 'subtitle': '准备下早点休息啦～'},
        {'title': '该休息了', 'subtitle': '让小万帮你定个闹钟吧！'},
      ];
      return greetings[DateTime.now().minute % greetings.length];
    }

    // 22:00 - 02:00: 睡前放松 / 深夜未眠
    final greetings = [
      {'title': '放下手机早点睡', 'subtitle': '明天才能元气满满～'},
      {'title': '深夜了', 'subtitle': '好好和今天说晚安～'},
    ];
    return greetings[DateTime.now().minute % greetings.length];
  }

  @override
  void initState() {
    super.initState();
    _syncMemoryCount();
    _loadConversations();
  }

  @override
  void didUpdateWidget(covariant HomeDrawer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.memoryCount != oldWidget.memoryCount) {
      if (widget.memoryCount != null) {
        setState(() {
          _localMemoryCount = widget.memoryCount!;
        });
      } else if (oldWidget.memoryCount != null) {
        _loadMemoryCount();
      }
    }
  }

  void reloadConversations() {
    _loadConversations();
    _syncMemoryCount();
  }

  void _syncMemoryCount() {
    if (widget.memoryCount != null) {
      _localMemoryCount = widget.memoryCount!;
    } else {
      _loadMemoryCount();
    }
    _loadCloudMemoryCount();
  }

  Future<void> _loadMemoryCount() async {
    try {
      final favoriteRecords = await CacheUtil.getAllFavoriteRecords();
      if (mounted) {
        setState(() {
          _localMemoryCount = favoriteRecords.length;
        });
      }
    } catch (e) {
      debugPrint('Error loading memory count: $e');
    }
  }

  Future<void> _loadCloudMemoryCount() async {
    try {
      final snapshot = await Mem0MemoryService.getMemories(limit: 200);
      if (!mounted) return;
      setState(() {
        _cloudMemoryCount = snapshot.configured ? snapshot.items.length : 0;
      });
    } catch (e) {
      debugPrint('Error loading cloud memory count: $e');
      if (!mounted) return;
      setState(() {
        _cloudMemoryCount = 0;
      });
    }
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
      if (mounted) {
        setState(() {
          conversations = loadedConversations;
          isLoadingConversations = false;
        });
      }
    } catch (e) {
      debugPrint('[HomeDrawer] 加载聊天记录出错: $e');
      if (mounted) {
        setState(() {
          isLoadingConversations = false;
        });
      }
    }
  }

  void _openNewConversation() {
    Navigator.pop(context);
    GoRouterManager.pushReplacement(
      '/home/chat',
      extra: ConversationThreadTarget.newConversation(
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
    return Drawer(
      width: MediaQuery.of(context).size.width * 0.8,
      backgroundColor: AppColors.background,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 13),
            _buildUserHeader(),

            const SizedBox(height: 24),

            _buildQuickAccessCards(context),

            const SizedBox(height: 16),

            _buildMenuItem(
              icon: 'assets/home/task_record_icon.svg',
              title: '任务记录',
              onTap: () => GoRouterManager.push('/task/execution_history'),
            ),

            _buildMenuItem(
              icon: 'assets/common/schedule_icon.svg',
              title: '定时',
              onTap: () => GoRouterManager.push('/task/scheduled_tasks'),
            ),
            const SizedBox(height: 16),

            Expanded(child: _buildConversationSection()),

            const SizedBox(height: 16),
            _buildMenuSection([
              _DrawerMenuItem(
                icon: 'assets/home/setting_icon.svg',
                title: '设置',
                onTap: () {
                  Navigator.pop(context);
                  GoRouterManager.push('/home/settings');
                },
              ),
            ]),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  /// 用户头像和问候语
  Widget _buildUserHeader() {
    final greeting = _getGreetingByTime();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            greeting['title'] ?? '你好！',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: AppColors.text,
              height: 1.5,
            ),
          ),
          Text(
            greeting['subtitle'] ?? '欢迎使用小万',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w400,
              color: AppColors.text,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  /// 快捷访问卡片
  Widget _buildQuickAccessCards(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: _buildQuickCard(
        title: '记忆中心',
        subtitle: '已记忆 $_totalMemoryCount 个碎片',
        gradient: const LinearGradient(
          begin: Alignment(-0.17, -0.47),
          end: Alignment(1.48, 1.69),
          colors: [const Color(0xFF0056FA), const Color(0xB2609CF7)],
        ),
        onTap: () {
          GoRouterManager.push("/memory/memory_center_page");
        },
      ),
    );
  }

  /// 快捷卡片组件
  Widget _buildQuickCard({
    required String title,
    required String subtitle,
    required Gradient gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        decoration: BoxDecoration(
          gradient: gradient,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: Colors.white,
                fontFamily: 'PingFang SC',
                height: 1.3,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w400,
                color: Colors.white.withOpacity(0.8),
                fontFamily: 'PingFang SC',
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 单个菜单项（白色背景卡片）
  Widget _buildMenuItem({
    required String icon,
    required String title,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          boxShadow: [AppColors.boxShadow],
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(4),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
              child: Row(
                children: [
                  // Icon placeholder - 使用 Container 代替实际图标
                  SvgPicture.asset(
                    icon,
                    width: 16,
                    height: 16,
                    color: AppColors.text,
                    errorBuilder: (context, error, stackTrace) =>
                        Icon(Icons.settings, size: 16, color: AppColors.text),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text,
                      fontFamily: 'PingFang SC',
                      height: 1.57,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 菜单组（白色背景卡片，包含多个菜单项）
  Widget _buildMenuSection(List<_DrawerMenuItem> items) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(4),
          boxShadow: [AppColors.boxShadow],
        ),
        child: Column(
          children: [
            for (int index = 0; index < items.length; index++) ...[
              if (index > 0)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: Divider(
                    height: 0.5,
                    thickness: 0.5,
                    color: AppColors.borderStandard,
                  ),
                ),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: items[index].onTap,
                  borderRadius: BorderRadius.vertical(
                    top: index == 0 ? const Radius.circular(4) : Radius.zero,
                    bottom: index == items.length - 1
                        ? const Radius.circular(4)
                        : Radius.zero,
                  ),
                  child: Container(
                    padding: EdgeInsets.fromLTRB(
                      12,
                      index == 0 ? 13 : 12,
                      12,
                      index == items.length - 1 ? 16 : 12,
                    ),
                    child: Row(
                      children: [
                        // Icon placeholder
                        SvgPicture.asset(
                          items[index].icon,
                          width: 16,
                          height: 16,
                          color: AppColors.text,
                          errorBuilder: (context, error, stackTrace) => Icon(
                            Icons.settings,
                            size: 16,
                            color: AppColors.text,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          items[index].title,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                            color: AppColors.text,
                            fontFamily: 'PingFang SC',
                            height: 1.57,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildConversationSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(8),
            boxShadow: [AppColors.boxShadow],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '聊天记录',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: AppColors.text,
                  ),
                ),
                Row(
                  children: [
                    _buildIconActionButton(
                      iconPath: 'assets/home/chat_history_icon.svg',
                      onTap: () {
                        Navigator.pop(context);
                        GoRouterManager.push('/home/chat_history');
                      },
                    ),
                    const SizedBox(width: 12),
                    _buildIconActionButton(
                      iconPath: 'assets/home/chat_add_icon.svg',
                      onTap: _openNewConversation,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            child: isLoadingConversations
                ? Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          AppColors.text,
                        ),
                      ),
                    ),
                  )
                : conversations.isEmpty
                ? _buildEmptyConversation()
                : SlidableAutoCloseBehavior(
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: conversations.length,
                      itemBuilder: (context, index) {
                        return _buildSwipeConversationItem(
                          conversations[index],
                        );
                      },
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
              style: TextStyle(
                fontSize: 14,
                color: AppColors.text.withOpacity(0.4),
              ),
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
                  gradient: const LinearGradient(
                    begin: Alignment(0.14, -1.09),
                    end: Alignment(1.10, 1.26),
                    colors: [Color(0xFF1930D9), Color(0xFF2CA5F0)],
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  '开始对话',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconActionButton({
    required String iconPath,
    required VoidCallback onTap,
    bool isPrimary = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: isPrimary ? const Color(0xFF1930D9) : Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            if (!isPrimary)
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 4,
                offset: const Offset(0, 2),
              ),
          ],
        ),
        padding: const EdgeInsets.all(
          8,
        ), // Padding to scale down the icon if needed
        child: SvgPicture.asset(
          iconPath,
          width: 16,
          height: 16,
          color: isPrimary
              ? Colors.white
              : AppColors.text, // Match text color for secondary
        ),
      ),
    );
  }

  /// 单个聊天记录项
  void _openConversationFromDrawer(ConversationModel conversation) {
    if (_deletingConversationKeys.contains(conversation.threadKey)) {
      return;
    }

    Navigator.pop(context);
    GoRouterManager.pushReplacement(
      '/home/chat',
      extra: ConversationThreadTarget.existing(
        conversationId: conversation.id,
        mode: conversation.mode,
      ),
    );
  }

  Future<void> _deleteConversation(ConversationModel conversation) async {
    if (_deletingConversationKeys.contains(conversation.threadKey)) {
      return;
    }

    final originalIndex = conversations.indexWhere(
      (item) => item.id == conversation.id,
    );
    if (originalIndex < 0) {
      return;
    }

    setState(() {
      _deletingConversationKeys.add(conversation.threadKey);
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
      _deletingConversationKeys.remove(conversation.threadKey);
      if (!deleted) {
        final restoredIndex = originalIndex <= conversations.length
            ? originalIndex
            : conversations.length;
        conversations = List<ConversationModel>.from(conversations)
          ..insert(restoredIndex, conversation);
      }
    });

    showToast(
      deleted ? '\u5df2\u5220\u9664' : '\u5220\u9664\u5931\u8d25',
      type: deleted ? ToastType.success : ToastType.error,
    );
  }

  Widget _buildSwipeConversationItem(ConversationModel conversation) {
    final isDeleting = _deletingConversationKeys.contains(
      conversation.threadKey,
    );

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      child: IgnorePointer(
        ignoring: isDeleting,
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 180),
          opacity: isDeleting ? 0.72 : 1,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final initialActionWidth =
                  constraints.maxWidth * _conversationDeleteExtentRatio;
              final deleteIconRightPadding =
                  ((initialActionWidth - _conversationDeleteIconSize) / 2)
                      .clamp(0.0, double.infinity)
                      .toDouble();

              return Slidable(
                key: ValueKey<String>(conversation.threadKey),
                groupTag: 'home-drawer-conversations',
                closeOnScroll: true,
                endActionPane: ActionPane(
                  motion: const BehindMotion(),
                  extentRatio: _conversationDeleteExtentRatio,
                  dismissible: DismissiblePane(
                    dismissThreshold: 0.4,
                    closeOnCancel: true,
                    motion: const InversedDrawerMotion(),
                    onDismissed: () => _deleteConversation(conversation),
                  ),
                  children: [
                    CustomSlidableAction(
                      onPressed: (_) => _deleteConversation(conversation),
                      backgroundColor: AppColors.alertRed,
                      borderRadius: _drawerDeleteActionRadius,
                      padding: EdgeInsets.zero,
                      alignment: Alignment.centerRight,
                      child: Padding(
                        padding: EdgeInsets.only(right: deleteIconRightPadding),
                        child: SvgPicture.asset(
                          'assets/memory/memory_delete.svg',
                          width: _conversationDeleteIconSize,
                          height: _conversationDeleteIconSize,
                          colorFilter: const ColorFilter.mode(
                            Colors.white,
                            BlendMode.srcIn,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.background,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    child: InkWell(
                      onTap: () => _openConversationFromDrawer(conversation),
                      borderRadius: BorderRadius.circular(8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 9,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      conversation.summary ??
                                          conversation.title,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.text,
                                        fontFamily: 'PingFang SC',
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ConversationModeBadge(
                                    mode: conversation.mode,
                                    compact: true,
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              conversation.timeDisplay,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppColors.text.withOpacity(0.4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildConversationItem(ConversationModel conversation) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: () {
            Navigator.pop(context);
            // 使用 pushReplacement 替换当前页面，避免路由栈堆积
            GoRouterManager.pushReplacement(
              '/home/chat',
              extra: ConversationThreadTarget.existing(
                conversationId: conversation.id,
                mode: conversation.mode,
              ),
            );
          },
          onLongPress: () => _showDeleteDialog(conversation),
          borderRadius: BorderRadius.circular(8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        conversation.summary ?? conversation.title,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: AppColors.text,
                          fontFamily: 'PingFang SC',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                SizedBox(width: 8),
                Text(
                  conversation.timeDisplay,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.text.withOpacity(0.4),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showDeleteDialog(ConversationModel conversation) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除对话'),
        content: Text('确定要删除这个对话吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('取消'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await ConversationService.deleteConversation(
                conversation.id,
                mode: conversation.mode,
              );
              if (success) {
                setState(() {
                  conversations.removeWhere((c) => c.id == conversation.id);
                });
              }
            },
            child: Text('删除', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

/// 菜单项数据模型
class _DrawerMenuItem {
  final String icon;
  final String title;
  final VoidCallback onTap;

  _DrawerMenuItem({
    required this.icon,
    required this.title,
    required this.onTap,
  });
}
