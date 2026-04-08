# Integrating OmniInfer Local Server into OpenOmniBot

This guide explains how to add OmniInfer as a local inference provider in OpenOmniBot, replacing or coexisting with the existing `mnn_local` module.

## Overview

OmniInfer provides a multi-backend local inference server as an Android Library module (`android/omniinfer-server/`). It embeds an OpenAI-compatible HTTP server backed by llama.cpp and MNN engines — all compiled into a single `.so` with zero external dependencies.

**What OpenOmniBot gets:**
- OpenAI-compatible local server (`/v1/chat/completions` with SSE streaming)
- Multi-backend support (llama.cpp GGUF + MNN models) in one library
- Drop-in replacement for `mnn_local` via `LocalModelProviderBridge`

**What OpenOmniBot does NOT need to do:**
- Write or maintain any C++ / JNI code
- Compile llama.cpp or MNN separately (Gradle handles it automatically)
- Modify `baselib`, `assists`, or `HttpController`

## Architecture

```
OpenOmniBot/
  ├── third_party/
  │   └── omniinfer/                     ← git submodule (OmniInfer repo)
  │       ├── framework/
  │       │   ├── llama.cpp/             ← inference engine (submodule)
  │       │   └── mnn/                   ← inference engine (submodule)
  │       └── android/
  │           └── omniinfer-server/      ← Android Library module
  ├── app/
  │   └── build.gradle.kts              ← depends on :omniinfer-server
  └── baselib/
      └── LocalModelProviderBridge.kt   ← unchanged, OmniInfer implements its Delegate
```

Data flow (identical to current `mnn_local` architecture):

```
Flutter UI / HttpController
    ↓ HTTP POST
OmniInfer Local Server (Ktor, 127.0.0.1:PORT)
    ↓ /v1/chat/completions
OmniInfer JNI Bridge (libomniinfer-jni.so)
    ↓ InferenceBackend interface
    ├── LlamaCppBackend  (GGUF models)
    └── MnnBackend       (MNN models)
```

## How the Build Works

The `omniinfer-server` module uses Gradle's `externalNativeBuild` with CMake. When you run `gradlew build`, the NDK toolchain automatically:

1. Compiles **llama.cpp** from source (`framework/llama.cpp/`) with ARM optimizations (FP16, dotprod, i8mm)
2. Compiles **MNN** from source (`framework/mnn/`) with LLM and transformer fuse support
3. Links both engines into a single `libomniinfer-jni.so`

**You do NOT need to run any separate build scripts.** Everything is handled by `gradlew`.

First build takes ~3-5 minutes (compiling the engines from source). Subsequent builds are incremental and fast.

> **Important:** The `framework/llama.cpp` and `framework/mnn` directories are git submodules inside OmniInfer. You must initialize them before building (see Step 1 below).

## Step-by-Step Integration

### 1. Add OmniInfer as a git submodule

```bash
cd OpenOmniBot
git submodule add git@github.com:omnimind-ai/OmniInfer.git third_party/omniinfer

# Initialize the nested submodules (llama.cpp and MNN engines)
cd third_party/omniinfer
git submodule update --init framework/llama.cpp framework/mnn
cd ../..
```

### 2. Include the module in settings.gradle.kts

Add to `settings.gradle.kts`:

```kotlin
include(":omniinfer-server")
project(":omniinfer-server").projectDir =
    file("third_party/omniinfer/android/omniinfer-server")
```

### 3. Replace mnn_local dependency

In `app/build.gradle.kts`, replace:

```kotlin
// Remove:
implementation(project(":mnn_local"))

// Add:
implementation(project(":omniinfer-server"))
```

### 4. Initialize in App.kt

Replace the `MnnLocalInitializer` call:

```kotlin
// Remove:
MnnLocalInitializer.initialize(this)

// Add:
OmniInferServer.init(this)
```

The `LocalModelProviderBridge.Delegate` registration stays the same pattern:

```kotlin
LocalModelProviderBridge.setDelegate(object : LocalModelProviderBridge.Delegate {
    override suspend fun prepareForRequest(
        profileId: String?,
        apiBase: String?,
        modelId: String
    ): Boolean {
        return OmniInferServer.ensureReady(modelId)
    }
})
```

### 5. Build

```bash
./gradlew assembleDevelopDebug
```

