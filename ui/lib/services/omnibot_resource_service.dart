import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:ui/core/router/go_router_manager.dart';
import 'package:ui/features/home/pages/authorize/authorize_page_args.dart';
import 'package:ui/services/special_permission.dart';

class OmnibotResourceMetadata {
  final String? uri;
  final String path;
  final String shellPath;
  final String title;
  final String previewKind;
  final String mimeType;
  final bool exists;
  final bool isDirectory;
  final String embedKind;
  final bool inlineRenderable;

  const OmnibotResourceMetadata({
    required this.uri,
    required this.path,
    required this.shellPath,
    required this.title,
    required this.previewKind,
    required this.mimeType,
    required this.exists,
    required this.isDirectory,
    required this.embedKind,
    required this.inlineRenderable,
  });
}

class OmnibotWorkspacePaths {
  final String rootPath;
  final String shellRootPath;
  final String internalRootPath;

  const OmnibotWorkspacePaths({
    required this.rootPath,
    required this.shellRootPath,
    required this.internalRootPath,
  });

  factory OmnibotWorkspacePaths.fromMap(Map<dynamic, dynamic> map) {
    final rootPath =
        (map['rootPath'] as String?)?.trim() ??
        '/data/user/0/cn.com.omnimind.bot/workspace';
    final shellRootPath =
        (map['shellRootPath'] as String?)?.trim() ?? '/workspace';
    final internalRootPath =
        (map['internalRootPath'] as String?)?.trim() ?? '$rootPath/.omnibot';
    return OmnibotWorkspacePaths(
      rootPath: rootPath,
      shellRootPath: shellRootPath,
      internalRootPath: internalRootPath,
    );
  }
}

class OmnibotResourceService {
  static const MethodChannel _fileChannel = MethodChannel(
    'cn.com.omnimind.bot/file_save',
  );
  static const OmnibotWorkspacePaths _defaultWorkspacePaths =
      OmnibotWorkspacePaths(
        rootPath: '/data/user/0/cn.com.omnimind.bot/workspace',
        shellRootPath: '/workspace',
        internalRootPath: '/data/user/0/cn.com.omnimind.bot/workspace/.omnibot',
      );

  static OmnibotWorkspacePaths _workspacePaths = _defaultWorkspacePaths;
  static Future<OmnibotWorkspacePaths>? _workspacePathsFuture;

  static String get rootPath => _workspacePaths.rootPath;
  static String get shellRootPath => _workspacePaths.shellRootPath;
  static String get internalRootPath => _workspacePaths.internalRootPath;

  static Future<OmnibotWorkspacePaths> ensureWorkspacePathsLoaded({
    bool forceRefresh = false,
  }) {
    if (forceRefresh) {
      _workspacePathsFuture = null;
    }
    final existing = _workspacePathsFuture;
    if (existing != null) {
      return existing;
    }
    final future = _loadWorkspacePaths();
    _workspacePathsFuture = future;
    return future;
  }

  static Future<OmnibotWorkspacePaths> _loadWorkspacePaths() async {
    try {
      final result = await spePermission.invokeMethod<Map<dynamic, dynamic>>(
        'getWorkspacePathSnapshot',
      );
      if (result != null) {
        _workspacePaths = OmnibotWorkspacePaths.fromMap(result);
      }
    } catch (_) {}
    return _workspacePaths;
  }

  static void debugSetWorkspacePaths(OmnibotWorkspacePaths paths) {
    _workspacePaths = paths;
    _workspacePathsFuture = Future<OmnibotWorkspacePaths>.value(paths);
  }

  static Future<bool> handleLinkTap(String href) async {
    if (href.startsWith('omnibot://')) {
      await openUri(href);
      return true;
    }
    if (href.startsWith('http://') || href.startsWith('https://')) {
      await launchUrlString(href, mode: LaunchMode.externalApplication);
      return true;
    }
    return false;
  }

  static Future<void> openUri(String uri) async {
    await ensureWorkspacePathsLoaded();
    if (!await _ensureWorkspaceStorageAccess()) {
      return;
    }
    final metadata = resolveUri(uri);
    if (metadata == null) return;
    if (metadata.isDirectory) {
      openWorkspace(
        absolutePath: metadata.path,
        shellPath: metadata.shellPath,
        uri: uri,
      );
      return;
    }
    if (uri.startsWith('omnibot://workspace/') && metadata.exists == false) {
      openWorkspace(absolutePath: metadata.path, shellPath: metadata.shellPath);
      return;
    }
    await openFilePath(
      metadata.path,
      uri: uri,
      title: metadata.title,
      previewKind: metadata.previewKind,
      mimeType: metadata.mimeType,
      shellPath: metadata.shellPath,
    );
  }

