import 'dart:ffi';

import 'package:flutter/material.dart';
import '../../../../widgets/card/edit_task_card.dart';
import '../../../../models/chat_models.dart';
import '../../../../services/task_storage_service.dart';
import '../../../../models/task_models.dart';
import '../task_edit/task_edit_page.dart';
import 'package:ui/widgets/common_app_bar.dart';
import 'package:ui/utils/popup_menu_anchor_position.dart';

class TaskCenterPage extends StatefulWidget {
  const TaskCenterPage({super.key});

  @override
  State<TaskCenterPage> createState() => _TaskCenterPageState();
}

class _TaskCenterPageState extends State<TaskCenterPage> {
  // 修改为使用 TaskData
  List<TaskData> tasks = [];

  // 新增：编辑状态管理
  bool _isEditing = false;
  TaskData? _editingTask;

  @override
  void initState() {
    super.initState();
    _loadTasks();
    _initializeSampleTasks();
  }

  Future<void> _loadTasks() async {
    final loadedTasks = await TaskStorageService.loadTasks();
    setState(() {
      tasks = loadedTasks;
    });
  }

  Future<void> _initializeSampleTasks() async {
    final existingTasks = await TaskStorageService.loadTasks();

    // 如果没有任务，则添加样例任务
    if (existingTasks.isEmpty) {
      final sampleTasks = [
        TaskData(
          id: '1',
          title: '打车去公司',
          date: DateTime.now().add(const Duration(days: 1)),
          time: const TimeOfDay(hour: 9, minute: 0),
          repeatOption: RepeatOption.fromLabel('每日'),
          isEnabled: true,
        ),
        TaskData(
          id: '2',
          title: '抢票',
          date: DateTime.now().add(const Duration(days: 2)),
          time: const TimeOfDay(hour: 15, minute: 0),
          repeatOption: RepeatOption.fromLabel('永不'),
          isEnabled: true,
        ),
        TaskData(
          id: '3',
          title: '打车去公司',
          date: DateTime.now().add(const Duration(days: 3)),
          time: const TimeOfDay(hour: 9, minute: 0),
          repeatOption: RepeatOption.fromLabel('每周'),
          isEnabled: true,
        ),
      ];

      // 保存样例任务
      for (final task in sampleTasks) {
        await TaskStorageService.saveTask(task);
      }

      // 重新加载任务列表
      _loadTasks();
    }
  }

  @override
  Widget build(BuildContext context) {
    const backgroundColor = Color(0xFFF1F1F1);
    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: const CommonAppBar(title: '任务中心', primary: true),
      body: Column(
        children: [
          // 任务列表
          Expanded(
            child: tasks.length > 0
                ? ListView.builder(
                    padding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 20),
                    itemCount: tasks.length,
                    itemBuilder: (context, index) {
                      return _buildTaskCard(tasks[index]);
                    },
                  )
                : Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.task_outlined,
                          size: 80,
                          color: Colors.grey[300],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '暂无任务',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[500],
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        onPressed: () {
          // 添加新任务
        },
        backgroundColor: Colors.black,
        shape: CircleBorder(),
        child: const Icon(
          Icons.add,
          color: Colors.white,
          size: 30,
        ),
      ),
    );
  }

  Widget _buildTaskCard(TaskData task) {
    const primaryBlack = Color(0xFF333333);
    return Container(
      margin: const EdgeInsets.only(bottom: 15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(15),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 20,
                      height: 20,
                      child: Transform.scale(
                        scale: 0.8,
                        alignment: Alignment.centerLeft,
                        child: Switch(
                          value: task.isEnabled,
                          activeTrackColor: Colors.blue,
                          inactiveTrackColor: Colors.white,
                          onChanged: (value) async {
                            setState(() {
                              task.isEnabled = value;
                            });
                            // 保存状态变化到本地存储
                            await TaskStorageService.saveTask(task);
                          },
                        ),
                      ),
                    ),
                    SizedBox(width: 10),
                  ],
                )
              ],
            ),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  task.repeatOption.label+'${task.time.hour.toString().padLeft(2, '0')}:${task.time.minute.toString().padLeft(2, '0')}',
                  style: TextStyle(
                    fontSize: 14,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w500,
                  ),
                ),
                GestureDetector(
                  onTapDown: (TapDownDetails details) {
                    showMenu(
                      context: context,
                      position: PopupMenuAnchorPosition.fromGlobalOffset(
                        context: context,
                        globalOffset: details.globalPosition,
                        estimatedMenuHeight: 160,
                      ),
                      color: Colors.white,
                      items: [
                        PopupMenuItem(
                          value: 'execute',
                          child: Row(
                            children: [
                              Icon(Icons.play_arrow,
                                  size: 18, color: Colors.grey[600]),
                              SizedBox(width: 8),
                              Text('立即执行'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit, size: 18, color: Colors.grey[600]),
                              SizedBox(width: 8),
                              Text('编辑'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, size: 18, color: Colors.grey[600]),
                              SizedBox(width: 8),
                              Text('删除'),
                            ],
                          ),
                        ),
                      ],
                    ).then((value) {
                      if (value == 'execute') {
                        _executeTaskImmediately(task);
                      } else if (value == 'edit') {
                        _editTask(task);
                      } else if (value == 'delete') {
                        _deleteTask(task);
                      }
                    });
                  },
                  child: Icon(
                    Icons.more_horiz,
                    color: Colors.grey[400],
                  ),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _executeTaskImmediately(TaskData task) {
    // 立即执行任务的逻辑
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('正在执行任务：${task.title}'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  void _editTask(TaskData task) {
    // 跳转到编辑页面
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TaskEditPage(
          taskId: task.id,
        ),
      ),
    ).then((_) {
      // 当返回时，刷新任务列表
      _loadTasks();
    });
  }

  void _deleteTask(TaskData task) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          actionsPadding: EdgeInsets.all(0),
          backgroundColor: Colors.white,
          title: Center(
            child: Text("确认删除？"),
          ),
          content: Text("您确定要删除任务：${task.title}吗？"),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          actions: [
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pop(context); // 取消删除
                    },
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.grey,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Align(
                        alignment: Alignment.center,
                        child: Text("取消"),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      final success =
                          await TaskStorageService.deleteTask(task.id);
                      Navigator.pop(context);

                      if (success) {
                        _loadTasks(); // 重新加载任务列表
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text("已删除任务：${task.title}")),
                        );
                      } else {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text("删除任务失败")),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.grey,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(20),
                      child: Align(
                        alignment: Alignment.center,
                        child: Text("确认", style: TextStyle(color: Colors.red)),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}
