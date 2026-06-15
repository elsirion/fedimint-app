#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: scripts/build-android-nix.sh [debug|release] [--aab] [--clean]

Builds the Flutter Android APK/AAB using the Android SDK, NDK, JDK, and Rust
cross toolchain from the Nix dev shell.

Run from the dev shell:
  nix develop -c just build-debug-android
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

BUILD_MODE="${1:-debug}"
if [[ $# -gt 0 ]]; then
  shift
fi

BUILD_FORMAT="apk"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --aab)
      BUILD_FORMAT="aab"
      ;;
    --clean)
      CLEAN=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown flag: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
  shift
done

if [[ "$BUILD_MODE" != "debug" && "$BUILD_MODE" != "release" ]]; then
  echo "Error: build mode must be 'debug' or 'release'" >&2
  usage >&2
  exit 1
fi

require_env() {
  local name="$1"
  if [[ -z "${!name:-}" ]]; then
    echo "Error: $name is not set. Enter the Nix dev shell first:" >&2
    echo "  nix develop" >&2
    exit 1
  fi
}

require_cmd() {
  local name="$1"
  if ! command -v "$name" >/dev/null 2>&1; then
    echo "Error: '$name' not found. Enter the Nix dev shell first:" >&2
    echo "  nix develop" >&2
    exit 1
  fi
}

require_env ANDROID_HOME
require_env ANDROID_NDK_HOME
require_env JAVA_HOME
require_env FLUTTER_ROOT
require_cmd flutter
require_cmd cargo
if ! cargo ndk --version >/dev/null 2>&1; then
  echo "Error: 'cargo ndk' is not available. Enter the Nix dev shell first." >&2
  exit 1
fi

find_ndk_prebuilt_dir() {
  local llvm_dir="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt"
  local dir
  for dir in linux-x86_64 darwin-x86_64 darwin-aarch64; do
    if [[ -d "$llvm_dir/$dir" ]]; then
      printf '%s\n' "$llvm_dir/$dir"
      return 0
    fi
  done

  echo "Error: no Android NDK LLVM prebuilt toolchain found in $llvm_dir" >&2
  exit 1
}

write_gradle_property() {
  local key="$1"
  local value="$2"
  local file="$GRADLE_USER_HOME/gradle.properties"
  local tmp

  mkdir -p "$GRADLE_USER_HOME"
  touch "$file"
  tmp="$(mktemp)"
  awk -F= -v key="$key" '$1 != key { print }' "$file" > "$tmp"
  printf '%s=%s\n' "$key" "$value" >> "$tmp"
  mv "$tmp" "$file"
}

prepare_android_project() {
  mkdir -p "$PROJECT_ROOT/android"
  cat > "$PROJECT_ROOT/android/local.properties" <<EOF_LOCAL_PROPERTIES
sdk.dir=$ANDROID_HOME
flutter.sdk=$FLUTTER_ROOT
EOF_LOCAL_PROPERTIES

  export GRADLE_USER_HOME="${GRADLE_USER_HOME:-$PROJECT_ROOT/.gradle}"
  write_gradle_property "org.gradle.java.home" "$JAVA_HOME"
  write_gradle_property "android.aapt2FromMavenOverride" "$ANDROID_HOME/build-tools/35.0.0/aapt2"
}

