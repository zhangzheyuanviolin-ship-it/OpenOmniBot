import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:ui/services/assists_core_service.dart';
import 'package:ui/services/storage_service.dart';

class ModelProviderConfig {
  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final String source;
  final String providerType;
  final bool readOnly;
  final bool ready;
  final String statusText;
  final bool configured;

  const ModelProviderConfig({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.source,
    required this.providerType,
    required this.readOnly,
    required this.ready,
    required this.statusText,
    required this.configured,
  });

  factory ModelProviderConfig.empty() {
    return const ModelProviderConfig(
      id: '',
      name: '',
      baseUrl: '',
      apiKey: '',
      source: 'none',
      providerType: 'custom',
      readOnly: false,
      ready: false,
      statusText: '',
      configured: false,
    );
  }

  factory ModelProviderConfig.fromMap(Map<dynamic, dynamic>? map) {
    if (map == null) {
      return ModelProviderConfig.empty();
    }
    return ModelProviderConfig(
      id: (map['id'] ?? '').toString(),
      name: (map['name'] ?? '').toString(),
      baseUrl: (map['baseUrl'] ?? '').toString(),
      apiKey: (map['apiKey'] ?? '').toString(),
      source: (map['source'] ?? 'none').toString(),
      providerType: (map['providerType'] ?? 'custom').toString(),
      readOnly: map['readOnly'] == true,
      ready: map['ready'] == true,
      statusText: (map['statusText'] ?? '').toString(),
      configured: map['configured'] == true,
    );
  }
}

class ModelProviderProfileSummary {
  final String id;
  final String name;
  final String baseUrl;
  final String apiKey;
  final String sourceType;
  final bool readOnly;
  final bool ready;
  final String statusText;
  final bool configured;

  const ModelProviderProfileSummary({
    required this.id,
    required this.name,
    required this.baseUrl,
    required this.apiKey,
    required this.sourceType,
    required this.readOnly,
    required this.ready,
    required this.statusText,
    required this.configured,
  });

  factory ModelProviderProfileSummary.fromMap(Map<dynamic, dynamic>? map) {
    return ModelProviderProfileSummary(
      id: (map?['id'] ?? '').toString(),
      name: (map?['name'] ?? '').toString(),
      baseUrl: (map?['baseUrl'] ?? '').toString(),
      apiKey: (map?['apiKey'] ?? '').toString(),
      sourceType: (map?['sourceType'] ?? 'custom').toString(),
      readOnly: map?['readOnly'] == true,
      ready: map?['ready'] == true,
      statusText: (map?['statusText'] ?? '').toString(),
      configured: map?['configured'] == true,
    );
  }

  ModelProviderConfig toConfig({String source = 'profile'}) {
    return ModelProviderConfig(
      id: id,
      name: name,
      baseUrl: baseUrl,
      apiKey: apiKey,
      source: source,
      providerType: sourceType,
      readOnly: readOnly,
      ready: ready,
      statusText: statusText,
      configured: configured,
    );
  }
}

class ModelProviderProfilesPayload {
  final List<ModelProviderProfileSummary> profiles;
  final String editingProfileId;

  const ModelProviderProfilesPayload({
    required this.profiles,
    required this.editingProfileId,
  });

  factory ModelProviderProfilesPayload.fromMap(Map<dynamic, dynamic>? map) {
    final profiles = ((map?['profiles'] as List?) ?? const [])
        .map((item) => ModelProviderProfileSummary.fromMap(item as Map?))
        .where((item) => item.id.isNotEmpty)
        .toList();
    final editingProfileId = (map?['editingProfileId'] ?? '').toString();
    return ModelProviderProfilesPayload(
      profiles: profiles,
      editingProfileId: editingProfileId,
    );
  }
}

class ProviderModelOption {
  final String id;
  final String displayName;
  final String? ownedBy;

  const ProviderModelOption({
    required this.id,
    required this.displayName,
    this.ownedBy,
  });

