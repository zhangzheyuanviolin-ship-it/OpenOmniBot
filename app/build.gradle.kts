plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.android)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

fun prop(name: String): String = (project.findProperty(name) as String?)?.trim() ?: ""

android {
    namespace = "cn.com.omnimind.bot"
    compileSdk = 36

    defaultConfig {
        applicationId = "cn.com.omnimind.bot"
        minSdk = 29
        targetSdk = 34
        versionCode = 1
        versionName = "0.0.2"

        ndk {
            abiFilters.addAll(listOf("armeabi-v7a", "arm64-v8a"))
        }

    }
    // 添加 flavor 维度
    flavorDimensions += "version"

    productFlavors {
        create("develop") {
            dimension = "version"
            buildConfigField("String", "BASE_URL", "\"${prop("OMNIBOT_BASE_URL")}\"")
            resValue("bool", "is_accessibility_tool", "true")
        }

        create("production") {
            dimension = "version"
            buildConfigField("String", "BASE_URL", "\"${prop("OMNIBOT_BASE_URL")}\"")
            resValue("bool", "is_accessibility_tool", "true")
        }
    }
    signingConfigs {
        create("release") {
            // 引用全局gradle.properties中的变量
            storeFile = project.findProperty("OMNI_RELEASE_STORE_FILE")?.let { file(it) }
            storePassword = project.findProperty("OMNI_RELEASE_STORE_PWD") as String?
            keyAlias = project.findProperty("OMNI_RELEASE_KEY_ALIAS") as String?
            keyPassword = project.findProperty("OMNI_RELEASE_KEY_PWD") as String?

            // V2/V3签名配置（minSdk=30）
            enableV1Signing = false
            enableV2Signing = true
            enableV3Signing = true
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = "11"
    }
    buildFeatures {
        compose = true
        buildConfig = true
    }

    sourceSets {
        getByName("main") {
            assets.srcDirs("src/main/assets", "../skills")
        }
    }

    lint {
        // 使用项目根目录的 lint.xml 配置
        lintConfig = file("../lint.xml")
        // 将错误视为警告继续构建
        abortOnError = false
    }
}
dependencies {
    implementation(project(":flutter"))
    implementation(project(":uikit"))
    implementation(project(":baselib"))
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar","*.jar"))))
    implementation(project(":assists"))
//    implementation(project(":lib"))

    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.livedata.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.ui)
    implementation(libs.androidx.ui.graphics)
    implementation(libs.androidx.ui.tooling.preview)
    implementation(libs.androidx.material3)
    implementation(libs.kotlin.stdlib)
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.androidx.appcompat)
    implementation(libs.androidx.lifecycle.service)
    implementation(libs.work.runtime)
    implementation(libs.androidx.security.crypto)
    implementation(libs.androidx.core.splashscreen)
    implementation(libs.ktor.server.core)
    implementation(libs.ktor.server.cio)
    implementation(libs.ktor.server.auth)
    implementation(libs.ktor.server.content.negotiation)
    implementation(libs.ktor.serialization.gson)
    implementation(libs.ktor.server.call.logging)
    testImplementation(libs.junit)
    debugImplementation(libs.androidx.ui.tooling)
    debugImplementation(libs.androidx.ui.test.manifest )
}
