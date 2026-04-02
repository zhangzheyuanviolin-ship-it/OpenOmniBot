import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:ui/services/agent_schedule_bridge_service.dart';
import 'package:ui/services/app_state_service.dart';

// 卡片推送
typedef CardPushCallback<T> = void Function(Map<String, dynamic> cardData);
//陪伴任务结束
typedef TaskFinishCallback = void Function();
//消息回执
typedef ChatTaskMessageCallBack =
    void Function(String taskID, String content, String? type);
//消息回执结束
typedef ChatTaskMessageEndCallBack = void Function(String taskID);
//VLM任务结束
typedef VLMTaskFinishEndCallBack = void Function(String? taskId);
//普通任务结束
typedef CommonTaskFinishEndCallBack = void Function();
//VLM请求用户输入（INFO动作）
typedef VLMRequestUserInputCallBack =
    void Function(String question, String? taskId);
//Dispatch流式数据回调
typedef DispatchStreamDataCallBack =
    void Function(String taskID, String data, String fullContent);
//Dispatch流式结束回调
typedef DispatchStreamEndCallBack =
    void Function(String taskID, String fullContent);
//Dispatch流式错误回调
typedef DispatchStreamErrorCallBack =
    void Function(
      String taskID,
      String error,
      String fullContent,
      bool isRateLimited,
    );

// Agent相关回调
typedef AgentThinkingStartCallback = void Function(String taskId);
typedef AgentThinkingUpdateCallback =
    void Function(String taskId, String thinking);
typedef AgentToolCallStartCallback = void Function(AgentToolEventData event);
typedef AgentToolCallProgressCallback = void Function(AgentToolEventData event);
typedef AgentToolCallCompleteCallback = void Function(AgentToolEventData event);
typedef AgentChatMessageCallback =
    void Function(String taskId, String message, {bool isFinal});
typedef AgentClarifyCallback =
    void Function(String taskId, String question, List<String> missingFields);
typedef AgentCompleteCallback =
    void Function(
      String taskId,
      bool success,
      String outputKind,
      bool hasUserVisibleOutput,
      int? latestPromptTokens,
      int? promptTokenThreshold,
    );
typedef AgentErrorCallback = void Function(String taskId, String error);
typedef AgentPermissionRequiredCallback =
    void Function(String taskId, List<String> missing);
typedef AgentUtgConfirmCallback = Future<bool> Function(String prompt);
typedef ScheduledTaskCancelledCallBack = void Function(String taskId);
typedef ScheduledTaskExecuteNowCallBack = void Function(String taskId);

class ModelAvailabilityCheckResult {
  final bool available;
  final int? code;
  final String message;

  const ModelAvailabilityCheckResult({
    required this.available,
    required this.code,
    required this.message,
  });

  factory ModelAvailabilityCheckResult.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return const ModelAvailabilityCheckResult(
        available: false,
        code: null,
        message: '检测失败：返回为空',
      );
    }

    final codeValue = map['code'];
    int? code;
    if (codeValue is int) {
      code = codeValue;
    } else if (codeValue is String) {
      code = int.tryParse(codeValue);
    }

    return ModelAvailabilityCheckResult(
      available: map['available'] == true,
      code: code,
      message: (map['message'] ?? '').toString(),
    );
  }
}

class UtgBridgeConfig {
  final bool utgEnabled;
  final String omnicloudBaseUrl;
  final String resolvedOmnicloudBaseUrl;
  final bool providerAutoStartEnabled;
  final bool fallbackToVlmOnFailureEnabled;
  final String providerStartCommand;
  final String? providerWorkingDirectory;
  final String providerStdoutPath;
  final bool runLogRecordingEnabled;
  final String runLogPath;
  final bool providerHealthy;
  final String providerHealthStatus;
  final String providerRunLogPath;
  final String canonicalRunLogPath;

  const UtgBridgeConfig({
    required this.utgEnabled,
    required this.omnicloudBaseUrl,
    required this.resolvedOmnicloudBaseUrl,
    required this.providerAutoStartEnabled,
    required this.fallbackToVlmOnFailureEnabled,
    required this.providerStartCommand,
    required this.providerWorkingDirectory,
    required this.providerStdoutPath,
    required this.runLogRecordingEnabled,
    required this.runLogPath,
    required this.providerHealthy,
    required this.providerHealthStatus,
    required this.providerRunLogPath,
    required this.canonicalRunLogPath,
  });

  factory UtgBridgeConfig.fromMap(Map<dynamic, dynamic>? map) {
    final raw = map ?? const {};
    final health = (raw['providerHealth'] as Map?) ?? const {};
    return UtgBridgeConfig(
      utgEnabled: raw['utgEnabled'] != false,
      omnicloudBaseUrl: (raw['omnicloudBaseUrl'] ?? '').toString(),
      resolvedOmnicloudBaseUrl: (raw['resolvedOmnicloudBaseUrl'] ?? '')
          .toString(),
      providerAutoStartEnabled: raw['providerAutoStartEnabled'] == true,
      fallbackToVlmOnFailureEnabled:
          raw['fallbackToVlmOnFailureEnabled'] != false,
      providerStartCommand: (raw['providerStartCommand'] ?? '').toString(),
      providerWorkingDirectory: raw['providerWorkingDirectory']?.toString(),
      providerStdoutPath: (raw['providerStdoutPath'] ?? '').toString(),
      runLogRecordingEnabled: raw['runLogRecordingEnabled'] == true,
      runLogPath: (raw['runLogPath'] ?? '').toString(),
      providerHealthy: raw['providerHealthy'] == true,
      providerHealthStatus: (health['status'] ?? '').toString(),
      providerRunLogPath: (raw['providerRunLogPath'] ?? '').toString(),
      canonicalRunLogPath: (raw['canonicalRunLogPath'] ?? '').toString(),
    );
  }
}

class UtgPathSummary {
  final String pathId;
  final String description;
  final int stepCount;
  final List<String> slotNames;
  final Map<String, String> slotExamples;
  final String startNodeId;
  final String endNodeId;
  final String startNodeDescription;
  final String endNodeDescription;
  final String packageName;
  final String appName;
  final String groupName;
  final String source;
  final String createdAt;
  final String updatedAt;
  final String syncStatus;
  final String syncOrigin;
  final String cloudBaseUrl;
  final String lastSyncedAt;
  final String pathKind;
  final String assetState;
  final String derivedFromRawPathId;
  final int runCount;
  final int successCount;
  final int failCount;
  final Map<String, dynamic> lastRun;

  const UtgPathSummary({
    required this.pathId,
    required this.description,
    required this.stepCount,
    required this.slotNames,
    required this.slotExamples,
    required this.startNodeId,
    required this.endNodeId,
    required this.startNodeDescription,
    required this.endNodeDescription,
    required this.packageName,
    required this.appName,
    required this.groupName,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
    required this.syncStatus,
    required this.syncOrigin,
    required this.cloudBaseUrl,
    required this.lastSyncedAt,
    required this.pathKind,
    required this.assetState,
    required this.derivedFromRawPathId,
    required this.runCount,
    required this.successCount,
    required this.failCount,
    required this.lastRun,
  });

