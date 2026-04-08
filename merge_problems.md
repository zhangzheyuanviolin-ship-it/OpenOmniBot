# OmniInfer Integration Problems

Problems encountered while integrating `omniinfer-server` into OpenOmniBot, for feedback to the OmniInfer repository.

## 1. [HIGH] Ktor Version Mismatch (2.x vs 3.x)

**Problem:** `omniinfer-server/build.gradle.kts` uses Ktor `2.3.12`, but OpenOmniBot uses Ktor `3.1.3` (from version catalog). Ktor 2 and 3 have breaking API changes and cannot coexist in the same classpath.

**Impact:** Build fails with classpath conflicts if versions are mixed.

**Fix applied:** Upgraded Ktor dependencies in `omniinfer-server/build.gradle.kts` from `2.3.12` to `3.1.3`.

**Code change required in OmniInferService.kt:**
```kotlin
// Ktor 3: embeddedServer() returns EmbeddedServer<*, *> instead of ApplicationEngine
// Before (Ktor 2):
private var server: ApplicationEngine? = null
// After (Ktor 3):
private var server: EmbeddedServer<*, *>? = null
```

**Recommendation:** Update OmniInfer to use Ktor 3.x, or make the Ktor version configurable via a property so host projects can override it.

## 2. [MEDIUM] Java Version Mismatch (17 vs 11)

**Problem:** `omniinfer-server/build.gradle.kts` sets `JavaVersion.VERSION_17`, but OpenOmniBot uses `JavaVersion.VERSION_11`. All modules in a multi-module Android build must use the same Java target.

**Fix applied:** Changed Java 17 to Java 11 in omniinfer-server's build.gradle.kts.

**Recommendation:** Either match the host project's Java version or document the minimum requirement clearly. Consider making it configurable.

## 3. [LOW] compileSdk Mismatch (34 vs 36)

**Problem:** `omniinfer-server` uses `compileSdk = 34`, OpenOmniBot uses `compileSdk = 36`. Lower compileSdk in library modules can cause warnings and compatibility issues.

**Fix applied:** Changed to `compileSdk = 36`.

**Recommendation:** Keep compileSdk in sync with the latest stable Android SDK, or allow host projects to override it.

## 4. [HIGH] Integration Guide API Mismatch — `ensureReady(modelId)` Does Not Exist

**Problem:** The integration guide (`openomnibot-integration-guide.md`) references:
```kotlin
OmniInferServer.ensureReady(modelId)
```
This method does **not exist** in `OmniInferServer.kt`. The actual API is:
```kotlin
OmniInferServer.loadModel(
    modelPath: String,     // absolute path to model file
    backend: String,       // "llama.cpp" or "mnn"
    port: Int,
    nThreads: Int,
    nCtx: Int
)
```

**Impact:** The `LocalModelProviderBridge.Delegate.prepareForRequest()` receives a `modelId` string, but `OmniInferServer.loadModel()` requires a file path and backend name. There is no model ID to file path resolution layer.

**Recommendation:** Either:
- (A) Add an `ensureReady(modelId: String): Boolean` method to `OmniInferServer` that resolves model IDs to file paths (matching the integration guide), or
- (B) Update the integration guide to reflect the actual API and provide a model registry/manager example.

## 5. [MEDIUM] Missing Model Discovery/Management Layer

**Problem:** The existing `mnn_local` module has `MnnLocalModelsManager` which handles:
- Model discovery (scanning for available models on device)
- Model ID to file path resolution
- Model download/status tracking
- API service lifecycle (`ensureApiServiceForModel(modelId)`)

OmniInfer has no equivalent. The `loadModel()` API requires the caller to know the exact file path and backend type.

**Recommendation:** Provide an `OmniInferModelsManager` or equivalent that:
- Scans a known directory for available models (GGUF files, MNN config.json)
- Maps model IDs to file paths
- Auto-detects backend type from file format
- Provides a simple `ensureModelReady(modelId): Boolean` interface

## 6. [LOW] Hardcoded Dependency Versions

**Problem:** `omniinfer-server/build.gradle.kts` hardcodes all dependency versions instead of using Gradle version catalog. When integrated as a submodule, this can cause version conflicts with the host project.

