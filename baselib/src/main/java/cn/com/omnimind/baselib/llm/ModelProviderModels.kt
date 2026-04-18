package cn.com.omnimind.baselib.llm

data class ModelProviderConfig(
    val id: String = "",
    val name: String = "",
    val baseUrl: String = "",
    val apiKey: String = "",
    val source: String = "none",
    val providerType: String = "custom",
    val readOnly: Boolean = false,
    val ready: Boolean = true,
    val statusText: String? = null
) {
    fun isConfigured(): Boolean = baseUrl.isNotBlank()
}

data class ModelProviderProfile(
    val id: String,
    val name: String,
    val baseUrl: String = "",
    val apiKey: String = "",
    val sourceType: String = "custom",
    val readOnly: Boolean = false,
    val ready: Boolean = true,
    val statusText: String? = null,
    val protocolType: String = "openai_compatible"
) {
    fun isConfigured(): Boolean = baseUrl.isNotBlank()
}

data class ProviderModelOption(
    val id: String,
    val displayName: String = id,
    val ownedBy: String? = null
)

data class SceneCatalogItem(
    val sceneId: String,
    val description: String? = null,
    val defaultModel: String,
    val effectiveModel: String,
    val effectiveProviderProfileId: String? = null,
    val effectiveProviderProfileName: String? = null,
    val boundProviderProfileId: String? = null,
    val boundProviderProfileName: String? = null,
    val transport: String,
    val configSource: String,
    val overrideApplied: Boolean,
    val overrideModel: String? = null,
    val providerConfigured: Boolean = false,
    val bindingExists: Boolean = false,
    val bindingProfileMissing: Boolean = false
)

data class SceneModelOverrideEntry(
    val sceneId: String,
    val model: String
)

data class SceneModelBindingEntry(
    val sceneId: String,
    val providerProfileId: String,
    val modelId: String
)

data class SceneVoiceConfig(
    val autoPlay: Boolean = false,
    val voiceId: String = "default_zh",
    val stylePreset: String = "默认",
    val customStyle: String = ""
)