  factory UtgPathSummary.fromMap(Map<dynamic, dynamic>? map) {
    final raw = map ?? const {};
    return UtgPathSummary(
      pathId: (raw['path_id'] ?? '').toString(),
      description: (raw['description'] ?? '').toString(),
      stepCount: raw['step_count'] is num
          ? (raw['step_count'] as num).toInt()
          : int.tryParse((raw['step_count'] ?? '0').toString()) ?? 0,
      slotNames:
          (raw['slot_names'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[],
      slotExamples:
          (raw['slot_examples'] as Map<dynamic, dynamic>?)?.map(
            (k, v) => MapEntry(k.toString(), v.toString()),
          ) ??
          const <String, String>{},
      startNodeId: (raw['start_node_id'] ?? '').toString(),
      endNodeId: (raw['end_node_id'] ?? '').toString(),
      startNodeDescription: (raw['start_node_description'] ?? '').toString(),
      endNodeDescription: (raw['end_node_description'] ?? '').toString(),
      packageName: (raw['package_name'] ?? '').toString(),
      appName: (raw['app_name'] ?? '').toString(),
      groupName: (raw['group_name'] ?? '').toString(),
      source: (raw['source'] ?? '').toString(),
      createdAt: (raw['created_at'] ?? '').toString(),
      updatedAt: (raw['updated_at'] ?? '').toString(),
      syncStatus: (raw['sync_status'] ?? '').toString(),
      syncOrigin: (raw['sync_origin'] ?? '').toString(),
      cloudBaseUrl: (raw['cloud_base_url'] ?? '').toString(),
      lastSyncedAt: (raw['last_synced_at'] ?? '').toString(),
      pathKind: (raw['path_kind'] ?? '').toString(),
      assetState: (raw['asset_state'] ?? '').toString(),
      derivedFromRawPathId: (raw['derived_from_raw_path_id'] ?? '').toString(),
      runCount: ((raw['run_stats'] as Map?)?['run_count'] is num)
          ? (((raw['run_stats'] as Map?)?['run_count'] as num).toInt())
          : int.tryParse(
                  (((raw['run_stats'] as Map?)?['run_count']) ?? '0')
                      .toString(),
                ) ??
                0,
      successCount: ((raw['run_stats'] as Map?)?['success_count'] is num)
          ? (((raw['run_stats'] as Map?)?['success_count'] as num).toInt())
          : int.tryParse(
                  (((raw['run_stats'] as Map?)?['success_count']) ?? '0')
                      .toString(),
                ) ??
                0,
      failCount: ((raw['run_stats'] as Map?)?['fail_count'] is num)
          ? (((raw['run_stats'] as Map?)?['fail_count'] as num).toInt())
          : int.tryParse(
                  (((raw['run_stats'] as Map?)?['fail_count']) ?? '0')
                      .toString(),
                ) ??
                0,
      lastRun:
          (raw['last_run'] as Map<dynamic, dynamic>?)?.map(
            (k, v) => MapEntry(k.toString(), v),
          ) ??
          const <String, dynamic>{},
    );
  }
}

class UtgPathsSnapshot {
  final bool success;
  final int count;
  final List<UtgPathSummary> paths;
  final String provider;

  const UtgPathsSnapshot({
    required this.success,
    required this.count,
    required this.paths,
    required this.provider,
  });

  factory UtgPathsSnapshot.fromMap(Map<String, dynamic> map) {
    return UtgPathsSnapshot(
      success: map['success'] == true,
      count: map['count'] is num
          ? (map['count'] as num).toInt()
          : int.tryParse((map['count'] ?? '0').toString()) ?? 0,
      paths:
          (map['paths'] as List<dynamic>?)
              ?.map((e) => UtgPathSummary.fromMap(e as Map?))
              .toList() ??
          const <UtgPathSummary>[],
      provider: (map['provider'] ?? '').toString(),
    );
  }
}

class UtgBridgeExecutionContext {
  final String bridgeBaseUrl;
  final String bridgeToken;
  final String resolvedOmnicloudBaseUrl;
  final bool providerHealthy;
  final String providerMessage;

  const UtgBridgeExecutionContext({
    required this.bridgeBaseUrl,
    required this.bridgeToken,
    required this.resolvedOmnicloudBaseUrl,
    required this.providerHealthy,
    required this.providerMessage,
  });

  factory UtgBridgeExecutionContext.fromMap(Map<dynamic, dynamic>? map) {
    final raw = map ?? const {};
    return UtgBridgeExecutionContext(
      bridgeBaseUrl: (raw['bridgeBaseUrl'] ?? '').toString(),
      bridgeToken: (raw['bridgeToken'] ?? '').toString(),
      resolvedOmnicloudBaseUrl: (raw['resolvedOmnicloudBaseUrl'] ?? '')
          .toString(),
      providerHealthy: raw['providerHealthy'] == true,
      providerMessage: (raw['providerMessage'] ?? '').toString(),
    );
  }
}

class UtgManualRunResult {
  final bool success;
  final String goal;
  final String pathId;
  final String? errorCode;
  final String? errorMessage;
  final Map<String, dynamic> terminalState;
  final String providerRunLogPath;
  final String canonicalRunLogPath;
  final Map<String, dynamic> rawJson;

  const UtgManualRunResult({
    required this.success,
    required this.goal,
    required this.pathId,
    required this.errorCode,
    required this.errorMessage,
    required this.terminalState,
    required this.providerRunLogPath,
    required this.canonicalRunLogPath,
    required this.rawJson,
  });

  factory UtgManualRunResult.fromMap(Map<String, dynamic> map) {
    return UtgManualRunResult(
      success: map['success'] == true,
      goal: (map['goal'] ?? '').toString(),
      pathId: (map['path_id'] ?? '').toString(),
      errorCode: map['error_code']?.toString(),
      errorMessage: map['error_message']?.toString(),
      terminalState:
          (map['terminal_state'] as Map<dynamic, dynamic>?)?.map(
            (k, v) => MapEntry(k.toString(), v),
          ) ??
          const <String, dynamic>{},
      providerRunLogPath: (map['provider_run_log_path'] ?? '').toString(),
      canonicalRunLogPath: (map['canonical_run_log_path'] ?? '').toString(),
      rawJson: Map<String, dynamic>.from(map),
    );
  }
}

class UtgPathMutationResult {
  final bool success;
  final String pathId;
  final String createdPathId;
  final String? errorCode;
  final String? errorMessage;
  final bool deleted;
  final bool imported;
  final bool alreadyExists;
  final int count;
  final String? cloudBaseUrl;
  final String pathKind;
  final String assetState;
  final String derivedFromRawPathId;
  final Map<String, dynamic> rawJson;

  const UtgPathMutationResult({
    required this.success,
    required this.pathId,
    required this.createdPathId,
    required this.errorCode,
    required this.errorMessage,
    required this.deleted,
    required this.imported,
    required this.alreadyExists,
    required this.count,
    required this.cloudBaseUrl,
    required this.pathKind,
    required this.assetState,
    required this.derivedFromRawPathId,
    required this.rawJson,
  });

  factory UtgPathMutationResult.fromMap(Map<String, dynamic> map) {
    return UtgPathMutationResult(
      success: map['success'] == true,
      pathId: (map['path_id'] ?? '').toString(),
      createdPathId: (map['created_path_id'] ?? '').toString(),
      errorCode: map['error_code']?.toString(),
      errorMessage: map['error_message']?.toString(),
      deleted: map['deleted'] == true,
      imported: map['imported'] == true,
      alreadyExists: map['already_exists'] == true,
      count: map['count'] is num
          ? (map['count'] as num).toInt()
          : int.tryParse((map['count'] ?? '0').toString()) ?? 0,
      cloudBaseUrl: map['cloud_base_url']?.toString(),
      pathKind: (map['path_kind'] ?? '').toString(),
      assetState: (map['asset_state'] ?? '').toString(),
      derivedFromRawPathId: (map['derived_from_raw_path_id'] ?? '').toString(),
      rawJson: Map<String, dynamic>.from(map),
    );
  }
}

class UtgProviderControlResult {
  final bool success;
  final String action;
  final String message;
  final UtgBridgeConfig config;
  final Map<String, dynamic> rawJson;

  const UtgProviderControlResult({
    required this.success,
    required this.action,
    required this.message,
    required this.config,
    required this.rawJson,
  });

  factory UtgProviderControlResult.fromMap(Map<dynamic, dynamic>? map) {
    final raw = map ?? const {};
    return UtgProviderControlResult(
      success: raw['success'] == true,
      action: (raw['action'] ?? '').toString(),
      message: (raw['message'] ?? '').toString(),
      config: UtgBridgeConfig.fromMap(raw),
      rawJson: Map<String, dynamic>.from(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      ),
    );
  }
}

class UtgRunLogSummary {
  final String runId;
  final String goal;
  final bool success;
  final String doneReason;
  final int stepCount;
  final String startedAt;
  final String finishedAt;
  final num? durationMs;
  final String toolName;
  final String compileStatus;
  final String compilePathId;
  final String compileMode;
  final String actPathId;
  final String source;
  final String compileSummary;
  final String operationDescription;
  final String selectorLabel;
  final String selectorReason;
  final String errorMessage;
  final String finalPackageName;
  final Map<String, dynamic> rawJson;

  const UtgRunLogSummary({
    required this.runId,
    required this.goal,
    required this.success,
    required this.doneReason,
    required this.stepCount,
    required this.startedAt,
    required this.finishedAt,
    required this.durationMs,
    required this.toolName,
    required this.compileStatus,
    required this.compilePathId,
    required this.compileMode,
    required this.actPathId,
    required this.source,
    required this.compileSummary,
    required this.operationDescription,
    required this.selectorLabel,
    required this.selectorReason,
    required this.errorMessage,
    required this.finalPackageName,
    required this.rawJson,
  });

  factory UtgRunLogSummary.fromMap(Map<dynamic, dynamic>? map) {
    final raw = map ?? const {};
    return UtgRunLogSummary(
      runId: (raw['run_id'] ?? '').toString(),
      goal: (raw['goal'] ?? '').toString(),
      success: raw['success'] == true,
      doneReason: (raw['done_reason'] ?? '').toString(),
      stepCount: raw['step_count'] is num
          ? (raw['step_count'] as num).toInt()
          : int.tryParse((raw['step_count'] ?? '0').toString()) ?? 0,
      startedAt: (raw['started_at'] ?? '').toString(),
      finishedAt: (raw['finished_at'] ?? '').toString(),
      durationMs: raw['duration_ms'] as num?,
      toolName: (raw['tool_name'] ?? '').toString(),
      compileStatus: (raw['compile_status'] ?? '').toString(),
      compilePathId: (raw['compile_path_id'] ?? '').toString(),
      compileMode: (raw['compile_mode'] ?? '').toString(),
      actPathId: (raw['act_path_id'] ?? '').toString(),
      source: (raw['source'] ?? '').toString(),
      compileSummary: (raw['compile_summary'] ?? '').toString(),
      operationDescription: (raw['operation_description'] ?? '').toString(),
      selectorLabel: (raw['selector_label'] ?? '').toString(),
      selectorReason: (raw['selector_reason'] ?? '').toString(),
      errorMessage: (raw['error_message'] ?? '').toString(),
      finalPackageName: (raw['final_package_name'] ?? '').toString(),
      rawJson: Map<String, dynamic>.from(
        (raw['raw_run'] as Map<dynamic, dynamic>? ?? const {}).map(
          (k, v) => MapEntry(k.toString(), v),
        ),
      ),
    );
  }
}

class UtgRunLogsSnapshot {
  final bool success;
  final int count;
  final List<UtgRunLogSummary> runs;
  final String runLogPath;
  final String provider;

  const UtgRunLogsSnapshot({
    required this.success,
    required this.count,
    required this.runs,
    required this.runLogPath,
    required this.provider,
  });

  factory UtgRunLogsSnapshot.fromMap(Map<String, dynamic> map) {
    return UtgRunLogsSnapshot(
      success: map['success'] == true,
      count: map['count'] is num
          ? (map['count'] as num).toInt()
          : int.tryParse((map['count'] ?? '0').toString()) ?? 0,
      runs:
          (map['runs'] as List<dynamic>?)
              ?.map((e) => UtgRunLogSummary.fromMap(e as Map?))
              .toList() ??
          const <UtgRunLogSummary>[],
      runLogPath: (map['run_log_path'] ?? '').toString(),
      provider: (map['provider'] ?? '').toString(),
    );
  }
}

class UtgRunLogDetail {
  final bool success;
  final String runId;
  final String runLogPath;
  final String provider;
  final String errorCode;
  final String errorMessage;
  final Map<String, dynamic> runLog;
  final Map<String, dynamic> rawJson;

  const UtgRunLogDetail({
    required this.success,
    required this.runId,
    required this.runLogPath,
    required this.provider,
    required this.errorCode,
    required this.errorMessage,
    required this.runLog,
    required this.rawJson,
  });

  factory UtgRunLogDetail.fromMap(Map<dynamic, dynamic>? map) {
    final raw = map ?? const {};
    return UtgRunLogDetail(
      success: raw['success'] == true,
      runId: (raw['run_id'] ?? '').toString(),
      runLogPath: (raw['run_log_path'] ?? '').toString(),
      provider: (raw['provider'] ?? '').toString(),
      errorCode: (raw['error_code'] ?? '').toString(),
      errorMessage: (raw['error_message'] ?? '').toString(),
      runLog: Map<String, dynamic>.from(
        (raw['run_log'] as Map<dynamic, dynamic>? ?? const {}).map(
          (k, v) => MapEntry(k.toString(), v),
        ),
      ),
      rawJson: Map<String, dynamic>.from(
        raw.map((key, value) => MapEntry(key.toString(), value)),
      ),
    );
  }
}

class UtgRunLogImportResult {
  final bool success;
  final String runId;
  final String createdPathId;
  final String? errorCode;
  final String? errorMessage;
  final int pathsCreated;
  final int nodesCreated;
  final int nodesUpdated;
  final int sequencesCreated;
  final List<String> warnings;
  final String runLogPath;
  final String pathKind;
  final String assetState;
  final Map<String, dynamic> rawJson;

  const UtgRunLogImportResult({
    required this.success,
    required this.runId,
    required this.createdPathId,
    required this.errorCode,
    required this.errorMessage,
    required this.pathsCreated,
    required this.nodesCreated,
    required this.nodesUpdated,
    required this.sequencesCreated,
    required this.warnings,
    required this.runLogPath,
    required this.pathKind,
    required this.assetState,
    required this.rawJson,
  });

  factory UtgRunLogImportResult.fromMap(Map<String, dynamic> map) {
    return UtgRunLogImportResult(
      success: map['success'] == true,
      runId: (map['run_id'] ?? '').toString(),
      createdPathId: (map['created_path_id'] ?? '').toString(),
      errorCode: map['error_code']?.toString(),
      errorMessage: map['error_message']?.toString(),
      pathsCreated: map['paths_created'] is num
          ? (map['paths_created'] as num).toInt()
          : int.tryParse((map['paths_created'] ?? '0').toString()) ?? 0,
      nodesCreated: map['nodes_created'] is num
          ? (map['nodes_created'] as num).toInt()
          : int.tryParse((map['nodes_created'] ?? '0').toString()) ?? 0,
      nodesUpdated: map['nodes_updated'] is num
          ? (map['nodes_updated'] as num).toInt()
          : int.tryParse((map['nodes_updated'] ?? '0').toString()) ?? 0,
      sequencesCreated: map['sequences_created'] is num
          ? (map['sequences_created'] as num).toInt()
          : int.tryParse((map['sequences_created'] ?? '0').toString()) ?? 0,
      warnings:
          (map['warnings'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          const <String>[],
      runLogPath: (map['run_log_path'] ?? '').toString(),
      pathKind: (map['path_kind'] ?? '').toString(),
      assetState: (map['asset_state'] ?? '').toString(),
      rawJson: Map<String, dynamic>.from(map),
    );
  }
}

class AgentToolEventData {
  final String taskId;
  final String toolName;
  final String displayName;
  final String toolTitle;
  final String toolType;
  final String? serverName;
  final String status;
  final String argsJson;
  final String progress;
  final String summary;
  final String compileStatus;
  final String executionRoute;
  final String resultPreviewJson;
  final String rawResultJson;
  final String terminalOutput;
  final String terminalOutputDelta;
  final String? terminalSessionId;
  final String terminalStreamState;
  final String? workspaceId;
  final List<Map<String, dynamic>> artifacts;
  final List<Map<String, dynamic>> actions;
  final bool success;

  const AgentToolEventData({
    required this.taskId,
    required this.toolName,
    required this.displayName,
    this.toolTitle = '',
    required this.toolType,
    this.serverName,
    this.status = '',
    this.argsJson = '',
    this.progress = '',
    this.summary = '',
    this.compileStatus = '',
    this.executionRoute = '',
    this.resultPreviewJson = '',
    this.rawResultJson = '',
    this.terminalOutput = '',
    this.terminalOutputDelta = '',
    this.terminalSessionId,
    this.terminalStreamState = '',
    this.workspaceId,
    this.artifacts = const [],
    this.actions = const [],
    this.success = true,
  });

  factory AgentToolEventData.fromMap(Map<dynamic, dynamic>? map) {
    final raw = map ?? const {};
    return AgentToolEventData(
      taskId: (raw['taskId'] ?? '').toString(),
      toolName: (raw['toolName'] ?? '').toString(),
      displayName: (raw['displayName'] ?? raw['toolName'] ?? '').toString(),
      toolTitle: (raw['toolTitle'] ?? '').toString(),
      toolType: (raw['toolType'] ?? 'builtin').toString(),
      serverName: raw['serverName']?.toString(),
      status: (raw['status'] ?? '').toString(),
      argsJson: (raw['argsJson'] ?? raw['args'] ?? '').toString(),
      progress: (raw['progress'] ?? '').toString(),
      summary: (raw['summary'] ?? '').toString(),
      compileStatus: (raw['compileStatus'] ?? '').toString(),
      executionRoute: (raw['executionRoute'] ?? '').toString(),
      resultPreviewJson: (raw['resultPreviewJson'] ?? '').toString(),
      rawResultJson: (raw['rawResultJson'] ?? '').toString(),
      terminalOutput: (raw['terminalOutput'] ?? '').toString(),
      terminalOutputDelta: (raw['terminalOutputDelta'] ?? '').toString(),
      terminalSessionId: raw['terminalSessionId']?.toString(),
      terminalStreamState: (raw['terminalStreamState'] ?? '').toString(),
      workspaceId: raw['workspaceId']?.toString(),
      artifacts: ((raw['artifacts'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
          .toList(),
      actions: ((raw['actions'] as List?) ?? const [])
          .whereType<Map>()
          .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
          .toList(),
      success: raw['success'] != false,
    );
  }
}

class AssistsMessageService {
  static const MethodChannel assistCore = MethodChannel(
    'cn.com.omnimind.bot/AssistCoreEvent',
  );

  // 回调函数
  static CardPushCallback? _onCardPushCallback;
  static TaskFinishCallback? _onTaskFinishCallback;
  static ChatTaskMessageCallBack? _onChatTaskMessageCallBack;
  static ChatTaskMessageEndCallBack? _onChatTaskMessageEndCallBack;
  static VLMRequestUserInputCallBack? _onVLMRequestUserInputCallBack;
  static DispatchStreamDataCallBack? _onDispatchStreamDataCallBack;
  static DispatchStreamEndCallBack? _onDispatchStreamEndCallBack;
  static DispatchStreamErrorCallBack? _onDispatchStreamErrorCallBack;

  // Agent回调
  static AgentThinkingStartCallback? _onAgentThinkingStartCallback;
  static AgentThinkingUpdateCallback? _onAgentThinkingUpdateCallback;
  static AgentToolCallStartCallback? _onAgentToolCallStartCallback;
  static AgentToolCallProgressCallback? _onAgentToolCallProgressCallback;
  static AgentToolCallCompleteCallback? _onAgentToolCallCompleteCallback;
  static AgentChatMessageCallback? _onAgentChatMessageCallback;
  static AgentClarifyCallback? _onAgentClarifyCallback;
  static AgentCompleteCallback? _onAgentCompleteCallback;
  static AgentErrorCallback? _onAgentErrorCallback;
  static AgentPermissionRequiredCallback? _onAgentPermissionRequiredCallback;
  static AgentUtgConfirmCallback? _onAgentUtgConfirmCallback;

  static ScheduledTaskCancelledCallBack? _onScheduledTaskCancelledCallBack;
  static ScheduledTaskExecuteNowCallBack? _onScheduledTaskExecuteNowCallBack;

  // 改为回调列表，支持多个监听器
  static final List<VLMTaskFinishEndCallBack> _onVLMTaskFinishCallBacks = [];
  static final List<CommonTaskFinishEndCallBack> _onCommonTaskFinishCallBacks =
      [];

  static void initialize() {
    assistCore.setMethodCallHandler(_handleMethod);
  }

  static Future<dynamic> _handleMethod(MethodCall call) async {
    try {
      switch (call.method) {
        case 'onCardPush':
          final Map<String, dynamic> cardData = Map<String, dynamic>.from(
            call.arguments,
          );
          _onCardPushCallback?.call(cardData['data']);
          break;

        case 'onTaskFinish':
          print('任务完成');
          _onTaskFinishCallback?.call();
          break;
        case 'onChatMessage':
          final Map<String, dynamic> data = Map<String, dynamic>.from(
            call.arguments,
          );
          print(
            'onChatMessage content: ${data['content']}, type: ${data['type']}',
          );
          _onChatTaskMessageCallBack?.call(
            data['taskID'],
            data['content'],
            data['type'],
          );
          break;
        case 'onChatMessageEnd':
          final Map<String, dynamic> data = Map<String, dynamic>.from(
            call.arguments,
          );
          _onChatTaskMessageEndCallBack?.call(data['taskID']);
          break;
        case 'onVLMRequestUserInput':
          final Map<String, dynamic> data = Map<String, dynamic>.from(
            call.arguments,
          );
          print('onVLMRequestUserInput question: ${data['question']}');
          _onVLMRequestUserInputCallBack?.call(
            data['question'],
            data['taskId']?.toString(),
          );
          break;
        case 'onVLMTaskFinish':
          print('任务完成');
          // 通知所有注册的回调
          for (final callback in _onVLMTaskFinishCallBacks) {
            callback((call.arguments as Map?)?['taskId']?.toString());
          }
          break;
        case 'onCommonTaskFinish':
          print('任务完成');
          // 通知所有注册的回调
          for (final callback in _onCommonTaskFinishCallBacks) {
            callback();
          }
          break;
        case 'onDispatchStreamData':
          final Map<String, dynamic> data = Map<String, dynamic>.from(
            call.arguments,
          );
          _onDispatchStreamDataCallBack?.call(
            data['taskID'] ?? '',
            data['data'] ?? '',
            data['fullContent'] ?? '',
          );
          break;
        case 'onDispatchStreamEnd':
          final Map<String, dynamic> data = Map<String, dynamic>.from(
            call.arguments,
          );
          _onDispatchStreamEndCallBack?.call(
            data['taskID'] ?? '',
            data['fullContent'] ?? '',
          );
          break;
        case 'onDispatchStreamError':
          final Map<String, dynamic> data = Map<String, dynamic>.from(
            call.arguments,
          );
          _onDispatchStreamErrorCallBack?.call(
            data['taskID'] ?? '',
            data['error'] ?? '',
            data['fullContent'] ?? '',
            data['isRateLimited'] == true,
          );
          break;
        case 'onAgentThinkingStart':
          _onAgentThinkingStartCallback?.call(
            ((call.arguments as Map?)?['taskId'] ?? '').toString(),
          );
          break;
        case 'onAgentThinkingUpdate':
          final Map<String, dynamic> data = Map<String, dynamic>.from(
            call.arguments,
          );
          _onAgentThinkingUpdateCallback?.call(
            (data['taskId'] ?? '').toString(),
            data['thinking'] ?? '',
          );
          break;
        case 'onAgentToolCallStart':
          _onAgentToolCallStartCallback?.call(
            AgentToolEventData.fromMap(call.arguments as Map?),
          );
          break;
        case 'onAgentToolCallProgress':
          _onAgentToolCallProgressCallback?.call(
            AgentToolEventData.fromMap(call.arguments as Map?),
          );
          break;
        case 'onAgentToolCallComplete':
          _onAgentToolCallCompleteCallback?.call(
            AgentToolEventData.fromMap(call.arguments as Map?),
          );
          break;
        case 'onAgentChatMessage':
          final Map<String, dynamic> data = Map<String, dynamic>.from(
            call.arguments,
          );
          final dynamic isFinalRaw = data['isFinal'];
          final bool isFinal = isFinalRaw == null
              ? true
              : (isFinalRaw is bool
                    ? isFinalRaw
                    : isFinalRaw.toString().toLowerCase() == 'true');
          _onAgentChatMessageCallback?.call(
            (data['taskId'] ?? '').toString(),
            (data['message'] ?? '').toString(),
            isFinal: isFinal,
          );
          break;
        case 'onAgentClarifyRequired':
          final Map<String, dynamic> data = Map<String, dynamic>.from(
            call.arguments,
          );
          final List<String> missingFields =
              (data['missingFields'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
          _onAgentClarifyCallback?.call(
            (data['taskId'] ?? '').toString(),
            data['question'] ?? '',
            missingFields,
          );
          break;
        case 'onAgentComplete':
          final Map<String, dynamic> data = Map<String, dynamic>.from(
            call.arguments,
          );
          _onAgentCompleteCallback?.call(
            (data['taskId'] ?? '').toString(),
            data['success'] == true,
            (data['outputKind'] ?? 'none').toString(),
            data['hasUserVisibleOutput'] == true,
            _asNullableInt(data['latestPromptTokens']),
            _asNullableInt(data['promptTokenThreshold']),
          );
          break;
        case 'onAgentError':
          final Map<String, dynamic> data = Map<String, dynamic>.from(
            call.arguments,
          );
          _onAgentErrorCallback?.call(
            (data['taskId'] ?? '').toString(),
            data['error'] ?? '',
          );
          break;
        case 'onAgentPermissionRequired':
          final Map<String, dynamic> data = Map<String, dynamic>.from(
            call.arguments,
          );
          final List<String> missing =
              (data['missing'] as List<dynamic>?)
                  ?.map((e) => e.toString())
                  .toList() ??
              [];
          _onAgentPermissionRequiredCallback?.call(
            (data['taskId'] ?? '').toString(),
            missing,
          );
          break;
        case 'onScheduledTaskCancelled':
          final Map<String, dynamic> data = Map<String, dynamic>.from(
            call.arguments,
          );
          _onScheduledTaskCancelledCallBack?.call(data['taskId'] ?? '');
          break;
        case 'onScheduledTaskExecuteNow':
          final Map<String, dynamic> data = Map<String, dynamic>.from(
            call.arguments,
          );
          _onScheduledTaskExecuteNowCallBack?.call(data['taskId'] ?? '');
          break;
        case 'agentScheduleCreate':
          return await AgentScheduleBridgeService.createTask(
            Map<String, dynamic>.from(call.arguments as Map),
          );
        case 'agentScheduleList':
          return await AgentScheduleBridgeService.listTasks();
        case 'agentScheduleUpdate':
          return await AgentScheduleBridgeService.updateTask(
            Map<String, dynamic>.from(call.arguments as Map),
          );
        case 'agentScheduleDelete':
          return await AgentScheduleBridgeService.deleteTask(
            Map<String, dynamic>.from(call.arguments as Map),
          );
        case 'agentUtgConfirm':
          final Map<String, dynamic> data = Map<String, dynamic>.from(
            call.arguments as Map,
          );
          final prompt = (data['prompt'] ?? '').toString();
          final callback = _onAgentUtgConfirmCallback;
          if (callback == null) {
            return false;
          }
          return await callback(prompt);

        default:
          print('未处理的方法: ${call.method}');
      }
    } catch (e) {
      print('处理方法调用时出错: $e');
      rethrow;
    }
  }

  // 设置回调函数
  static void setOnCardPushCallback(CardPushCallback callback) {
    _onCardPushCallback = callback;
  }

  static void setOnTaskFinishCallback(TaskFinishCallback callback) {
    _onTaskFinishCallback = callback;
  }

  static void setOnChatTaskMessageCallBack(ChatTaskMessageCallBack callback) {
    _onChatTaskMessageCallBack = callback;
  }

  static void setOnChatTaskMessageEndCallBack(
    ChatTaskMessageEndCallBack callback,
  ) {
    _onChatTaskMessageEndCallBack = callback;
  }

  static void setOnVLMRequestUserInputCallBack(
    VLMRequestUserInputCallBack callback,
  ) {
    _onVLMRequestUserInputCallBack = callback;
  }

  static void setOnVLMTaskFinishCallBack(VLMTaskFinishEndCallBack? callback) {
    if (callback != null && !_onVLMTaskFinishCallBacks.contains(callback)) {
      _onVLMTaskFinishCallBacks.add(callback);
    }
  }

  static void setOnCommonTaskFinishCallBack(
    CommonTaskFinishEndCallBack? callback,
  ) {
    if (callback != null && !_onCommonTaskFinishCallBacks.contains(callback)) {
      _onCommonTaskFinishCallBacks.add(callback);
    }
  }

  static void removeOnVLMTaskFinishCallBack(
    VLMTaskFinishEndCallBack? callback,
  ) {
    _onVLMTaskFinishCallBacks.remove(callback);
  }

  static void removeOnCommonTaskFinishCallBack(
    CommonTaskFinishEndCallBack? callback,
  ) {
    _onCommonTaskFinishCallBacks.remove(callback);
  }

  static void setOnDispatchStreamDataCallBack(
    DispatchStreamDataCallBack? callback,
  ) {
    _onDispatchStreamDataCallBack = callback;
  }

  static void setOnDispatchStreamEndCallBack(
    DispatchStreamEndCallBack? callback,
  ) {
    _onDispatchStreamEndCallBack = callback;
  }

  static void setOnDispatchStreamErrorCallBack(
    DispatchStreamErrorCallBack? callback,
  ) {
    _onDispatchStreamErrorCallBack = callback;
  }

  static void setOnScheduledTaskCancelledCallBack(
    ScheduledTaskCancelledCallBack? callback,
  ) {
    _onScheduledTaskCancelledCallBack = callback;
  }

  static void setOnScheduledTaskExecuteNowCallBack(
    ScheduledTaskExecuteNowCallBack? callback,
  ) {
    _onScheduledTaskExecuteNowCallBack = callback;
  }

  static void setOnAgentThinkingStartCallback(
    AgentThinkingStartCallback? callback,
  ) {
    _onAgentThinkingStartCallback = callback;
  }

  static void setOnAgentThinkingUpdateCallback(
    AgentThinkingUpdateCallback? callback,
  ) {
    _onAgentThinkingUpdateCallback = callback;
  }

  static void setOnAgentToolCallStartCallback(
    AgentToolCallStartCallback? callback,
  ) {
    _onAgentToolCallStartCallback = callback;
  }

  static void setOnAgentToolCallProgressCallback(
    AgentToolCallProgressCallback? callback,
  ) {
    _onAgentToolCallProgressCallback = callback;
  }

  static void setOnAgentToolCallCompleteCallback(
    AgentToolCallCompleteCallback? callback,
  ) {
    _onAgentToolCallCompleteCallback = callback;
  }

  static void setOnAgentChatMessageCallback(
    AgentChatMessageCallback? callback,
  ) {
    _onAgentChatMessageCallback = callback;
  }

  static void setOnAgentClarifyCallback(AgentClarifyCallback? callback) {
    _onAgentClarifyCallback = callback;
  }

  static void setOnAgentCompleteCallback(AgentCompleteCallback? callback) {
    _onAgentCompleteCallback = callback;
  }

  static int? _asNullableInt(dynamic raw) {
    if (raw is int) return raw;
    if (raw is num) return raw.toInt();
    if (raw is String) return int.tryParse(raw);
    return null;
  }

  static void setOnAgentErrorCallback(AgentErrorCallback? callback) {
    _onAgentErrorCallback = callback;
  }

  static void setOnAgentPermissionRequiredCallback(
    AgentPermissionRequiredCallback? callback,
  ) {
    _onAgentPermissionRequiredCallback = callback;
  }

  static void setOnAgentUtgConfirmCallback(AgentUtgConfirmCallback? callback) {
    _onAgentUtgConfirmCallback = callback;
  }

  // 发送按钮点击事件到Android端
  static Future<bool> clickButton(
    String taskID,
    String btnId,
    String value, //需要保留.因为有多选数据比如选择app列表,具体协议再定义
    bool isNeedPermission, //是否需要检查权限
  ) async {
    try {
      var result = await assistCore.invokeMethod('clickButton', {
        'taskID': taskID,
        'id': btnId,
        'value': value,
        'isNeedPermission': isNeedPermission,
      });
      return result == "SUCCESS";
    } on PlatformException catch (e) {
      print('发送按钮点击事件失败: ${e.message}');
      return false;
    }
  }

  // 创建陪伴任务
  static Future<bool> createCompanionTask() async {
    var result = await assistCore.invokeMethod('createCompanionTask');
    return result == "SUCCESS";
  }

  //取消陪伴任务
  static Future<bool> cancelTask() async {
    var result = await assistCore.invokeMethod('cancelTask');
    return result == "SUCCESS";
  }

  /// 取消正在运行的任务，不影响陪伴模式
  static Future<bool> cancelRunningTask({String? taskId}) async {
    try {
      var result = await assistCore.invokeMethod(
        'cancelRunningTask',
        taskId == null ? null : {'taskId': taskId},
      );
      return result == "SUCCESS";
    } on PlatformException catch (e) {
      print('取消运行中任务失败: ${e.message}');
      return false;
    }
  }

  /// 取消陪伴任务的回到桌面操作
  /// 当用户在开启陪伴后离开主页时调用
  static Future<bool> cancelCompanionGoHome() async {
    try {
      var result = await assistCore.invokeMethod('cancelCompanionGoHome');
      return result == "SUCCESS";
    } on PlatformException catch (e) {
      print('取消回到桌面失败: ${e.message}');
      return false;
    }
  }

  /// Trigger the system Home action.
  static Future<bool> pressHome() async {
    try {
      var result = await assistCore.invokeMethod('pressHome');
      return result == "SUCCESS";
    } on PlatformException catch (e) {
      print('pressHome failed: ${e.message}');
      return false;
    }
  }

  // cancel chat task
  static Future<bool> cancelChatTask({String? taskId}) async {
    var result = await assistCore.invokeMethod(
      'cancelChatTask',
      taskId == null ? null : {'taskId': taskId},
    );
    return result == "SUCCESS";
  }

  static Future<UtgBridgeConfig> getUtgBridgeConfig() async {
    final result = await assistCore.invokeMethod('getUtgBridgeConfig');
    return UtgBridgeConfig.fromMap(result as Map?);
  }

  static Future<UtgBridgeConfig> saveUtgBridgeConfig({
    bool? utgEnabled,
    bool? providerAutoStartEnabled,
    bool? fallbackToVlmOnFailureEnabled,
    bool? runLogRecordingEnabled,
    String? omnicloudBaseUrl,
    String? providerStartCommand,
    String? providerWorkingDirectory,
  }) async {
    final result = await assistCore.invokeMethod('saveUtgBridgeConfig', {
      if (utgEnabled != null) 'utgEnabled': utgEnabled,
      if (providerAutoStartEnabled != null)
        'providerAutoStartEnabled': providerAutoStartEnabled,
      if (fallbackToVlmOnFailureEnabled != null)
        'fallbackToVlmOnFailureEnabled': fallbackToVlmOnFailureEnabled,
      if (runLogRecordingEnabled != null)
        'runLogRecordingEnabled': runLogRecordingEnabled,
      if (omnicloudBaseUrl != null) 'omnicloudBaseUrl': omnicloudBaseUrl,
      if (providerStartCommand != null)
        'providerStartCommand': providerStartCommand,
      if (providerWorkingDirectory != null)
        'providerWorkingDirectory': providerWorkingDirectory,
    });
    return UtgBridgeConfig.fromMap(result as Map?);
  }

  static Future<UtgProviderControlResult> controlUtgProvider({
    required String action,
  }) async {
    final result = await assistCore.invokeMethod('controlUtgProvider', {
      'action': action.trim(),
    });
    return UtgProviderControlResult.fromMap(result as Map?);
  }

  static Future<UtgBridgeExecutionContext>
  getUtgBridgeExecutionContext() async {
    final result = await assistCore.invokeMethod(
      'getUtgBridgeExecutionContext',
    );
    return UtgBridgeExecutionContext.fromMap(result as Map?);
  }

  static String _normalizeUtgPath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) {
      return '/';
    }
    return trimmed.startsWith('/') ? trimmed : '/$trimmed';
  }

  static Future<Map<String, dynamic>> _requestUtgJson({
    required String method,
    required String path,
    Object? payload,
    String? baseUrl,
  }) async {
    final result = await assistCore.invokeMethod('requestUtgJson', {
      'method': method.trim().toUpperCase(),
      'path': _normalizeUtgPath(path),
      if (payload != null) 'payload': payload,
      if (baseUrl != null && baseUrl.trim().isNotEmpty)
        'baseUrl': baseUrl.trim(),
    });
    if (result == null) {
      throw Exception('OmniFlow provider 无响应');
    }
    if (result is! Map) {
      throw Exception('OmniFlow provider 响应格式错误');
    }
    return Map<String, dynamic>.from(result);
  }

  static Future<UtgRunLogsSnapshot> getUtgRunLogs({
    String? baseUrl,
    int limit = 20,
  }) async {
    final decoded = await _requestUtgJson(
      method: 'GET',
      path: '/run_logs?limit=$limit',
      baseUrl: baseUrl,
    );
    return UtgRunLogsSnapshot.fromMap(decoded);
  }

  static Future<UtgRunLogDetail> getUtgRunLogDetail({
    required String runId,
    String? baseUrl,
  }) async {
    final decoded = await _requestUtgJson(
      method: 'GET',
      path: '/run_logs/${Uri.encodeComponent(runId.trim())}',
      baseUrl: baseUrl,
    );
    final detail = UtgRunLogDetail.fromMap(decoded);
    if (!detail.success) {
      throw Exception(
        detail.errorMessage.trim().isNotEmpty
            ? detail.errorMessage
            : '加载 run_log 详情失败',
      );
    }
    return detail;
  }

  static Future<Map<String, dynamic>> getVlmTaskRunLog({
    required String taskId,
  }) async {
    final result = await assistCore.invokeMethod<Map<Object?, Object?>>(
      'getVlmTaskRunLog',
      {'taskId': taskId.trim()},
    );
    if (result == null) {
      return <String, dynamic>{
        'success': false,
        'task_id': taskId.trim(),
        'error_message': '未找到对应的 run_log',
      };
    }
    return result.map((key, value) => MapEntry(key.toString(), value));
  }

  static Future<UtgRunLogImportResult> importUtgRunLog({
    required String runId,
    String? baseUrl,
  }) async {
    final decoded = await _requestUtgJson(
      method: 'POST',
      path: '/run_logs/import',
      baseUrl: baseUrl,
      payload: {'run_id': runId.trim()},
    );
    return UtgRunLogImportResult.fromMap(decoded);
  }

  static Future<UtgPathsSnapshot> getUtgPaths({String? baseUrl}) async {
    final decoded = await _requestUtgJson(
      method: 'GET',
      path: '/paths',
      baseUrl: baseUrl,
    );
    return UtgPathsSnapshot.fromMap(decoded);
  }

  static Future<Map<String, dynamic>> getUtgPathBundle({
    required String pathId,
    String? baseUrl,
  }) async {
    final decoded = await _requestUtgJson(
      method: 'GET',
      path: '/paths/$pathId/bundle',
      baseUrl: baseUrl,
    );
    final normalized = jsonDecode(jsonEncode(decoded));
    if (normalized is Map<String, dynamic>) {
      return normalized;
    }
    if (normalized is Map) {
      return Map<String, dynamic>.from(normalized);
    }
    throw Exception('OmniFlow path bundle 响应格式错误');
  }

  static Future<UtgPathMutationResult> deleteUtgPath({
    required String pathId,
    String? baseUrl,
  }) async {
    final decoded = await _requestUtgJson(
      method: 'DELETE',
      path: '/paths/$pathId',
      baseUrl: baseUrl,
    );
    return UtgPathMutationResult.fromMap(decoded);
  }

  static Future<UtgPathMutationResult> distillUtgPath({
    required String pathId,
    String? baseUrl,
  }) async {
    final decoded = await _requestUtgJson(
      method: 'POST',
      path: '/paths/$pathId/distill',
      baseUrl: baseUrl,
    );
    return UtgPathMutationResult.fromMap(decoded);
  }

  static Future<UtgPathMutationResult> downloadCloudUtgPath({
    String pathId = '',
    required String cloudBaseUrl,
    String? baseUrl,
  }) async {
    final decoded = await _requestUtgJson(
      method: 'POST',
      path: '/cloud_paths/download',
      baseUrl: baseUrl,
      payload: {
        'cloud_base_url': cloudBaseUrl.trim(),
        'path_id': pathId.trim(),
      },
    );
    return UtgPathMutationResult.fromMap(decoded);
  }

  static Future<UtgPathMutationResult> uploadCloudUtgPath({
    required String pathId,
    required String cloudBaseUrl,
    String? baseUrl,
  }) async {
    final decoded = await _requestUtgJson(
      method: 'POST',
      path: '/cloud_paths/upload',
      baseUrl: baseUrl,
      payload: {
        'cloud_base_url': cloudBaseUrl.trim(),
        'path_id': pathId.trim(),
      },
    );
    return UtgPathMutationResult.fromMap(decoded);
  }

  static Future<UtgManualRunResult> runUtgPath({
    required String pathId,
    Map<String, String> slots = const {},
    String? baseUrl,
  }) async {
    final executionContext = await getUtgBridgeExecutionContext();
    if (executionContext.bridgeBaseUrl.trim().isEmpty ||
        executionContext.bridgeToken.trim().isEmpty) {
      throw Exception('UTG bridge 上下文不可用');
    }
    final decoded = await _requestUtgJson(
      method: 'POST',
      path: '/run_compiled_path',
      baseUrl: baseUrl,
      payload: {
        'goal': 'manual_utg_path_run:$pathId',
        'path_id': pathId,
        'slots': slots,
        'bridge_base_url': executionContext.bridgeBaseUrl,
        'bridge_token': executionContext.bridgeToken,
        'skip_terminal_verify': true,
        'context': {'source': 'utg_manual_dashboard'},
      },
    );
    return UtgManualRunResult.fromMap(decoded);
  }

  static Future<bool> copyToClipboard(String text) async {
    try {
      var result = await assistCore.invokeMethod('copyToClipboard', {
        'text': text,
      });
      return result == "SUCCESS";
    } on PlatformException catch (e) {
      print('复制到剪贴板失败: ${e.message}');
      return false;
    }
  }

  static Future<String?> getClipboardText() async {
    try {
      final result = await assistCore.invokeMethod<String>('getClipboardText');
      return result;
    } on PlatformException catch (e) {
      print('读取剪贴板失败: ${e.message}');
      return null;
    }
  }

  //开始聊天任务
  static Future<bool> createChatTask(
    String taskID,
    List<Map<String, dynamic>> content, {
    String? provider,
    Map<String, dynamic>? openClawConfig,
    int? conversationId,
    String? conversationMode,
    String? userMessage,
    List<Map<String, dynamic>> userAttachments = const [],
  }) async {
    try {
      print('createChatTask taskID: $taskID content: $content');
      final args = {'taskID': taskID, 'content': content};
      if (provider != null) {
        args['provider'] = provider;
      }
      if (openClawConfig != null) {
        args['openClawConfig'] = openClawConfig;
      }
      if (conversationId != null) {
        args['conversationId'] = conversationId;
      }
      if (conversationMode != null && conversationMode.trim().isNotEmpty) {
        args['conversationMode'] = conversationMode.trim();
      }
      if (userMessage != null) {
        args['userMessage'] = userMessage;
      }
      if (userAttachments.isNotEmpty) {
        args['userAttachments'] = userAttachments;
      }
      final result = await assistCore.invokeMethod('createChatTask', args);
      return result == "SUCCESS";
    } on PlatformException catch (e) {
      print('createChatTask failed: ${e.message}');
      return false;
    }
  }

  //开始视觉模型任务
  static Future<bool> createVLMOperationTask(
    String goal, {
    String? taskId,
    String model = "scene.vlm.operation.primary",
    int maxSteps = 25,
    String? packageName,
    bool needSummary = false,
    bool skipGoHome = false, // 是否跳过回到主页，从当前页面开始执行
  }) async {
    print(
      'createVLMOperationTask goal: $goal model: $model  maxSteps: $maxSteps packageName: $packageName needSummary: $needSummary skipGoHome: $skipGoHome',
    );
    var result = await assistCore.invokeMethod('createVLMOperationTask', {
      'goal': goal,
      if (taskId != null) 'taskId': taskId,
      'model': model,
      'maxSteps': maxSteps,
      'packageName': packageName,
      'needSummary': needSummary,
      'skipGoHome': skipGoHome,
    });

    return result == "SUCCESS";
  }

  /// 向运行中的VLM任务提供用户输入（INFO动作）
  static Future<bool> provideUserInputToVLMTask(String userInput) async {
    try {
      final result = await assistCore.invokeMethod<bool>(
        'provideUserInputToVLMTask',
        {'userInput': userInput},
      );
      return result == true;
    } on PlatformException catch (e) {
      print('提供用户输入失败: ${e.message}');
      return false;
    }
  }

  /// 通知原生层ChatBotSheet已准备好接收总结
  static Future<bool> notifySummarySheetReady() async {
    try {
      final result = await assistCore.invokeMethod<String>(
        'notifySummarySheetReady',
      );
      return result == "SUCCESS";
    } on PlatformException catch (e) {
      print('通知总结Sheet准备就绪失败: ${e.message}');
      return false;
    }
  }

  static Future<bool> isCompanionTaskRunning() async {
    return await assistCore.invokeMethod('isCompanionTaskRunning', {});
  }

  /// 获取已安装应用（包含中文应用名和包名）
  static Future<List<Map<String, dynamic>>> getInstalledApplications() async {
    try {
      final result = await assistCore.invokeMethod<List<dynamic>>(
        'getInstalledApplications',
      );
      if (result != null) {
        return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    } on PlatformException catch (e) {
      print('获取已安装应用失败: ${e.message}');
      return [];
    }
  }

  /// 获取已安装应用（附带图标更新）
  static Future<List<Map<String, dynamic>>>
  getInstalledApplicationsWithIconUpdate() async {
    try {
      final result = await assistCore.invokeMethod<List<dynamic>>(
        'getInstalledApplicationsWithIconUpdate',
      );
      if (result != null) {
        return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    } on PlatformException catch (e) {
      print('获取已安装应用(附带图标更新)失败: ${e.message}');
      return [];
    }
  }

  /// 开源版不提供 suggestions
  static Future<List<Map<String, dynamic>>> getSuggestions() async {
    return [];
  }

  static Future<bool> isPackageAuthorized(String packageName) async {
    try {
      final result = await assistCore.invokeMethod<bool>(
        'isPackageAuthorized',
        {'packageName': packageName},
      );
      return result ?? false;
    } on PlatformException catch (e) {
      print('检查包名授权状态失败: ${e.message}');
      return false;
    }
  }

  // 开源版已移除学习模式

  /// 预约VLM操作任务
  static Future<String?> scheduleVLMOperationTask(
    String goal, //目标文本
    int times, { //预约时间
    String model = "scene.vlm.operation.primary", //模型(sceneId)
    int maxSteps = 25, //最大步数
    String? packageName, //执行任务包名
    String title = "", //任务标题
    String? subTitle, //子标题
    String? extraJson, //额外参数,获取info时会返回
  }) async {
    print(
      'scheduleVLMOperationTask goal: $goal, times: $times, model: $model, maxSteps: $maxSteps, packageName: $packageName',
    );
    try {
      final result = await assistCore
          .invokeMethod<String>('scheduleVLMOperationTask', {
            'goal': goal,
            'model': model,
            'maxSteps': maxSteps,
            'packageName': packageName,
            'times': times,
            'title': title,
            'subTitle': subTitle,
            'extraJson': extraJson,
          });
      return result;
    } on PlatformException catch (e) {
      print('预约VLM操作任务失败: ${e.message}');
      return null;
    }
  }

  /// 获取预约任务信息信息
  static Future<Map<String, dynamic>?> getScheduleTaskInfo() async {
    try {
      final result = await assistCore.invokeMethod<Map<Object?, Object?>>(
        'getScheduleInfo',
      );
      if (result != null) {
        return result.cast<String, dynamic>();
      }
      return null;
    } on PlatformException catch (e) {
      print('获取预约任务信息失败: ${e.message}');
      return null;
    }
  }

  /// 清除预约任务
  static Future<bool> clearScheduleTask() async {
    try {
      final result = await assistCore.invokeMethod('clearScheduleTask');
      return result == "SUCCESS";
    } on PlatformException catch (e) {
      print('清除预约任务失败: ${e.message}');
      return false;
    }
  }

  /// 立即执行预约任务
  static Future<bool> doScheduleNow() async {
    try {
      final result = await assistCore.invokeMethod('doScheduleNow');
      return result == "SUCCESS";
    } on PlatformException catch (e) {
      print('立即执行预约任务失败: ${e.message}');
      return false;
    }
  }

  /// 取消预约任务
  static Future<bool> cancelScheduleTask() async {
    try {
      final result = await assistCore.invokeMethod('cancelScheduleTask');
      return result == "SUCCESS";
    } on PlatformException catch (e) {
      print('取消预约任务失败: ${e.message}');
      return false;
    }
  }

  /// 查询统一 Agent 创建的应用内闹钟（exact_alarm）
  static Future<List<Map<String, dynamic>>> listAgentExactAlarms() async {
    try {
      final result = await assistCore.invokeMethod<List<dynamic>>(
        'listAgentExactAlarms',
      );
      if (result == null) return [];
      return result.map((item) {
        if (item is Map) {
          return Map<String, dynamic>.from(item);
        }
        return <String, dynamic>{};
      }).toList();
    } on PlatformException catch (e) {
      print('查询应用内闹钟失败: ${e.message}');
      return [];
    }
  }

  /// 删除统一 Agent 创建的应用内闹钟（exact_alarm）
  static Future<bool> deleteAgentExactAlarm(String alarmId) async {
    try {
      final result = await assistCore.invokeMethod<Map<dynamic, dynamic>>(
        'deleteAgentExactAlarm',
        {'alarmId': alarmId},
      );
      return result?['success'] == true;
    } on PlatformException catch (e) {
      print('删除应用内闹钟失败: ${e.message}');
      return false;
    }
  }

  static Future<Map<String, dynamic>> getAlarmSettings() async {
    try {
      final result = await assistCore.invokeMethod<Map<dynamic, dynamic>>(
        'getAlarmSettings',
      );
      return Map<String, dynamic>.from(result ?? const {});
    } on PlatformException catch (e) {
      print('读取闹钟设置失败: ${e.message}');
      return {};
    }
  }

  static Future<Map<String, dynamic>> saveAlarmSettings({
    required String source,
    String? localPath,
    String? remoteUrl,
  }) async {
    try {
      final result = await assistCore.invokeMethod<Map<dynamic, dynamic>>(
        'saveAlarmSettings',
        {'source': source, 'localPath': localPath, 'remoteUrl': remoteUrl},
      );
      return Map<String, dynamic>.from(result ?? const {});
    } on PlatformException catch (e) {
      print('保存闹钟设置失败: ${e.message}');
      return {'success': false, 'message': e.message ?? '保存失败'};
    }
  }

  /// 获取当前 nanoTime（毫秒级，System.nanoTime() / 1_000_000）
  static Future<int?> getNanoTime() async {
    try {
      final result = await assistCore.invokeMethod<int>('getNanoTime');
      return result;
    } on PlatformException catch (e) {
      print('获取nanoTime失败: ${e.message}');
      return null;
    }
  }

  /// 执行首次任务
  static Future<bool> startFirstUse(String packageName) async {
    try {
      final result = await assistCore.invokeMethod('startFirstUse', {
        'packageName': packageName,
      });
      return result == "SUCCESS";
    } on PlatformException catch (e) {
      print('执行首次任务失败: ${e.message}');
      return false;
    }
  }

  /// 初始化半屏引擎并启动首次体验
  static Future<void> initializeAndStartFirstUse(String packageName) async {
    print('🎯 [FirstUse] 开始初始化半屏引擎并启动首次体验');

    // 1. 首先初始化半屏引擎
    final initSuccess = await AppStateService.initHalfScreenEngine();
    if (initSuccess) {
      print('✅ [FirstUse] 半屏引擎初始化成功');
    } else {
      print('⚠️ [FirstUse] 半屏引擎初始化失败');
    }

    // 2. 延迟启动首次体验，确保引擎完全就绪
    await Future.delayed(const Duration(milliseconds: 300));

    // 3. 启动首次体验
    final startSuccess = await startFirstUse(packageName);
    if (startSuccess) {
      print('✅ [FirstUse] 首次体验启动成功');
    } else {
      print('⚠️ [FirstUse] 首次体验启动失败');
    }
  }

  /// 调用LLM chat接口（非流式）
  /// 用于修复JSON格式等场景
  static Future<String?> postLLMChat({
    required String text,
    String model = 'scene.dispatch.model',
  }) async {
    try {
      final result = await assistCore.invokeMethod<String>('postLLMChat', {
        'text': text,
        'model': model,
      });
      return result;
    } on PlatformException catch (e) {
      print('调用LLM chat失败: ${e.message}');
      return null;
    }
  }

  /// 生成记忆中心问候语（原生端优先使用标准 tool_calls）
  static Future<String?> generateMemoryGreeting({
    required List<Map<String, String>> records,
    String model = 'scene.compactor.context',
  }) async {
    try {
      final payloadRecords = records
          .map(
            (item) => {
              'title': item['title'] ?? '',
              'description': item['description'] ?? '',
              'appName': item['appName'] ?? '',
            },
          )
          .toList();
      final result = await assistCore.invokeMethod<String>(
        'generateMemoryGreeting',
        {'model': model, 'records': payloadRecords},
      );
      return result;
    } on PlatformException catch (e) {
      print('生成记忆中心问候语失败: ${e.message}');
      return null;
    }
  }

  /// 创建 Agent 任务
  static Future<bool> createAgentTask({
    required String taskId,
    required String userMessage,
    List<Map<String, dynamic>> conversationHistory = const [],
    List<Map<String, dynamic>> attachments = const [],
    int? userMessageCreatedAtMillis,
    int? conversationId,
    String? conversationMode,
    String? scheduledTaskId,
    String? scheduledTaskTitle,
    bool? scheduleNotificationEnabled,
    Map<String, dynamic>? modelOverride,
    Map<String, String>? terminalEnvironment,
  }) async {
    try {
      final args = <String, dynamic>{
        'taskId': taskId,
        'userMessage': userMessage,
      };
      if (conversationHistory.isNotEmpty) {
        args['conversationHistory'] = conversationHistory;
      }
      if (conversationId != null) {
        args['conversationId'] = conversationId;
      }
      if (conversationMode != null && conversationMode.trim().isNotEmpty) {
        args['conversationMode'] = conversationMode.trim();
      }
      if (userMessageCreatedAtMillis != null &&
          userMessageCreatedAtMillis > 0) {
        args['userMessageCreatedAt'] = userMessageCreatedAtMillis;
      }
      if (scheduledTaskId != null && scheduledTaskId.trim().isNotEmpty) {
        args['scheduledTaskId'] = scheduledTaskId.trim();
      }
      if (scheduledTaskTitle != null && scheduledTaskTitle.trim().isNotEmpty) {
        args['scheduledTaskTitle'] = scheduledTaskTitle.trim();
      }
      if (scheduleNotificationEnabled != null) {
        args['scheduleNotificationEnabled'] = scheduleNotificationEnabled;
      }
      if (attachments.isNotEmpty) {
        args['attachments'] = attachments;
      }
      if (modelOverride != null) {
        args['modelOverride'] = modelOverride;
      }
      if (terminalEnvironment != null && terminalEnvironment.isNotEmpty) {
        args['terminalEnvironment'] = terminalEnvironment;
      }
      final result = await assistCore.invokeMethod('createAgentTask', {
        ...args,
      });
      return result == "SUCCESS";
    } on PlatformException catch (e) {
      print('创建 Agent 任务失败: ${e.message}');
      return false;
    }
  }

  static Future<Map<String, dynamic>?> upsertWorkspaceScheduledTask(
    Map<String, dynamic> task,
  ) async {
    try {
      final result = await assistCore.invokeMethod<Map<dynamic, dynamic>>(
        'upsertWorkspaceScheduledTask',
        {'task': task},
      );
      if (result == null) return null;
      return result.map((k, v) => MapEntry(k.toString(), v));
    } on PlatformException catch (e) {
      print('更新原生定时任务失败: ${e.message}');
      return null;
    }
  }

  static Future<bool> deleteWorkspaceScheduledTask(String taskId) async {
    try {
      final result = await assistCore.invokeMethod<Map<dynamic, dynamic>>(
        'deleteWorkspaceScheduledTask',
        {'taskId': taskId},
      );
      if (result == null) return false;
      return result['deleted'] == true;
    } on PlatformException catch (e) {
      print('删除原生定时任务失败: ${e.message}');
      return false;
    }
  }

  static Future<int> syncWorkspaceScheduledTasks(
    List<Map<String, dynamic>> tasks,
  ) async {
    try {
      final result = await assistCore.invokeMethod<Map<dynamic, dynamic>>(
        'syncWorkspaceScheduledTasks',
        {'tasks': tasks},
      );
      if (result == null) return 0;
      final count = result['count'];
      if (count is int) return count;
      if (count is String) return int.tryParse(count) ?? 0;
      return 0;
    } on PlatformException catch (e) {
      print('同步原生定时任务失败: ${e.message}');
      return 0;
    }
  }

  static Future<List<Map<String, dynamic>>> listAgentSkills() async {
    try {
      final result = await assistCore.invokeMethod<List<dynamic>>(
        'agentSkillList',
      );
      return (result ?? const [])
          .whereType<Map>()
          .map((item) => item.map((k, v) => MapEntry(k.toString(), v)))
          .toList();
    } on PlatformException catch (e) {
      print('读取 Agent skills 失败: ${e.message}');
      return const [];
    }
  }

  static Future<Map<String, dynamic>?> installAgentSkill({
    required String sourcePath,
  }) async {
    try {
      final result = await assistCore.invokeMethod<Map<dynamic, dynamic>>(
        'agentSkillInstall',
        {'sourcePath': sourcePath},
      );
      if (result == null) return null;
      return result.map((k, v) => MapEntry(k.toString(), v));
    } on PlatformException catch (e) {
      print('安装 Agent skill 失败: ${e.message}');
      return null;
    }
  }

  /// 检测自定义 VLM 模型可用性（OpenAI-compatible）
  static Future<ModelAvailabilityCheckResult> checkVlmModelAvailability({
    required String model,
    required String apiBase,
    String apiKey = '',
  }) async {
    try {
      final result = await assistCore.invokeMethod<Map<dynamic, dynamic>>(
        'checkVlmModelAvailability',
        {'model': model, 'apiBase': apiBase, 'apiKey': apiKey},
      );
      return ModelAvailabilityCheckResult.fromMap(result);
    } on PlatformException catch (e) {
      return ModelAvailabilityCheckResult(
        available: false,
        code: null,
        message: e.message ?? '检测失败',
      );
    } catch (e) {
      return ModelAvailabilityCheckResult(
        available: false,
        code: null,
        message: '检测失败: $e',
      );
    }
  }

  /// 打开应用市场
  static Future<String?> openAPPMarket(String packageName) async {
    try {
      final result = await assistCore.invokeMethod<String>('openAPPMarket', {
        'packageName': packageName,
      });
      return result;
    } on PlatformException catch (e) {
      print('调用openAPPMarket失败: ${e.message}');
      return null;
    }
  }

  /// 检查是否在桌面
  static Future<bool> isDesktop() async {
    try {
      final result = await assistCore.invokeMethod<bool>('isDesktop');
      return result ?? false;
    } on PlatformException catch (e) {
      print('检查是否在桌面失败: ${e.message}');
      return false;
    }
  }

  /// 获取桌面包名
  static Future<List<String>?> getDeskTopPackageName() async {
    try {
      final result = await assistCore.invokeMethod<List<dynamic>>(
        'getDeskTopPackageName',
      );
      if (result != null) {
        return result.map((e) => e.toString()).toList();
      }
      return null;
    } on PlatformException catch (e) {
      print('获取桌面包名失败: ${e.message}');
      return null;
    }
  }

  /// 获取当前应用包名
  /// 用于从当前页面开始执行任务
  static Future<String?> getCurrentPackageName() async {
    try {
      final result = await assistCore.invokeMethod<String>(
        'getCurrentPackageName',
      );
      return result;
    } on PlatformException catch (e) {
      print('获取当前应用包名失败: ${e.message}');
      return null;
    }
  }

  /// 同步“任务完成后自动回聊天”设置到原生层
  static Future<bool> setAutoBackToChatAfterTaskEnabled(bool enabled) async {
    try {
      final result = await assistCore.invokeMethod<String>(
        'setAutoBackToChatAfterTaskEnabled',
        {'enabled': enabled},
      );
      return result == 'SUCCESS';
    } on PlatformException catch (e) {
      print('同步自动回聊天设置失败: ${e.message}');
      return false;
    }
  }

  /// 跳转到主引擎路由
  static Future<bool> navigateToMainEngineRoute(String route) async {
    try {
      final result = await assistCore.invokeMethod(
        'navigateToMainEngineRoute',
        {'route': route},
      );
      return result == 'SUCCESS';
    } on PlatformException catch (e) {
      print('跳转到主引擎路由失败: ${e.message}');
      return false;
    }
  }

  /// 显示定时任务倒计时提醒（原生浮层）
  static Future<bool> showScheduledTaskReminder({
    required String taskId,
    required String taskName,
    int countdownSeconds = 5,
  }) async {
    try {
      final result = await assistCore.invokeMethod(
        'showScheduledTaskReminder',
        {
          'taskId': taskId,
          'taskName': taskName,
          'countdownSeconds': countdownSeconds,
        },
      );
      return result == 'SUCCESS';
    } on PlatformException catch (e) {
      print('显示定时任务提醒失败: ${e.message}');
      return false;
    }
  }

  /// 隐藏定时任务倒计时提醒
  static Future<bool> hideScheduledTaskReminder() async {
    try {
      final result = await assistCore.invokeMethod('hideScheduledTaskReminder');
      return result == 'SUCCESS';
    } on PlatformException catch (e) {
      print('隐藏定时任务提醒失败: ${e.message}');
      return false;
    }
  }

  /// 授权完成后重新打开ChatBot
  static Future<bool> reopenChatBotAfterAuth() async {
    try {
      final result = await assistCore.invokeMethod('reopenChatBotAfterAuth');
      return result == 'SUCCESS';
    } on PlatformException catch (e) {
      print('重新打开ChatBot失败: ${e.message}');
      return false;
    }
  }
}
