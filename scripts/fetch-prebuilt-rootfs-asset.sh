#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
METADATA_SCRIPT="$ROOT_DIR/scripts/prebuilt-rootfs-metadata.sh"
ASSET_DIR="$ROOT_DIR/flutter_app/assets/bootstrap"
TMP_DIR="${OPENCLAW_PREBUILT_FETCH_TMP:-$ROOT_DIR/.tmp/prebuilt-rootfs-fetch}"

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
need_command gzip
need_command python3

ASSET_NAME="$(bash "$METADATA_SCRIPT" asset-name)"
MANIFEST_NAME="$(bash "$METADATA_SCRIPT" manifest-name)"
EXPECTED_FINGERPRINT="$(bash "$METADATA_SCRIPT" fingerprint)"
DEST_PATH="$ASSET_DIR/$ASSET_NAME"
MANIFEST_PATH="$TMP_DIR/$MANIFEST_NAME"

rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR" "$ASSET_DIR"

echo "==> Checking prebuilt rootfs manifest from release '$RELEASE_TAG'"
if ! gh release download "$RELEASE_TAG" --pattern "$MANIFEST_NAME" --dir "$TMP_DIR" >/dev/null 2>&1; then
  echo "No matching rootfs manifest asset found."
  exit 1
fi

python3 - "$MANIFEST_PATH" "$EXPECTED_FINGERPRINT" "$ASSET_NAME" <<'PY'
import json
import sys

manifest_path, expected_fingerprint, expected_asset_name = sys.argv[1:4]
with open(manifest_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

if data.get("format") != "openclaw-prebuilt-rootfs-manifest":
    raise SystemExit("Unsupported prebuilt rootfs manifest format")
if data.get("asset_name") != expected_asset_name:
    raise SystemExit("Manifest asset_name does not match expected rootfs asset")
if data.get("fingerprint") != expected_fingerprint:
    raise SystemExit("Prebuilt rootfs fingerprint mismatch")
PY

echo "==> Rootfs manifest matched current build fingerprint"
gh release download "$RELEASE_TAG" --pattern "$ASSET_NAME" --dir "$ASSET_DIR" --clobber >/dev/null

if [[ ! -s "$DEST_PATH" ]]; then
  echo "Downloaded rootfs asset is missing or empty: $DEST_PATH" >&2
  exit 1
fi

gzip -t "$DEST_PATH"

python3 - "$MANIFEST_PATH" "$DEST_PATH" <<'PY'
import hashlib
import json
import os
import sys

manifest_path, archive_path = sys.argv[1:3]
with open(manifest_path, "r", encoding="utf-8") as handle:
    data = json.load(handle)

archive_size = os.path.getsize(archive_path)
if data.get("archive_size") and archive_size != int(data["archive_size"]):
    raise SystemExit("Prebuilt rootfs size mismatch")

expected_sha = data.get("archive_sha256")
if expected_sha:
    digest = hashlib.sha256()
    with open(archive_path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    if digest.hexdigest() != expected_sha:
        raise SystemExit("Prebuilt rootfs sha256 mismatch")
PY

echo "==> Reused prebuilt rootfs asset: $DEST_PATH"