First build compiles llama.cpp and MNN from source (~3-5 minutes). Subsequent builds are incremental.

### 6. That's it

No changes needed in:
- `baselib/` (LocalModelProviderBridge, MnnLocalProviderStateStore)
- `assists/` (HttpController)
- `ui/` (Flutter)
- `omniintelligence/`

The existing `HttpController` will automatically route local model requests to OmniInfer's server via the same `127.0.0.1:PORT` mechanism.

## Updating OmniInfer

When the OmniInfer maintainer pushes updates (new backend features, performance fixes, model support):

```bash
cd third_party/omniinfer
git pull origin main
git submodule update --init
cd ../..
git add third_party/omniinfer
git commit -m "chore: update omniinfer submodule"
```

Rebuild the project. No code changes needed in OpenOmniBot unless the `OmniInferServer` public API changes (which should be rare and backward-compatible).

## Coexisting with mnn_local

You can keep both `mnn_local` and `omniinfer-server` in the project during migration:

```kotlin
// settings.gradle.kts
include(":mnn_local")
include(":omniinfer-server")

// app/build.gradle.kts — choose one:
implementation(project(":mnn_local"))        // existing MNN-only
// implementation(project(":omniinfer-server"))  // new multi-backend
```

Switch by commenting/uncommenting the dependency line and updating the initializer in `App.kt`.

## Backend Selection

Users (or the app) select the backend via the `model_path` and `backend` fields when loading a model:

```kotlin
// llama.cpp backend — pass a .gguf file
OmniInferServer.loadModel(
    modelPath = "/data/local/tmp/model.gguf",
    backend = "llama.cpp"
)

// MNN backend — pass a config.json
OmniInferServer.loadModel(
    modelPath = "/data/local/tmp/Qwen3.5-0.8B-MNN/config.json",
    backend = "mnn"
)
```

The server auto-selects the backend based on model format if `backend` is not specified.

## Disabling a Backend

To reduce APK size, you can disable one backend. In your `app/build.gradle.kts`, override the CMake arguments:

```kotlin
android {
    defaultConfig {
        externalNativeBuild {
            cmake {
                // Disable MNN (llama.cpp only):
                arguments += "-DOMNIINFER_BACKEND_MNN=OFF"

                // Or disable llama.cpp (MNN only):
                // arguments += "-DOMNIINFER_BACKEND_LLAMA_CPP=OFF"
            }
        }
    }
}
```

When a backend is disabled, its engine is not compiled, and the corresponding `framework/` submodule does not need to be initialized.

## API Compatibility

OmniInfer's local server implements the same OpenAI-compatible endpoints that `mnn_local` provides:

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/v1/chat/completions` | POST | Chat completion (streaming SSE supported) |
| `/v1/models` | GET | List loaded models |
| `/health` | GET | Server health check |

Request and response formats follow the OpenAI API specification. `HttpController` in `assists/` works without modification.

## Troubleshooting

**CMake error: `llama.cpp not found` or `MNN not found`**
You forgot to initialize the nested submodules. Run:
```bash
cd third_party/omniinfer
git submodule update --init framework/llama.cpp framework/mnn
```

**Build error: `NDK not found`**
Install NDK via Android Studio: SDK Manager → SDK Tools → NDK (Side by side). The module requires NDK r25+ and CMake 3.22.1+.

**Server returns `{"error":"no model loaded"}`**
Call `OmniInferServer.loadModel(...)` before sending requests to the server.

## FAQ

**Q: Do I need to install NDK or CMake separately?**
A: No. Android Studio's bundled NDK and CMake are sufficient. The `omniinfer-server` module's `build.gradle.kts` specifies the required versions.

**Q: How large is the APK size increase?**
A: The `libomniinfer-jni.so` (arm64-v8a) adds approximately 20-40 MB to the APK, depending on which backends are enabled.

**Q: Does this affect cloud model providers?**
A: No. OmniInfer only handles local inference. Cloud providers (OpenAI, Anthropic, etc.) continue to work through `HttpController` as before. The switch between local and cloud is determined by the `apiBase` URL, which is unchanged.

**Q: Can I use a prebuilt `.so` instead of compiling from source?**
A: Not yet. Currently the engines are compiled from source during `gradlew build`. Prebuilt binaries may be provided in a future release.