  factory ProviderModelOption.fromMap(Map<dynamic, dynamic>? map) {
    return ProviderModelOption(
      id: (map?['id'] ?? '').toString(),
      displayName: (map?['displayName'] ?? map?['id'] ?? '').toString(),
      ownedBy: map?['ownedBy']?.toString(),
    );
  }
}

class ProviderModelGroup {
  final ModelProviderProfileSummary profile;
  final List<ProviderModelOption> models;

  const ProviderModelGroup({required this.profile, required this.models});
}

class ModelProviderConfigService {
  static const String _kBuiltinOmniInferProfileId = 'omniinfer-local';
  static const String _kLegacyBuiltinMnnLocalProfileId = 'mnn-local';
  static const String _kManualModelIdsKey = 'manual_provider_model_ids_v2';
  static const String _kCachedFetchedModelsKey =
      'cached_provider_models_with_base_v2';
  static const String _kLegacyManualModelIdsKey =
      'manual_provider_model_ids_v1';
  static const String _kLegacyCachedFetchedModelsKey =
      'cached_provider_models_with_base_v1';

  static bool _isBuiltinLocalProfileId(String profileId) {
    final normalized = profileId.trim();
    return normalized == _kBuiltinOmniInferProfileId ||
        normalized == _kLegacyBuiltinMnnLocalProfileId;
  }

  static String _canonicalProfileId(String profileId) {
    final normalized = profileId.trim();
    if (_isBuiltinLocalProfileId(normalized)) {
      return _kBuiltinOmniInferProfileId;
    }
    return normalized;
  }

  static Future<ModelProviderConfig> getConfig() async {
    try {
      final result = await AssistsMessageService.assistCore
          .invokeMethod<Map<dynamic, dynamic>>('getModelProviderConfig');
      return ModelProviderConfig.fromMap(result);
    } on PlatformException {
      return ModelProviderConfig.empty();
    }
  }

  static Future<ModelProviderProfilesPayload> listProfiles() async {
    try {
      final result = await AssistsMessageService.assistCore
          .invokeMethod<Map<dynamic, dynamic>>('listModelProviderProfiles');
      return ModelProviderProfilesPayload.fromMap(result);
    } on PlatformException {
      final fallback = await getConfig();
      final profile = ModelProviderProfileSummary(
        id: fallback.id.isNotEmpty ? fallback.id : 'profile-1',
        name: fallback.name.isNotEmpty ? fallback.name : 'Provider 1',
        baseUrl: fallback.baseUrl,
        apiKey: fallback.apiKey,
        sourceType: fallback.providerType,
        readOnly: fallback.readOnly,
        ready: fallback.ready,
        statusText: fallback.statusText,
        configured: fallback.configured,
      );
      return ModelProviderProfilesPayload(
        profiles: [profile],
        editingProfileId: profile.id,
      );
    }
  }

  static Future<ModelProviderProfileSummary> saveProfile({
    String? id,
    required String name,
    required String baseUrl,
    required String apiKey,
  }) async {
    final result = await AssistsMessageService.assistCore
        .invokeMethod<Map<dynamic, dynamic>>('saveModelProviderProfile', {
          if (id != null && id.trim().isNotEmpty) 'id': id.trim(),
          'name': name,
          'baseUrl': baseUrl,
          'apiKey': apiKey,
        });
    return ModelProviderProfileSummary.fromMap(result);
  }

  static Future<ModelProviderProfilesPayload> deleteProfile(
    String profileId,
  ) async {
    final result = await AssistsMessageService.assistCore
        .invokeMethod<Map<dynamic, dynamic>>('deleteModelProviderProfile', {
          'profileId': profileId,
        });
    return ModelProviderProfilesPayload.fromMap(result);
  }

  static Future<ModelProviderProfileSummary> setEditingProfile(
    String profileId,
  ) async {
    final result = await AssistsMessageService.assistCore
        .invokeMethod<Map<dynamic, dynamic>>('setEditingModelProviderProfile', {
          'profileId': profileId,
        });
    return ModelProviderProfileSummary.fromMap(result);
  }

