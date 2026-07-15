#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

CODENAME="${CODENAME:-noble}"
UBUNTU_VERSION="${UBUNTU_VERSION:-24.04.3}"
ARCH="${ARCH:-arm64}"
NODE_VERSION="${NODE_VERSION:-24.15.0}"
OPENCLAW_VERSION="${OPENCLAW_VERSION:-latest}"
QQBOT_PACKAGE="${QQBOT_PACKAGE:-@tencent-connect/openclaw-qqbot@latest}"
WEIXIN_PACKAGE="${WEIXIN_PACKAGE:-@tencent-weixin/openclaw-weixin@latest}"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
NPM_REGISTRY_FALLBACK="${NPM_REGISTRY_FALLBACK:-https://registry.npmjs.org}"
NPM_DISTURL="${NPM_DISTURL:-https://npmmirror.com/mirrors/node}"
BUILD_SCRIPT="$ROOT_DIR/scripts/build-prebuilt-rootfs.sh"

_RESOLVED_OPENCLAW_VERSION=""
_RESOLVED_QQBOT_VERSION=""
_RESOLVED_WEIXIN_VERSION=""

asset_name() {
  printf 'openclaw-rootfs-%s-%s.tar.gz\n' "$CODENAME" "$ARCH"
}

manifest_name() {
  printf 'openclaw-rootfs-%s-%s.json\n' "$CODENAME" "$ARCH"
}

build_script_sha() {
  sha256sum "$BUILD_SCRIPT" | awk '{print $1}'
}

openclaw_spec() {
  printf 'openclaw@%s\n' "$OPENCLAW_VERSION"
}

resolve_package_version() {
  local package_spec="$1"
  local default_package_name="$2"
  python3 - "$package_spec" "$default_package_name" "$NPM_REGISTRY" "$NPM_REGISTRY_FALLBACK" <<'PY'
import json
import sys
import urllib.parse
import urllib.request

package_spec, default_name, primary_registry, fallback_registry = sys.argv[1:5]


def split_package_spec(spec: str, default_package: str) -> tuple[str, str]:
    normalized = spec.strip()
    if not normalized:
        return default_package, "latest"
    if normalized.startswith("@"):
        marker = normalized.rfind("@")
        if marker > 0:
            candidate_name = normalized[:marker]
            candidate_selector = normalized[marker + 1 :].strip()
            if "/" in candidate_name and candidate_selector:
                return candidate_name, candidate_selector
        return normalized, "latest"
    if "@" in normalized:
        candidate_name, candidate_selector = normalized.rsplit("@", 1)
        if candidate_name.strip():
            selector = candidate_selector.strip() or "latest"
            return candidate_name.strip(), selector
    return normalized, "latest"


def is_exact_version(selector: str) -> bool:
    if not selector:
        return False
    normalized = selector.lstrip("v")
    return normalized[:1].isdigit()


def should_bypass_registry(selector: str) -> bool:
    if not selector:
        return False
    if is_exact_version(selector):
        return True
    return any(ch in selector for ch in "^~<>=|* xX")


package_name, selector = split_package_spec(package_spec, default_name)

if should_bypass_registry(selector):
    print(selector.lstrip("v"))
    raise SystemExit(0)

quoted_name = urllib.parse.quote(package_name, safe="@/")
last_error = None
for base_url in (primary_registry, fallback_registry):
    url = f"{base_url.rstrip('/')}/{quoted_name}"
    try:
        with urllib.request.urlopen(url, timeout=15) as response:
            payload = json.load(response)
        dist_tags = payload.get("dist-tags") or {}
        resolved = dist_tags.get(selector)
        if resolved:
            print(resolved)
            raise SystemExit(0)
        versions = payload.get("versions") or {}
        if selector in versions:
            print(selector)
            raise SystemExit(0)
        last_error = f"selector {selector!r} not found in {url}"
    except Exception as exc:  # pragma: no cover - shell script fallback path
        last_error = exc

raise SystemExit(
    f"Failed to resolve {package_spec!r} via npm registry metadata: {last_error}"
)
PY
}

resolved_openclaw_version() {
  if [[ -z "$_RESOLVED_OPENCLAW_VERSION" ]]; then
    _RESOLVED_OPENCLAW_VERSION="$(resolve_package_version "$(openclaw_spec)" "openclaw")"
  fi
  printf '%s\n' "$_RESOLVED_OPENCLAW_VERSION"
}

resolved_qqbot_version() {
  if [[ -z "$_RESOLVED_QQBOT_VERSION" ]]; then
    _RESOLVED_QQBOT_VERSION="$(resolve_package_version "$QQBOT_PACKAGE" "@tencent-connect/openclaw-qqbot")"
  fi
  printf '%s\n' "$_RESOLVED_QQBOT_VERSION"
}

resolved_weixin_version() {
  if [[ -z "$_RESOLVED_WEIXIN_VERSION" ]]; then
    _RESOLVED_WEIXIN_VERSION="$(resolve_package_version "$WEIXIN_PACKAGE" "@tencent-weixin/openclaw-weixin")"
  fi
  printf '%s\n' "$_RESOLVED_WEIXIN_VERSION"
}

fingerprint() {
  {
    printf 'codename=%s\n' "$CODENAME"
    printf 'ubuntu_version=%s\n' "$UBUNTU_VERSION"
    printf 'arch=%s\n' "$ARCH"
    printf 'node_version=%s\n' "$NODE_VERSION"
    printf 'openclaw_spec=%s\n' "$(openclaw_spec)"
    printf 'openclaw_resolved_version=%s\n' "$(resolved_openclaw_version)"
    printf 'openclaw_version=%s\n' "$OPENCLAW_VERSION"
    printf 'qqbot_resolved_version=%s\n' "$(resolved_qqbot_version)"
    printf 'qqbot_package=%s\n' "$QQBOT_PACKAGE"
    printf 'weixin_resolved_version=%s\n' "$(resolved_weixin_version)"
    printf 'weixin_package=%s\n' "$WEIXIN_PACKAGE"
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
    "format": "openclaw-prebuilt-rootfs-manifest",
    "version": 1,
    "asset_name": os.environ["ASSET_NAME"],
    "codename": os.environ["CODENAME"],
    "ubuntu_version": os.environ["UBUNTU_VERSION"],
    "arch": os.environ["ARCH"],
    "node_version": os.environ["NODE_VERSION"],
    "openclaw_spec": os.environ["OPENCLAW_SPEC"],
    "openclaw_version": os.environ["OPENCLAW_VERSION"],
    "openclaw_resolved_version": os.environ["OPENCLAW_RESOLVED_VERSION"],
    "qqbot_package": os.environ["QQBOT_PACKAGE"],
    "qqbot_resolved_version": os.environ["QQBOT_RESOLVED_VERSION"],
    "weixin_package": os.environ["WEIXIN_PACKAGE"],
    "weixin_resolved_version": os.environ["WEIXIN_RESOLVED_VERSION"],
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
    OPENCLAW_SPEC="$(openclaw_spec)"
    OPENCLAW_RESOLVED_VERSION="$(resolved_openclaw_version)"
    QQBOT_RESOLVED_VERSION="$(resolved_qqbot_version)"
    WEIXIN_RESOLVED_VERSION="$(resolved_weixin_version)"
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
      OPENCLAW_SPEC \
      OPENCLAW_VERSION \
      OPENCLAW_RESOLVED_VERSION \
      QQBOT_PACKAGE \
      QQBOT_RESOLVED_VERSION \
      WEIXIN_PACKAGE \
      WEIXIN_RESOLVED_VERSION \
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
