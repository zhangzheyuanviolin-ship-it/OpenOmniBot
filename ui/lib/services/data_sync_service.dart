import 'package:flutter/services.dart';

class DataSyncConfig {
  const DataSyncConfig({
    this.enabled = false,
    this.configured = false,
    this.supabaseUrl = '',
    this.anonKey = '',
    this.namespace = '',
    this.syncSecret = '',
    this.s3Endpoint = '',
    this.region = '',
    this.bucket = '',
    this.accessKey = '',
    this.secretKey = '',
    this.sessionToken = '',
    this.forcePathStyle = true,
    this.deviceId = '',
    this.updatedAt = 0,
  });

  final bool enabled;
  final bool configured;
  final String supabaseUrl;
  final String anonKey;
  final String namespace;
  final String syncSecret;
  final String s3Endpoint;
  final String region;
  final String bucket;
  final String accessKey;
  final String secretKey;
  final String sessionToken;
  final bool forcePathStyle;
  final String deviceId;
  final int updatedAt;

  DataSyncConfig copyWith({
    bool? enabled,
    bool? configured,
    String? supabaseUrl,
    String? anonKey,
    String? namespace,
    String? syncSecret,
    String? s3Endpoint,
    String? region,
    String? bucket,
    String? accessKey,
    String? secretKey,
    String? sessionToken,
    bool? forcePathStyle,
    String? deviceId,
    int? updatedAt,
  }) {
    return DataSyncConfig(
      enabled: enabled ?? this.enabled,
      configured: configured ?? this.configured,
      supabaseUrl: supabaseUrl ?? this.supabaseUrl,
      anonKey: anonKey ?? this.anonKey,
      namespace: namespace ?? this.namespace,
      syncSecret: syncSecret ?? this.syncSecret,
      s3Endpoint: s3Endpoint ?? this.s3Endpoint,
      region: region ?? this.region,
      bucket: bucket ?? this.bucket,
      accessKey: accessKey ?? this.accessKey,
      secretKey: secretKey ?? this.secretKey,
      sessionToken: sessionToken ?? this.sessionToken,
      forcePathStyle: forcePathStyle ?? this.forcePathStyle,
      deviceId: deviceId ?? this.deviceId,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'enabled': enabled,
      'supabaseUrl': supabaseUrl,
      'anonKey': anonKey,
      'namespace': namespace,
      'syncSecret': syncSecret,
      's3Endpoint': s3Endpoint,
      'region': region,
      'bucket': bucket,
      'accessKey': accessKey,
      'secretKey': secretKey,
      'sessionToken': sessionToken,
      'forcePathStyle': forcePathStyle,
      'deviceId': deviceId,
      'updatedAt': updatedAt,
    };
  }

  factory DataSyncConfig.fromMap(Map<dynamic, dynamic> raw) {
    return DataSyncConfig(
      enabled: raw['enabled'] == true,
      configured: raw['configured'] == true,
      supabaseUrl: (raw['supabaseUrl'] ?? '').toString(),
      anonKey: (raw['anonKey'] ?? '').toString(),
      namespace: (raw['namespace'] ?? '').toString(),
      syncSecret: (raw['syncSecret'] ?? '').toString(),
      s3Endpoint: (raw['s3Endpoint'] ?? '').toString(),
      region: (raw['region'] ?? '').toString(),
      bucket: (raw['bucket'] ?? '').toString(),
      accessKey: (raw['accessKey'] ?? '').toString(),
      secretKey: (raw['secretKey'] ?? '').toString(),
      sessionToken: (raw['sessionToken'] ?? '').toString(),
      forcePathStyle: raw['forcePathStyle'] != false,
      deviceId: (raw['deviceId'] ?? '').toString(),
      updatedAt: _readInt(raw['updatedAt']),
    );
  }
}

class DataSyncProgress {
  const DataSyncProgress({
    this.stage = '',
    this.detail = '',
    this.completed = 0,
    this.total = 0,
    this.percent = 0,
    this.updatedAt = 0,
  });

  final String stage;
  final String detail;
  final int completed;
  final int total;
  final int percent;
  final int updatedAt;

  factory DataSyncProgress.fromMap(Map<dynamic, dynamic> raw) {
    return DataSyncProgress(
      stage: (raw['stage'] ?? '').toString(),
      detail: (raw['detail'] ?? '').toString(),
      completed: _readInt(raw['completed']),
      total: _readInt(raw['total']),
      percent: _readInt(raw['percent']),
      updatedAt: _readInt(raw['updatedAt']),
    );
  }
}

class DataSyncStatus {
  const DataSyncStatus({
    this.enabled = false,
    this.configured = false,
    this.state = 'disabled',
    this.namespace = '',
    this.deviceId = '',
    this.lastSyncAt = 0,
    this.lastSuccessAt = 0,
    this.remoteCursor = 0,
    this.pendingOutboxCount = 0,
    this.openConflictCount = 0,
    this.lastError = '',
    this.lastMessage = '',
    this.currentStep = '',
    this.progress = const DataSyncProgress(),
    this.updatedAt = 0,
  });

  final bool enabled;
  final bool configured;
  final String state;
  final String namespace;
  final String deviceId;
  final int lastSyncAt;
  final int lastSuccessAt;
  final int remoteCursor;
  final int pendingOutboxCount;
  final int openConflictCount;
  final String lastError;
  final String lastMessage;
  final String currentStep;
  final DataSyncProgress progress;
  final int updatedAt;

  bool get isSyncing => state == 'syncing';

