# Add project specific ProGuard rules here.
# You can control the set of applied configuration files using the
# proguardFiles setting in build.gradle.
#
# For more details, see
#   http://developer.android.com/guide/developing/tools/proguard.html

# If your project uses WebView with JS, uncomment the following
# and specify the fully qualified class name to the JavaScript interface
# class:
#-keepclassmembers class fqcn.of.javascript.interface.for.webview {
#   public *;
#}

# Uncomment this to preserve the line number information for
# debugging stack traces.
#-keepattributes SourceFile,LineNumberTable

# If you keep the line number information, uncomment this to
# hide the original source file name.
#-renamesourcefileattribute SourceFile

# Model market and local market_config parsing rely on Gson reflection.
# Omnibot's release app enables minification, so these DTO field names must remain stable.
-keepattributes Signature,*Annotation*
-keep class com.alibaba.mnnllm.android.modelmarket.ModelMarketData {
    <fields>;
    <methods>;
    public <init>(...);
}
-keep class com.alibaba.mnnllm.android.modelmarket.ModelMarketConfig {
    <fields>;
    <methods>;
    public <init>(...);
}
-keep class com.alibaba.mnnllm.android.modelmarket.ModelMarketItem {
    <fields>;
    <methods>;
    public <init>(...);
}

# Additional Gson-backed config/cache DTOs that are read from disk in release builds.
-keep class com.alibaba.mnnllm.android.modelsettings.JinjaContext {
    <fields>;
    <methods>;
    public <init>(...);
}
-keep class com.alibaba.mnnllm.android.modelsettings.Jinja {
    <fields>;
    <methods>;
    public <init>(...);
}
-keep class com.alibaba.mnnllm.android.modelsettings.ModelConfig {
    <fields>;
    <methods>;
    public <init>(...);
}
-keep class com.alibaba.mnnllm.android.modelist.ModelListManager$ModelItemCacheDTO {
    <fields>;
    <methods>;
    public <init>(...);
}
-keep class com.alibaba.mnnllm.android.modelist.ModelListManager$ModelListCache {
    <fields>;
    <methods>;
    public <init>(...);
}
-keep class com.alibaba.mnnllm.android.utils.FileSplitter$SplitInfo {
    <fields>;
    <methods>;
    public <init>(...);
}
-keep class com.alibaba.mnnllm.android.utils.FileSplitter$ChunkInfo {
    <fields>;
    <methods>;
    public <init>(...);
}

# Sherpa ASR JNI reads Kotlin object fields by their original names via GetFieldID/GetObjectField.
# Release minification must not rename or strip these classes, fields, or constructors.
-keep class com.k2fsa.sherpa.mnn.** {
    <fields>;
    <methods>;
    public <init>(...);
}
