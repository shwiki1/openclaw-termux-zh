#!/bin/bash
# Build the OpenClaw Flutter APK for arm64-v8a only.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$SCRIPT_DIR/.."
FLUTTER_DIR="$PROJECT_DIR/flutter_app"

echo "=== OpenClaw APK Build ==="
echo ""

# Step 1: Fetch proot binaries if not present
if [ ! -f "$FLUTTER_DIR/android/app/src/main/jniLibs/arm64-v8a/libproot.so" ]; then
    echo "[1/3] Fetching PRoot binaries..."
    bash "$SCRIPT_DIR/fetch-proot-binaries.sh"
else
    echo "[1/3] PRoot binaries already present"
fi
echo ""

# Step 2: Get Flutter dependencies
echo "[2/3] Getting Flutter dependencies..."
cd "$FLUTTER_DIR"
flutter pub get
echo ""

# Step 3: Build APK
echo "[3/3] Building arm64-v8a release APK..."
APP_VERSION="$(awk '/^version:/ {print $2; exit}' pubspec.yaml)"
BASE_VERSION_NAME="${APP_VERSION%%+*}"
BASE_VERSION_CODE="${APP_VERSION#*+}"
if [ "$BASE_VERSION_CODE" = "$APP_VERSION" ] || [ -z "$BASE_VERSION_CODE" ]; then
    BASE_VERSION_CODE=1
fi
if [ -n "${BUILD_VERSION_CODE:-}" ]; then
    VERSION_CODE="$BUILD_VERSION_CODE"
else
    VERSION_CODE="$((BASE_VERSION_CODE + 1))"
fi
eval "$(
    python3 "$PROJECT_DIR/scripts/versioning.py" derive \
        --base-version "$BASE_VERSION_NAME" \
        --base-build "$BASE_VERSION_CODE" \
        --target-build "$VERSION_CODE" \
        --format shell
)"
VERSION_NAME="$SEMANTIC_VERSION"
VERSION_DISPLAY="$DISPLAY_VERSION"
echo "Version name shown during install: $VERSION_DISPLAY"
flutter build apk --release \
    --split-per-abi \
    --target-platform android-arm64 \
    --build-name "$VERSION_NAME" \
    --build-number "$VERSION_CODE" \
    --dart-define=APP_VERSION_NAME="$VERSION_NAME" \
    --dart-define=APP_VERSION_DISPLAY="$VERSION_DISPLAY" \
    --dart-define=APP_VERSION_CODE="$VERSION_CODE"
echo ""

APK_PATH="$FLUTTER_DIR/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk"
if [ -f "$APK_PATH" ]; then
    echo "=== Build Successful ==="
    echo "APK: $APK_PATH"
    echo "Install-visible version: $VERSION_DISPLAY"
    echo "Internal version/build: $VERSION_NAME+$VERSION_CODE"
    echo "Size: $(du -h "$APK_PATH" | cut -f1)"
    echo ""
    echo "Install: adb install $APK_PATH"
else
    echo "=== Build Failed ==="
    exit 1
fi
