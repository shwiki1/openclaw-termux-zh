#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
METADATA_SCRIPT="$ROOT_DIR/scripts/prebuilt-rootfs-metadata.sh"
TMP_DIR="${OPENCLAW_PREBUILT_PUBLISH_TMP:-$ROOT_DIR/.tmp/prebuilt-rootfs-publish}"
ASSET_DIR="$ROOT_DIR/flutter_app/assets/bootstrap"

ARCH="${ARCH:-arm64}"
RELEASE_TAG="basic-resource"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch)
      ARCH="${2:-}"
      shift 2
      ;;
    --release-tag)
      RELEASE_TAG="${2:-}"
      shift 2
      ;;
    *)
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

export ARCH

need_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

need_command gh
need_command python3

ASSET_NAME="$("$METADATA_SCRIPT" asset-name)"
MANIFEST_NAME="$("$METADATA_SCRIPT" manifest-name)"
ARCHIVE_PATH="$ASSET_DIR/$ASSET_NAME"
MANIFEST_PATH="$TMP_DIR/$MANIFEST_NAME"

if [[ ! -s "$ARCHIVE_PATH" ]]; then
  echo "Rootfs archive does not exist: $ARCHIVE_PATH" >&2
  exit 1
fi

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"

"$METADATA_SCRIPT" write-manifest "$MANIFEST_PATH" "$ARCHIVE_PATH"

if ! gh release view "$RELEASE_TAG" >/dev/null 2>&1; then
  gh release create "$RELEASE_TAG" \
    --title "basic-resource" \
    --notes "Reusable prebuilt rootfs assets for OpenClaw cloud builds." \
    >/dev/null
fi

echo "==> Publishing prebuilt rootfs assets to release '$RELEASE_TAG'"
gh release upload "$RELEASE_TAG" "$ARCHIVE_PATH" "$MANIFEST_PATH" --clobber >/dev/null
echo "==> Published assets: $ASSET_NAME, $MANIFEST_NAME"