  factory DataSyncStatus.fromMap(Map<dynamic, dynamic> raw) {
    return DataSyncStatus(
      enabled: raw['enabled'] == true,
      configured: raw['configured'] == true,
      state: (raw['state'] ?? 'disabled').toString(),
      namespace: (raw['namespace'] ?? '').toString(),
      deviceId: (raw['deviceId'] ?? '').toString(),
      lastSyncAt: _readInt(raw['lastSyncAt']),
      lastSuccessAt: _readInt(raw['lastSuccessAt']),
      remoteCursor: _readInt(raw['remoteCursor']),
      pendingOutboxCount: _readInt(raw['pendingOutboxCount']),
      openConflictCount: _readInt(raw['openConflictCount']),
      lastError: (raw['lastError'] ?? '').toString(),
      lastMessage: (raw['lastMessage'] ?? '').toString(),
      currentStep: (raw['currentStep'] ?? '').toString(),
      progress: DataSyncProgress.fromMap(
        Map<dynamic, dynamic>.from(raw['progress'] as Map? ?? const {}),
      ),
      updatedAt: _readInt(raw['updatedAt']),
    );
  }
}

class DataSyncConflictItem {
  const DataSyncConflictItem({
    required this.id,
    required this.relativePath,
    required this.localHash,
    required this.remoteHash,
    required this.remoteObjectKey,
    required this.conflictCopyPath,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String relativePath;
  final String localHash;
  final String remoteHash;
  final String remoteObjectKey;
  final String conflictCopyPath;
  final String status;
  final int createdAt;
  final int updatedAt;

  factory DataSyncConflictItem.fromMap(Map<dynamic, dynamic> raw) {
    return DataSyncConflictItem(
      id: _readInt(raw['id']),
      relativePath: (raw['relativePath'] ?? '').toString(),
      localHash: (raw['localHash'] ?? '').toString(),
      remoteHash: (raw['remoteHash'] ?? '').toString(),
      remoteObjectKey: (raw['remoteObjectKey'] ?? '').toString(),
      conflictCopyPath: (raw['conflictCopyPath'] ?? '').toString(),
      status: (raw['status'] ?? '').toString(),
      createdAt: _readInt(raw['createdAt']),
      updatedAt: _readInt(raw['updatedAt']),
    );
  }
}

class DataSyncPairingPayload {
  const DataSyncPairingPayload({
    required this.encodedPayload,
    required this.namespace,
    required this.createdAt,
  });

  final String encodedPayload;
  final String namespace;
  final int createdAt;

  factory DataSyncPairingPayload.fromMap(Map<dynamic, dynamic> raw) {
    return DataSyncPairingPayload(
      encodedPayload: (raw['encodedPayload'] ?? '').toString(),
      namespace: (raw['namespace'] ?? '').toString(),
      createdAt: _readInt(raw['createdAt']),
    );
  }
}

class DataSyncService {
  static const MethodChannel _channel = MethodChannel(
    'cn.com.omnimind.bot/DataSync',
  );

  static Future<DataSyncConfig> getConfig() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getConfig');
    return DataSyncConfig.fromMap(result ?? const {});
  }

  static Future<DataSyncConfig> saveConfig(DataSyncConfig config) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'saveConfig',
      config.toMap(),
    );
    return DataSyncConfig.fromMap(result ?? const {});
  }

  static Future<Map<String, dynamic>> testConnection(DataSyncConfig config) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'testConnection',
      config.toMap(),
    );
    return (result ?? const <dynamic, dynamic>{}).map(
      (key, value) => MapEntry(key.toString(), value),
    );
  }

  static Future<DataSyncStatus> setEnabled(bool enabled) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'setEnabled',
      {'enabled': enabled},
    );
    return DataSyncStatus.fromMap(result ?? const {});
  }

  static Future<DataSyncStatus> syncNow() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('syncNow');
    return DataSyncStatus.fromMap(result ?? const {});
  }

  static Future<DataSyncStatus> getStatus() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>('getStatus');
    return DataSyncStatus.fromMap(result ?? const {});
  }

  static Future<DataSyncPairingPayload> exportPairingPayload(
    String passphrase,
  ) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'exportPairingPayload',
      {'passphrase': passphrase},
    );
    return DataSyncPairingPayload.fromMap(result ?? const {});
  }

  static Future<DataSyncStatus> importPairingPayload({
    required String encodedPayload,
    required String passphrase,
  }) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'importPairingPayload',
      {'encodedPayload': encodedPayload, 'passphrase': passphrase},
    );
    return DataSyncStatus.fromMap(result ?? const {});
  }

  static Future<List<DataSyncConflictItem>> listConflicts() async {
    final result = await _channel.invokeMethod<List<dynamic>>('listConflicts');
    return (result ?? const [])
        .map((item) => DataSyncConflictItem.fromMap(Map<dynamic, dynamic>.from(item)))
        .toList();
  }

  static Future<bool> ackConflict(int id) async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'ackConflict',
      {'id': id},
    );
    return result?['success'] == true;
  }

  static Future<DataSyncStatus> reindexLocalSnapshot() async {
    final result = await _channel.invokeMethod<Map<dynamic, dynamic>>(
      'reindexLocalSnapshot',
    );
    return DataSyncStatus.fromMap(result ?? const {});
  }
}

int _readInt(dynamic raw) {
  if (raw is int) return raw;
  if (raw is double) return raw.toInt();
  if (raw is String) return int.tryParse(raw) ?? 0;
  return 0;
}
