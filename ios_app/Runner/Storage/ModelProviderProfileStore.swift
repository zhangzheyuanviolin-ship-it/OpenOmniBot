import Foundation

@MainActor
final class ModelProviderProfileStore {
    static let shared = ModelProviderProfileStore()

    fileprivate struct StoredProfile: Codable, Equatable {
        let id: String
        let name: String
        let baseUrl: String
        let apiKey: String
        let protocolType: String
    }

    private let defaults = UserDefaults.standard

    private let profilesKey = "omnibot.model_provider_profiles_v1"
    private let editingProfileIdKey = "omnibot.model_provider_editing_profile_id"
    private let defaultProfileID = "profile-1"
    private let defaultProfileName = "Provider 1"
    private let builtinProfileID = "omniinfer-local"
    private let legacyBuiltinProfileID = "mnn-local"
    private let builtinProfileName = "OmniInfer"
    private let directRequestURLMarker = "#"
    private let canonicalEndpointSuffixes = [
        "/v1/chat/completions",
        "/chat/completions",
        "/v1/models",
        "/models",
        "/v1/messages",
        "/messages",
    ]
#if DEBUG
    private let developmentProfileID = "debug-octopus-provider"
    private let developmentProfileName = "Octopus Dev"
    private let developmentProfileBaseURL = "https://api.1775885.xyz"
    private let developmentProfileAPIKey = "sk-octopus-fl2T2zk9LmanVV9ZyJRsug3C9OtL8qFmVewZPX9fSjx9gSi5"
#endif

    private init() {}

    func currentConfig() async -> [String: Any] {
        let profile = await editingProfile()
        return configDictionary(for: profile)
    }

    func listProfilesPayload() async -> [String: Any] {
        let profiles = await listProfiles()
        return [
            "profiles": profiles.map { profileDictionary(for: $0) },
            "editingProfileId": currentEditingProfileID(customProfiles: storedProfiles()),
        ]
    }

    func saveProfile(
        id: String?,
        name: String,
        baseURL: String,
        apiKey: String,
        protocolType: String
    ) throws -> [String: Any] {
        let normalizedID = canonicalProfileID(id?.trimmingCharacters(in: .whitespacesAndNewlines))
        if normalizedID == builtinProfileID {
            throw StoreError.readOnlyProfile
        }

        var profiles = storedProfiles()
        let profileID = normalizedID.isEmpty == false ? normalizedID : generateProfileID(from: profiles)
        let existingIndex = profiles.firstIndex(where: { $0.id == profileID })
        let resolvedName = sanitizeProfileName(
            raw: name,
            profiles: profiles,
            existingID: existingIndex == nil ? nil : profileID
        )
        let nextProfile = StoredProfile(
            id: profileID,
            name: resolvedName,
            baseUrl: normalizeBaseURL(baseURL) ?? "",
            apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
            protocolType: protocolType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "openai_compatible"
                : protocolType.trimmingCharacters(in: .whitespacesAndNewlines)
        )

        if let existingIndex {
            profiles[existingIndex] = nextProfile
        } else {
            profiles.append(nextProfile)
        }
        persistProfiles(profiles, editingProfileID: nextProfile.id)
        return profileDictionary(for: .custom(nextProfile))
    }

    func deleteProfile(profileID: String) async throws -> [String: Any] {
        let normalizedID = canonicalProfileID(profileID.trimmingCharacters(in: .whitespacesAndNewlines))
        if normalizedID == builtinProfileID {
            throw StoreError.readOnlyProfile
        }

        var profiles = storedProfiles()
        guard profiles.count > 1 else {
            throw StoreError.lastEditableProfile
        }
        guard profiles.contains(where: { $0.id == normalizedID }) else {
            throw StoreError.profileNotFound
        }
        profiles.removeAll(where: { $0.id == normalizedID })

        let nextEditingID = currentEditingProfileID(customProfiles: profiles, preferredEditingID: nil)
        persistProfiles(profiles, editingProfileID: nextEditingID)

        let merged = await listProfiles()
        return [
            "profiles": merged.map { profileDictionary(for: $0) },
            "editingProfileId": nextEditingID,
        ]
    }

