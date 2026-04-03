#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
MNN_ROOT="$REPO_ROOT/third_party/mnn_android"
BUILD_DIR="$MNN_ROOT/project/android/build_64"
LIB_DIR="$BUILD_DIR/lib"
LOCK_DIR="$BUILD_DIR/.prepare-native-lock"
REQUIRED_LIBS=(
  "$LIB_DIR/libMNN.so"
)
ROOT_OUTPUT_LIBS=(
  "$BUILD_DIR/libMNN.so"
)
OPTIONAL_ROOT_OUTPUT_LIBS=(
  "$BUILD_DIR/libMNN_Express.so"
  "$BUILD_DIR/libllm.so"
)
REQUIRED_SCHEMA_HEADERS=(
  "$MNN_ROOT/schema/current/MNN_generated.h"
  "$MNN_ROOT/schema/current/Tensor_generated.h"
)

mkdir -p "$BUILD_DIR"

all_present() {
  for lib in "${REQUIRED_LIBS[@]}"; do
    if [[ ! -f "$lib" ]]; then
      return 1
    fi
  done
  return 0
}

for header in "${REQUIRED_SCHEMA_HEADERS[@]}"; do
  if [[ ! -f "$header" ]]; then
    pushd "$MNN_ROOT/schema" >/dev/null
    bash ./generate.sh -lazy
    popd >/dev/null
    break
  fi
done

if all_present; then
  exit 0
fi

while ! mkdir "$LOCK_DIR" 2>/dev/null; do
  if all_present; then
    exit 0
  fi
  sleep 1
done

cleanup_lock() {
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

trap cleanup_lock EXIT

if all_present; then
  exit 0
fi

SDK_DIR=""
if [[ -f "$REPO_ROOT/local.properties" ]]; then
  SDK_DIR="$(grep '^sdk.dir=' "$REPO_ROOT/local.properties" | sed 's#^sdk.dir=##' | tail -n 1)"
fi

CMAKE_BIN_DIR=""
if [[ -n "$SDK_DIR" && -x "$SDK_DIR/cmake/3.22.1/bin/cmake" ]]; then
  CMAKE_BIN_DIR="$SDK_DIR/cmake/3.22.1/bin"
fi
if [[ -n "$CMAKE_BIN_DIR" ]]; then
  export PATH="$CMAKE_BIN_DIR:$PATH"
fi

if [[ -n "${ANDROID_NDK_HOME:-}" ]]; then
  NDK_DIR="$ANDROID_NDK_HOME"
elif [[ -n "${ANDROID_NDK:-}" ]]; then
  NDK_DIR="$ANDROID_NDK"
elif [[ -n "$SDK_DIR" && -d "$SDK_DIR/ndk/28.2.13676358" ]]; then
  NDK_DIR="$SDK_DIR/ndk/28.2.13676358"
elif [[ -n "$SDK_DIR" && -d "$SDK_DIR/ndk/27.0.12077973" ]]; then
  NDK_DIR="$SDK_DIR/ndk/27.0.12077973"
else
  NDK_DIR="$(find "${SDK_DIR:-/nonexistent}/ndk" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -V | tail -n 1 || true)"
fi

if [[ -z "${NDK_DIR:-}" || ! -d "$NDK_DIR" ]]; then
  echo "Unable to locate Android NDK. Set ANDROID_NDK_HOME or install an NDK under sdk.dir." >&2
  exit 1
fi

pushd "$BUILD_DIR" >/dev/null
ANDROID_NDK="$NDK_DIR" bash ../build_64.sh "\
-DMNN_LOW_MEMORY=true \
-DMNN_CPU_WEIGHT_DEQUANT_GEMM=true \
-DMNN_BUILD_LLM=true \
-DMNN_SUPPORT_TRANSFORMER_FUSE=true \
-DMNN_ARM82=true \
-DMNN_USE_LOGCAT=true \
-DMNN_OPENCL=true \
-DLLM_SUPPORT_VISION=true \
-DMNN_BUILD_OPENCV=true \
-DMNN_IMGCODECS=true \
-DLLM_SUPPORT_AUDIO=true \
-DMNN_BUILD_AUDIO=true \
-DMNN_BUILD_DIFFUSION=ON \
-DMNN_SEP_BUILD=OFF \
-DBUILD_PLUGIN=ON \
-DMNN_QNN=OFF \
-DCMAKE_SHARED_LINKER_FLAGS=-Wl,-z,max-page-size=16384 \
-DCMAKE_INSTALL_PREFIX=."
make install
popd >/dev/null

mkdir -p "$LIB_DIR"
for lib in "${ROOT_OUTPUT_LIBS[@]}" "${OPTIONAL_ROOT_OUTPUT_LIBS[@]}"; do
  if [[ -f "$lib" ]]; then
    cp -f "$lib" "$LIB_DIR/$(basename "$lib")"
  fi
done
