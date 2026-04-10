import org.gradle.api.GradleException

pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    // PREFER_PROJECT 避免 Flutter 等插件在 build.gradle 里添加仓库时刷屏警告
    repositoriesMode.set(RepositoriesMode.PREFER_PROJECT)
    val storageUrl: String = System.getenv("FLUTTER_STORAGE_BASE_URL") ?: "https://storage.googleapis.com"

    repositories {
        maven("https://maven.google.com/")
        google()
        mavenCentral()
        maven("https://jitpack.io")
        maven("$storageUrl/download.flutter.io")
        maven("https://repo1.maven.org/maven2/")

    }
}

rootProject.name = "OmnibotApp"
include(":app")
include(":assists")
val filePath = settingsDir.toString() + "/ui/.android/include_flutter.groovy"
apply(from = File(filePath))

include(":baselib")
include(":accessibility")
include(":omniintelligence")

fun requireOmniInferModule(moduleName: String, moduleDir: File, markerFileName: String) {
    if (File(moduleDir, markerFileName).exists()) {
        return
    }

    throw GradleException(
        """
        Missing required OmniInfer sources for $moduleName at: ${moduleDir.relativeTo(settingsDir)}
        
        Initialize the required submodules with:
          git submodule update --init third_party/omniinfer
          git -C third_party/omniinfer submodule update --init framework/mnn
        """.trimIndent()
    )
}

val omniInferServerDir = File(settingsDir, "third_party/omniinfer/android/omniinfer-server")
val modelDownloaderDir =
    File(settingsDir, "third_party/omniinfer/framework/mnn/apps/frameworks/model_downloader/android")

requireOmniInferModule(":omniinfer-server", omniInferServerDir, "build.gradle.kts")
requireOmniInferModule(":model_downloader", modelDownloaderDir, "build.gradle")

include(":omniinfer-server")
project(":omniinfer-server").projectDir = omniInferServerDir
include(":model_downloader")
project(":model_downloader").projectDir = modelDownloaderDir
include(":uikit")
include(":core:main")
project(":core:main").projectDir = File(settingsDir, "ReTerminal/core/main")
include(":core:components")
project(":core:components").projectDir = File(settingsDir, "ReTerminal/core/components")
include(":core:resources")
project(":core:resources").projectDir = File(settingsDir, "ReTerminal/core/resources")
include(":core:terminal-emulator")
project(":core:terminal-emulator").projectDir = File(settingsDir, "ReTerminal/core/terminal-emulator")
include(":core:terminal-view")
project(":core:terminal-view").projectDir = File(settingsDir, "ReTerminal/core/terminal-view")