    func setEditingProfile(_ profileID: String) async throws -> [String: Any] {
        let normalizedID = canonicalProfileID(profileID.trimmingCharacters(in: .whitespacesAndNewlines))
        let profiles = await listProfiles()
        guard let target = profiles.first(where: { $0.id == normalizedID }) else {
            throw StoreError.profileNotFound
        }
        defaults.set(normalizedID, forKey: editingProfileIdKey)
        return profileDictionary(for: target)
    }

    func saveConfig(baseURL: String, apiKey: String) async throws -> [String: Any] {
        let current = await editingProfile()
        guard case let .custom(profile) = current else {
            throw StoreError.readOnlyProfile
        }
        _ = try saveProfile(
            id: profile.id,
            name: profile.name,
            baseURL: baseURL,
            apiKey: apiKey,
            protocolType: profile.protocolType
        )
        return await currentConfig()
    }

    func clearConfig() async throws -> [String: Any] {
        let current = await editingProfile()
        guard case let .custom(profile) = current else {
            throw StoreError.readOnlyProfile
        }
        _ = try saveProfile(
            id: profile.id,
            name: profile.name,
            baseURL: "",
            apiKey: "",
            protocolType: profile.protocolType
        )
        return await currentConfig()
    }

    func fetchProviderModels(
        apiBase: String,
        apiKey: String,
        profileID: String?
    ) async throws -> [[String: Any]] {
        let editingProfile = await editingProfile()
        let targetProfile = await resolvedProfile(profileID: profileID, fallback: editingProfile)
        if targetProfile.id == builtinProfileID {
            return await fetchBuiltinLocalModels()
        }

        let baseURL = apiBase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? targetProfile.baseURL
            : apiBase.trimmingCharacters(in: .whitespacesAndNewlines)
        let authToken = apiBase.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? targetProfile.apiKey
            : apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let requestURL = try buildModelsRequestURL(from: baseURL)
        let protocolType = targetProfile.protocolType

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.timeoutInterval = 20
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if protocolType == "anthropic" {
            if authToken.isEmpty == false {
                request.setValue(authToken, forHTTPHeaderField: "x-api-key")
            }
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        } else if authToken.isEmpty == false {
            request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StoreError.invalidResponse("Provider response is missing HTTP metadata.")
        }
        guard (200 ... 299).contains(httpResponse.statusCode) else {
            throw StoreError.invalidResponse(parseServerError(from: data) ?? "Provider request failed with status \(httpResponse.statusCode).")
        }

        return try parseProviderModels(from: data)
    }

