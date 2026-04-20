import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/theme/theme_context.dart';

class ExecutionRecordListItem extends StatelessWidget {
  final ExecutionRecordListItemData recordModel;
  final VoidCallback? onLongPress;
  // 选择模式相关
  final bool isSelectionMode;
  final bool isSelected;
  // 定时任务相关
  final VoidCallback? onSchedulePressed;
  final bool hasScheduledTask;
  // 重放相关
  final VoidCallback? onReplayPressed;

  const ExecutionRecordListItem({
    Key? key,
    required this.recordModel,
    this.onLongPress,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSchedulePressed,
    this.hasScheduledTask = false,
    this.onReplayPressed,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: (details) {
        onLongPress?.call();
      },
      child: _buildCardContent(context),
    );
  }

  Widget _buildCardContent(BuildContext context) {
    final palette = context.omniPalette;
    final isDark = context.isDarkTheme;
    return Stack(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isDark ? palette.surfacePrimary : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: isDark ? Border.all(color: palette.borderSubtle) : null,
            boxShadow: isDark ? null : [AppColors.boxShadow],
          ),
          child: Row(
            children: [
              // 原有内容
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // 显示多个图标
                        ...recordModel.icons.asMap().entries.map((entry) {
                          final index = entry.key;
                          final icon = entry.value;
                          return Padding(
                            padding: EdgeInsets.only(
                              right: index < recordModel.icons.length - 1
                                  ? 4
                                  : 0,
                            ),
                            child: icon,
                          );
                        }),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      recordModel.title,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.57,
                        letterSpacing: 0,
                        color: isDark ? palette.textPrimary : AppColors.text,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          '最近执行：${recordModel.lastExecutionTimeLabel}',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark
                                ? palette.textSecondary
                                : AppColors.text70,
                            height: 1.60,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          child: Container(
                            width: 0.5,
                            height: 7,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? palette.textSecondary
                                  : AppColors.text70,
                            ),
                          ),
                        ),
                        // 统一显示执行次数
                        Text(
                          '共执行 ${recordModel.times} 次',
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark
                                ? palette.textSecondary
                                : AppColors.text70,
                            height: 1.60,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // 选择模式下显示复选框
              if (isSelectionMode) ...[
                _buildCheckbox(),
                const SizedBox(width: 12),
              ],
            ],
          ),
        ),
        // 右上角按钮组（选择模式下不显示）
        if (!isSelectionMode) ...[
          Positioned(
            top: 6,
            right: 4,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // 重放按钮
                if (recordModel.isReplayable) _buildReplayButton(),
                // 执行按钮
                if (recordModel.isExecutable) _buildExecuteButton(),
              ],
            ),
          ),
        ],
        // 定时按钮
        if (recordModel.isSchedulable && !isSelectionMode) ...[
          Positioned(bottom: 6, right: 4, child: _buildScheduleButton()),
        ],
      ],
    );
  }

  /// 构建重放按钮
  Widget _buildReplayButton() {
    return Builder(
      builder: (context) {
        final palette = context.omniPalette;
        final isDark = context.isDarkTheme;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            onReplayPressed?.call();
          },
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            child: Icon(
              Icons.replay_rounded,
              size: 18,
              color: isDark ? palette.textSecondary : AppColors.text70,
            ),
          ),
        );
      },
    );
  }

  Widget _buildScheduleButton() {
    return Builder(
      builder: (context) {
        final palette = context.omniPalette;
        final isDark = context.isDarkTheme;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            onSchedulePressed?.call();
          },
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            child: SvgPicture.asset(
              'assets/common/schedule_icon.svg',
              width: 16,
              height: 16,
              colorFilter: ColorFilter.mode(
                hasScheduledTask
                    ? (isDark ? palette.accentPrimary : AppColors.primaryBlue)
                    : (isDark ? palette.textSecondary : AppColors.text70),
                BlendMode.srcIn,
              ),
            ),
          ),
        );
      },
    );
  }

  /// 构建执行按钮
  Widget _buildExecuteButton() {
    return Builder(
      builder: (context) {
        final palette = context.omniPalette;
        final isDark = context.isDarkTheme;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            recordModel.onExecute?.call();
          },
          child: Container(
            width: 32,
            height: 32,
            alignment: Alignment.center,
            child: Icon(
              Icons.play_arrow_rounded,
              size: 18,
              color: isDark ? palette.accentPrimary : AppColors.primaryBlue,
            ),
          ),
        );
      },
    );
  }

  Widget _buildCheckbox() {
    return SizedBox(
      width: 20,
      height: 20,
      child: SvgPicture.asset(
        isSelected
            ? 'assets/common/card_selected.svg'
            : 'assets/common/card_unselected.svg',
        width: 20,
        height: 20,
      ),
    );
  }

}

/// 执行记录数据模型（仅 OmniFlow run logs）
class ExecutionRecordListItemData {
  final int id;
  final String title;
  final String packageName;
  final String nodeId;
  final String suggestionId;
  final int times;
  final String lastExecutionTimeLabel;
  final List<Widget> icons;
  final String? section;

  // 可执行相关属性
  final bool isExecutable;
  final bool isSchedulable;
  final bool isReplayable; // 是否可重放
  final Map<String, dynamic>? suggestionData;
  final VoidCallback? onExecute;
  final VoidCallback? onReplay; // 重放回调

  // OmniFlow run log 标识
  final String? runId;

  // 排序用时间戳
  final DateTime? sortTimestamp;

  ExecutionRecordListItemData({
    required this.id,
    required this.title,
    required this.packageName,
    required this.nodeId,
    required this.suggestionId,
    required this.times,
    required this.lastExecutionTimeLabel,
    required this.icons,
    this.section,
    this.isExecutable = false,
    this.isSchedulable = false,
    this.isReplayable = false,
    this.suggestionData,
    this.onExecute,
    this.onReplay,
    this.runId,
    this.sortTimestamp,
  });
}
