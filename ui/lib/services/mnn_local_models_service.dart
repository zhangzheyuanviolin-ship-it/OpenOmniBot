import 'dart:async';

import 'package:flutter/services.dart';

class MnnLocalDownloadInfo {
  final int state;
  final String stateLabel;
  final double progress;
  final int savedSize;
  final int totalSize;
  final String speedInfo;
  final String errorMessage;
  final String progressStage;
  final String currentFile;
  final bool hasUpdate;

  const MnnLocalDownloadInfo({
    required this.state,
    required this.stateLabel,
    required this.progress,
    required this.savedSize,
    required this.totalSize,
    required this.speedInfo,
    required this.errorMessage,
    required this.progressStage,
    required this.currentFile,
    required this.hasUpdate,
  });

  factory MnnLocalDownloadInfo.fromMap(Map<dynamic, dynamic>? map) {
    return MnnLocalDownloadInfo(
      state: (map?['state'] as num?)?.toInt() ?? 0,
      stateLabel: (map?['stateLabel'] ?? 'not_started').toString(),
      progress: (map?['progress'] as num?)?.toDouble() ?? 0,
      savedSize: (map?['savedSize'] as num?)?.toInt() ?? 0,
      totalSize: (map?['totalSize'] as num?)?.toInt() ?? 0,
      speedInfo: (map?['speedInfo'] ?? '').toString(),
      errorMessage: (map?['errorMessage'] ?? '').toString(),
      progressStage: (map?['progressStage'] ?? '').toString(),
      currentFile: (map?['currentFile'] ?? '').toString(),
      hasUpdate: map?['hasUpdate'] == true,
    );
  }

  bool get isDownloading =>
      stateLabel == 'downloading' || stateLabel == 'preparing';
  bool get isCompleted => stateLabel == 'completed';
  bool get isPaused => stateLabel == 'paused';
}

class MnnLocalModel {
  final String id;
  final String name;
  final String category;
  final String source;
  final String description;
  final String path;
  final String vendor;
  final List<String> tags;
  final List<String> extraTags;
  final bool active;
  final bool isLocal;
  final bool isPinned;
  final bool hasUpdate;
  final int fileSize;
  final double sizeB;
  final String formattedSize;
  final int lastUsedAt;
  final int downloadedAt;
  final MnnLocalDownloadInfo? download;

  const MnnLocalModel({
    required this.id,
    required this.name,
    required this.category,
    required this.source,
    required this.description,
    required this.path,
    required this.vendor,
    required this.tags,
    required this.extraTags,
    required this.active,
    required this.isLocal,
    required this.isPinned,
    required this.hasUpdate,
    required this.fileSize,
    required this.sizeB,
    required this.formattedSize,
    required this.lastUsedAt,
    required this.downloadedAt,
    this.download,
  });