    private func parseProviderModels(from data: Data) throws -> [[String: Any]] {
        let jsonObject = try JSONSerialization.jsonObject(with: data)
        let items: [[String: Any]]
        if let array = jsonObject as? [[String: Any]] {
            items = array
        } else if let dictionary = jsonObject as? [String: Any] {
            if let dataItems = dictionary["data"] as? [[String: Any]] {
                items = dataItems
            } else if let modelItems = dictionary["models"] as? [[String: Any]] {
                items = modelItems
            } else if let itemItems = dictionary["items"] as? [[String: Any]] {
                items = itemItems
            } else {
                items = []
            }
        } else {
            items = []
        }

        return items.compactMap { item in
            let identifier = (item["id"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard identifier.isEmpty == false else { return nil }
            let displayName = (
                item["displayName"] as? String ??
                item["display_name"] as? String ??
                item["name"] as? String ??
                identifier
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            let ownedBy = (
                item["ownedBy"] as? String ??
                item["owned_by"] as? String ??
                item["category"] as? String ??
                item["type"] as? String
            )?.trimmingCharacters(in: .whitespacesAndNewlines)
            return providerModelDictionary(
                id: identifier,
                displayName: displayName.isEmpty ? identifier : displayName,
                ownedBy: ownedBy
            )
        }
        .sorted { left, right in
            let leftID = (left["id"] as? String ?? "").lowercased()
            let rightID = (right["id"] as? String ?? "").lowercased()
            return leftID < rightID
        }
    }

    private func parseServerError(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) else {
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if let dictionary = object as? [String: Any] {
            if let message = dictionary["error"] as? String, message.isEmpty == false {
                return message
            }
            if let error = dictionary["error"] as? [String: Any] {
                if let message = error["message"] as? String, message.isEmpty == false {
                    return message
                }
                if let type = error["type"] as? String, type.isEmpty == false {
                    return type
                }
            }
            if let message = dictionary["message"] as? String, message.isEmpty == false {
                return message
            }
        }
        return nil
    }

    private func fetchBuiltinLocalModels() async -> [[String: Any]] {
        let workspace = TerminalRuntimeCoordinator.shared.resolveWorkspacePaths()
        let modelRoot = URL(fileURLWithPath: workspace.internalRootPath, isDirectory: true)
            .appendingPathComponent("models/OmniInfer-llama", isDirectory: true)
        var identifiers = Set<String>()

        if let contents = try? FileManager.default.contentsOfDirectory(
            at: modelRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) {
            for item in contents {
                let resourceValues = try? item.resourceValues(forKeys: [.isDirectoryKey])
                if resourceValues?.isDirectory == true {
                    identifiers.insert(item.lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines))
                } else if item.pathExtension.lowercased() == "gguf" {
                    identifiers.insert(item.deletingPathExtension().lastPathComponent.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }
        }

        let status = await LocalModelCoordinator.shared.statusMessage()
        if let activeModelID = status.activeModelId?.trimmingCharacters(in: .whitespacesAndNewlines), activeModelID.isEmpty == false {
            identifiers.insert(activeModelID)
        }
        if let loadedModelID = status.loadedModelId?.trimmingCharacters(in: .whitespacesAndNewlines), loadedModelID.isEmpty == false {
            identifiers.insert(loadedModelID)
        }

        return identifiers
            .filter { $0.isEmpty == false }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
            .map { providerModelDictionary(id: $0, displayName: $0, ownedBy: "omniinfer") }
    }

    private func storedProfiles() -> [StoredProfile] {
        if
            let data = defaults.data(forKey: profilesKey),
            let decoded = try? JSONDecoder().decode([StoredProfile].self, from: data)
        {
            let normalized = decoded.compactMap { profile -> StoredProfile? in
                let normalizedID = canonicalProfileID(profile.id.trimmingCharacters(in: .whitespacesAndNewlines))
                guard normalizedID.isEmpty == false, normalizedID != builtinProfileID else {
                    return nil
                }
                return StoredProfile(
                    id: normalizedID,
                    name: profile.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? defaultProfileName
                        : profile.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    baseUrl: normalizeBaseURL(profile.baseUrl) ?? "",
                    apiKey: profile.apiKey.trimmingCharacters(in: .whitespacesAndNewlines),
                    protocolType: profile.protocolType.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? "openai_compatible"
                        : profile.protocolType.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
            }
            let deduplicated = ensureDevelopmentProfiles(in: deduplicatedProfiles(normalized))
            if deduplicated.isEmpty == false {
                if deduplicated != normalized {
                    persistProfiles(
                        deduplicated,
                        editingProfileID: defaults.string(forKey: editingProfileIdKey)
                    )
                }
                return deduplicated
            }
        }

        let fallback = ensureDevelopmentProfiles(in: [StoredProfile(
            id: defaultProfileID,
            name: defaultProfileName,
            baseUrl: "",
            apiKey: "",
            protocolType: "openai_compatible"
        )])
        persistProfiles(fallback, editingProfileID: defaults.string(forKey: editingProfileIdKey))
        return fallback
    }

    private func persistProfiles(_ profiles: [StoredProfile], editingProfileID: String?) {
        let normalized = deduplicatedProfiles(profiles)
        let encoded = try? JSONEncoder().encode(normalized)
        defaults.set(encoded, forKey: profilesKey)
        defaults.set(
            currentEditingProfileID(customProfiles: normalized, preferredEditingID: editingProfileID),
            forKey: editingProfileIdKey
        )
    }

    private func deduplicatedProfiles(_ profiles: [StoredProfile]) -> [StoredProfile] {
        var seen = Set<String>()
        return profiles.compactMap { profile in
            guard seen.insert(profile.id).inserted else { return nil }
            return profile
        }
    }

    private func ensureDevelopmentProfiles(in profiles: [StoredProfile]) -> [StoredProfile] {
#if DEBUG
        let developmentProfile = StoredProfile(
            id: developmentProfileID,
            name: developmentProfileName,
            baseUrl: normalizeBaseURL(developmentProfileBaseURL) ?? developmentProfileBaseURL,
            apiKey: developmentProfileAPIKey,
            protocolType: "openai_compatible"
        )

        if profiles.contains(where: { $0.id == developmentProfileID }) {
            return profiles
        }

        return [developmentProfile] + profiles
#else
        return profiles
#endif
    }

    private func currentEditingProfileID(
        customProfiles: [StoredProfile],
        preferredEditingID: String? = nil
    ) -> String {
        let preferred = canonicalProfileID(
            preferredEditingID?.trimmingCharacters(in: .whitespacesAndNewlines) ??
            defaults.string(forKey: editingProfileIdKey)?.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        if preferred == builtinProfileID {
            return builtinProfileID
        }
        if preferred.isEmpty == false, customProfiles.contains(where: { $0.id == preferred }) {
            return preferred
        }
        return customProfiles.first?.id ?? defaultProfileID
    }

    private func listProfiles() async -> [ProviderProfile] {
        let builtin = await builtinProfile()
        let custom = storedProfiles().map(ProviderProfile.custom)
        return [builtin] + custom.filter { $0.id != builtin.id }
    }

    private func editingProfile() async -> ProviderProfile {
        let profiles = await listProfiles()
        let editingID = currentEditingProfileID(customProfiles: storedProfiles())
        return profiles.first(where: { $0.id == editingID }) ?? profiles.first ?? ProviderProfile.custom(
            StoredProfile(
                id: defaultProfileID,
                name: defaultProfileName,
                baseUrl: "",
                apiKey: "",
                protocolType: "openai_compatible"
            )
        )
    }

    private func resolvedProfile(profileID: String?, fallback: ProviderProfile) async -> ProviderProfile {
        guard let profileID else {
            return fallback
        }
        let normalizedID = canonicalProfileID(profileID.trimmingCharacters(in: .whitespacesAndNewlines))
        let profiles = await listProfiles()
        return profiles.first(where: { $0.id == normalizedID }) ?? fallback
    }

    private func builtinProfile() async -> ProviderProfile {
        let status = await LocalModelCoordinator.shared.statusMessage()
        return .builtin(
            id: builtinProfileID,
            name: builtinProfileName,
            baseURL: status.baseUrl,
            apiKey: "",
            ready: status.apiReady,
            statusText: status.apiReady ? "已就绪" : "未就绪"
        )
    }

    private func generateProfileID(from profiles: [StoredProfile]) -> String {
        var nextIndex = profiles.count + 1
        while true {
            let candidate = "profile-\(nextIndex)"
            if profiles.contains(where: { $0.id == candidate }) == false {
                return candidate
            }
            nextIndex += 1
        }
    }

    private func sanitizeProfileName(raw: String, profiles: [StoredProfile], existingID: String?) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty == false {
            return trimmed
        }
        if let existingID, let existing = profiles.first(where: { $0.id == existingID }) {
            return existing.name
        }

        let names = Set(profiles.map(\.name))
        var nextIndex = 1
        while true {
            let candidate = "Provider \(nextIndex)"
            if names.contains(candidate) == false {
                return candidate
            }
            nextIndex += 1
        }
    }

    private func profileDictionary(for profile: ProviderProfile) -> [String: Any] {
        switch profile {
        case let .builtin(id, name, baseURL, apiKey, ready, statusText):
            return [
                "id": id,
                "name": name,
                "baseUrl": baseURL,
                "apiKey": apiKey,
                "sourceType": "omniinfer",
                "readOnly": true,
                "ready": ready,
                "statusText": statusText,
                "configured": baseURL.isEmpty == false,
                "protocolType": "openai_compatible",
            ]
        case let .custom(profile):
            return [
                "id": profile.id,
                "name": profile.name,
                "baseUrl": profile.baseUrl,
                "apiKey": profile.apiKey,
                "sourceType": "custom",
                "readOnly": false,
                "ready": true,
                "statusText": profile.baseUrl.isEmpty ? "" : "已配置",
                "configured": profile.baseUrl.isEmpty == false,
                "protocolType": profile.protocolType,
            ]
        }
    }

    private func configDictionary(for profile: ProviderProfile) -> [String: Any] {
        switch profile {
        case let .builtin(id, name, baseURL, apiKey, ready, statusText):
            return [
                "id": id,
                "name": name,
                "baseUrl": baseURL,
                "apiKey": apiKey,
                "source": "omniinfer",
                "providerType": "omniinfer",
                "readOnly": true,
                "ready": ready,
                "statusText": statusText,
                "configured": baseURL.isEmpty == false,
            ]
        case let .custom(profile):
            return [
                "id": profile.id,
                "name": profile.name,
                "baseUrl": profile.baseUrl,
                "apiKey": profile.apiKey,
                "source": "profile",
                "providerType": "custom",
                "readOnly": false,
                "ready": true,
                "statusText": profile.baseUrl.isEmpty ? "" : "已配置",
                "configured": profile.baseUrl.isEmpty == false,
            ]
        }
    }

    private func providerModelDictionary(id: String, displayName: String, ownedBy: String?) -> [String: Any] {
        [
            "id": id,
            "displayName": displayName,
            "ownedBy": ownedBy ?? NSNull(),
        ]
    }

    private func buildModelsRequestURL(from value: String) throws -> URL {
        guard let normalizedBase = normalizeBaseURL(value) else {
            throw StoreError.invalidBaseURL
        }
        let stripped = stripDirectRequestURLMarker(normalizedBase)
        let urlString: String
        if hasDirectRequestURLMarker(normalizedBase) {
            urlString = stripped
        } else if stripped.lowercased().hasSuffix("/v1") {
            urlString = "\(stripped)/models"
        } else {
            urlString = "\(stripped)/v1/models"
        }
        guard let url = URL(string: urlString) else {
            throw StoreError.invalidBaseURL
        }
        return url
    }

    private func canonicalProfileID(_ value: String?) -> String {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines) {
        case builtinProfileID, legacyBuiltinProfileID:
            return builtinProfileID
        default:
            return value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        }
    }

    private func normalizeBaseURL(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        let hasDirectRequest = hasDirectRequestURLMarker(trimmed)
        let candidate = hasDirectRequest
            ? String(trimmed.dropLast(directRequestURLMarker.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            : trimmed
        guard candidate.isEmpty == false, let url = URL(string: candidate), let scheme = url.scheme?.lowercased(),
              (scheme == "http" || scheme == "https"), url.host?.isEmpty == false
        else {
            return nil
        }

        var result = candidate.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        if hasDirectRequest == false {
            for suffix in canonicalEndpointSuffixes where result.lowercased().hasSuffix(suffix) {
                result = String(result.dropLast(suffix.count))
                break
            }
        }
        result = result.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
        guard result.isEmpty == false else { return nil }
        return hasDirectRequest ? "\(result)\(directRequestURLMarker)" : result
    }

    private func hasDirectRequestURLMarker(_ value: String) -> Bool {
        value.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(directRequestURLMarker)
    }

    private func stripDirectRequestURLMarker(_ value: String) -> String {
        var result = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if result.hasSuffix(directRequestURLMarker) {
            result.removeLast(directRequestURLMarker.count)
        }
        return result.replacingOccurrences(of: "/+$", with: "", options: .regularExpression)
    }
}

private enum ProviderProfile {
    case builtin(id: String, name: String, baseURL: String, apiKey: String, ready: Bool, statusText: String)
    case custom(ModelProviderProfileStore.StoredProfile)

    var id: String {
        switch self {
        case let .builtin(id, _, _, _, _, _):
            return id
        case let .custom(profile):
            return profile.id
        }
    }

    var name: String {
        switch self {
        case let .builtin(_, name, _, _, _, _):
            return name
        case let .custom(profile):
            return profile.name
        }
    }

    var baseURL: String {
        switch self {
        case let .builtin(_, _, baseURL, _, _, _):
            return baseURL
        case let .custom(profile):
            return profile.baseUrl
        }
    }

    var apiKey: String {
        switch self {
        case let .builtin(_, _, _, apiKey, _, _):
            return apiKey
        case let .custom(profile):
            return profile.apiKey
        }
    }

    var protocolType: String {
        switch self {
        case .builtin:
            return "openai_compatible"
        case let .custom(profile):
            return profile.protocolType
        }
    }

    var isConfigured: Bool {
        baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}

extension ModelProviderProfileStore {
    struct CompletionRequestConfig {
        let providerProfileId: String
        let providerProfileName: String
        let apiBase: String
        let apiKey: String
        let modelId: String
        let protocolType: String
    }

    enum StoreError: LocalizedError {
        case readOnlyProfile
        case lastEditableProfile
        case profileNotFound
        case invalidBaseURL
        case invalidResponse(String)
        case invalidSceneID
        case invalidModelName
        case invalidProviderProfile

        var errorDescription: String? {
            switch self {
            case .readOnlyProfile:
                return "Builtin provider is read only."
            case .lastEditableProfile:
                return "At least one editable provider profile must remain."
            case .profileNotFound:
                return "Provider profile was not found."
            case .invalidBaseURL:
                return "Base URL is invalid."
            case let .invalidResponse(message):
                return message
            case .invalidSceneID:
                return "Scene ID is invalid."
            case .invalidModelName:
                return "Model name is invalid."
            case .invalidProviderProfile:
                return "Provider profile is invalid."
            }
        }
    }
}

extension ModelProviderProfileStore {
    private struct SceneCatalogDefinition {
        let sceneId: String
        let description: String
        let defaultModel: String
        let transport: String
        let configSource: String
    }

    private struct SceneModelBindingRecord: Codable {
        let sceneId: String
        let providerProfileId: String
        let modelId: String
    }

    private var sceneModelBindingsKey: String {
        "omnibot.scene_model_bindings_v1"
    }

    private var sceneCatalogDefinitions: [SceneCatalogDefinition] {
        [
            SceneCatalogDefinition(
                sceneId: "scene.dispatch.model",
                description: "可执行任务三段式分流默认模型",
                defaultModel: "qwen3.5-plus",
                transport: "openai_compatible",
                configSource: "builtin"
            ),
            SceneCatalogDefinition(
                sceneId: "scene.vlm.operation.primary",
                description: "GUI-Agent 逐步 UI 自动化主模型",
                defaultModel: "qwen3-vl-plus",
                transport: "openai_compatible",
                configSource: "builtin"
            ),
            SceneCatalogDefinition(
                sceneId: "scene.compactor.context",
                description: "VLM 上下文压缩与纠错 Agent",
                defaultModel: "qwen3-vl-plus",
                transport: "openai_compatible",
                configSource: "builtin"
            ),
            SceneCatalogDefinition(
                sceneId: "scene.compactor.context.chat",
                description: "聊天历史上下文压缩模型",
                defaultModel: "qwen3.5-plus",
                transport: "openai_compatible",
                configSource: "builtin"
            ),
            SceneCatalogDefinition(
                sceneId: "scene.loading.sprite",
                description: "赛博精灵加载状态生成器",
                defaultModel: "qwen-plus",
                transport: "openai_compatible",
                configSource: "builtin"
            ),
            SceneCatalogDefinition(
                sceneId: "scene.memory.embedding",
                description: "Workspace 记忆向量检索（embedding）模型",
                defaultModel: "text-embedding-3-small",
                transport: "openai_compatible",
                configSource: "builtin"
            ),
            SceneCatalogDefinition(
                sceneId: "scene.memory.rollup",
                description: "Workspace 夜间记忆整理模型",
                defaultModel: "qwen3.5-plus",
                transport: "openai_compatible",
                configSource: "builtin"
            ),
        ]
    }

    private var allowedSceneIDs: Set<String> {
        Set(sceneCatalogDefinitions.map(\.sceneId))
    }

    func sceneModelCatalogPayload() async -> [[String: Any]] {
        let profiles = await listProfiles()
        let profilesByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })
        let bindings = storedSceneModelBindings()

        return sceneCatalogDefinitions.map { definition in
            let binding = bindings[definition.sceneId]
            let boundProfile = binding.flatMap { profilesByID[$0.providerProfileId] }
            let bindingApplied = binding != nil && boundProfile?.isConfigured == true
            let bindingProfileMissing = binding != nil && boundProfile == nil

            return [
                "sceneId": definition.sceneId,
                "description": definition.description,
                "defaultModel": definition.defaultModel,
                "effectiveModel": bindingApplied ? (binding?.modelId ?? definition.defaultModel) : definition.defaultModel,
                "effectiveProviderProfileId": nullable(bindingApplied ? boundProfile?.id : nil),
                "effectiveProviderProfileName": nullable(bindingApplied ? boundProfile?.name : nil),
                "boundProviderProfileId": nullable(binding?.providerProfileId),
                "boundProviderProfileName": nullable(boundProfile?.name),
                "transport": bindingApplied ? "openai_compatible" : definition.transport,
                "configSource": definition.configSource,
                "overrideApplied": bindingApplied,
                "overrideModel": nullable(binding?.modelId),
                "providerConfigured": boundProfile?.isConfigured == true,
                "bindingExists": binding != nil,
                "bindingProfileMissing": bindingProfileMissing,
            ]
        }
    }

    func sceneModelBindingsPayload() -> [[String: Any]] {
        storedSceneModelBindings()
            .values
            .sorted { $0.sceneId < $1.sceneId }
            .map {
                [
                    "sceneId": $0.sceneId,
                    "providerProfileId": $0.providerProfileId,
                    "modelId": $0.modelId,
                ]
            }
    }

    func saveSceneModelBinding(
        sceneId: String,
        providerProfileId: String,
        modelId: String
    ) throws -> [[String: Any]] {
        let normalizedSceneID = sceneId.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedProviderProfileID = canonicalProfileID(
            providerProfileId.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let normalizedModelID = modelId.trimmingCharacters(in: .whitespacesAndNewlines)

        guard allowedSceneIDs.contains(normalizedSceneID) else {
            throw StoreError.invalidSceneID
        }
        guard normalizedProviderProfileID.isEmpty == false else {
            throw StoreError.invalidProviderProfile
        }
        guard isValidSceneModelName(normalizedModelID) else {
            throw StoreError.invalidModelName
        }

        var bindings = storedSceneModelBindings()
        bindings[normalizedSceneID] = SceneModelBindingRecord(
            sceneId: normalizedSceneID,
            providerProfileId: normalizedProviderProfileID,
            modelId: normalizedModelID
        )
        persistSceneModelBindings(bindings)
        return sceneModelBindingsPayload()
    }

    func clearSceneModelBinding(sceneId: String) -> [[String: Any]] {
        let normalizedSceneID = sceneId.trimmingCharacters(in: .whitespacesAndNewlines)
        var bindings = storedSceneModelBindings()
        bindings.removeValue(forKey: normalizedSceneID)
        persistSceneModelBindings(bindings)
        return sceneModelBindingsPayload()
    }

    func sceneModelOverridesPayload() -> [[String: Any]] {
        storedSceneModelBindings()
            .values
            .sorted { $0.sceneId < $1.sceneId }
            .map {
                [
                    "sceneId": $0.sceneId,
                    "model": $0.modelId,
                ]
            }
    }

    func saveSceneModelOverride(sceneId: String, modelId: String) async throws -> [[String: Any]] {
        let editingProfileID = (await editingProfile()).id
        _ = try saveSceneModelBinding(
            sceneId: sceneId,
            providerProfileId: editingProfileID,
            modelId: modelId
        )
        return sceneModelOverridesPayload()
    }

    func clearSceneModelOverride(sceneId: String) -> [[String: Any]] {
        _ = clearSceneModelBinding(sceneId: sceneId)
        return sceneModelOverridesPayload()
    }

    func resolveCompletionRequestConfig(
        sceneId: String,
        modelOverride: [String: Any]?
    ) async throws -> CompletionRequestConfig {
        let normalizedSceneID = sceneId.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallbackDefinition = sceneCatalogDefinitions.first(where: { $0.sceneId == normalizedSceneID })
            ?? sceneCatalogDefinitions.first(where: { $0.sceneId == "scene.dispatch.model" })
            ?? SceneCatalogDefinition(
                sceneId: "scene.dispatch.model",
                description: "Agent",
                defaultModel: "qwen3.5-plus",
                transport: "openai_compatible",
                configSource: "builtin"
            )

        let profiles = await listProfiles()
        let profilesByID = Dictionary(uniqueKeysWithValues: profiles.map { ($0.id, $0) })

        if let override = sanitizedModelOverride(modelOverride, profilesByID: profilesByID) {
            return override
        }

        let bindings = storedSceneModelBindings()
        if let binding = bindings[normalizedSceneID],
           let profile = profilesByID[binding.providerProfileId],
           profile.isConfigured
        {
            return CompletionRequestConfig(
                providerProfileId: profile.id,
                providerProfileName: profile.name,
                apiBase: profile.baseURL,
                apiKey: profile.apiKey,
                modelId: binding.modelId,
                protocolType: profile.protocolType
            )
        }

        let editing = await editingProfile()
        if editing.isConfigured {
            return CompletionRequestConfig(
                providerProfileId: editing.id,
                providerProfileName: editing.name,
                apiBase: editing.baseURL,
                apiKey: editing.apiKey,
                modelId: fallbackDefinition.defaultModel,
                protocolType: editing.protocolType
            )
        }

        if let fallbackProfile = profiles.first(where: { $0.isConfigured }) {
            return CompletionRequestConfig(
                providerProfileId: fallbackProfile.id,
                providerProfileName: fallbackProfile.name,
                apiBase: fallbackProfile.baseURL,
                apiKey: fallbackProfile.apiKey,
                modelId: fallbackDefinition.defaultModel,
                protocolType: fallbackProfile.protocolType
            )
        }

        throw StoreError.invalidProviderProfile
    }

    private func storedSceneModelBindings() -> [String: SceneModelBindingRecord] {
        if
            let data = defaults.data(forKey: sceneModelBindingsKey),
            let decoded = try? JSONDecoder().decode([String: SceneModelBindingRecord].self, from: data)
        {
            return decoded.reduce(into: [String: SceneModelBindingRecord]()) { partialResult, entry in
                let normalizedSceneID = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
                let normalizedProviderProfileID = canonicalProfileID(
                    entry.value.providerProfileId.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                let normalizedModelID = entry.value.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
                guard allowedSceneIDs.contains(normalizedSceneID),
                      normalizedProviderProfileID.isEmpty == false,
                      isValidSceneModelName(normalizedModelID)
                else {
                    return
                }
                partialResult[normalizedSceneID] = SceneModelBindingRecord(
                    sceneId: normalizedSceneID,
                    providerProfileId: normalizedProviderProfileID,
                    modelId: normalizedModelID
                )
            }
        }
        return [:]
    }

    private func persistSceneModelBindings(_ bindings: [String: SceneModelBindingRecord]) {
        let normalized = bindings.reduce(into: [String: SceneModelBindingRecord]()) { partialResult, entry in
            let normalizedSceneID = entry.key.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedProviderProfileID = canonicalProfileID(
                entry.value.providerProfileId.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            let normalizedModelID = entry.value.modelId.trimmingCharacters(in: .whitespacesAndNewlines)
            guard allowedSceneIDs.contains(normalizedSceneID),
                  normalizedProviderProfileID.isEmpty == false,
                  isValidSceneModelName(normalizedModelID)
            else {
                return
            }
            partialResult[normalizedSceneID] = SceneModelBindingRecord(
                sceneId: normalizedSceneID,
                providerProfileId: normalizedProviderProfileID,
                modelId: normalizedModelID
            )
        }

        let encoded = try? JSONEncoder().encode(normalized)
        defaults.set(encoded, forKey: sceneModelBindingsKey)
    }

    private func isValidSceneModelName(_ value: String) -> Bool {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return normalized.isEmpty == false && normalized.hasPrefix("scene.") == false
    }

    private func sanitizedModelOverride(
        _ raw: [String: Any]?,
        profilesByID: [String: ProviderProfile]
    ) -> CompletionRequestConfig? {
        guard let raw else {
            return nil
        }
        let providerProfileID = canonicalProfileID(
            (raw["providerProfileId"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let modelID = (raw["modelId"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard providerProfileID.isEmpty == false,
              modelID.isEmpty == false,
              isValidSceneModelName(modelID),
              let profile = profilesByID[providerProfileID],
              profile.isConfigured
        else {
            return nil
        }

        let explicitBase = normalizeBaseURL(
            (raw["apiBase"] as? String ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
        let explicitProtocol = (raw["protocolType"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let explicitAPIKey = (raw["apiKey"] as? String ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return CompletionRequestConfig(
            providerProfileId: profile.id,
            providerProfileName: profile.name,
            apiBase: explicitBase ?? profile.baseURL,
            apiKey: explicitAPIKey.isEmpty ? profile.apiKey : explicitAPIKey,
            modelId: modelID,
            protocolType: explicitProtocol.isEmpty ? profile.protocolType : explicitProtocol
        )
    }

    private func nullable(_ value: String?) -> Any {
        value ?? NSNull()
    }
}
