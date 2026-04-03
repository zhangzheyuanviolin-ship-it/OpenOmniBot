import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ui/services/mnn_local_models_service.dart';
import 'package:ui/theme/app_colors.dart';
import 'package:ui/utils/ui.dart';
import 'package:ui/widgets/common_app_bar.dart';

enum _LocalModelsTab { installed, market, inference, service }

class LocalModelsPage extends StatefulWidget {
  const LocalModelsPage({super.key, this.initialTab = 'installed'});

  final String initialTab;

  @override
  State<LocalModelsPage> createState() => _LocalModelsPageState();
}

class _LocalModelsPageState extends State<LocalModelsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  final TextEditingController _installedSearchController =
      TextEditingController();
  final TextEditingController _marketSearchController = TextEditingController();
  final TextEditingController _promptController = TextEditingController();
  final TextEditingController _imagePathController = TextEditingController();
  final TextEditingController _audioPathController = TextEditingController();
  final TextEditingController _videoPathController = TextEditingController();
  final TextEditingController _outputPathController = TextEditingController();
  final TextEditingController _portController = TextEditingController();
  final TextEditingController _apiKeyController = TextEditingController();
  final TextEditingController _benchmarkPromptController =
      TextEditingController(text: '512');
  final TextEditingController _benchmarkGenerateController =
      TextEditingController(text: '128');
  final TextEditingController _benchmarkRepeatController =
      TextEditingController(text: '5');

  StreamSubscription<MnnLocalEvent>? _eventSubscription;
  Timer? _pollTimer;

  MnnLocalConfig? _config;
  MnnLocalBenchmarkState? _benchmarkState;
  List<MnnLocalModel> _installedModels = const [];
  List<MnnLocalModel> _marketModels = const [];

  bool _loadingInstalled = true;
  bool _loadingMarket = true;
  bool _loadingConfig = true;
  bool _savingConfig = false;
  bool _startingBenchmark = false;
  bool _generating = false;

  String _installedCategory = 'all';
  String _marketCategory = 'all';
  String _generationOutput = '';
  String _generationMetrics = '';
  String _activeRequestId = '';
  String _benchmarkBackend = 'cpu';
  String? _benchmarkModelId;
  bool _enableAudioOutput = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: _LocalModelsTab.values.length,
      vsync: this,
      initialIndex: _tabIndexFromName(widget.initialTab),
    );
    _tabController.addListener(_handleTabChanged);
    _eventSubscription = MnnLocalModelsService.eventStream.listen(_handleEvent);
    _bootstrap();
    _startPolling();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _eventSubscription?.cancel();
    _tabController
      ..removeListener(_handleTabChanged)
      ..dispose();
    _installedSearchController.dispose();
    _marketSearchController.dispose();
    _promptController.dispose();
    _imagePathController.dispose();
    _audioPathController.dispose();
    _videoPathController.dispose();
    _outputPathController.dispose();
    _portController.dispose();
    _apiKeyController.dispose();
    _benchmarkPromptController.dispose();
    _benchmarkGenerateController.dispose();
    _benchmarkRepeatController.dispose();
    super.dispose();
  }

  int _tabIndexFromName(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'market':
        return _LocalModelsTab.market.index;
      case 'inference':
        return _LocalModelsTab.inference.index;
      case 'service':
        return _LocalModelsTab.service.index;
      case 'installed':
      default:
        return _LocalModelsTab.installed.index;
    }
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _refreshConfig(),
      _refreshInstalled(),
      _refreshMarket(),
      _refreshBenchmarkState(),
    ]);
  }

  void _handleTabChanged() {
    if (_tabController.indexIsChanging) {
      return;
    }
    switch (_LocalModelsTab.values[_tabController.index]) {
      case _LocalModelsTab.installed:
        _refreshInstalled(silent: true);
        _refreshBenchmarkState(silent: true);
        break;
      case _LocalModelsTab.market:
        _refreshMarket(silent: true);
        break;
      case _LocalModelsTab.inference:
        _refreshInstalled(silent: true);
        break;
      case _LocalModelsTab.service:
        _refreshConfig(silent: true);
        break;
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (!mounted) return;
      switch (_LocalModelsTab.values[_tabController.index]) {
        case _LocalModelsTab.installed:
          _refreshInstalled(silent: true);
          _refreshBenchmarkState(silent: true);
          break;
        case _LocalModelsTab.market:
          _refreshMarket(silent: true);
          break;
        case _LocalModelsTab.inference:
          if (_generating) {
            _refreshConfig(silent: true);
          }
          break;
        case _LocalModelsTab.service:
          _refreshConfig(silent: true);
          break;
      }
    });
  }

  Future<void> _refreshConfig({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _loadingConfig = true);
    }
    try {
      final config = await MnnLocalModelsService.getConfig();
      if (!mounted) return;
      setState(() {
        _config = config;
        _loadingConfig = false;
      });
      if (_portController.text != config.apiPort.toString()) {
        _portController.text = config.apiPort.toString();
      }
      if (_apiKeyController.text != config.apiKey) {
        _apiKeyController.text = config.apiKey;
      }
    } catch (error) {
      if (!mounted) return;
      if (!silent) {
        showToast('加载本地模型配置失败', type: ToastType.error);
      }
      setState(() => _loadingConfig = false);
    }
  }

  Future<void> _refreshInstalled({bool silent = false}) async {
    if (!silent && mounted) {
      setState(() => _loadingInstalled = true);
    }
    try {
      final models = await MnnLocalModelsService.listInstalledModels(
        query: _installedSearchController.text.trim(),
        category: _installedCategory,
      );
      if (!mounted) return;
      setState(() {
        _installedModels = models;
        _loadingInstalled = false;
        final benchmarkModelStillExists = _benchmarkModelId != null &&
            models.any((item) => item.id == _benchmarkModelId);
        if (!benchmarkModelStillExists) {
          final llmModels = models.where((item) => item.category == 'llm');
          _benchmarkModelId = llmModels.isNotEmpty ? llmModels.first.id : null;
        }
      });
    } catch (error) {
      if (!mounted) return;
      if (!silent) {
        showToast('加载已安装模型失败', type: ToastType.error);
      }
      setState(() => _loadingInstalled = false);
    }
  }

  Future<void> _refreshMarket({bool silent = false, bool refresh = false}) async {
    if (!silent && mounted) {
      setState(() => _loadingMarket = true);
    }
    try {
      final payload = await MnnLocalModelsService.listMarketModels(
        query: _marketSearchController.text.trim(),
        category: _marketCategory,
        refresh: refresh,
      );
      if (!mounted) return;
      setState(() {
        _marketModels = payload.models;
        _loadingMarket = false;
      });
    } catch (error) {
      if (!mounted) return;
      if (!silent) {
        showToast('加载模型市场失败', type: ToastType.error);
      }
      setState(() => _loadingMarket = false);
    }
  }

  Future<void> _refreshBenchmarkState({bool silent = false}) async {
    try {
      final state = await MnnLocalModelsService.getBenchmarkState();
      if (!mounted) return;
      setState(() {
        _benchmarkState = state;
        if (_benchmarkModelId == null && state.modelId.isNotEmpty) {
          _benchmarkModelId = state.modelId;
        }
        if (state.backend.isNotEmpty) {
          _benchmarkBackend = state.backend;
        }
      });
    } catch (error) {
      if (!silent) {
        showToast('加载 Benchmark 状态失败', type: ToastType.error);
      }
    }
  }

  void _handleEvent(MnnLocalEvent event) {
    if (!mounted) return;
    switch (event.type) {
      case 'download_update':
        final modelId = (event.payload['modelId'] ?? '').toString();
        final rawDownload = event.payload['download'];
        final download = rawDownload is Map
            ? MnnLocalDownloadInfo.fromMap(rawDownload)
            : null;
        _updateMarketDownloadState(modelId, download);
        if (download?.isCompleted == true) {
          _refreshInstalled(silent: true);
        }
        break;
      case 'generation_started':
        setState(() {
          _generating = true;
          _activeRequestId = (event.payload['requestId'] ?? '').toString();
          _generationOutput = '';
          _generationMetrics = '';
        });
        break;
      case 'generation_chunk':
        if (_activeRequestId.isNotEmpty &&
            _activeRequestId != (event.payload['requestId'] ?? '').toString()) {
          return;
        }
        setState(() {
          _generationOutput += (event.payload['text'] ?? '').toString();
        });
        break;
      case 'generation_completed':
        final resultRaw = event.payload['result'];
        final result = resultRaw is Map
            ? resultRaw.map((key, value) => MapEntry(key.toString(), value))
            : const <String, dynamic>{};
        final outputPath = (result['output'] ?? result['output_path'] ?? '')
            .toString();
        setState(() {
          _generating = false;
          _generationMetrics = (event.payload['metricsText'] ?? '').toString();
          if (outputPath.isNotEmpty &&
              !_generationOutput.contains(outputPath)) {
            if (_generationOutput.isNotEmpty) {
              _generationOutput += '\n\n';
            }
            _generationOutput += '生成文件：$outputPath';
          }
        });
        _refreshConfig(silent: true);
        break;
      case 'generation_error':
        setState(() {
          _generating = false;
          _generationMetrics = '';
        });
        showToast(
          (event.payload['message'] ?? '本地推理失败').toString(),
          type: ToastType.error,
        );
        break;
      case 'generation_cancelled':
        setState(() {
          _generating = false;
        });
        showToast('已停止本地推理');
        break;
      case 'config_changed':
        _refreshConfig(silent: true);
        break;
      case 'downloads_changed':
        _refreshInstalled(silent: true);
        _refreshMarket(silent: true);
        break;
      case 'benchmark_started':
      case 'benchmark_progress':
      case 'benchmark_result':
      case 'benchmark_stop_requested':
      case 'benchmark_finished':
      case 'benchmark_stopped':
      case 'benchmark_error':
        final statePayload = event.payload['state'];
        if (statePayload is Map) {
          setState(() {
            _benchmarkState = MnnLocalBenchmarkState.fromMap(statePayload);
            if (_benchmarkState!.modelId.isNotEmpty) {
              _benchmarkModelId = _benchmarkState!.modelId;
            }
            if (_benchmarkState!.backend.isNotEmpty) {
              _benchmarkBackend = _benchmarkState!.backend;
            }
          });
        } else {
          _refreshBenchmarkState(silent: true);
        }
        if (event.type == 'benchmark_finished') {
          showToast('Benchmark 已完成', type: ToastType.success);
        } else if (event.type == 'benchmark_stopped') {
          showToast('Benchmark 已停止');
        } else if (event.type == 'benchmark_error') {
          showToast(
            (event.payload['message'] ?? 'Benchmark 运行失败').toString(),
            type: ToastType.error,
          );
        }
        break;
      default:
        break;
    }
  }

  void _updateMarketDownloadState(
    String modelId,
    MnnLocalDownloadInfo? download,
  ) {
    if (modelId.isEmpty || !mounted) {
      return;
    }
    final targetIndex = _marketModels.indexWhere((item) => item.id == modelId);
    if (targetIndex < 0) {
      return;
    }
    final current = _marketModels[targetIndex];
    final updated = _copyModelWithDownload(current, download);
    setState(() {
      _marketModels = List<MnnLocalModel>.from(_marketModels)
        ..[targetIndex] = updated;
    });
  }

  MnnLocalModel _copyModelWithDownload(
    MnnLocalModel model,
    MnnLocalDownloadInfo? download,
  ) {
    return MnnLocalModel(
      id: model.id,
      name: model.name,
      category: model.category,
      source: model.source,
      description: model.description,
      path: model.path,
      vendor: model.vendor,
      tags: model.tags,
      extraTags: model.extraTags,
      active: model.active,
      isLocal: model.isLocal,
      isPinned: model.isPinned,
      hasUpdate: model.hasUpdate,
      fileSize: model.fileSize,
      sizeB: model.sizeB,
      formattedSize: model.formattedSize,
      lastUsedAt: model.lastUsedAt,
      downloadedAt: model.downloadedAt,
      download: download,
    );
  }

  MnnLocalDownloadInfo _downloadPlaceholder({
    required String stateLabel,
    double progress = 0,
    String progressStage = '',
  }) {
    return MnnLocalDownloadInfo(
      state: 0,
      stateLabel: stateLabel,
      progress: progress,
      savedSize: 0,
      totalSize: 0,
      speedInfo: '',
      errorMessage: '',
      progressStage: progressStage,
      currentFile: '',
      hasUpdate: false,
    );
  }

  String _downloadStatusLabel(MnnLocalDownloadInfo download) {
    switch (download.stateLabel) {
      case 'preparing':
        return '准备中';
      case 'downloading':
        return download.progressStage.trim().isNotEmpty
            ? download.progressStage.trim()
            : '下载中';
      case 'paused':
        return '已暂停';
      case 'completed':
        return '已完成';
      case 'failed':
        return '下载失败';
      case 'cancelled':
        return '已取消';
      case 'not_started':
        return '未下载';
      default:
        return download.stateLabel;
    }
  }

  Future<void> _setActiveModel(String? modelId) async {
    try {
      final config = await MnnLocalModelsService.setActiveModel(modelId);
      if (!mounted) return;
      setState(() {
        _config = config;
      });
      showToast('已更新当前推理模型');
      _refreshInstalled(silent: true);
    } catch (error) {
      showToast('设置当前模型失败', type: ToastType.error);
    }
  }

  Future<void> _saveServiceConfig() async {
    final port = int.tryParse(_portController.text.trim());
    if (port == null || port <= 0) {
      showToast('端口格式不正确', type: ToastType.warning);
      return;
    }
    setState(() => _savingConfig = true);
    try {
      final config = await MnnLocalModelsService.saveConfig(
        apiPort: port,
        apiKey: _apiKeyController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _config = config;
      });
      showToast('本地模型服务配置已保存', type: ToastType.success);
    } catch (error) {
      showToast('保存配置失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _savingConfig = false);
      }
    }
  }

  Future<void> _toggleApiService(bool enable) async {
    try {
      final nextConfig = enable
          ? await MnnLocalModelsService.startApiService(
              modelId: _config?.activeModelId.isEmpty == true
                  ? null
                  : _config?.activeModelId,
            )
          : await MnnLocalModelsService.stopApiService();
      if (!mounted) return;
      setState(() {
        _config = nextConfig;
      });
      showToast(enable ? '本地 API 服务已启动' : '本地 API 服务已停止');
    } catch (error) {
      showToast(enable ? '启动 API 服务失败' : '停止 API 服务失败', type: ToastType.error);
    }
  }

  Future<void> _startGeneration() async {
    final selectedModelId = _config?.activeModelId ?? '';
    if (selectedModelId.isEmpty) {
      showToast('请先选择一个本地模型', type: ToastType.warning);
      return;
    }
    if (_promptController.text.trim().isEmpty &&
        _imagePathController.text.trim().isEmpty &&
        _audioPathController.text.trim().isEmpty &&
        _videoPathController.text.trim().isEmpty) {
      showToast('请输入提示词或附件路径', type: ToastType.warning);
      return;
    }
    try {
      await MnnLocalModelsService.startGeneration(
        modelId: selectedModelId,
        prompt: _promptController.text.trim(),
        imagePath: _imagePathController.text.trim().isEmpty
            ? null
            : _imagePathController.text.trim(),
        audioPath: _audioPathController.text.trim().isEmpty
            ? null
            : _audioPathController.text.trim(),
        videoPath: _videoPathController.text.trim().isEmpty
            ? null
            : _videoPathController.text.trim(),
        outputPath: _outputPathController.text.trim().isEmpty
            ? null
            : _outputPathController.text.trim(),
        enableAudioOutput: _enableAudioOutput,
      );
    } catch (error) {
      showToast('启动本地推理失败', type: ToastType.error);
    }
  }

  Future<void> _updateSpeechProvider(String value) async {
    try {
      final config = await MnnLocalModelsService.saveConfig(
        speechRecognitionProvider: value,
      );
      if (!mounted) return;
      setState(() {
        _config = config;
      });
      showToast('语音输入引擎已更新');
    } catch (error) {
      showToast('更新语音输入引擎失败', type: ToastType.error);
    }
  }

  Future<void> _updateVoiceDefault({
    String? asrModelId,
    String? ttsModelId,
  }) async {
    try {
      final config = await MnnLocalModelsService.saveConfig(
        defaultAsrModelId: asrModelId,
        defaultTtsModelId: ttsModelId,
      );
      if (!mounted) return;
      setState(() {
        _config = config;
      });
      showToast('语音模型设置已更新');
    } catch (error) {
      showToast('更新语音模型失败', type: ToastType.error);
    }
  }

  Future<void> _startBenchmark({String? modelId}) async {
    final resolvedModelId = modelId ?? _benchmarkModelId;
    if (resolvedModelId == null || resolvedModelId.isEmpty) {
      showToast('请先选择一个 LLM 模型进行 Benchmark', type: ToastType.warning);
      return;
    }
    final nPrompt = int.tryParse(_benchmarkPromptController.text.trim()) ?? 512;
    final nGenerate =
        int.tryParse(_benchmarkGenerateController.text.trim()) ?? 128;
    final repeat = int.tryParse(_benchmarkRepeatController.text.trim()) ?? 5;
    setState(() => _startingBenchmark = true);
    try {
      final state = await MnnLocalModelsService.startBenchmark(
        modelId: resolvedModelId,
        backend: _benchmarkBackend,
        nPrompt: nPrompt,
        nGenerate: nGenerate,
        repeat: repeat,
      );
      if (!mounted) return;
      setState(() {
        _benchmarkState = state;
        _benchmarkModelId = resolvedModelId;
      });
      showToast('Benchmark 已启动');
    } catch (error) {
      showToast('启动 Benchmark 失败', type: ToastType.error);
    } finally {
      if (mounted) {
        setState(() => _startingBenchmark = false);
      }
    }
  }

  Future<void> _stopBenchmark() async {
    try {
      final state = await MnnLocalModelsService.stopBenchmark();
      if (!mounted) return;
      setState(() {
        _benchmarkState = state;
      });
    } catch (error) {
      showToast('停止 Benchmark 失败', type: ToastType.error);
    }
  }

  List<MnnLocalModel> get _inferenceModels => _installedModels
      .where((model) => model.category != 'asr' && model.category != 'tts' && model.category != 'libs')
      .toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: const CommonAppBar(title: '本地模型', primary: true),
      body: Column(
        children: [
          Material(
            color: AppColors.background,
            child: TabBar(
              controller: _tabController,
              labelColor: AppColors.text,
              unselectedLabelColor: AppColors.text50,
              indicatorColor: AppColors.buttonPrimary,
              tabs: const [
                Tab(text: '已安装'),
                Tab(text: '模型市场'),
                Tab(text: '推理台'),
                Tab(text: '服务与语音'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildInstalledTab(),
                _buildMarketTab(),
                _buildInferenceTab(),
                _buildServiceTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstalledTab() {
    final llmModels = _installedModels
        .where((item) => item.category == 'llm')
        .toList();
    return Column(
      children: [
        _buildSearchBar(
          controller: _installedSearchController,
          hint: '搜索已安装模型',
          onSubmitted: (_) => _refreshInstalled(),
          onRefresh: () => _refreshInstalled(),
        ),
        _buildCategoryChips(
          current: _installedCategory,
          categories: const ['all', 'llm', 'diffusion', 'asr', 'tts'],
          onSelected: (value) {
            setState(() => _installedCategory = value);
            _refreshInstalled();
          },
        ),
        Expanded(
          child: _loadingInstalled
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  children: [
                    _buildBenchmarkCard(llmModels),
                    const SizedBox(height: 12),
                    if (_installedModels.isEmpty)
                      _buildEmptyState(
                        title: '还没有可用的本地模型',
                        subtitle:
                            '可以先到“模型市场”下载模型，或把模型放到 /data/local/tmp/mnn_models 后返回刷新。',
                      )
                    else
                      ..._installedModels.map(_buildInstalledCard),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _buildMarketTab() {
    final config = _config;
    return Column(
      children: [
        _buildSearchBar(
          controller: _marketSearchController,
          hint: '搜索模型市场',
          onSubmitted: (_) => _refreshMarket(),
          onRefresh: () => _refreshMarket(refresh: true),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey(
                    'download-provider-${config?.downloadProvider ?? 'none'}',
                  ),
                  initialValue: config?.downloadProvider.isNotEmpty == true
                      ? config!.downloadProvider
                      : null,
                  decoration: const InputDecoration(
                    labelText: '下载源',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: (config?.availableSources ?? const ['ModelScope'])
                      .map(
                        (item) => DropdownMenuItem<String>(
                          value: item,
                          child: Text(item),
                        ),
                      )
                      .toList(),
                  onChanged: (value) async {
                    if (value == null) return;
                    final nextConfig = await MnnLocalModelsService.saveConfig(
                      downloadProvider: value,
                    );
                    if (!mounted) return;
                    setState(() {
                      _config = nextConfig;
                    });
                    _refreshMarket(refresh: true);
                  },
                ),
              ),
            ],
          ),
        ),
        _buildCategoryChips(
          current: _marketCategory,
          categories: const ['all', 'llm', 'asr', 'tts', 'libs'],
          onSelected: (value) {
            setState(() => _marketCategory = value);
            _refreshMarket();
          },
        ),
        Expanded(
          child: _loadingMarket
              ? const Center(child: CircularProgressIndicator())
              : _marketModels.isEmpty
              ? _buildEmptyState(
                  title: '模型市场暂无结果',
                  subtitle: '试试更换下载源、切换分类，或刷新市场数据。',
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  itemCount: _marketModels.length,
                  itemBuilder: (context, index) {
                    final model = _marketModels[index];
                    return _buildMarketCard(model);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildInferenceTab() {
    final currentModelId = _config?.activeModelId ?? '';
    final isDiffusionModel = _inferenceModels
        .any((item) => item.id == currentModelId && item.category == 'diffusion');
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        DropdownButtonFormField<String>(
          key: ValueKey('inference-model-$currentModelId'),
          initialValue: currentModelId.isNotEmpty &&
                  _inferenceModels.any((item) => item.id == currentModelId)
              ? currentModelId
              : null,
          decoration: const InputDecoration(
            labelText: '当前模型',
            border: OutlineInputBorder(),
          ),
          items: _inferenceModels
              .map(
                (item) => DropdownMenuItem<String>(
                  value: item.id,
                  child: Text('${item.name} · ${item.category.toUpperCase()}'),
                ),
              )
              .toList(),
          onChanged: (value) {
            _setActiveModel(value);
          },
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _promptController,
          minLines: 5,
          maxLines: 8,
          decoration: const InputDecoration(
            labelText: '提示词',
            hintText: '输入文本，或搭配图片 / 音频 / 视频路径一起推理',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding: const EdgeInsets.only(bottom: 8),
          title: const Text('多模态输入'),
          subtitle: const Text('可选：图片、音频、视频本地路径'),
          children: [
            TextField(
              controller: _imagePathController,
              decoration: const InputDecoration(
                labelText: '图片路径',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _audioPathController,
              decoration: const InputDecoration(
                labelText: '音频路径',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _videoPathController,
              decoration: const InputDecoration(
                labelText: '视频路径',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        if (isDiffusionModel) ...[
          const SizedBox(height: 12),
          TextField(
            controller: _outputPathController,
            decoration: const InputDecoration(
              labelText: '输出图片路径',
              border: OutlineInputBorder(),
            ),
          ),
        ],
        const SizedBox(height: 12),
        SwitchListTile(
          value: _enableAudioOutput,
          contentPadding: EdgeInsets.zero,
          title: const Text('生成结果语音播报'),
          subtitle: Text(
            _config?.defaultTtsModelId.isNotEmpty == true
                ? '使用默认 TTS 模型播报输出'
                : '需要先在“服务与语音”里设置默认 TTS 模型',
          ),
          onChanged: (value) {
            setState(() {
              _enableAudioOutput = value;
            });
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton(
                onPressed: _generating ? null : _startGeneration,
                child: Text(_generating ? '推理中…' : '开始推理'),
              ),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: _generating
                  ? () {
                      MnnLocalModelsService.stopGeneration();
                    }
                  : null,
              child: const Text('停止'),
            ),
            const SizedBox(width: 10),
            OutlinedButton(
              onPressed: () {
                MnnLocalModelsService.resetInferenceSession();
                setState(() {
                  _generationOutput = '';
                  _generationMetrics = '';
                });
              },
              child: const Text('重置会话'),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildInfoCard(
          title: '输出',
          child: SelectableText(
            _generationOutput.isEmpty ? '等待本地模型输出…' : _generationOutput,
            style: const TextStyle(height: 1.6),
          ),
        ),
        const SizedBox(height: 12),
        _buildInfoCard(
          title: '性能指标',
          child: Text(
            _generationMetrics.isEmpty ? '暂无数据' : _generationMetrics,
            style: const TextStyle(height: 1.6),
          ),
        ),
      ],
    );
  }

  Widget _buildServiceTab() {
    final config = _config;
    if (_loadingConfig && config == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final resolvedConfig = config;
    if (resolvedConfig == null) {
      return _buildEmptyState(
        title: '本地模型服务尚未就绪',
        subtitle: '请稍后重试。',
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        _buildInfoCard(
          title: 'API 网络服务',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('状态：${resolvedConfig.apiState}'),
              const SizedBox(height: 6),
              Text('Base URL：${resolvedConfig.baseUrl}'),
              const SizedBox(height: 6),
              Text('当前模型：${resolvedConfig.activeModelId.isEmpty ? '未选择' : resolvedConfig.activeModelId}'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () => _toggleApiService(true),
                      child: const Text('启动服务'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _toggleApiService(false),
                      child: const Text('停止服务'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _portController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '端口',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _apiKeyController,
                decoration: const InputDecoration(
                  labelText: 'API Key',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _savingConfig ? null : _saveServiceConfig,
                      child: const Text('保存服务配置'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton(
                    onPressed: () async {
                      await Clipboard.setData(
                        ClipboardData(text: resolvedConfig.baseUrl),
                      );
                      showToast('已复制 Base URL');
                    },
                    child: const Text('复制地址'),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SwitchListTile(
          value: resolvedConfig.autoStartOnAppOpen,
          title: const Text('打开 App 自动预热本地推理'),
          subtitle: const Text('仅在打开 Omnibot 时自动恢复本地模型服务'),
          contentPadding: EdgeInsets.zero,
          onChanged: (value) async {
            final config = await MnnLocalModelsService.saveConfig(
              autoStartOnAppOpen: value,
            );
            if (!mounted) return;
            setState(() {
              _config = config;
            });
          },
        ),
        SwitchListTile(
          value: resolvedConfig.apiLanEnabled,
          title: const Text('允许局域网访问'),
          subtitle: const Text('关闭时仅监听 127.0.0.1，避免默认对外暴露'),
          contentPadding: EdgeInsets.zero,
          onChanged: (value) async {
            final config = await MnnLocalModelsService.saveConfig(
              apiLanEnabled: value,
            );
            if (!mounted) return;
            setState(() {
              _config = config;
            });
          },
        ),
        const SizedBox(height: 12),
        _buildInfoCard(
          title: '语音与默认模型',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'speech-provider-${resolvedConfig.speechRecognitionProvider}',
                ),
                initialValue: resolvedConfig.speechRecognitionProvider,
                decoration: const InputDecoration(
                  labelText: '语音输入引擎',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'system', child: Text('系统现有')),
                  DropdownMenuItem(value: 'mnn_local', child: Text('MNN 本地')),
                  DropdownMenuItem(value: 'disabled', child: Text('关闭')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  _updateSpeechProvider(value);
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'default-asr-${resolvedConfig.defaultAsrModelId}',
                ),
                initialValue: resolvedConfig.defaultAsrModelId.isNotEmpty
                    ? resolvedConfig.defaultAsrModelId
                    : null,
                decoration: const InputDecoration(
                  labelText: '默认 ASR 模型',
                  border: OutlineInputBorder(),
                ),
                items: resolvedConfig.installedAsrModels
                    .map(
                      (item) => DropdownMenuItem<String>(
                        value: item.id,
                        child: Text(item.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  _updateVoiceDefault(asrModelId: value);
                },
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                key: ValueKey(
                  'default-tts-${resolvedConfig.defaultTtsModelId}',
                ),
                initialValue: resolvedConfig.defaultTtsModelId.isNotEmpty
                    ? resolvedConfig.defaultTtsModelId
                    : null,
                decoration: const InputDecoration(
                  labelText: '默认 TTS 模型',
                  border: OutlineInputBorder(),
                ),
                items: resolvedConfig.installedTtsModels
                    .map(
                      (item) => DropdownMenuItem<String>(
                        value: item.id,
                        child: Text(item.name),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  _updateVoiceDefault(ttsModelId: value);
                },
              ),
              const SizedBox(height: 12),
              Text(
                resolvedConfig.voiceStatusText.isEmpty
                    ? (resolvedConfig.voiceReady ? '语音模型状态正常' : '尚未配置语音模型')
                    : resolvedConfig.voiceStatusText,
                style: TextStyle(
                  color: resolvedConfig.voiceReady
                      ? AppColors.text
                      : AppColors.text50,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBenchmarkCard(List<MnnLocalModel> llmModels) {
    final benchmarkState = _benchmarkState;
    final benchmarkResults = benchmarkState?.results ?? const [];
    final progress = benchmarkState?.progress;
    final selectedModelId = (_benchmarkModelId != null &&
            llmModels.any((item) => item.id == _benchmarkModelId))
        ? _benchmarkModelId
        : null;
    return _buildInfoCard(
      title: 'Benchmark',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (llmModels.isEmpty)
            const Text(
              '当前没有可用于 Benchmark 的 LLM 模型。先到模型市场下载一个文本模型即可开始。',
              style: TextStyle(height: 1.6, color: AppColors.text50),
            )
          else ...[
            DropdownButtonFormField<String>(
              initialValue: selectedModelId,
              decoration: const InputDecoration(
                labelText: 'Benchmark 模型',
                border: OutlineInputBorder(),
              ),
              items: llmModels
                  .map(
                    (item) => DropdownMenuItem<String>(
                      value: item.id,
                      child: Text(item.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) {
                setState(() {
                  _benchmarkModelId = value;
                });
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: _benchmarkBackend,
                    decoration: const InputDecoration(
                      labelText: '后端',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'cpu', child: Text('CPU')),
                      DropdownMenuItem(value: 'opencl', child: Text('OpenCL')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _benchmarkBackend = value;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _benchmarkPromptController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Prompt Token',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _benchmarkGenerateController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Generate Token',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _benchmarkRepeatController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Repeat',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: benchmarkState?.running == true || _startingBenchmark
                        ? null
                        : () => _startBenchmark(),
                    child: Text(
                      benchmarkState?.running == true ? 'Benchmark 运行中…' : '开始 Benchmark',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: benchmarkState?.running == true ? _stopBenchmark : null,
                  child: const Text('停止'),
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          Text(
            '状态：${benchmarkState?.status ?? 'idle'}',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          if (benchmarkState?.modelId.isNotEmpty == true) ...[
            const SizedBox(height: 6),
            Text('模型：${benchmarkState!.modelId}'),
          ],
          if (progress != null) ...[
            const SizedBox(height: 10),
            LinearProgressIndicator(value: (progress.progress / 100).clamp(0, 1)),
            const SizedBox(height: 8),
            Text(
              progress.statusMessage.isEmpty
                  ? '进度 ${progress.progress}%'
                  : '${progress.statusMessage} (${progress.progress}%)',
              style: const TextStyle(color: AppColors.text50),
            ),
          ],
          if ((benchmarkState?.errorMessage.isNotEmpty ?? false)) ...[
            const SizedBox(height: 10),
            Text(
              benchmarkState!.errorMessage,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ],
          if (benchmarkResults.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text(
              '结果',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...benchmarkResults.reversed.map(_buildBenchmarkResultCard),
          ],
        ],
      ),
    );
  }

  Widget _buildBenchmarkResultCard(MnnLocalBenchmarkResult result) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE6EBF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            result.title.isEmpty ? 'Benchmark 结果' : result.title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text('后端：${result.backend.toUpperCase()}'),
          Text('Repeat：${result.repeat}'),
          Text('Prefill：${result.prefillSpeedAvg.toStringAsFixed(2)} token/s'),
          Text('Decode：${result.decodeSpeedAvg.toStringAsFixed(2)} token/s'),
          if (result.errorMessage.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              result.errorMessage,
              style: const TextStyle(color: Colors.redAccent),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInstalledCard(MnnLocalModel model) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    model.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (model.active)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE8F5E9),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Text(
                      '当前使用',
                      style: TextStyle(fontSize: 12, color: Color(0xFF2E7D32)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTag(model.category.toUpperCase()),
                if (model.source.isNotEmpty) _buildTag(model.source),
                for (final tag in model.tags.take(4)) _buildTag(tag),
              ],
            ),
            if (model.path.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                model.path,
                style: const TextStyle(fontSize: 12, color: AppColors.text50),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (model.category == 'llm' || model.category == 'diffusion')
                  FilledButton.tonal(
                    onPressed: () => _setActiveModel(model.id),
                    child: const Text('设为推理模型'),
                  ),
                if (model.category == 'llm')
                  OutlinedButton(
                    onPressed: () {
                      setState(() {
                        _benchmarkModelId = model.id;
                      });
                      _startBenchmark(modelId: model.id);
                    },
                    child: const Text('Benchmark'),
                  ),
                if (model.category == 'asr')
                  FilledButton.tonal(
                    onPressed: () => _updateVoiceDefault(asrModelId: model.id),
                    child: const Text('设为默认 ASR'),
                  ),
                if (model.category == 'tts')
                  FilledButton.tonal(
                    onPressed: () => _updateVoiceDefault(ttsModelId: model.id),
                    child: const Text('设为默认 TTS'),
                  ),
                OutlinedButton(
                  onPressed: () async {
                    await MnnLocalModelsService.deleteModel(model.id);
                    _refreshInstalled(silent: true);
                    _refreshMarket(silent: true);
                  },
                  child: const Text('删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMarketCard(MnnLocalModel model) {
    final download = model.download;
    final isCompleted = download?.isCompleted == true;
    final isDownloading = download?.isDownloading == true;
    final isPaused = download?.isPaused == true;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    model.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (download != null)
                  Text(
                    _downloadStatusLabel(download),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.text50,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            if (model.description.isNotEmpty)
              Text(
                model.description,
                style: const TextStyle(color: AppColors.text70, height: 1.5),
              ),
            if (model.description.isNotEmpty) const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildTag(model.category.toUpperCase()),
                if (model.source.isNotEmpty) _buildTag(model.source),
                for (final tag in model.tags.take(4)) _buildTag(tag),
              ],
            ),
            if (download != null && (isDownloading || isPaused))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LinearProgressIndicator(value: download.progress),
                    const SizedBox(height: 8),
                    Text(
                      '${(download.progress * 100).toStringAsFixed(1)}% ${download.speedInfo}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.text50,
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (!isCompleted && !isDownloading)
                  FilledButton(
                    onPressed: () async {
                      _updateMarketDownloadState(
                        model.id,
                        _downloadPlaceholder(
                          stateLabel: 'preparing',
                          progress: download?.progress ?? 0,
                          progressStage: download?.progressStage ?? '',
                        ),
                      );
                      try {
                        await MnnLocalModelsService.startDownload(model.id);
                        _refreshMarket(silent: true);
                      } catch (error) {
                        _refreshMarket(silent: true);
                        showToast('启动下载失败', type: ToastType.error);
                      }
                    },
                    child: Text(isPaused ? '继续下载' : '下载'),
                  ),
                if (isDownloading)
                  OutlinedButton(
                    onPressed: () async {
                      _updateMarketDownloadState(
                        model.id,
                        _downloadPlaceholder(
                          stateLabel: 'paused',
                          progress: download?.progress ?? 0,
                          progressStage: download?.progressStage ?? '',
                        ),
                      );
                      try {
                        await MnnLocalModelsService.pauseDownload(model.id);
                        _refreshMarket(silent: true);
                      } catch (error) {
                        _refreshMarket(silent: true);
                        showToast('暂停下载失败', type: ToastType.error);
                      }
                    },
                    child: const Text('暂停'),
                  ),
                if (isCompleted)
                  FilledButton.tonal(
                    onPressed: () async {
                      await MnnLocalModelsService.deleteModel(model.id);
                      _refreshMarket(silent: true);
                      _refreshInstalled(silent: true);
                    },
                    child: Text(model.hasUpdate ? '删除旧版本' : '删除'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar({
    required TextEditingController controller,
    required String hint,
    required ValueChanged<String> onSubmitted,
    required VoidCallback onRefresh,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              textInputAction: TextInputAction.search,
              onSubmitted: onSubmitted,
              decoration: InputDecoration(
                hintText: hint,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          controller.clear();
                          onSubmitted('');
                        },
                        icon: const Icon(Icons.close),
                      ),
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChips({
    required String current,
    required List<String> categories,
    required ValueChanged<String> onSelected,
  }) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemBuilder: (context, index) {
          final value = categories[index];
          return ChoiceChip(
            label: Text(
              switch (value) {
                'all' => '全部',
                'llm' => 'LLM',
                'diffusion' => '扩散',
                'asr' => 'ASR',
                'tts' => 'TTS',
                'libs' => 'Libs',
                _ => value,
              },
            ),
            selected: current == value,
            onSelected: (_) => onSelected(value),
          );
        },
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemCount: categories.length,
      ),
    );
  }

  Widget _buildInfoCard({required String title, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFECEFF4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildTag(String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF2F4F7),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        value,
        style: const TextStyle(fontSize: 12, color: AppColors.text70),
      ),
    );
  }

  Widget _buildEmptyState({required String title, required String subtitle}) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.offline_bolt_outlined,
              size: 44,
              color: AppColors.text50,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(height: 1.6, color: AppColors.text50),
            ),
          ],
        ),
      ),
    );
  }
}