  factory MnnLocalModel.fromMap(Map<dynamic, dynamic>? map) {
    return MnnLocalModel(
      id: (map?['id'] ?? '').toString(),
      name: (map?['name'] ?? '').toString(),
      category: (map?['category'] ?? 'llm').toString(),
      source: (map?['source'] ?? '').toString(),
      description: (map?['description'] ?? '').toString(),
      path: (map?['path'] ?? '').toString(),
      vendor: (map?['vendor'] ?? '').toString(),
      tags: ((map?['tags'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(),
      extraTags: ((map?['extraTags'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(),
      active: map?['active'] == true,
      isLocal: map?['isLocal'] == true,
      isPinned: map?['isPinned'] == true,
      hasUpdate: map?['hasUpdate'] == true,
      fileSize: (map?['fileSize'] as num?)?.toInt() ?? 0,
      sizeB: (map?['sizeB'] as num?)?.toDouble() ?? 0,
      formattedSize: (map?['formattedSize'] ?? '').toString(),
      lastUsedAt: (map?['lastUsedAt'] as num?)?.toInt() ?? 0,
      downloadedAt: (map?['downloadedAt'] as num?)?.toInt() ?? 0,
      download: map?['download'] is Map
          ? MnnLocalDownloadInfo.fromMap(map?['download'] as Map?)
          : null,
    );
  }
}

class MnnLocalConfig {
  final String backend;
  final bool autoStartOnAppOpen;
  final bool apiEnabled;
  final bool apiLanEnabled;
  final bool apiRunning;
  final bool apiReady;
  final String apiState;
  final String apiHost;
  final int apiPort;
  final String apiKey;
  final String baseUrl;
  final String activeModelId;
  final String speechRecognitionProvider;
  final String defaultAsrModelId;
  final String defaultTtsModelId;
  final String downloadProvider;
  final List<String> availableSources;
  final bool voiceReady;
  final String voiceStatusText;
  final List<MnnLocalModel> installedAsrModels;
  final List<MnnLocalModel> installedTtsModels;

  const MnnLocalConfig({
    required this.backend,
    required this.autoStartOnAppOpen,
    required this.apiEnabled,
    required this.apiLanEnabled,
    required this.apiRunning,
    required this.apiReady,
    required this.apiState,
    required this.apiHost,
    required this.apiPort,
    required this.apiKey,
    required this.baseUrl,
    required this.activeModelId,
    required this.speechRecognitionProvider,
    required this.defaultAsrModelId,
    required this.defaultTtsModelId,
    required this.downloadProvider,
    required this.availableSources,
    required this.voiceReady,
    required this.voiceStatusText,
    required this.installedAsrModels,
    required this.installedTtsModels,
  });

  factory MnnLocalConfig.fromMap(Map<dynamic, dynamic>? map) {
    return MnnLocalConfig(
      backend: (map?['backend'] ?? 'llama.cpp').toString(),
      autoStartOnAppOpen: map?['autoStartOnAppOpen'] == true,
      apiEnabled: map?['apiEnabled'] == true,
      apiLanEnabled: map?['apiLanEnabled'] == true,
      apiRunning: map?['apiRunning'] == true,
      apiReady: map?['apiReady'] == true,
      apiState: (map?['apiState'] ?? 'stopped').toString(),
      apiHost: (map?['apiHost'] ?? '').toString(),
      apiPort: (map?['apiPort'] as num?)?.toInt() ?? 8080,
      apiKey: (map?['apiKey'] ?? '').toString(),
      baseUrl: (map?['baseUrl'] ?? '').toString(),
      activeModelId: (map?['activeModelId'] ?? '').toString(),
      speechRecognitionProvider: (map?['speechRecognitionProvider'] ?? 'system')
          .toString(),
      defaultAsrModelId: (map?['defaultAsrModelId'] ?? '').toString(),
      defaultTtsModelId: (map?['defaultTtsModelId'] ?? '').toString(),
      downloadProvider: (map?['downloadProvider'] ?? 'ModelScope').toString(),
      availableSources: ((map?['availableSources'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(),
      voiceReady: map?['voiceReady'] == true,
      voiceStatusText: (map?['voiceStatusText'] ?? '').toString(),
      installedAsrModels: ((map?['installedAsrModels'] as List?) ?? const [])
          .map((item) => MnnLocalModel.fromMap(item as Map?))
          .toList(),
      installedTtsModels: ((map?['installedTtsModels'] as List?) ?? const [])
          .map((item) => MnnLocalModel.fromMap(item as Map?))
          .toList(),
    );
  }
}

class MnnLocalMarketPayload {
  final String source;
  final String category;
  final List<String> availableSources;
  final List<MnnLocalModel> models;

  const MnnLocalMarketPayload({
    required this.source,
    required this.category,
    required this.availableSources,
    required this.models,
  });

  factory MnnLocalMarketPayload.fromMap(Map<dynamic, dynamic>? map) {
    return MnnLocalMarketPayload(
      source: (map?['source'] ?? '').toString(),
      category: (map?['category'] ?? 'llm').toString(),
      availableSources: ((map?['availableSources'] as List?) ?? const [])
          .map((item) => item.toString())
          .toList(),
      models: ((map?['models'] as List?) ?? const [])
          .map((item) => MnnLocalModel.fromMap(item as Map?))
          .toList(),
    );
  }
}

class MnnLocalOverviewPayload {
  final MnnLocalConfig config;
  final List<MnnLocalModel> installedModels;
  final MnnLocalMarketPayload market;

  const MnnLocalOverviewPayload({
    required this.config,
    required this.installedModels,
    required this.market,
  });

  factory MnnLocalOverviewPayload.fromMap(Map<dynamic, dynamic>? map) {
    return MnnLocalOverviewPayload(
      config: MnnLocalConfig.fromMap(map?['config'] as Map?),
      installedModels: ((map?['installedModels'] as List?) ?? const [])
          .map((item) => MnnLocalModel.fromMap(item as Map?))
          .toList(),
      market: MnnLocalMarketPayload.fromMap(map?['market'] as Map?),
    );
  }
}

class MnnLocalBenchmarkProgress {
  final int progress;
  final String statusMessage;
  final String progressType;
  final int currentIteration;
  final int totalIterations;
  final int nPrompt;
  final int nGenerate;
  final double runTimeSeconds;
  final double prefillTimeSeconds;
  final double decodeTimeSeconds;
  final double prefillSpeed;
  final double decodeSpeed;

  const MnnLocalBenchmarkProgress({
    required this.progress,
    required this.statusMessage,
    required this.progressType,
    required this.currentIteration,
    required this.totalIterations,
    required this.nPrompt,
    required this.nGenerate,
    required this.runTimeSeconds,
    required this.prefillTimeSeconds,
    required this.decodeTimeSeconds,
    required this.prefillSpeed,
    required this.decodeSpeed,
  });

  factory MnnLocalBenchmarkProgress.fromMap(Map<dynamic, dynamic>? map) {
    return MnnLocalBenchmarkProgress(
      progress: (map?['progress'] as num?)?.toInt() ?? 0,
      statusMessage: (map?['statusMessage'] ?? '').toString(),
      progressType: (map?['progressType'] ?? 'unknown').toString(),
      currentIteration: (map?['currentIteration'] as num?)?.toInt() ?? 0,
      totalIterations: (map?['totalIterations'] as num?)?.toInt() ?? 0,
      nPrompt: (map?['nPrompt'] as num?)?.toInt() ?? 0,
      nGenerate: (map?['nGenerate'] as num?)?.toInt() ?? 0,
      runTimeSeconds: (map?['runTimeSeconds'] as num?)?.toDouble() ?? 0,
      prefillTimeSeconds: (map?['prefillTimeSeconds'] as num?)?.toDouble() ?? 0,
      decodeTimeSeconds: (map?['decodeTimeSeconds'] as num?)?.toDouble() ?? 0,
      prefillSpeed: (map?['prefillSpeed'] as num?)?.toDouble() ?? 0,
      decodeSpeed: (map?['decodeSpeed'] as num?)?.toDouble() ?? 0,
    );
  }
}

class MnnLocalBenchmarkResult {
  final bool success;
  final String errorMessage;
  final String backend;
  final String modelId;
  final int repeat;
  final int nPrompt;
  final int nGenerate;
  final int threads;
  final bool useMmap;
  final double prefillSpeedAvg;
  final double decodeSpeedAvg;
  final List<double> prefillSpeedSamples;
  final List<double> decodeSpeedSamples;
  final List<int> prefillUs;
  final List<int> decodeUs;
  final String title;

  const MnnLocalBenchmarkResult({
    required this.success,
    required this.errorMessage,
    required this.backend,
    required this.modelId,
    required this.repeat,
    required this.nPrompt,
    required this.nGenerate,
    required this.threads,
    required this.useMmap,
    required this.prefillSpeedAvg,
    required this.decodeSpeedAvg,
    required this.prefillSpeedSamples,
    required this.decodeSpeedSamples,
    required this.prefillUs,
    required this.decodeUs,
    required this.title,
  });

  factory MnnLocalBenchmarkResult.fromMap(Map<dynamic, dynamic>? map) {
    return MnnLocalBenchmarkResult(
      success: map?['success'] == true,
      errorMessage: (map?['errorMessage'] ?? '').toString(),
      backend: (map?['backend'] ?? 'cpu').toString(),
      modelId: (map?['modelId'] ?? '').toString(),
      repeat: (map?['repeat'] as num?)?.toInt() ?? 0,
      nPrompt: (map?['nPrompt'] as num?)?.toInt() ?? 0,
      nGenerate: (map?['nGenerate'] as num?)?.toInt() ?? 0,
      threads: (map?['threads'] as num?)?.toInt() ?? 0,
      useMmap: map?['useMmap'] == true,
      prefillSpeedAvg: (map?['prefillSpeedAvg'] as num?)?.toDouble() ?? 0,
      decodeSpeedAvg: (map?['decodeSpeedAvg'] as num?)?.toDouble() ?? 0,
      prefillSpeedSamples: ((map?['prefillSpeedSamples'] as List?) ?? const [])
          .map((item) => (item as num).toDouble())
          .toList(),
      decodeSpeedSamples: ((map?['decodeSpeedSamples'] as List?) ?? const [])
          .map((item) => (item as num).toDouble())
          .toList(),
      prefillUs: ((map?['prefillUs'] as List?) ?? const [])
          .map((item) => (item as num).toInt())
          .toList(),
      decodeUs: ((map?['decodeUs'] as List?) ?? const [])
          .map((item) => (item as num).toInt())
          .toList(),
      title: (map?['title'] ?? '').toString(),
    );
  }
}

class MnnLocalBenchmarkState {
  final bool running;
  final String status;
  final String modelId;
  final String backend;
  final String errorMessage;
  final int updatedAt;
  final MnnLocalBenchmarkProgress? progress;
  final List<MnnLocalBenchmarkResult> results;

  const MnnLocalBenchmarkState({
    required this.running,
    required this.status,
    required this.modelId,
    required this.backend,
    required this.errorMessage,
    required this.updatedAt,
    required this.progress,
    required this.results,
  });

  factory MnnLocalBenchmarkState.fromMap(Map<dynamic, dynamic>? map) {
    return MnnLocalBenchmarkState(
      running: map?['running'] == true,
      status: (map?['status'] ?? 'idle').toString(),
      modelId: (map?['modelId'] ?? '').toString(),
      backend: (map?['backend'] ?? 'cpu').toString(),
      errorMessage: (map?['errorMessage'] ?? '').toString(),
      updatedAt: (map?['updatedAt'] as num?)?.toInt() ?? 0,
      progress: map?['progress'] is Map
          ? MnnLocalBenchmarkProgress.fromMap(map?['progress'] as Map?)
          : null,
      results: ((map?['results'] as List?) ?? const [])
          .map((item) => MnnLocalBenchmarkResult.fromMap(item as Map?))
          .toList(),
    );
  }
}

class MnnLocalEvent {
  final String type;
  final Map<String, dynamic> payload;

  const MnnLocalEvent({required this.type, required this.payload});

  factory MnnLocalEvent.fromDynamic(dynamic raw) {
    final map = (raw as Map?)?.cast<dynamic, dynamic>() ?? const {};
    return MnnLocalEvent(
      type: (map['type'] ?? '').toString(),
      payload: map.map((key, value) => MapEntry(key.toString(), value)),
    );
  }
}

class MnnLocalModelsService {
  static const MethodChannel _channel = MethodChannel(
    'cn.com.omnimind.bot/MnnLocalModels',
  );
  static const EventChannel _events = EventChannel(
    'cn.com.omnimind.bot/MnnLocalModelsEvents',
  );

  static Stream<MnnLocalEvent> get eventStream =>
      _events.receiveBroadcastStream().map(MnnLocalEvent.fromDynamic);

  static Future<MnnLocalOverviewPayload> getOverview({
    String installedQuery = '',
    String marketQuery = '',
    String marketCategory = 'llm',
  }) async {
    final result = await _channel
        .invokeMethod<Map<dynamic, dynamic>>('getOverview', {
          'installedQuery': installedQuery,
          'marketQuery': marketQuery,
          'marketCategory': marketCategory.trim().toLowerCase(),
        });
    return MnnLocalOverviewPayload.fromMap(result);
  }

  static Future<List<MnnLocalModel>> listInstalledModels({
    String query = '',
    String category = 'all',
  }) async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'listInstalledModels',
      {'query': query, 'category': category},
    );
    return (result ?? const [])
        .map((item) => MnnLocalModel.fromMap(item as Map?))
        .toList();
  }

  static Future<List<MnnLocalModel>> refreshInstalledModels() async {
    final result = await _channel.invokeMethod<List<dynamic>>(
      'refreshInstalledModels',
    );
    return (result ?? const [])
        .map((item) => MnnLocalModel.fromMap(item as Map?))
        .toList();
  }

  static Future<MnnLocalMarketPayload> listMarketModels({
    String query = '',
    String category = 'llm',
    bool refresh = false,
  }) async {
    final normalizedCategory = category.trim().toLowerCase();
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'listMarketModels',
      {'query': query, 'category': normalizedCategory, 'refresh': refresh},
    );
    return MnnLocalMarketPayload.fromMap(result);
  }

  static Future<MnnLocalConfig> getConfig() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getConfig',
    );
    return MnnLocalConfig.fromMap(result);
  }

  static Future<MnnLocalConfig> saveConfig({
    bool? autoStartOnAppOpen,
    bool? apiLanEnabled,
    int? apiPort,
    String? apiKey,
    String? activeModelId,
    String? speechRecognitionProvider,
    String? defaultAsrModelId,
    String? defaultTtsModelId,
    String? downloadProvider,
  }) async {
    final result = await _channel
        .invokeMethod<Map<dynamic, dynamic>>('saveConfig', {
          if (autoStartOnAppOpen != null)
            'autoStartOnAppOpen': autoStartOnAppOpen,
          if (apiLanEnabled != null) 'apiLanEnabled': apiLanEnabled,
          if (apiPort != null) 'apiPort': apiPort,
          if (apiKey != null) 'apiKey': apiKey,
          if (activeModelId != null) 'activeModelId': activeModelId,
          if (speechRecognitionProvider != null)
            'speechRecognitionProvider': speechRecognitionProvider,
          if (defaultAsrModelId != null) 'defaultAsrModelId': defaultAsrModelId,
          if (defaultTtsModelId != null) 'defaultTtsModelId': defaultTtsModelId,
          if (downloadProvider != null) 'downloadProvider': downloadProvider,
        });
    return MnnLocalConfig.fromMap(result);
  }

  static Future<MnnLocalConfig> setActiveModel(String? modelId) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'setActiveModel',
      {'modelId': modelId},
    );
    return MnnLocalConfig.fromMap(result);
  }

  static Future<MnnLocalConfig> startApiService({String? modelId}) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'startApiService',
      {'modelId': modelId},
    );
    return MnnLocalConfig.fromMap(result);
  }