  static Future<ModelProviderConfig> saveConfig({
    required String baseUrl,
    required String apiKey,
  }) async {
    final result = await AssistsMessageService.assistCore
        .invokeMethod<Map<dynamic, dynamic>>('saveModelProviderConfig', {
          'baseUrl': baseUrl,
          'apiKey': apiKey,
        });
    return ModelProviderConfig.fromMap(result);
  }

  static Future<ModelProviderConfig> clearConfig() async {
    final result = await AssistsMessageService.assistCore
        .invokeMethod<Map<dynamic, dynamic>>('clearModelProviderConfig');
    return ModelProviderConfig.fromMap(result);
  }

  static Future<List<ProviderModelOption>> fetchModels({
    String apiBase = '',
    String apiKey = '',
    String? profileId,
  }) async {
    final result = await AssistsMessageService.assistCore
        .invokeMethod<List<dynamic>>('fetchProviderModels', {
          'apiBase': apiBase,
          'apiKey': apiKey,
          if (profileId != null && profileId.trim().isNotEmpty)
            'profileId': profileId.trim(),
        });
    final models = (result ?? const [])
        .map((item) => ProviderModelOption.fromMap(item as Map?))
        .where((item) => item.id.isNotEmpty)
        .toList();

    final targetProfileId = await _resolveProfileId(profileId);
    if (targetProfileId != null) {
      try {
        var cacheBase = normalizeApiBase(apiBase) ?? '';
        if (cacheBase.isEmpty) {
          final config = await getConfig();
          cacheBase = config.baseUrl;
        }
        await _saveCachedFetchedModels(
          profileId: targetProfileId,
          apiBase: cacheBase,
          models: models,
        );
      } catch (_) {
        // ignore cache write failures
      }
    }

    return models;
  }

  static Future<List<ProviderModelOption>> getCachedFetchedModels({
    required String profileId,
    String apiBase = '',
  }) async {
    final normalizedProfileId = _canonicalProfileId(profileId);
    await _migrateLegacyStorageIfNeeded(normalizedProfileId);
    final raw = StorageService.getString(
      _kCachedFetchedModelsKey,
      defaultValue: '',
    );
    if (raw == null || raw.trim().isEmpty) {
      return const [];
    }

    final requestedBase = normalizeApiBase(apiBase) ?? '';
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return const [];
      }
      final bucket = decoded[normalizedProfileId];
      if (bucket is! Map<String, dynamic>) {
        return const [];
      }
      final cacheBase = (bucket['apiBase'] ?? '').toString();
      if (requestedBase.isNotEmpty && cacheBase != requestedBase) {
        return const [];
      }
      final modelsRaw = bucket['models'];
      if (modelsRaw is! List) {
        return const [];
      }
      return modelsRaw
          .map((item) => ProviderModelOption.fromMap(item as Map?))
          .where((item) => item.id.isNotEmpty)
          .toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> saveCachedFetchedModels({
    required String profileId,
    required String apiBase,
    required List<ProviderModelOption> models,
  }) async {
    await _saveCachedFetchedModels(
      profileId: profileId,
      apiBase: apiBase,
      models: models,
    );
  }

  static Future<void> _saveCachedFetchedModels({
    required String profileId,
    required String apiBase,
    required List<ProviderModelOption> models,
  }) async {
    final normalizedProfileId = _canonicalProfileId(profileId);
    await _migrateLegacyStorageIfNeeded(normalizedProfileId);
    final current = _readJsonMap(_kCachedFetchedModelsKey);
    final normalizedBase = normalizeApiBase(apiBase) ?? '';
    current[normalizedProfileId] = {
      'apiBase': normalizedBase,
      'models': models
          .map(
            (item) => {
              'id': item.id,
              'displayName': item.displayName,
              'ownedBy': item.ownedBy,
            },
          )
          .toList(),
    };
    await StorageService.setString(
      _kCachedFetchedModelsKey,
      jsonEncode(current),
    );
  }