  static Future<void> openFilePath(
    String path, {
    String? uri,
    String? title,
    String? previewKind,
    String? mimeType,
    String? shellPath,
  }) async {
    await ensureWorkspacePathsLoaded();
    if (!await _ensureWorkspaceStorageAccess()) {
      return;
    }
    final metadata = describePath(
      path,
      uri: uri,
      shellPath: shellPath,
      title: title,
      previewKind: previewKind,
      mimeType: mimeType,
    );

    GoRouterManager.push(
      '/home/omnibot_artifact_preview',
      extra: <String, dynamic>{
        'path': path,
        'uri': uri,
        'title': metadata.title,
        'previewKind': metadata.previewKind,
        'mimeType': metadata.mimeType,
        'shellPath': metadata.shellPath,
        'exists': metadata.exists,
      },
    );
  }

  static Future<void> openWorkspace({
    String? workspaceId,
    String? absolutePath,
    String? shellPath,
    String? uri,
  }) async {
    await ensureWorkspacePathsLoaded();
    if (!await _ensureWorkspaceStorageAccess()) {
      return;
    }
    final path = absolutePath ?? resolveUriToPath(uri ?? '') ?? rootPath;
    final resolvedShellPath =
        shellPath ?? resolveUriToShellPath(uri ?? '') ?? shellRootPath;
    final effectiveWorkspaceId = path == rootPath ? null : workspaceId;
    GoRouterManager.push(
      '/home/omnibot_workspace',
      extra: <String, dynamic>{
        'workspacePath': path,
        'workspaceId': effectiveWorkspaceId,
        'workspaceShellPath': resolvedShellPath,
      },
    );
  }

  static Future<String?> saveToLocal({
    required String sourcePath,
    required String fileName,
    required String mimeType,
  }) async {
    await ensureWorkspacePathsLoaded();
    if (!await _ensureWorkspaceStorageAccess()) {
      return null;
    }
    return _fileChannel.invokeMethod<String>('saveFileWithSystemDialog', {
      'sourcePath': sourcePath,
      'fileName': fileName,
      'mimeType': mimeType,
    });
  }

  static Future<bool> openWithSystem({
    required String sourcePath,
    required String mimeType,
  }) async {
    await ensureWorkspacePathsLoaded();
    if (!await _ensureWorkspaceStorageAccess()) {
      return false;
    }
    final result = await _fileChannel.invokeMethod<dynamic>('openFile', {
      'sourcePath': sourcePath,
      'mimeType': mimeType,
    });
    return result == true;
  }

  static Future<bool> _ensureWorkspaceStorageAccess() async {
    final granted = await isWorkspaceStorageAccessGranted();
    if (granted) {
      return true;
    }
    final result = await GoRouterManager.pushForResult<bool>(
      '/home/authorize',
      extra: const AuthorizePageArgs(
        requiredPermissionIds: <String>[kWorkspaceStoragePermissionId],
      ),
    );
    if (result == true) {
      return await isWorkspaceStorageAccessGranted();
    }
    return false;
  }

  static OmnibotResourceMetadata? resolveUri(String uri) {
    final path = resolveUriToPath(uri);
    if (path == null) return null;
    return describePath(path, uri: uri, shellPath: resolveUriToShellPath(uri));
  }

  static OmnibotResourceMetadata describePath(
    String path, {
    String? uri,
    String? shellPath,
    String? title,
    String? previewKind,
    String? mimeType,
  }) {
    final resolvedShellPath =
        shellPath ?? shellPathForAndroidPath(path) ?? path;
    final isDirectory = _safeIsDirectory(path);
    final resolvedPreviewKind = isDirectory
        ? 'directory'
        : (previewKind ?? _guessPreviewKind(path));
    final resolvedMimeType = isDirectory
        ? 'inode/directory'
        : (mimeType ?? _guessMimeType(path));
    final derivedTitle = path.split(Platform.pathSeparator).last;
    final resolvedTitle =
        title ?? (derivedTitle.isEmpty ? 'workspace' : derivedTitle);
    final resolvedEmbedKind = switch (resolvedPreviewKind) {
      'image' => 'image',
      'audio' => 'audio',
      'video' => 'video',
      _ => 'link',
    };
    return OmnibotResourceMetadata(
      uri: uri,
      path: path,
      shellPath: resolvedShellPath,
      title: resolvedTitle,
      previewKind: resolvedPreviewKind,
      mimeType: resolvedMimeType,
      exists: _safeExists(path),
      isDirectory: isDirectory,
      embedKind: resolvedEmbedKind,
      inlineRenderable: resolvedEmbedKind != 'link',
    );
  }