  static Future<MnnLocalConfig> stopApiService() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'stopApiService',
    );
    return MnnLocalConfig.fromMap(result);
  }

  static Future<void> startDownload(String modelId) {
    return _channel.invokeMethod('startDownload', {'modelId': modelId});
  }

  static Future<void> pauseDownload(String modelId) {
    return _channel.invokeMethod('pauseDownload', {'modelId': modelId});
  }

  static Future<List<MnnLocalModel>> deleteModel(String modelId) async {
    final result = await _channel.invokeMethod<List<dynamic>>('deleteModel', {
      'modelId': modelId,
    });
    return (result ?? const [])
        .map((item) => MnnLocalModel.fromMap(item as Map?))
        .toList();
  }

  static Future<Map<dynamic, dynamic>?> startGeneration({
    required String prompt,
    String? modelId,
    String? imagePath,
    String? audioPath,
    String? videoPath,
    String? outputPath,
    bool enableAudioOutput = false,
    int steps = 20,
    int seed = 1024,
    bool useCfg = true,
    double cfgScale = 4.5,
  }) {
    return _channel.invokeMethod<Map<dynamic, dynamic>>('startGeneration', {
      'prompt': prompt,
      if (modelId != null) 'modelId': modelId,
      if (imagePath != null) 'imagePath': imagePath,
      if (audioPath != null) 'audioPath': audioPath,
      if (videoPath != null) 'videoPath': videoPath,
      if (outputPath != null) 'outputPath': outputPath,
      'enableAudioOutput': enableAudioOutput,
      'steps': steps,
      'seed': seed,
      'useCfg': useCfg,
      'cfgScale': cfgScale,
    });
  }

  static Future<void> stopGeneration() {
    return _channel.invokeMethod('stopGeneration');
  }

  static Future<void> resetInferenceSession() {
    return _channel.invokeMethod('resetInferenceSession');
  }

  static Future<MnnLocalBenchmarkState> getBenchmarkState() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'getBenchmarkState',
    );
    return MnnLocalBenchmarkState.fromMap(result);
  }

  static Future<MnnLocalBenchmarkState> startBenchmark({
    required String modelId,
    String backend = 'cpu',
    int nPrompt = 512,
    int nGenerate = 128,
    int repeat = 5,
  }) async {
    final result = await _channel
        .invokeMethod<Map<dynamic, dynamic>>('startBenchmark', {
          'modelId': modelId,
          'backend': backend,
          'nPrompt': nPrompt,
          'nGenerate': nGenerate,
          'repeat': repeat,
        });
    return MnnLocalBenchmarkState.fromMap(result);
  }

  static Future<MnnLocalBenchmarkState> stopBenchmark() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'stopBenchmark',
    );
    return MnnLocalBenchmarkState.fromMap(result);
  }

  static Future<String> getBackend() async {
    final result = await _channel.invokeMethod<String>('getBackend');
    return result ?? 'llama.cpp';
  }

  static Future<String> setBackend(String backend) async {
    final result = await _channel.invokeMethod<String>(
      'setBackend',
      {'backend': backend},
    );
    return result ?? backend;
  }
}
