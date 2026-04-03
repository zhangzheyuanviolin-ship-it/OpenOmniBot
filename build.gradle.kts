import org.gradle.api.tasks.Exec

// Top-level build file where you can add configuration options common to all sub-projects/modules.
plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.android.library) apply false
}

val forcedCoroutinesVersion = libs.versions.kotlinxCoroutines.get()

val prepareMnnAndroidNativeLibs by tasks.registering(Exec::class) {
    group = "build setup"
    description = "Prepare shared MNN Android native libraries for modules that link libMNN.so."
    workingDir = rootProject.projectDir
    commandLine("bash", "${rootProject.projectDir}/scripts/prepare_mnn_android_native.sh")
    inputs.file(rootProject.file("scripts/prepare_mnn_android_native.sh"))
    outputs.file(rootProject.file("third_party/mnn_android/project/android/build_64/lib/libMNN.so"))
}

subprojects {
    repositories {
        google()
        mavenCentral()
        maven(url = "https://jitpack.io")
        val storageUrl: String =
            System.getenv("FLUTTER_STORAGE_BASE_URL") ?: "https://storage.googleapis.com"
        maven(url = "$storageUrl/download.flutter.io")
    }

    configurations.configureEach {
        resolutionStrategy.force(
            "org.jetbrains.kotlinx:kotlinx-coroutines-core:$forcedCoroutinesVersion",
            "org.jetbrains.kotlinx:kotlinx-coroutines-android:$forcedCoroutinesVersion",
        )
    }
}