  static Future<List<String>> getManualModelIds({
    required String profileId,
  }) async {
    final normalizedProfileId = _canonicalProfileId(profileId);
    await _migrateLegacyStorageIfNeeded(normalizedProfileId);
    final current = _readJsonMap(_kManualModelIdsKey);
    final rawIds = (current[normalizedProfileId] as List?)
        ?.map((item) => item.toString())
        .toList();
    return _normalizeModelIds(rawIds ?? const []);
  }

  static Future<void> saveManualModelIds({
    required String profileId,
    required List<String> ids,
  }) async {
    final normalizedProfileId = _canonicalProfileId(profileId);
    await _migrateLegacyStorageIfNeeded(normalizedProfileId);
    final current = _readJsonMap(_kManualModelIdsKey);
    current[normalizedProfileId] = _normalizeModelIds(ids);
    await StorageService.setString(_kManualModelIdsKey, jsonEncode(current));
  }

  static Future<List<ProviderModelOption>> getStoredModelOptionsForProfile(
    String profileId,
  ) async {
    final normalizedProfileId = _canonicalProfileId(profileId);
    final manualModelIds = await getManualModelIds(
      profileId: normalizedProfileId,
    );
    List<ProviderModelOption> remoteModels;
    if (_isBuiltinLocalProfileId(normalizedProfileId)) {
      try {
        remoteModels = await fetchModels(profileId: normalizedProfileId);
      } catch (_) {
        remoteModels = await getCachedFetchedModels(
          profileId: normalizedProfileId,
        );
      }
    } else {
      remoteModels = await getCachedFetchedModels(
        profileId: normalizedProfileId,
      );
    }
    return mergeModelOptions(
      remoteModels: remoteModels,
      manualModelIds: manualModelIds,
    );
  }

  static Future<List<ProviderModelGroup>> loadModelGroups() async {
    final payload = await listProfiles();
    final groups = <ProviderModelGroup>[];
    for (final profile in payload.profiles) {
      final models = await getStoredModelOptionsForProfile(profile.id);
      groups.add(ProviderModelGroup(profile: profile, models: models));
    }
    return groups;
  }

  static List<ProviderModelOption> mergeModelOptions({
    required List<ProviderModelOption> remoteModels,
    required List<String> manualModelIds,
  }) {
    final merged = <ProviderModelOption>[];
    final seen = <String>{};

    for (final modelId in _normalizeModelIds(manualModelIds)) {
      if (seen.add(modelId)) {
        merged.add(
          ProviderModelOption(
            id: modelId,
            displayName: modelId,
            ownedBy: 'manual',
          ),
        );
      }
    }

    for (final item in remoteModels) {
      if (seen.add(item.id)) {
        merged.add(item);
      }
    }
    return merged;
  }

  static Future<String?> _resolveProfileId(String? profileId) async {
    if (profileId != null && profileId.trim().isNotEmpty) {
      return _canonicalProfileId(profileId);
    }
    final config = await getConfig();
    final normalized = _canonicalProfileId(config.id);
    return normalized.isEmpty ? null : normalized;
  }

  static Map<String, dynamic> _readJsonMap(String key) {
    final raw = StorageService.getString(key, defaultValue: '');
    if (raw == null || raw.trim().isEmpty) {
      return <String, dynamic>{};
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      // ignore broken cache
    }
    return <String, dynamic>{};
  }

