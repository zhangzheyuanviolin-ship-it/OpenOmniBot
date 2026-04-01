import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:ui/services/storage_service.dart';

enum AppBackgroundSourceType { none, local, remote }

class AppBackgroundConfig {
  final bool enabled;
  final AppBackgroundSourceType sourceType;
  final String localImagePath;
  final String remoteImageUrl;
  final double blurSigma;
  final double frostOpacity;
  final double brightness;
  final double focalX;
  final double focalY;

  const AppBackgroundConfig({
    required this.enabled,
    required this.sourceType,
    required this.localImagePath,
    required this.remoteImageUrl,
    required this.blurSigma,
    required this.frostOpacity,
    required this.brightness,
    required this.focalX,
    required this.focalY,
  });

  static const AppBackgroundConfig defaults = AppBackgroundConfig(
    enabled: false,
    sourceType: AppBackgroundSourceType.none,
    localImagePath: '',
    remoteImageUrl: '',
    blurSigma: 8,
    frostOpacity: 0.18,
    brightness: 1,
    focalX: 0,
    focalY: 0,
  );

  bool get hasResolvedImage {
    return switch (sourceType) {
      AppBackgroundSourceType.local => localImagePath.trim().isNotEmpty,
      AppBackgroundSourceType.remote => remoteImageUrl.trim().isNotEmpty,
      AppBackgroundSourceType.none => false,
    };
  }

  bool get isActive => enabled && hasResolvedImage;

  AppBackgroundConfig copyWith({
    bool? enabled,
    AppBackgroundSourceType? sourceType,
    String? localImagePath,
    String? remoteImageUrl,
    double? blurSigma,
    double? frostOpacity,
    double? brightness,
    double? focalX,
    double? focalY,
  }) {
    return AppBackgroundConfig(
      enabled: enabled ?? this.enabled,
      sourceType: sourceType ?? this.sourceType,
      localImagePath: localImagePath ?? this.localImagePath,
      remoteImageUrl: remoteImageUrl ?? this.remoteImageUrl,
      blurSigma: blurSigma ?? this.blurSigma,
      frostOpacity: frostOpacity ?? this.frostOpacity,
      brightness: brightness ?? this.brightness,
      focalX: focalX ?? this.focalX,
      focalY: focalY ?? this.focalY,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'enabled': enabled,
      'sourceType': sourceType.name,
      'localImagePath': localImagePath,
      'remoteImageUrl': remoteImageUrl,
      'blurSigma': blurSigma,
      'frostOpacity': frostOpacity,
      'brightness': brightness,
      'focalX': focalX,
      'focalY': focalY,
    };
  }

  factory AppBackgroundConfig.fromJson(Map<String, dynamic> json) {
    final sourceName = (json['sourceType'] as String? ?? 'none').trim();
    final sourceType = AppBackgroundSourceType.values.firstWhere(
      (value) => value.name == sourceName,
      orElse: () => AppBackgroundSourceType.none,
    );
    return AppBackgroundConfig(
      enabled: json['enabled'] == true,
      sourceType: sourceType,
      localImagePath: (json['localImagePath'] as String? ?? '').trim(),
      remoteImageUrl: (json['remoteImageUrl'] as String? ?? '').trim(),
      blurSigma: ((json['blurSigma'] as num?)?.toDouble() ?? defaults.blurSigma)
          .clamp(0, 24)
          .toDouble(),
      frostOpacity:
          ((json['frostOpacity'] as num?)?.toDouble() ?? defaults.frostOpacity)
              .clamp(0, 0.55)
              .toDouble(),
      brightness:
          ((json['brightness'] as num?)?.toDouble() ?? defaults.brightness)
              .clamp(0.5, 1.5)
              .toDouble(),
      focalX: ((json['focalX'] as num?)?.toDouble() ?? defaults.focalX)
          .clamp(-1, 1)
          .toDouble(),
      focalY: ((json['focalY'] as num?)?.toDouble() ?? defaults.focalY)
          .clamp(-1, 1)
          .toDouble(),
    );
  }
}

class AppBackgroundService {
  AppBackgroundService._();

  static const String _storageKey = 'app_background_config_v1';
  static final ValueNotifier<AppBackgroundConfig> notifier =
      ValueNotifier<AppBackgroundConfig>(AppBackgroundConfig.defaults);

  static AppBackgroundConfig get current => notifier.value;

  static Future<void> load() async {
    final raw = StorageService.getString(_storageKey);
    if (raw == null || raw.trim().isEmpty) {
      notifier.value = AppBackgroundConfig.defaults;
      return;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        notifier.value = AppBackgroundConfig.fromJson(decoded);
        return;
      }
      if (decoded is Map) {
        notifier.value = AppBackgroundConfig.fromJson(
          decoded.map((key, value) => MapEntry(key.toString(), value)),
        );
        return;
      }
    } catch (_) {
      // Fall through to defaults.
    }
    notifier.value = AppBackgroundConfig.defaults;
  }

  static Future<void> save(AppBackgroundConfig config) async {
    await StorageService.setString(_storageKey, jsonEncode(config.toJson()));
    notifier.value = config;
  }

  static Future<void> reset() async {
    final previous = notifier.value;
    if (previous.sourceType == AppBackgroundSourceType.local &&
        previous.localImagePath.trim().isNotEmpty) {
      await deleteManagedLocalImage(previous.localImagePath);
    }
    await StorageService.remove(_storageKey);
    notifier.value = AppBackgroundConfig.defaults;
  }

  static Future<String> importLocalImage(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      throw Exception('所选图片不存在');
    }
    final directory = await _backgroundDirectory();
    final extension = _normalizedExtension(sourcePath);
    final fileName =
        'background_${DateTime.now().millisecondsSinceEpoch}$extension';
    final targetFile = File('${directory.path}/$fileName');
    await sourceFile.copy(targetFile.path);
    return targetFile.path;
  }

  static Future<void> deleteManagedLocalImage(String path) async {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return;
    }
    final file = File(trimmed);
    if (await file.exists()) {
      await file.delete();
    }
  }

  static Future<Directory> _backgroundDirectory() async {
    final baseDirectory = await getApplicationSupportDirectory();
    final directory = Directory('${baseDirectory.path}/backgrounds');
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

  static String _normalizedExtension(String path) {
    final lower = path.toLowerCase();
    final dotIndex = lower.lastIndexOf('.');
    if (dotIndex < 0) {
      return '.jpg';
    }
    final extension = lower.substring(dotIndex);
    return switch (extension) {
      '.png' || '.jpg' || '.jpeg' || '.webp' => extension,
      _ => '.jpg',
    };
  }
}
