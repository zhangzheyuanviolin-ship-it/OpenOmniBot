import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:ui/services/omnibot_resource_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/app_background_widgets.dart';

enum _WorkspaceEntryAction { edit, rename, delete }

class _WorkspaceDragPayload {
  const _WorkspaceDragPayload({
    required this.sourcePath,
    required this.isDirectory,
  });

  final String sourcePath;
  final bool isDirectory;
}

class OmnibotWorkspaceBrowser extends StatefulWidget {
  final String workspacePath;
  final String? workspaceShellPath;
  final bool enableSystemBackHandler;
  final bool translucentSurfaces;
  final ValueChanged<bool>? onCanGoUpChanged;

  const OmnibotWorkspaceBrowser({
    super.key,
    required this.workspacePath,
    this.workspaceShellPath,
    this.enableSystemBackHandler = true,
    this.translucentSurfaces = false,
    this.onCanGoUpChanged,
  });

  @override
  State<OmnibotWorkspaceBrowser> createState() =>
      OmnibotWorkspaceBrowserState();
}

class OmnibotWorkspaceBrowserState extends State<OmnibotWorkspaceBrowser> {
  static const String _folderIconAsset =
      'assets/home/workspace_folder_icon.svg';
  static const String _folderOpenIconAsset =
      'assets/home/workspace_folder_open_icon.svg';
  static const String _audioIconAsset = 'assets/home/workspace_audio_icon.svg';
  static const String _videoIconAsset = 'assets/home/workspace_video_icon.svg';
  static const String _fileIconAsset = 'assets/home/workspace_file_icon.svg';
  static const int _maxInlineExpansionDepth = 2;
  static const int _maxExpandedItemsBeforeScroll = 8;
  static const double _itemHeight = 40;
  static const double _indentStep = 16;
  static const Set<String> _audioExtensions = <String>{
    '.mp3',
    '.m4a',
    '.wav',
    '.aac',
    '.ogg',
    '.flac',
  };
  static const Set<String> _videoExtensions = <String>{
    '.mp4',
    '.mov',
    '.m4v',
    '.avi',
    '.mkv',
    '.webm',
  };

  late final Directory _rootDirectory;
  late Directory _directory;
  List<FileSystemEntity> _entries = const [];
  final Set<String> _expandedDirectoryPaths = <String>{};
  final Map<String, List<FileSystemEntity>> _directoryChildrenCache =
      <String, List<FileSystemEntity>>{};
  String? _dragHoverTargetPath;

  Color _surfaceColor({double opacity = 0.8}) {
    return backgroundSurfaceColor(
      translucent: widget.translucentSurfaces,
      opacity: opacity,
    );
  }

  Color _secondarySurfaceColor({double opacity = 0.64}) {
    return widget.translucentSurfaces
        ? Colors.white.withValues(alpha: opacity)
        : const Color(0xFFF7F8FA);
  }

  @override
  void initState() {
    super.initState();
    _rootDirectory = Directory(widget.workspacePath);
    _directory = _rootDirectory;
    _notifyCanGoUpChanged();
    _refresh();
  }