  static Future<void> _migrateLegacyStorageIfNeeded(String profileId) async {
    final targetProfileId = _canonicalProfileId(profileId);
    if (targetProfileId.isEmpty) {
      return;
    }

    final currentManual = _readJsonMap(_kManualModelIdsKey);
    if (targetProfileId == _kBuiltinOmniInferProfileId &&
        !currentManual.containsKey(targetProfileId) &&
        currentManual.containsKey(_kLegacyBuiltinMnnLocalProfileId)) {
      currentManual[targetProfileId] =
          currentManual[_kLegacyBuiltinMnnLocalProfileId];
      currentManual.remove(_kLegacyBuiltinMnnLocalProfileId);
      await StorageService.setString(
        _kManualModelIdsKey,
        jsonEncode(currentManual),
      );
    }
    if (!currentManual.containsKey(targetProfileId)) {
      final legacyManual = StorageService.getStringList(
        _kLegacyManualModelIdsKey,
        defaultValue: [],
      );
      if (legacyManual != null && legacyManual.isNotEmpty) {
        currentManual[targetProfileId] = _normalizeModelIds(legacyManual);
        await StorageService.setString(
          _kManualModelIdsKey,
          jsonEncode(currentManual),
        );
        await StorageService.remove(_kLegacyManualModelIdsKey);
      }
    }

    final currentCached = _readJsonMap(_kCachedFetchedModelsKey);
    if (targetProfileId == _kBuiltinOmniInferProfileId &&
        !currentCached.containsKey(targetProfileId) &&
        currentCached.containsKey(_kLegacyBuiltinMnnLocalProfileId)) {
      currentCached[targetProfileId] =
          currentCached[_kLegacyBuiltinMnnLocalProfileId];
      currentCached.remove(_kLegacyBuiltinMnnLocalProfileId);
      await StorageService.setString(
        _kCachedFetchedModelsKey,
        jsonEncode(currentCached),
      );
    }
    if (!currentCached.containsKey(targetProfileId)) {
      final legacyRaw = StorageService.getString(
        _kLegacyCachedFetchedModelsKey,
        defaultValue: '',
      );
      if (legacyRaw != null && legacyRaw.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(legacyRaw);
          if (decoded is Map<String, dynamic>) {
            currentCached[targetProfileId] = decoded;
            await StorageService.setString(
              _kCachedFetchedModelsKey,
              jsonEncode(currentCached),
            );
            await StorageService.remove(_kLegacyCachedFetchedModelsKey);
          }
        } catch (_) {
          // ignore
        }
      }
    }
  }

  static List<String> _normalizeModelIds(List<String> ids) {
    final result = <String>[];
    final seen = <String>{};
    for (final raw in ids) {
      final normalized = raw.trim();
      if (!isValidModelName(normalized)) {
        continue;
      }
      if (seen.add(normalized)) {
        result.add(normalized);
      }
    }
    return result;
  }

  static bool isValidApiBase(String value) {
    return normalizeApiBase(value) != null;
  }

  static String? normalizeApiBase(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || !uri.hasAuthority) {
      return null;
    }
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      return null;
    }

    var result = normalized.replaceAll(RegExp(r'/+$'), '');
    const suffixes = [
      '/v1/chat/completions',
      '/chat/completions',
      '/v1/models',
      '/models',
    ];
    for (final suffix in suffixes) {
      if (result.toLowerCase().endsWith(suffix)) {
        result = result.substring(0, result.length - suffix.length);
        break;
      }
    }
    return result.replaceAll(RegExp(r'/+$'), '');
  }

  static String? buildModelsRequestUrl(String value) {
    return _buildRequestUrl(
      value,
      suffixAfterV1: '/models',
      suffixWithVersion: '/v1/models',
    );
  }

  static String? buildChatCompletionsRequestUrl(String value) {
    return _buildRequestUrl(
      value,
      suffixAfterV1: '/chat/completions',
      suffixWithVersion: '/v1/chat/completions',
    );
  }

  static String? _buildRequestUrl(
    String value, {
    required String suffixAfterV1,
    required String suffixWithVersion,
  }) {
    final normalizedBase = normalizeApiBase(value);
    if (normalizedBase == null) {
      return null;
    }
    final base = normalizedBase.replaceAll(RegExp(r'/+$'), '');
    if (base.toLowerCase().endsWith('/v1')) {
      return '$base$suffixAfterV1';
    }
    return '$base$suffixWithVersion';
  }

  static bool isValidModelName(String value) {
    final normalized = value.trim();
    return normalized.isNotEmpty && !normalized.startsWith('scene.');
  }
}