**Affected dependencies:**
- `kotlinx-serialization-json:1.6.3` (host uses `1.6.3` — OK for now)
- `kotlinx-coroutines-android:1.7.3` (host forces `1.7.1` — resolved by Gradle's forced resolution)
- `androidx.core:core-ktx:1.12.0` (host uses `1.13.0` — resolved by Gradle)

**Recommendation:** Consider using Gradle version catalog references, or document the minimum compatible versions.

## 7. [INFO] C/C++ Compiler Warnings

**Problem:** Native compilation produces format-string warnings in MNN source files (`-Wformat`, `-Wimplicit-const-int-float-conversion`, `-Wc99-designator`). These are in MNN's upstream code, not omniinfer-jni.

**Impact:** No functional impact, but adds noise to build output.

## 8. [HIGH] Windows Path Length Exceeds 250 Characters (CMAKE_OBJECT_PATH_MAX)

**Problem:** When building the MNN backend on Windows, CMake's intermediate build directory (`.cxx`) is located deep inside the submodule path:
```
third_party/omniinfer/android/omniinfer-server/.cxx/Debug/<hash>/arm64-v8a/build-mnn/...
```
MNN's KleidiAI dependency generates extremely long object file names (e.g. `kai_matmul_clamp_f16_qsi8d32p1vlx4_qai4c32p4vlx4_1vlx4vl_sme2_mopa_asm.S.o`). The combined path reaches **302 characters**, exceeding Windows' `CMAKE_OBJECT_PATH_MAX` of 250.

**Impact:** Build fails with `ninja: build stopped: subcommand failed` on Windows.

**Fix applied:** Added `buildStagingDirectory` to redirect `.cxx` to a shorter path:
```kotlin
externalNativeBuild {
    cmake {
        path = file("src/main/cpp/omniinfer-jni/CMakeLists.txt")
        buildStagingDirectory = file("C:/.cxx/oi")
    }
}
```

**Recommendation:** Either:
- (A) Add `buildStagingDirectory` configuration to `omniinfer-server/build.gradle.kts` with a short default path, or
- (B) Document this Windows-specific requirement in the integration guide, or
- (C) Consider shortening the CMake output directory structure to avoid hitting path limits

## 9. [INFO] `libc++_shared.so` Duplication

**Problem:** Both `mnn_local` and `omniinfer-server` bundle `libc++_shared.so`. This is handled by the host project's `pickFirsts += setOf("**/libc++_shared.so")` in packaging config.

**Impact:** None with the current workaround. The first encountered `.so` is used.

**Recommendation:** Document this requirement in the integration guide.

## 10. [HIGH] GGUF Download URL Filename Mismatch

**Problem:** The integration guide implies download filenames follow `{modelName}-{Quant}.gguf` pattern (e.g. `Gemma-4-E2B-Q4_K_M.gguf`), but the actual filenames on HuggingFace/ModelScope are derived from the **repo name**, not the `modelName` field in `model_market.json`.

**Example:**
- `model_market.json`: `modelName = "Gemma-4-E2B"`, `sources.HuggingFace = "unsloth/gemma-4-E2B-it-GGUF"`
- Expected by our code: `Gemma-4-E2B-Q4_K_M.gguf` → **404 Not Found**
- Actual file on HuggingFace: `gemma-4-E2B-it-Q4_K_M.gguf` (derived from repo name minus `-GGUF` suffix)

**Impact:** All models where `modelName` differs from the repo base name fail to download with HTTP 404.

**Fix applied:** Changed download URL construction to derive the remote filename from the repo name:
```kotlin
val repoBaseName = repo.substringAfterLast("/").removeSuffix("-GGUF").removeSuffix("-gguf")
val remoteFileName = "$repoBaseName-$quantName.gguf"
```

**Recommendation:** Either:
- (A) Add an explicit `filename` field per quant in `model_market.json` to avoid ambiguity, or
- (B) Document the filename derivation rule: `{repo_name_without_GGUF_suffix}-{Quant}.gguf`

## 11. [HIGH] OmniInferService Crashes on Array-format Content (HTTP 500)

**Problem:** `OmniInferService.kt` line 75 assumes message `content` is always a JSON string:
```kotlin
val content = msg.jsonObject["content"]?.jsonPrimitive?.contentOrNull ?: continue
```

But OpenAI's API supports **array-format content** for multimodal messages:
```json
"content": [{"type": "text", "text": "Hello"}]
```

When the host app's agent system sends requests with array-format content, `jsonPrimitive` throws `IllegalArgumentException` → Ktor returns HTTP 500 → agent reports "unknown stream failure".

**Impact:** Agent chat is completely broken — every request fails with 500.

**Fix applied:** Added `extractTextContent()` helper that handles both string and array formats:
```kotlin
private fun extractTextContent(element: JsonElement?): String? {
    if (element == null || element is JsonNull) return null
    if (element is JsonPrimitive) return element.contentOrNull
    if (element is JsonArray) {
        // Concatenate all "text" type parts
        ...
    }
    return null
}
```

**Recommendation:** The `/v1/chat/completions` endpoint should fully support the OpenAI message content format, including:
- String content: `"content": "hello"`
- Array content: `"content": [{"type":"text","text":"hello"}, {"type":"image_url",...}]`
- Also add a top-level try-catch to avoid unhandled 500 errors

## 12. [MEDIUM] OmniInferService Killed by Android System (App Idle)

**Problem:** `OmniInferService` extends `Service` (not a foreground service). When the app goes to the background, Android stops it due to app idle:
```
W ActivityManager: Stopping service due to app idle: u0a335 -50s390ms cn.com.omnimind.bot.debug/com.omniinfer.server.OmniInferService
```

**Impact:** The local inference server stops working after ~1 minute in background. Subsequent requests get "Connection refused".

**Recommendation:** Convert `OmniInferService` to a **Foreground Service** with a persistent notification, similar to how other long-running Android services (music players, VPN) maintain background operation.

## 13. [CRITICAL] `common_chat_format_single` Incompatible with Qwen3.5 Jinja Template — Native Crash

**File:** `backend_llama_cpp.h` — `generate()` and `chat_add_and_format()`

**Problem:** The original `generate()` formats messages **incrementally** using `common_chat_format_single`: first formats `[system]` alone, then `[system, user]`. But Qwen3.5's Jinja template (lines 67-80) has an **unconditional validation** that iterates ALL messages looking for a non-tool-response user message:

```jinja
{%- set ns = namespace(multi_step_tool=true, ...) %}
{%- for message in messages[::-1] %}
    {%- if ns.multi_step_tool and message.role == "user" %}
        {%- if not(content.startswith('<tool_response>') ...) %}
            {%- set ns.multi_step_tool = false %}  {# found valid user query #}
{%- if ns.multi_step_tool %}
    {{- raise_exception('No user query found in messages.') }}
```

When `common_chat_format_single` formats just `[system]`, the template sees no user message → throws Jinja exception → **uncaught C++ exception** → `SIGABRT` → **app crash**.

**Impact:** Every chat request with a system prompt crashes the entire app.

**Fix applied:** Replaced incremental `chat_add_and_format` with `common_chat_templates_apply`, which passes **all messages at once** to the template:

```cpp
common_chat_templates_inputs inputs;
inputs.use_jinja = true;
inputs.add_generation_prompt = true;
inputs.messages = { {system_msg}, {user_msg} };  // ALL messages at once
auto params = common_chat_templates_apply(chat_templates_.get(), inputs);
full_prompt = params.prompt;
```

**Recommendation:** 
- (A) `generate()` should use `common_chat_templates_apply` instead of `common_chat_format_single` for initial prompt formatting — the incremental API is fundamentally incompatible with templates that validate full conversation structure
- (B) Alternatively, wrap `common_chat_format_single` calls in try-catch to prevent native crashes

## 14. [HIGH] OmniInferService Stateless HTTP Design vs Stateful Backend Session

**File:** `OmniInferService.kt` — `/v1/chat/completions` route, `backend_llama_cpp.h` — `generate()`

**Problem:** OmniInferService serves an OpenAI-compatible HTTP API where each request contains the **full conversation** (messages array). But the original `backend_llama_cpp.h` `generate()` was designed as a **stateful session** — it accumulates `chat_msgs_` across calls and uses incremental formatting.

This mismatch caused:
1. Second requests would skip system prompt (because `chat_msgs_` was not empty)
2. Template formatting used stale history that didn't match the actual request
3. Context window filled up across requests without being reset

**Fix applied:** Each HTTP request now calls `reset()` before `generate()`, and `generate()` clears all state (`chat_msgs_`, `cur_pos_`, KV cache) at the start. The backend is effectively stateless per-request.

**Recommendation:** Consider adding a `generateFromMessages(messages: List<Pair<role, content>>)` API that:
- Accepts a full messages array (matching OpenAI format)
- Formats all messages at once with the template
- Handles the full lifecycle internally (reset → format → decode → sample)
- This would be the natural API for an HTTP server backend

---

## Summary

| # | Issue | Severity | Status |
|---|-------|----------|--------|
| 1 | Ktor 2.x vs 3.x version mismatch | HIGH | Fixed locally |
| 2 | Java 17 vs 11 mismatch | MEDIUM | Fixed locally |
| 3 | compileSdk 34 vs 36 mismatch | LOW | Fixed locally |
| 4 | `ensureReady(modelId)` API does not exist | HIGH | Needs OmniInfer update |
| 5 | Missing model discovery/management layer | MEDIUM | Needs OmniInfer update |
| 6 | Hardcoded dependency versions | LOW | Recommendation |
| 7 | C/C++ compiler warnings in MNN | INFO | Upstream issue |
| 8 | Windows path length exceeds 250 chars | HIGH | Fixed locally |
| 9 | `libc++_shared.so` duplication | INFO | Documented |
| 10 | GGUF download URL filename mismatch | HIGH | Fixed locally |
| 11 | Array-format content causes HTTP 500 | HIGH | Fixed locally |
| 12 | Service killed by Android app idle | MEDIUM | Needs OmniInfer update |
| 13 | `common_chat_format_single` crashes with Qwen3.5 template | CRITICAL | Fixed locally |
| 14 | Stateless HTTP vs stateful session mismatch | HIGH | Fixed locally |

**Build result:** `assembleDevelopDebug` passes successfully after fixes 1-3, 8, 10-11, 13-15.