  void _notifyCanGoUpChanged() {
    final callback = widget.onCanGoUpChanged;
    if (callback == null) return;
    final value = canGoUp;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      callback(value);
    });
  }

  void _refresh() {
    final exists = _directory.existsSync();
    final nextEntries = exists
        ? _sortedEntriesFor(_directory)
        : const <FileSystemEntity>[];
    final nextExpandedPaths = <String>{};
    final nextChildrenCache = <String, List<FileSystemEntity>>{};

    for (final path in _expandedDirectoryPaths) {
      if (!_isDescendantOfCurrentDirectory(path)) continue;
      final dir = Directory(path);
      if (!dir.existsSync()) continue;
      nextExpandedPaths.add(path);
      nextChildrenCache[path] = _sortedEntriesFor(dir);
    }

    setState(() {
      _entries = nextEntries;
      _expandedDirectoryPaths
        ..clear()
        ..addAll(nextExpandedPaths);
      _directoryChildrenCache
        ..clear()
        ..addAll(nextChildrenCache);
    });
  }

  bool get canGoUp => _directory.path != _rootDirectory.path;

  void openParentDirectory() {
    if (!canGoUp) return;
    setState(() {
      _directory = _directory.parent;
      _expandedDirectoryPaths.clear();
      _directoryChildrenCache.clear();
    });
    _notifyCanGoUpChanged();
    _refresh();
  }

  void _openDirectory(Directory directory) {
    setState(() {
      _directory = directory;
      _expandedDirectoryPaths.clear();
      _directoryChildrenCache.clear();
    });
    _notifyCanGoUpChanged();
    _refresh();
  }

  List<FileSystemEntity> _sortedEntriesFor(Directory directory) {
    return directory.listSync().toList()..sort((a, b) {
      if (a is Directory && b is! Directory) return -1;
      if (a is! Directory && b is Directory) return 1;
      return a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });
  }

  bool _isDescendantOfCurrentDirectory(String path) {
    if (path == _directory.path) return true;
    return path.startsWith('${_directory.path}/');
  }

  void _collapseDirectory(String directoryPath) {
    setState(() {
      _expandedDirectoryPaths.removeWhere(
        (path) => path == directoryPath || path.startsWith('$directoryPath/'),
      );
      _directoryChildrenCache.removeWhere(
        (path, _) =>
            path == directoryPath || path.startsWith('$directoryPath/'),
      );
    });
  }

  void _toggleDirectoryExpansion(Directory directory, {required int depth}) {
    if (depth >= _maxInlineExpansionDepth) {
      _openDirectory(directory);
      return;
    }
    final path = directory.path;
    if (_expandedDirectoryPaths.contains(path)) {
      _collapseDirectory(path);
      return;
    }
    final children = _sortedEntriesFor(directory);
    setState(() {
      _expandedDirectoryPaths.add(path);
      _directoryChildrenCache[path] = children;
    });
  }

  @override
  Widget build(BuildContext context) {
    final exists = _directory.existsSync();
    final currentShellPath = _currentShellPath();
    final canGoUp = _directory.path != _rootDirectory.path;
    final itemCount = _entries.length + (canGoUp ? 1 : 0);

    final content = Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async => _refresh(),
            child: !exists
                ? _buildStatusList(message: '工作区不存在')
                : itemCount == 0
                ? _buildStatusList(message: '当前目录为空')
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                    itemCount: itemCount,
                    separatorBuilder: (_, __) => const Divider(
                      height: 1,
                      thickness: 1,
                      indent: 12,
                      endIndent: 12,
                    ),
                    itemBuilder: (context, index) {
                      final isFirst = index == 0;
                      final isLast = index == itemCount - 1;
                      final borderRadius = BorderRadius.vertical(
                        top: isFirst ? const Radius.circular(4) : Radius.zero,
                        bottom: isLast ? const Radius.circular(4) : Radius.zero,
                      );

                      if (canGoUp && index == 0) {
                        final parentRow = _buildWorkspaceItem(
                          title: '..',
                          leading: Icon(
                            Icons.arrow_upward_rounded,
                            size: 20,
                            color: AppColors.text.withValues(alpha: 0.8),
                          ),
                          borderRadius: borderRadius,
                          onTap: openParentDirectory,
                        );
                        return _buildDirectoryDropTarget(
                          child: parentRow,
                          borderRadius: borderRadius,
                          targetDirectoryPath: _directory.parent.path,
                        );
                      }

                      final entry = _entries[index - (canGoUp ? 1 : 0)];
                      return _buildEntryNode(
                        entry: entry,
                        depth: 0,
                        currentShellPath: currentShellPath,
                        borderRadius: borderRadius,
                      );
                    },
                  ),
          ),
        ),
      ],
    );

    if (!widget.enableSystemBackHandler) {
      return content;
    }
    return PopScope(
      canPop: !canGoUp,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        openParentDirectory();
      },
      child: content,
    );
  }

  Widget _buildEntryNode({
    required FileSystemEntity entry,
    required int depth,
    required String? currentShellPath,
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(4)),
  }) {
    final name = entry.path.split('/').last;
    final isDirectory = entry is Directory;
    final canExpandInline = isDirectory && depth < _maxInlineExpansionDepth;
    final isExpanded =
        isDirectory &&
        canExpandInline &&
        _expandedDirectoryPaths.contains(entry.path);

    final trailing = isDirectory
        ? Icon(
            canExpandInline
                ? (isExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded)
                : Icons.chevron_right_rounded,
            color: AppColors.text.withValues(alpha: 0.5),
            size: 18,
          )
        : null;

    Widget row = _buildWorkspaceItem(
      title: name,
      leading: _buildDraggableLeadingIcon(entry: entry, isExpanded: isExpanded),
      borderRadius: borderRadius,
      trailing: trailing,
      onTap: () {
        if (entry is Directory) {
          final directory = entry;
          if (canExpandInline) {
            _toggleDirectoryExpansion(directory, depth: depth);
          } else {
            _openDirectory(directory);
          }
          return;
        }
        _openFileEntry(entry, currentShellPath: currentShellPath);
      },
      onLongPress: () => _showEntryActionSheet(entry),
    );

    if (isDirectory) {
      row = _buildDirectoryDropTarget(
        child: row,
        borderRadius: borderRadius,
        targetDirectoryPath: entry.path,
      );
    }

    if (!isDirectory || !isExpanded) {
      return row;
    }

    final children = _directoryChildrenCache[entry.path] ?? const [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        row,
        _buildExpandedChildren(
          entries: children,
          depth: depth + 1,
          currentShellPath: currentShellPath,
        ),
      ],
    );
  }

  Widget _buildDraggableLeadingIcon({
    required FileSystemEntity entry,
    required bool isExpanded,
  }) {
    Widget buildIcon({double size = 20}) {
      return SvgPicture.asset(
        _iconAssetForEntry(entry, isExpanded: isExpanded),
        width: size,
        height: size,
        colorFilter: const ColorFilter.mode(AppColors.text, BlendMode.srcIn),
      );
    }

    final payload = _WorkspaceDragPayload(
      sourcePath: _normalizePath(entry.path),
      isDirectory: entry is Directory,
    );

    return LongPressDraggable<_WorkspaceDragPayload>(
      data: payload,
      feedback: _buildDragFeedback(
        name: _entryNameFromPath(entry.path),
        icon: buildIcon(size: 18),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: buildIcon()),
      onDragStarted: () => _setDragHoverTarget(null),
      onDragEnd: (_) => _setDragHoverTarget(null),
      onDraggableCanceled: (_, __) => _setDragHoverTarget(null),
      child: buildIcon(),
    );
  }

  Widget _buildDragFeedback({required String name, required Widget icon}) {
    return Material(
      color: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 220),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: _surfaceColor(opacity: 0.9),
            borderRadius: BorderRadius.circular(8),
            boxShadow: [AppColors.boxShadow],
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                icon,
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: AppColors.text,
                      fontFamily: 'PingFang SC',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDirectoryDropTarget({
    required Widget child,
    required BorderRadius borderRadius,
    required String targetDirectoryPath,
  }) {
    return DragTarget<_WorkspaceDragPayload>(
      onWillAcceptWithDetails: (details) {
        final canMove = _canMovePayloadToDirectory(
          payload: details.data,
          targetDirectoryPath: targetDirectoryPath,
        );
        _setDragHoverTarget(canMove ? targetDirectoryPath : null);
        return canMove;
      },
      onLeave: (_) => _setDragHoverTarget(null),
      onAcceptWithDetails: (details) {
        _setDragHoverTarget(null);
        _handleDropMove(
          payload: details.data,
          targetDirectoryPath: targetDirectoryPath,
        );
      },
      builder: (context, candidateData, rejectedData) {
        final highlighted =
            _dragHoverTargetPath == targetDirectoryPath ||
            candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: highlighted
              ? BoxDecoration(
                  color: const Color(0x142C7FEB),
                  borderRadius: borderRadius,
                  border: Border.all(color: const Color(0x882C7FEB), width: 1),
                )
              : null,
          child: child,
        );
      },
    );
  }

  void _setDragHoverTarget(String? path) {
    if (_dragHoverTargetPath == path || !mounted) return;
    setState(() {
      _dragHoverTargetPath = path;
    });
  }

  bool _canMovePayloadToDirectory({
    required _WorkspaceDragPayload payload,
    required String targetDirectoryPath,
  }) {
    final sourcePath = _normalizePath(payload.sourcePath);
    final targetPath = _normalizePath(targetDirectoryPath);

    if (!_isInsideWorkspace(sourcePath) || !_isInsideWorkspace(targetPath)) {
      return false;
    }
    if (sourcePath == targetPath) return false;

    final sourceParentPath = _normalizePath(File(sourcePath).parent.path);
    if (sourceParentPath == targetPath) return false;

    if (payload.isDirectory && targetPath.startsWith('$sourcePath/')) {
      return false;
    }

    if (!Directory(targetPath).existsSync()) return false;

    final destinationPath = '$targetPath/${_entryNameFromPath(sourcePath)}';
    return FileSystemEntity.typeSync(destinationPath) ==
        FileSystemEntityType.notFound;
  }

  Future<void> _handleDropMove({
    required _WorkspaceDragPayload payload,
    required String targetDirectoryPath,
  }) async {
    final sourcePath = _normalizePath(payload.sourcePath);
    final targetPath = _normalizePath(targetDirectoryPath);
    final sourceName = _entryNameFromPath(sourcePath);

    if (sourceName.isEmpty) {
      showToast('移动失败：文件名无效', type: ToastType.error);
      return;
    }
    if (!_isInsideWorkspace(sourcePath) || !_isInsideWorkspace(targetPath)) {
      showToast('仅支持在当前 workspace 内移动', type: ToastType.warning);
      return;
    }
    if (sourcePath == targetPath) {
      showToast('不能移动到自身目录', type: ToastType.warning);
      return;
    }

    final sourceParentPath = _normalizePath(File(sourcePath).parent.path);
    if (sourceParentPath == targetPath) {
      showToast('文件已在目标目录中', type: ToastType.info);
      return;
    }

    if (payload.isDirectory && targetPath.startsWith('$sourcePath/')) {
      showToast('不能移动到自身或子目录', type: ToastType.warning);
      return;
    }

    final destinationPath = '$targetPath/$sourceName';
    if (FileSystemEntity.typeSync(destinationPath) !=
        FileSystemEntityType.notFound) {
      showToast('目标目录存在同名项，请先重命名', type: ToastType.warning);
      return;
    }

    final sourceType = FileSystemEntity.typeSync(sourcePath);
    if (sourceType == FileSystemEntityType.notFound) {
      showToast('源文件不存在，请刷新重试', type: ToastType.warning);
      _refresh();
      return;
    }

    try {
      final sourceEntity = sourceType == FileSystemEntityType.directory
          ? Directory(sourcePath)
          : File(sourcePath);
      await sourceEntity.rename(destinationPath);
      showToast(
        sourceType == FileSystemEntityType.directory ? '文件夹已移动' : '文件已移动',
        type: ToastType.success,
      );
      _refresh();
    } catch (error) {
      showToast('移动失败：$error', type: ToastType.error);
    }
  }

  Future<void> _showEntryActionSheet(FileSystemEntity entry) async {
    final name = _entryNameFromPath(entry.path);
    final editable = _canEditEntry(entry);
    final action = await showModalBottomSheet<_WorkspaceEntryAction>(
      context: context,
      backgroundColor: _surfaceColor(opacity: 0.92),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.text.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.text,
                    fontFamily: 'PingFang SC',
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '长按左侧图标并拖动到目标文件夹可移动位置',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.text.withValues(alpha: 0.55),
                    fontFamily: 'PingFang SC',
                  ),
                ),
                const SizedBox(height: 12),
                if (editable) ...[
                  ListTile(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    tileColor: _secondarySurfaceColor(),
                    leading: const Icon(
                      Icons.edit_outlined,
                      color: AppColors.text,
                    ),
                    title: const Text(
                      '编辑',
                      style: TextStyle(
                        color: AppColors.text,
                        fontWeight: FontWeight.w600,
                        fontFamily: 'PingFang SC',
                      ),
                    ),
                    onTap: () => Navigator.of(
                      sheetContext,
                    ).pop(_WorkspaceEntryAction.edit),
                  ),
                  const SizedBox(height: 8),
                ],
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  tileColor: _secondarySurfaceColor(),
                  leading: const Icon(
                    Icons.drive_file_rename_outline_rounded,
                    color: AppColors.text,
                  ),
                  title: const Text(
                    '重命名',
                    style: TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'PingFang SC',
                    ),
                  ),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_WorkspaceEntryAction.rename),
                ),
                const SizedBox(height: 8),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  tileColor: _secondarySurfaceColor(),
                  leading: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFE53935),
                  ),
                  title: const Text(
                    '删除',
                    style: TextStyle(
                      color: Color(0xFFE53935),
                      fontWeight: FontWeight.w600,
                      fontFamily: 'PingFang SC',
                    ),
                  ),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_WorkspaceEntryAction.delete),
                ),
                const SizedBox(height: 8),
                ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  tileColor: _secondarySurfaceColor(),
                  leading: const Icon(
                    Icons.close_rounded,
                    color: AppColors.text,
                  ),
                  title: const Text(
                    '取消',
                    style: TextStyle(
                      color: AppColors.text,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'PingFang SC',
                    ),
                  ),
                  onTap: () => Navigator.of(sheetContext).pop(),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    if (action == _WorkspaceEntryAction.edit) {
      _openFileEntry(entry, startInEditMode: true);
      return;
    }
    if (action == _WorkspaceEntryAction.rename) {
      await _promptRenameEntry(entry);
      return;
    }
    await _confirmAndDeleteEntry(entry);
  }

  bool _canEditEntry(FileSystemEntity entry) {
    if (entry is! File) {
      return false;
    }
    final metadata = OmnibotResourceService.describePath(entry.path);
    return metadata.previewKind == 'text' || metadata.previewKind == 'code';
  }

  void _openFileEntry(
    FileSystemEntity entry, {
    String? currentShellPath,
    bool startInEditMode = false,
  }) {
    final name = _entryNameFromPath(entry.path);
    final shellPath =
        OmnibotResourceService.shellPathForAndroidPath(entry.path) ??
        (currentShellPath == null ? null : '$currentShellPath/$name');
    OmnibotResourceService.openFilePath(
      entry.path,
      title: name,
      shellPath: shellPath,
      startInEditMode: startInEditMode,
    );
  }

  Future<void> _promptRenameEntry(FileSystemEntity entry) async {
    final sourcePath = _normalizePath(entry.path);
    final sourceType = FileSystemEntity.typeSync(sourcePath);
    if (sourceType == FileSystemEntityType.notFound) {
      showToast('目标不存在，请刷新重试', type: ToastType.warning);
      _refresh();
      return;
    }

    final oldName = _entryNameFromPath(sourcePath);
    final isDirectory = sourceType == FileSystemEntityType.directory;
    final nextName = (await AppDialog.input(
      context,
      title: isDirectory ? '重命名文件夹' : '重命名文件',
      hintText: '请输入新名称',
      initialValue: oldName,
      confirmText: '保存',
      cancelText: '取消',
    ))?.trim();

    if (nextName == null) return;

    final validationError = _validateEntryName(nextName);
    if (validationError != null) {
      showToast(validationError, type: ToastType.warning);
      return;
    }
    if (nextName == oldName) {
      showToast('名称未发生变化', type: ToastType.info);
      return;
    }

    final parentPath = _normalizePath(File(sourcePath).parent.path);
    final destinationPath = '$parentPath/$nextName';

    if (!_isInsideWorkspace(destinationPath)) {
      showToast('重命名失败：目标路径无效', type: ToastType.error);
      return;
    }
    if (FileSystemEntity.typeSync(destinationPath) !=
        FileSystemEntityType.notFound) {
      showToast('同名文件或文件夹已存在', type: ToastType.warning);
      return;
    }

    try {
      final sourceEntity = isDirectory
          ? Directory(sourcePath)
          : File(sourcePath);
      await sourceEntity.rename(destinationPath);
      showToast('重命名成功', type: ToastType.success);
      _refresh();
    } catch (error) {
      showToast('重命名失败：$error', type: ToastType.error);
    }
  }

  String? _validateEntryName(String name) {
    if (name.trim().isEmpty) return '名称不能为空';
    if (name == '.' || name == '..') return '名称不能为 . 或 ..';
    if (name.contains('/')) return '名称不能包含 /';
    if (name.contains('\\')) return '名称不能包含 "\\"';
    if (name.contains('\u0000')) return '名称包含非法字符';
    return null;
  }

  Future<void> _confirmAndDeleteEntry(FileSystemEntity entry) async {
    final path = _normalizePath(entry.path);
    final name = _entryNameFromPath(path);
    final sourceType = FileSystemEntity.typeSync(path);
    if (sourceType == FileSystemEntityType.notFound) {
      showToast('目标不存在，请刷新重试', type: ToastType.warning);
      _refresh();
      return;
    }

    final isDirectory = sourceType == FileSystemEntityType.directory;
    final confirmed = await AppDialog.confirm(
      context,
      title: isDirectory ? '删除文件夹' : '删除文件',
      content: '确认删除“$name”？删除后不可恢复。',
      cancelText: '取消',
      confirmText: '删除',
      confirmButtonColor: const Color(0xFFE53935),
    );
    if (confirmed != true) return;

    try {
      if (isDirectory) {
        await Directory(path).delete(recursive: true);
      } else {
        await File(path).delete();
      }
      showToast(isDirectory ? '文件夹已删除' : '文件已删除', type: ToastType.success);
      _refresh();
    } catch (error) {
      showToast('删除失败：$error', type: ToastType.error);
    }
  }

  String _normalizePath(String path) {
    if (path.length > 1 && path.endsWith('/')) {
      return path.substring(0, path.length - 1);
    }
    return path;
  }

  bool _isInsideWorkspace(String path) {
    final normalizedPath = _normalizePath(path);
    final normalizedRoot = _normalizePath(_rootDirectory.path);
    return normalizedPath == normalizedRoot ||
        normalizedPath.startsWith('$normalizedRoot/');
  }

  String _entryNameFromPath(String path) {
    final normalizedPath = _normalizePath(path);
    final slashIndex = normalizedPath.lastIndexOf('/');
    if (slashIndex < 0 || slashIndex == normalizedPath.length - 1) {
      return normalizedPath;
    }
    return normalizedPath.substring(slashIndex + 1);
  }

  Widget _buildExpandedChildren({
    required List<FileSystemEntity> entries,
    required int depth,
    required String? currentShellPath,
  }) {
    final indent = _indentStep * depth;

    if (entries.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(left: indent + 12, top: 6, bottom: 6),
        child: Text(
          '空文件夹',
          style: TextStyle(
            fontSize: 12,
            color: AppColors.text.withValues(alpha: 0.45),
          ),
        ),
      );
    }

    Widget buildItem(BuildContext context, int index) {
      return _buildEntryNode(
        entry: entries[index],
        depth: depth,
        currentShellPath: currentShellPath,
      );
    }

    final listContent = entries.length > _maxExpandedItemsBeforeScroll
        ? SizedBox(
            height: (_itemHeight + 1) * _maxExpandedItemsBeforeScroll - 1,
            child: ListView.separated(
              primary: false,
              physics: const ClampingScrollPhysics(),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(
                height: 1,
                thickness: 1,
                indent: 12,
                endIndent: 12,
              ),
              itemBuilder: buildItem,
            ),
          )
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < entries.length; index++) ...[
                if (index > 0)
                  const Divider(
                    height: 1,
                    thickness: 1,
                    indent: 12,
                    endIndent: 12,
                  ),
                buildItem(context, index),
              ],
            ],
          );

    return Padding(
      padding: EdgeInsets.only(left: indent, top: 2, bottom: 2),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: _surfaceColor(),
          borderRadius: const BorderRadius.all(Radius.circular(4)),
          boxShadow: [AppColors.boxShadow],
        ),
        child: listContent,
      ),
    );
  }

  Widget _buildStatusList({required String message}) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        SizedBox(
          height: 280,
          child: Center(
            child: Text(
              message,
              style: TextStyle(
                color: AppColors.text.withValues(alpha: 0.45),
                fontSize: 14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildWorkspaceItem({
    required String title,
    required Widget leading,
    required BorderRadius borderRadius,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    Widget? trailing,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _surfaceColor(),
        borderRadius: borderRadius,
        boxShadow: [AppColors.boxShadow],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        child: InkWell(
          onTap: onTap,
          onLongPress: onLongPress,
          borderRadius: borderRadius,
          child: SizedBox(
            height: _itemHeight,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  leading,
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: AppColors.text,
                        fontFamily: 'PingFang SC',
                      ),
                    ),
                  ),
                  if (trailing != null) ...[const SizedBox(width: 8), trailing],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _iconAssetForEntry(FileSystemEntity entry, {bool isExpanded = false}) {
    if (entry is Directory) {
      return isExpanded ? _folderOpenIconAsset : _folderIconAsset;
    }
    final fileName = entry.path.split('/').last.toLowerCase();
    final dotIndex = fileName.lastIndexOf('.');
    final extension = dotIndex >= 0 ? fileName.substring(dotIndex) : '';
    if (_audioExtensions.contains(extension)) {
      return _audioIconAsset;
    }
    if (_videoExtensions.contains(extension)) {
      return _videoIconAsset;
    }
    return _fileIconAsset;
  }

  String? _currentShellPath() {
    final baseAndroid = widget.workspacePath;
    final baseShell = widget.workspaceShellPath;
    if (baseShell == null || baseShell.isEmpty) return null;
    if (_directory.path == baseAndroid) return baseShell;
    if (_directory.path.startsWith('$baseAndroid/')) {
      final suffix = _directory.path.substring(baseAndroid.length + 1);
      return '$baseShell/$suffix';
    }
    return OmnibotResourceService.shellPathForAndroidPath(_directory.path) ??
        baseShell;
  }
}
