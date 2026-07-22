#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CODENAME="${CODENAME:-noble}"
UBUNTU_VERSION="${UBUNTU_VERSION:-24.04.3}"
ARCH="${ARCH:-arm64}"
NODE_VERSION="${NODE_VERSION:-24.15.0}"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
NPM_DISTURL="${NPM_DISTURL:-https://npmmirror.com/mirrors/node}"
BUILD_SCRIPT="$ROOT_DIR/scripts/build-prebuilt-rootfs.sh"

asset_name() {
  printf 'openclaw-rootfs-%s-%s.tar.gz\n' "$CODENAME" "$ARCH"
}

manifest_name() {
  printf 'openclaw-rootfs-%s-%s.json\n' "$CODENAME" "$ARCH"
}

build_script_sha() {
  sha256sum "$BUILD_SCRIPT" | awk '{print $1}'
}

fingerprint() {
  {
    printf 'codename=%s\n' "$CODENAME"
    printf 'ubuntu_version=%s\n' "$UBUNTU_VERSION"
    printf 'arch=%s\n' "$ARCH"
    printf 'node_version=%s\n' "$NODE_VERSION"
    printf 'npm_registry=%s\n' "$NPM_REGISTRY"
    printf 'npm_disturl=%s\n' "$NPM_DISTURL"
    printf 'build_script_sha256=%s\n' "$(build_script_sha)"
  } | sha256sum | awk '{print $1}'
}

write_manifest() {
  local output_path="$1"
  python3 - "$output_path" <<'PY'
import json
import os
import sys

output_path = sys.argv[1]
payload = {
    "format": "ciyuanxia-prebuilt-rootfs-manifest",
    "version": 2,
    "asset_name": os.environ["ASSET_NAME"],
    "codename": os.environ["CODENAME"],
    "ubuntu_version": os.environ["UBUNTU_VERSION"],
    "arch": os.environ["ARCH"],
    "node_version": os.environ["NODE_VERSION"],
    "npm_registry": os.environ["NPM_REGISTRY"],
    "npm_disturl": os.environ["NPM_DISTURL"],
    "build_script_sha256": os.environ["BUILD_SCRIPT_SHA256"],
    "fingerprint": os.environ["FINGERPRINT"],
    "archive_sha256": os.environ.get("ARCHIVE_SHA256", ""),
    "archive_size": int(os.environ.get("ARCHIVE_SIZE", "0")),
    "built_at": os.environ["BUILT_AT"],
}
with open(output_path, "w", encoding="utf-8") as handle:
    json.dump(payload, handle, ensure_ascii=True, indent=2)
    handle.write("\n")
PY
}

command="${1:-}"
case "$command" in
  asset-name)
    asset_name
    ;;
  manifest-name)
    manifest_name
    ;;
  fingerprint)
    fingerprint
    ;;
  write-manifest)
    if [[ $# -lt 2 || $# -gt 3 ]]; then
      echo "Usage: $0 write-manifest <output-path> [archive-path]" >&2
      exit 2
    fi
    ASSET_NAME="$(asset_name)"
    BUILD_SCRIPT_SHA256="$(build_script_sha)"
    FINGERPRINT="$(fingerprint)"
    BUILT_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    ARCHIVE_SHA256=""
    ARCHIVE_SIZE="0"
    if [[ $# -eq 3 ]]; then
      ARCHIVE_SHA256="$(sha256sum "$3" | awk '{print $1}')"
      ARCHIVE_SIZE="$(stat -c%s "$3")"
    fi
    export \
      CODENAME \
      UBUNTU_VERSION \
      ARCH \
      NODE_VERSION \
      NPM_REGISTRY \
      NPM_DISTURL \
      ASSET_NAME \
      BUILD_SCRIPT_SHA256 \
      FINGERPRINT \
      BUILT_AT \
      ARCHIVE_SHA256 \
      ARCHIVE_SIZE
    write_manifest "$2" "${3:-}"
    ;;
  *)
    cat >&2 <<'EOF'
Usage:
  scripts/prebuilt-rootfs-metadata.sh asset-name
  scripts/prebuilt-rootfs-metadata.sh manifest-name
  scripts/prebuilt-rootfs-metadata.sh fingerprint
  scripts/prebuilt-rootfs-metadata.sh write-manifest <output-path> [archive-path]
EOF
    exit 2
    ;;
esac