  static String? resolveUriToPath(String uri) {
    if (!uri.startsWith('omnibot://')) return null;
    final parsed = Uri.tryParse(uri);
    final authority = parsed?.host;
    if (authority == null || authority.isEmpty) return null;
    final segments = parsed?.pathSegments ?? const <String>[];
    final base = switch (authority) {
      'attachments' => '$internalRootPath/attachments',
      'workspace' => rootPath,
      'shared' => '$internalRootPath/shared',
      'offloads' => '$internalRootPath/offloads',
      'browser' => '$internalRootPath/browser',
      'skills' => '$internalRootPath/skills',
      'memory' => '$internalRootPath/memory',
      _ => null,
    };
    if (base == null) return null;
    final normalizedSegments = segments
        .where((segment) => segment.isNotEmpty && segment != '..')
        .toList();
    if (normalizedSegments.isEmpty) return base;
    return '$base/${normalizedSegments.join('/')}';
  }

  static String? resolveUriToShellPath(String uri) {
    if (!uri.startsWith('omnibot://')) return null;
    final parsed = Uri.tryParse(uri);
    final authority = parsed?.host;
    if (authority == null || authority.isEmpty) return null;
    final suffix = (parsed?.pathSegments ?? const <String>[])
        .where((segment) => segment.isNotEmpty && segment != '..')
        .join('/');
    final base = authority == 'workspace'
        ? shellRootPath
        : '$shellRootPath/.omnibot/$authority';
    return suffix.isEmpty ? base : '$base/$suffix';
  }

  static String? shellPathForAndroidPath(String path) {
    if (path == rootPath) {
      return shellRootPath;
    }
    if (path.startsWith('$rootPath/')) {
      final relative = path.substring(rootPath.length + 1);
      return '$shellRootPath/$relative';
    }
    if (path == internalRootPath) {
      return '$shellRootPath/.omnibot';
    }
    if (path.startsWith('$internalRootPath/')) {
      final relative = path.substring(internalRootPath.length + 1);
      return '$shellRootPath/.omnibot/$relative';
    }
    return null;
  }

  static bool _safeExists(String path) {
    try {
      return FileSystemEntity.typeSync(path) != FileSystemEntityType.notFound;
    } catch (_) {
      return false;
    }
  }

  static bool _safeIsDirectory(String path) {
    try {
      return FileSystemEntity.typeSync(path) == FileSystemEntityType.directory;
    } catch (_) {
      return false;
    }
  }

  static String _guessPreviewKind(String path) {
    final lower = path.toLowerCase();
    if (_matchesAny(lower, const ['.png', '.jpg', '.jpeg', '.gif', '.webp'])) {
      return 'image';
    }
    if (_matchesAny(lower, const ['.html', '.htm'])) {
      return 'html';
    }
    if (lower.endsWith('.pdf')) {
      return 'pdf';
    }
    if (_matchesAny(lower, const ['.mp3', '.m4a', '.wav'])) {
      return 'audio';
    }
    if (_matchesAny(lower, const ['.mp4', '.mov'])) {
      return 'video';
    }
    if (_matchesAny(lower, const [
      '.json',
      '.jsonl',
      '.yaml',
      '.yml',
      '.xml',
    ])) {
      return 'code';
    }
    if (_matchesAny(lower, const [
      '.md',
      '.txt',
      '.log',
      '.kt',
      '.java',
      '.py',
      '.js',
      '.ts',
      '.css',
      '.sh',
      '.csv',
    ])) {
      return 'text';
    }
    return 'file';
  }

  static String _guessMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.md')) return 'text/markdown';
    if (lower.endsWith('.json')) return 'application/json';
    if (lower.endsWith('.jsonl')) return 'application/x-ndjson';
    if (lower.endsWith('.yaml') || lower.endsWith('.yml')) {
      return 'application/yaml';
    }
    if (lower.endsWith('.xml')) return 'application/xml';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.html') || lower.endsWith('.htm')) return 'text/html';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.gif')) return 'image/gif';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.mp3')) return 'audio/mpeg';
    if (lower.endsWith('.m4a')) return 'audio/mp4';
    if (lower.endsWith('.wav')) return 'audio/wav';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.mov')) return 'video/quicktime';
    if (_guessPreviewKind(path) == 'text' ||
        _guessPreviewKind(path) == 'code') {
      return 'text/plain';
    }
    return 'application/octet-stream';
  }

  static bool _matchesAny(String value, List<String> suffixes) {
    return suffixes.any(value.endsWith);
  }
}