build_rust_library() {
  local ndk_prebuilt_dir="$1"
  local rust_target="aarch64-linux-android"
  local jni_libs_dir="$PROJECT_ROOT/android/app/src/main/jniLibs/arm64-v8a"
  local rust_profile="release"
  local ndk_cache_stamp="$PROJECT_ROOT/rust/ecashapp/target/.nix-android-ndk"
  local ndk_cache_key="$ANDROID_NDK_HOME|$ndk_prebuilt_dir"

  if [[ "$BUILD_MODE" == "debug" ]]; then
    rust_profile="release-dev"
  fi

  mkdir -p "$jni_libs_dir"

  # aws-lc's CMake build caches host/NDK-specific generated assembly paths.
  # Keep the rest of the Rust target cache, but make this one crate rebuild
  # when the Nix-provided NDK path changes.
  if [[ -d "$PROJECT_ROOT/rust/ecashapp/target" ]] \
    && [[ "$(cat "$ndk_cache_stamp" 2>/dev/null || true)" != "$ndk_cache_key" ]]; then
    find "$PROJECT_ROOT/rust/ecashapp/target" \
      -path '*/build/aws-lc-sys-*' \
      -type d \
      -prune \
      -exec rm -rf {} +
  fi

  export CC_aarch64_linux_android="$ndk_prebuilt_dir/bin/aarch64-linux-android28-clang"
  export CXX_aarch64_linux_android="$ndk_prebuilt_dir/bin/aarch64-linux-android28-clang++"
  export AR_aarch64_linux_android="$ndk_prebuilt_dir/bin/llvm-ar"
  export CARGO_TARGET_AARCH64_LINUX_ANDROID_LINKER="$CC_aarch64_linux_android"
  export CFLAGS_aarch64_linux_android="--sysroot=$ndk_prebuilt_dir/sysroot"
  export CXXFLAGS_aarch64_linux_android="--sysroot=$ndk_prebuilt_dir/sysroot"
  export BINDGEN_EXTRA_CLANG_ARGS_aarch64_linux_android="--sysroot=$ndk_prebuilt_dir/sysroot -I$ndk_prebuilt_dir/sysroot/usr/include -I$ndk_prebuilt_dir/sysroot/usr/include/$rust_target"
  export ANDROID_NDK_ROOT="$ANDROID_NDK_HOME"
  export ANDROID_NDK="$ANDROID_NDK_HOME"

  echo "Building Rust library for $rust_target ($rust_profile)..."
  (
    cd "$PROJECT_ROOT/rust/ecashapp"
    cargo ndk \
      -t arm64-v8a \
      --platform 28 \
      -o "$jni_libs_dir" \
      build \
      --profile "$rust_profile" \
      --target "$rust_target"
  )
  mkdir -p "$(dirname "$ndk_cache_stamp")"
  printf '%s\n' "$ndk_cache_key" > "$ndk_cache_stamp"

  find "$jni_libs_dir" -mindepth 2 -type f -name '*.so' -exec mv {} "$jni_libs_dir" \;
  find "$jni_libs_dir" -mindepth 1 -type d -empty -delete
  cp "$ndk_prebuilt_dir/sysroot/usr/lib/aarch64-linux-android/libc++_shared.so" "$jni_libs_dir/" 2>/dev/null || true
}

copy_named_artifact() {
  local default_artifact="$1"
  local extension="$2"
  local output_dir app_name version timestamp named_artifact

  output_dir="$(dirname "$default_artifact")"
  app_name="$(awk -F': *' '/^name:/ { print $2; exit }' "$PROJECT_ROOT/pubspec.yaml")"
  version="$(awk -F': *' '/^version:/ { print $2; exit }' "$PROJECT_ROOT/pubspec.yaml" | cut -d+ -f1)"
  timestamp="$(date +%Y%m%d-%H%M%S)"
  named_artifact="$output_dir/${app_name}-${version}-${BUILD_MODE}-${timestamp}.${extension}"

  cp "$default_artifact" "$named_artifact"
  printf '%s\n' "$named_artifact"
}

cd "$PROJECT_ROOT"

prepare_android_project

if [[ "${CLEAN:-0}" == "1" ]]; then
  echo "CLEAN=1 enabled - wiping Flutter, Gradle, and Rust build caches..."
  flutter clean
  rm -rf android/.gradle android/build build rust/ecashapp/target
fi

echo "Getting Flutter dependencies..."
flutter pub get

build_rust_library "$(find_ndk_prebuilt_dir)"

if [[ "$BUILD_FORMAT" == "aab" ]]; then
  echo "Building Flutter App Bundle ($BUILD_MODE)..."
  flutter build appbundle --"$BUILD_MODE"
  artifact="$(copy_named_artifact "build/app/outputs/bundle/$BUILD_MODE/app-$BUILD_MODE.aab" aab)"
else
  echo "Building Flutter APK ($BUILD_MODE)..."
  flutter build apk --"$BUILD_MODE"
  artifact="$(copy_named_artifact "build/app/outputs/flutter-apk/app-$BUILD_MODE.apk" apk)"
fi

printf '\nBuild complete: %s\n' "$artifact"
