# Release builds of the host app minify this vendored module.
# The downloader relies on Retrofit annotations and Gson reflection for API responses
# and persisted metadata, so these contracts must remain stable.
-keepattributes Signature,*Annotation*,InnerClasses,EnclosingMethod

-keep interface com.alibaba.mls.api.HfApiService { *; }
-keep interface com.alibaba.mls.api.ms.MsApiService { *; }
-keep interface com.alibaba.mls.api.ml.MlApiClient$MlApiService { *; }

-keep class com.alibaba.mls.api.HfTreeItem { <fields>; <methods>; public <init>(...); }
-keep class com.alibaba.mls.api.HfTreeItem$LfsInfo { <fields>; <methods>; public <init>(...); }
-keep class com.alibaba.mls.api.HfFileMetadata { <fields>; <methods>; public <init>(...); }
-keep class com.alibaba.mls.api.HfRepoInfo { <fields>; <methods>; public <init>(...); }
-keep class com.alibaba.mls.api.HfRepoInfo$SiblingItem { <fields>; <methods>; public <init>(...); }
-keep class com.alibaba.mls.api.ms.MsRepoInfo { <fields>; <methods>; public <init>(...); }
-keep class com.alibaba.mls.api.ms.MsRepoInfo$* { <fields>; <methods>; public <init>(...); }
-keep class com.alibaba.mls.api.ml.MlRepoInfo { <fields>; <methods>; public <init>(...); }
-keep class com.alibaba.mls.api.ml.MlRepoData { <fields>; <methods>; public <init>(...); }
-keep class com.alibaba.mls.api.ml.FileInfo { <fields>; <methods>; public <init>(...); }
-keep class com.alibaba.mls.api.ml.CommitInfo { <fields>; <methods>; public <init>(...); }
-keep class com.alibaba.mls.api.ml.FileScanInfo { <fields>; <methods>; public <init>(...); }
-keep class com.alibaba.mls.api.ml.LastCommitInfo { <fields>; <methods>; public <init>(...); }
-keep class com.alibaba.mls.api.ml.AuthorInfo { <fields>; <methods>; public <init>(...); }
