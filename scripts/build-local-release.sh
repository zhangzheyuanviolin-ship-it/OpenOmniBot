#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

NDK_VERSION="${NDK_VERSION:-28.2.13676358}"
FLUTTER_DIR="$ROOT_DIR/ui"
APK_PATH="$ROOT_DIR/app/build/outputs/apk/production/release/app-production-release.apk"
AAB_PATH="$ROOT_DIR/app/build/outputs/bundle/productionRelease/app-production-release.aab"

INSTALL_APK=0
SKIP_SUBMODULES=0
SKIP_FLUTTER=0
TASK="assembleProductionRelease"

usage() {
  cat <<'EOF'
Usage:
  bash scripts/build-local-release.sh [options]

Options:
  --install           Build the release APK and install it with adb.
  --bundle            Build an AAB instead of an APK.
  --skip-submodules   Skip OmniInfer submodule initialization.
  --skip-flutter      Skip `flutter pub get` in ui/.
  --help              Show this help text.

Required environment variables:
  OMNI_RELEASE_STORE_PWD
  OMNI_RELEASE_KEY_ALIAS

Optional environment variables:
  OMNI_RELEASE_STORE_FILE   Defaults to ./release.jks when present.
  OMNI_RELEASE_KEY_PWD      Defaults to OMNI_RELEASE_STORE_PWD.
  ANDROID_SDK_ROOT          Auto-detected from local.properties when absent.
  ANDROID_NDK_HOME          Auto-detected as $ANDROID_SDK_ROOT/ndk/28.2.13676358 when absent.
  GRADLE_OPTS              Defaults to the same memory settings used in CI.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install)
      INSTALL_APK=1
      ;;
    --bundle)
      TASK="bundleProductionRelease"
      ;;
    --skip-submodules)
      SKIP_SUBMODULES=1
      ;;
    --skip-flutter)
      SKIP_FLUTTER=1
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
  shift
done

if [[ -z "${OMNI_RELEASE_STORE_FILE:-}" && -f "$ROOT_DIR/release.jks" ]]; then
  export OMNI_RELEASE_STORE_FILE="$ROOT_DIR/release.jks"
fi

if [[ -z "${OMNI_RELEASE_STORE_PWD:-}" ]]; then
  echo "Missing OMNI_RELEASE_STORE_PWD" >&2
  exit 1
fi

if [[ -z "${OMNI_RELEASE_KEY_ALIAS:-}" ]]; then
  echo "Missing OMNI_RELEASE_KEY_ALIAS" >&2
  exit 1
fi

if [[ -z "${OMNI_RELEASE_STORE_FILE:-}" ]]; then
  echo "Missing OMNI_RELEASE_STORE_FILE and default ./release.jks was not found" >&2
  exit 1
fi

if [[ ! -f "$OMNI_RELEASE_STORE_FILE" ]]; then
  echo "Keystore not found: $OMNI_RELEASE_STORE_FILE" >&2
  exit 1
fi

if [[ -z "${OMNI_RELEASE_KEY_PWD:-}" ]]; then
  export OMNI_RELEASE_KEY_PWD="$OMNI_RELEASE_STORE_PWD"
fi

if [[ -z "${ANDROID_SDK_ROOT:-}" && -f "$ROOT_DIR/local.properties" ]]; then
  sdk_dir="$(sed -n 's/^sdk\.dir=//p' "$ROOT_DIR/local.properties" | tail -n 1)"
  if [[ -n "$sdk_dir" ]]; then
    sdk_dir="${sdk_dir//\\:/:}"
    sdk_dir="${sdk_dir//\\\\/\\}"
    export ANDROID_SDK_ROOT="$sdk_dir"
  fi
fi

if [[ -z "${ANDROID_SDK_ROOT:-}" ]]; then
  echo "Missing ANDROID_SDK_ROOT and could not detect it from local.properties" >&2
  exit 1
fi

if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  export ANDROID_NDK_HOME="$ANDROID_SDK_ROOT/ndk/$NDK_VERSION"
fi

if [[ -z "${ANDROID_NDK_ROOT:-}" ]]; then
  export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
fi

if [[ ! -d "$ANDROID_NDK_HOME" ]]; then
  cat >&2 <<EOF
Android NDK not found: $ANDROID_NDK_HOME
Install the CI-matching NDK with:
  sdkmanager "ndk;$NDK_VERSION"
EOF
  exit 1
fi

if [[ -z "${GRADLE_OPTS:-}" ]]; then
  export GRADLE_OPTS="-Dorg.gradle.jvmargs=-Xmx5g -XX:MaxMetaspaceSize=1g -Dfile.encoding=UTF-8 --enable-native-access=ALL-UNNAMED"
fi

cpu_count="$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 4)"
if [[ "$cpu_count" -ge 4 ]]; then
  max_workers=4
elif [[ "$cpu_count" -ge 2 ]]; then
  max_workers="$cpu_count"
else
  max_workers=2
fi

echo "Repo root: $ROOT_DIR"
echo "Gradle task: $TASK"
echo "Keystore: $OMNI_RELEASE_STORE_FILE"
echo "Android SDK: $ANDROID_SDK_ROOT"
echo "Android NDK: $ANDROID_NDK_HOME"
echo "Gradle max workers: $max_workers"

chmod +x ./gradlew

if [[ "$SKIP_SUBMODULES" -eq 0 ]]; then
  echo "Initializing OmniInfer submodules..."
  git submodule update --init third_party/omniinfer
  git -C third_party/omniinfer submodule update --init framework/mnn framework/llama.cpp
fi

if [[ "$SKIP_FLUTTER" -eq 0 ]]; then
  echo "Installing Flutter dependencies..."
  (cd "$FLUTTER_DIR" && flutter pub get --enforce-lockfile)
fi

echo "Building release artifact..."
./gradlew \
  --build-cache \
  --max-workers="$max_workers" \
  "$TASK" \
  -POMNI_RELEASE_STORE_FILE="$OMNI_RELEASE_STORE_FILE" \
  -POMNI_RELEASE_STORE_PWD="$OMNI_RELEASE_STORE_PWD" \
  -POMNI_RELEASE_KEY_ALIAS="$OMNI_RELEASE_KEY_ALIAS" \
  -POMNI_RELEASE_KEY_PWD="$OMNI_RELEASE_KEY_PWD"

if [[ "$TASK" == "assembleProductionRelease" ]]; then
  if [[ ! -f "$APK_PATH" ]]; then
    echo "Build finished but APK was not found: $APK_PATH" >&2
    exit 1
  fi
  echo "APK ready: $APK_PATH"
  shasum -a 256 "$APK_PATH"

  if [[ "$INSTALL_APK" -eq 1 ]]; then
    echo "Installing APK via adb..."
    adb install -r "$APK_PATH"
  fi
else
  if [[ ! -f "$AAB_PATH" ]]; then
    echo "Build finished but AAB was not found: $AAB_PATH" >&2
    exit 1
  fi
  echo "AAB ready: $AAB_PATH"
  shasum -a 256 "$AAB_PATH"
fi
