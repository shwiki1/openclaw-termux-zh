#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ASSET_DIR="$ROOT_DIR/flutter_app/assets/bootstrap"
CACHE_DIR="${OPENCLAW_ROOTFS_CACHE:-$ROOT_DIR/.tmp/rootfs-cache}"
WORK_BASE="${OPENCLAW_ROOTFS_WORKDIR:-$ROOT_DIR/.tmp/prebuilt-rootfs}"

CODENAME="${CODENAME:-noble}"
UBUNTU_VERSION="${UBUNTU_VERSION:-24.04.3}"
ARCH="arm64"
MIRROR=""
USE_DOCKER=0
NO_DOCKER=0
PACKAGES=(ca-certificates git python3 python3-pip make g++ curl wget lsof)
NODE_VERSION="${NODE_VERSION:-24.15.0}"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
NPM_DISTURL="${NPM_DISTURL:-https://npmmirror.com/mirrors/node}"

usage() {
  cat <<USAGE
Build a prebuilt Ubuntu rootfs archive for CiYuanXia.

Usage:
  scripts/build-prebuilt-rootfs.sh [arm64|armhf|amd64]
  scripts/build-prebuilt-rootfs.sh --arch arm64 [--mirror URL]
  scripts/build-prebuilt-rootfs.sh --docker --arch arm64

Output:
  flutter_app/assets/bootstrap/openclaw-rootfs-${CODENAME}-<arch>.tar.gz

Notes:
  - Run from Linux or WSL.
  - Use --docker on Windows/WSL when host sudo is not available.
  - Cross-arch builds need qemu-user-static installed.
  - The archive includes Ubuntu base packages, Node.js, and local relay
    Python dependencies. It no longer preinstalls OpenClaw or OpenClaw plugins.
  - The APK will still fall back to standard Ubuntu base + apt if this archive
    is missing, corrupt, or does not contain the required base packages.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --arch)
      ARCH="${2:-}"
      shift 2
      ;;
    --mirror)
      MIRROR="${2:-}"
      shift 2
      ;;
    --docker)
      USE_DOCKER=1
      shift
      ;;
    --no-docker)
      NO_DOCKER=1
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    arm64|armhf|amd64)
      ARCH="$1"
      shift
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

case "$ARCH" in
  arm64)
    ROOTFS_ARCH="arm64"
    QEMU_BIN="qemu-aarch64-static"
    DEFAULT_MIRROR="http://mirrors.ustc.edu.cn/ubuntu-ports"
    ;;
  armhf)
    ROOTFS_ARCH="armhf"
    QEMU_BIN="qemu-arm-static"
    DEFAULT_MIRROR="http://mirrors.ustc.edu.cn/ubuntu-ports"
    ;;
  amd64)
    ROOTFS_ARCH="amd64"
    QEMU_BIN="qemu-x86_64-static"
    DEFAULT_MIRROR="http://mirrors.ustc.edu.cn/ubuntu"
    ;;
  *)
    echo "Unsupported arch: $ARCH" >&2
    exit 2
    ;;
esac

MIRROR="${MIRROR:-$DEFAULT_MIRROR}"
BOOTSTRAP_MIRROR="${MIRROR/https:\/\//http://}"
APT_MIRRORS=("$BOOTSTRAP_MIRROR")
case "$ROOTFS_ARCH" in
  arm64|armhf)
    APT_MIRRORS+=(
      "http://mirrors.aliyun.com/ubuntu-ports"
      "http://ports.ubuntu.com/ubuntu-ports"
    )
    ;;
  amd64)
    APT_MIRRORS+=(
      "http://mirrors.aliyun.com/ubuntu"
      "http://archive.ubuntu.com/ubuntu"
    )
    ;;
esac

deduped_apt_mirrors=()
for candidate in "${APT_MIRRORS[@]}"; do
  [[ -n "$candidate" ]] || continue
  skip_candidate=0
  for existing in "${deduped_apt_mirrors[@]}"; do
    if [[ "$existing" == "$candidate" ]]; then
      skip_candidate=1
      break
    fi
  done
  if [[ "$skip_candidate" == "0" ]]; then
    deduped_apt_mirrors+=("$candidate")
  fi
done
APT_MIRRORS=("${deduped_apt_mirrors[@]}")

BASE_NAME="ubuntu-base-${UBUNTU_VERSION}-base-${ROOTFS_ARCH}.tar.gz"
BASE_URLS=(
  "https://mirrors.ustc.edu.cn/ubuntu-cdimage/ubuntu-base/releases/24.04/release/$BASE_NAME"
  "https://mirrors.aliyun.com/ubuntu-cdimage/ubuntu-base/releases/24.04/release/$BASE_NAME"
  "https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cdimage/ubuntu-base/releases/24.04/release/$BASE_NAME"
  "https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/$BASE_NAME"
)
OUTPUT_NAME="openclaw-rootfs-${CODENAME}-${ROOTFS_ARCH}.tar.gz"
WORK_DIR="$WORK_BASE/$ROOTFS_ARCH"
ROOTFS_DIR="$WORK_DIR/rootfs"
BASE_TARBALL="$CACHE_DIR/$BASE_NAME"
OUTPUT_PATH="$ASSET_DIR/$OUTPUT_NAME"

need_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

if [[ "$USE_DOCKER" == "1" && "$NO_DOCKER" != "1" ]]; then
  need_command docker
  mirror_args=()
  if [[ -n "$MIRROR" ]]; then
    mirror_args=(--mirror "$MIRROR")
  fi
  case "$ROOTFS_ARCH" in
    arm64)
      echo "==> Registering Docker binfmt for arm64"
      docker run --privileged --rm tonistiigi/binfmt --install arm64 >/dev/null
      ;;
    armhf)
      echo "==> Registering Docker binfmt for arm"
      docker run --privileged --rm tonistiigi/binfmt --install arm >/dev/null
      ;;
  esac
  echo "==> Starting privileged Ubuntu builder container"
  docker run --rm --privileged \
    -v "$ROOT_DIR:/work" \
    -w /work \
    -e CODENAME="$CODENAME" \
    -e UBUNTU_VERSION="$UBUNTU_VERSION" \
    -e NODE_VERSION="$NODE_VERSION" \
    -e NPM_REGISTRY="$NPM_REGISTRY" \
    -e NPM_DISTURL="$NPM_DISTURL" \
    -e OPENCLAW_ROOTFS_CACHE=/tmp/openclaw-rootfs-cache \
    -e OPENCLAW_ROOTFS_WORKDIR=/tmp/openclaw-prebuilt-rootfs \
    ubuntu:24.04 \
    bash -lc "apt-get update && apt-get install -y --no-install-recommends ca-certificates curl xz-utils qemu-user-static mount sudo && bash scripts/build-prebuilt-rootfs.sh --no-docker --arch '$ROOTFS_ARCH' ${mirror_args[*]}"
  exit 0
fi

need_command curl
need_command tar
need_command mountpoint
need_command xz
if [[ "$(id -u)" != "0" ]]; then
  need_command sudo
fi

run_root() {
  if [[ "$(id -u)" == "0" ]]; then
    "$@"
  else
    sudo "$@"
  fi
}

HOST_ARCH="$(uname -m)"
NEEDS_QEMU=1
case "$ROOTFS_ARCH:$HOST_ARCH" in
  arm64:aarch64|amd64:x86_64|armhf:armv7l|armhf:armv8l)
    NEEDS_QEMU=0
    ;;
esac

if [[ "$NEEDS_QEMU" == "1" ]]; then
  need_command "$QEMU_BIN"
fi

mounted_paths=()

mount_rootfs_path() {
  local source="$1"
  local target="$2"
  local mode="$3"
  run_root mkdir -p "$target"
  if mountpoint -q "$target"; then
    return
  fi
  if [[ "$mode" == "proc" ]]; then
    run_root mount -t proc proc "$target"
  else
    run_root mount --rbind "$source" "$target"
  fi
  mounted_paths+=("$target")
}

unmount_rootfs_paths() {
  local index
  for ((index=${#mounted_paths[@]} - 1; index >= 0; index--)); do
    run_root umount -l "${mounted_paths[$index]}" >/dev/null 2>&1 || true
  done
  mounted_paths=()
}

cleanup() {
  unmount_rootfs_paths
}
trap cleanup EXIT

chroot_run() {
  local env_args=(
    HOME=/root
    TERM=xterm-256color
    DEBIAN_FRONTEND=noninteractive
    PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
  )
  if [[ "$NEEDS_QEMU" == "1" ]]; then
    run_root chroot "$ROOTFS_DIR" "/usr/bin/$QEMU_BIN" /usr/bin/env -i "${env_args[@]}" "$@"
  else
    run_root chroot "$ROOTFS_DIR" /usr/bin/env -i "${env_args[@]}" "$@"
  fi
}

download_with_fallbacks() {
  local destination="$1"
  shift
  local downloaded=0
  local url
  for url in "$@"; do
    echo "    -> $url"
    if curl -fL --retry 3 --connect-timeout 20 -o "$destination.tmp" "$url"; then
      mv "$destination.tmp" "$destination"
      downloaded=1
      break
    fi
  done
  if [[ "$downloaded" != "1" ]]; then
    rm -f "$destination.tmp"
    echo "Failed to download $destination" >&2
    return 1
  fi
}

shell_quote() {
  printf "'%s'" "$(printf "%s" "$1" | sed "s/'/'\\\\''/g")"
}

write_apt_sources() {
  local mirror="$1"
  run_root tee "$ROOTFS_DIR/etc/apt/sources.list" >/dev/null <<EOF
deb $mirror $CODENAME main restricted universe multiverse
deb $mirror ${CODENAME}-updates main restricted universe multiverse
deb $mirror ${CODENAME}-backports main restricted universe multiverse
deb $mirror ${CODENAME}-security main restricted universe multiverse
EOF
}

ACTIVE_APT_MIRROR=""

apt_update_with_fallbacks() {
  local mirror
  for mirror in "${APT_MIRRORS[@]}"; do
    echo "==> apt-get update via $mirror"
    write_apt_sources "$mirror"
    if chroot_run apt-get update; then
      ACTIVE_APT_MIRROR="$mirror"
      return 0
    fi
  done
  echo "Failed to update apt metadata from all configured mirrors" >&2
  return 1
}

apt_install_with_fallbacks() {
  local install_args=("$@")
  if chroot_run apt-get install "${install_args[@]}"; then
    return 0
  fi

  local mirror
  for mirror in "${APT_MIRRORS[@]}"; do
    if [[ "$mirror" == "$ACTIVE_APT_MIRROR" ]]; then
      continue
    fi
    echo "==> Retrying apt install via $mirror"
    write_apt_sources "$mirror"
    if chroot_run apt-get update && chroot_run apt-get install "${install_args[@]}"; then
      ACTIVE_APT_MIRROR="$mirror"
      return 0
    fi
  done

  echo "Failed to install apt packages from all configured mirrors" >&2
  return 1
}

echo "==> Building prebuilt rootfs: $OUTPUT_NAME"
echo "    Ubuntu base: ${BASE_URLS[0]}"
echo "    Mirror:      $MIRROR"
echo "    Bootstrap apt mirror: $BOOTSTRAP_MIRROR"
echo "    APT mirrors: ${APT_MIRRORS[*]}"

mkdir -p "$CACHE_DIR" "$ASSET_DIR" "$WORK_DIR"
if [[ ! -s "$BASE_TARBALL" ]]; then
  echo "==> Downloading Ubuntu base rootfs"
  downloaded=0
  for base_url in "${BASE_URLS[@]}"; do
    if curl -fL --retry 3 --connect-timeout 20 -o "$BASE_TARBALL.tmp" "$base_url"; then
      mv "$BASE_TARBALL.tmp" "$BASE_TARBALL"
      downloaded=1
      break
    fi
  done
  if [[ "$downloaded" != "1" ]]; then
    rm -f "$BASE_TARBALL.tmp"
    echo "Failed to download Ubuntu base rootfs from all mirrors" >&2
    exit 1
  fi
else
  echo "==> Reusing cached Ubuntu base rootfs"
fi

echo "==> Extracting workspace"
run_root rm -rf "$ROOTFS_DIR"
mkdir -p "$ROOTFS_DIR"
run_root tar -xzf "$BASE_TARBALL" -C "$ROOTFS_DIR"

if [[ "$NEEDS_QEMU" == "1" ]]; then
  echo "==> Installing qemu helper for cross-arch chroot"
  run_root cp "$(command -v "$QEMU_BIN")" "$ROOTFS_DIR/usr/bin/$QEMU_BIN"
  run_root chmod 755 "$ROOTFS_DIR/usr/bin/$QEMU_BIN"
fi

echo "==> Preparing apt/dpkg config"
run_root mkdir -p \
  "$ROOTFS_DIR/etc/apt/apt.conf.d" \
  "$ROOTFS_DIR/etc/dpkg/dpkg.cfg.d" \
  "$ROOTFS_DIR/etc/apt/sources.list.d" \
  "$ROOTFS_DIR/usr/sbin" \
  "$ROOTFS_DIR/etc/ssl/certs" \
  "$ROOTFS_DIR/var/lib/apt/lists/partial" \
  "$ROOTFS_DIR/var/cache/apt/archives/partial" \
  "$ROOTFS_DIR/var/lib/dpkg/updates" \
  "$ROOTFS_DIR/var/lib/dpkg/triggers"

run_root rm -f "$ROOTFS_DIR/etc/apt/sources.list.d/ubuntu.sources"
write_apt_sources "${APT_MIRRORS[0]}"

run_root tee "$ROOTFS_DIR/etc/apt/apt.conf.d/01-openclaw-proot" >/dev/null <<'EOF'
APT::Sandbox::User "root";
Acquire::Languages "none";
Acquire::Retries "3";
Acquire::By-Hash "force";
Acquire::http::Timeout "20";
Acquire::https::Timeout "20";
Dpkg::Use-Pty "0";
Dpkg::Options { "--force-confnew"; "--force-overwrite"; };
EOF

run_root tee "$ROOTFS_DIR/etc/dpkg/dpkg.cfg.d/01-openclaw-proot" >/dev/null <<'EOF'
force-unsafe-io
no-debsig
force-overwrite
force-depends
EOF

run_root tee "$ROOTFS_DIR/usr/sbin/policy-rc.d" >/dev/null <<'EOF'
#!/bin/sh
exit 101
EOF
run_root chmod 755 "$ROOTFS_DIR/usr/sbin/policy-rc.d"

run_root tee "$ROOTFS_DIR/etc/resolv.conf" >/dev/null <<'EOF'
nameserver 223.5.5.5
nameserver 119.29.29.29
nameserver 8.8.8.8
EOF

run_root ln -sf /usr/share/zoneinfo/Asia/Shanghai "$ROOTFS_DIR/etc/localtime" || true
echo "Asia/Shanghai" | run_root tee "$ROOTFS_DIR/etc/timezone" >/dev/null

mount_rootfs_path proc "$ROOTFS_DIR/proc" proc
mount_rootfs_path /dev "$ROOTFS_DIR/dev" bind
mount_rootfs_path /sys "$ROOTFS_DIR/sys" bind

echo "==> Installing base packages: ${PACKAGES[*]}"
apt_update_with_fallbacks
apt_install_with_fallbacks -y --no-install-recommends "${PACKAGES[@]}"

case "$ROOTFS_ARCH" in
  arm64)
    NODE_ARCH="arm64"
    ;;
  armhf)
    NODE_ARCH="armv7l"
    ;;
  amd64)
    NODE_ARCH="x64"
    ;;
  *)
    echo "Unsupported Node.js arch for $ROOTFS_ARCH" >&2
    exit 2
    ;;
esac

NODE_BASENAME="node-v${NODE_VERSION}-linux-${NODE_ARCH}.tar.xz"
NODE_TARBALL="$CACHE_DIR/$NODE_BASENAME"
NODE_URLS=(
  "$NPM_DISTURL/v$NODE_VERSION/$NODE_BASENAME"
  "https://mirrors.ustc.edu.cn/node/v$NODE_VERSION/$NODE_BASENAME"
  "https://mirrors.aliyun.com/nodejs-release/v$NODE_VERSION/$NODE_BASENAME"
  "https://nodejs.org/dist/v$NODE_VERSION/$NODE_BASENAME"
)

if [[ ! -s "$NODE_TARBALL" ]]; then
  echo "==> Downloading Node.js $NODE_VERSION for $NODE_ARCH"
  download_with_fallbacks "$NODE_TARBALL" "${NODE_URLS[@]}"
else
  echo "==> Reusing cached Node.js $NODE_VERSION"
fi

echo "==> Installing Node.js $NODE_VERSION"
run_root rm -rf "$ROOTFS_DIR/usr/local/bin/node" \
  "$ROOTFS_DIR/usr/local/bin/npm" \
  "$ROOTFS_DIR/usr/local/bin/npx" \
  "$ROOTFS_DIR/usr/local/lib/node_modules/npm"
run_root tar -xJf "$NODE_TARBALL" -C "$ROOTFS_DIR/usr/local" --strip-components=1
run_root mkdir -p \
  "$ROOTFS_DIR/root/.openclaw" \
  "$ROOTFS_DIR/root/.npm" \
  "$ROOTFS_DIR/usr/local/etc" \
  "$ROOTFS_DIR/tmp/npm-cache" \
  "$ROOTFS_DIR/tmp/npm-tmp"

run_root tee "$ROOTFS_DIR/root/.npmrc" >/dev/null <<EOF
registry=$NPM_REGISTRY
audit=false
fund=false
progress=false
update-notifier=false
fetch-retries=5
fetch-retry-mintimeout=2000
fetch-retry-maxtimeout=20000
EOF
run_root cp "$ROOTFS_DIR/root/.npmrc" "$ROOTFS_DIR/usr/local/etc/npmrc"

echo "==> Verifying Node.js and npm"
chroot_run node --version
chroot_run npm --version

echo "==> Preinstalling api2py Python dependencies"
run_root mkdir -p "$ROOTFS_DIR/tmp/openclaw-api2py"
run_root cp "$ROOT_DIR/flutter_app/assets/api2py/requirements.txt" \
  "$ROOTFS_DIR/tmp/openclaw-api2py/requirements.txt"
chroot_run bash -lc "python3 -m pip install --break-system-packages --no-cache-dir -r /tmp/openclaw-api2py/requirements.txt || python3 -m pip install --break-system-packages --no-cache-dir --index-url https://pypi.org/simple -r /tmp/openclaw-api2py/requirements.txt"
chroot_run python3 - <<'PY'
for module in ('starlette', 'uvicorn', 'httpx', 'aiosqlite'):
    __import__(module)
PY
run_root rm -rf "$ROOTFS_DIR/tmp/openclaw-api2py"

echo "==> Cleaning npm cache"
chroot_run npm cache clean --force >/dev/null 2>&1 || true

echo "==> Cleaning rootfs"
chroot_run apt-get clean
unmount_rootfs_paths

if [[ "$NEEDS_QEMU" == "1" ]]; then
  run_root rm -f "$ROOTFS_DIR/usr/bin/$QEMU_BIN"
fi

run_root rm -rf \
  "$ROOTFS_DIR/var/lib/apt/lists/"* \
  "$ROOTFS_DIR/var/cache/apt/archives/"*.deb \
  "$ROOTFS_DIR/var/log/"* \
  "$ROOTFS_DIR/root/.npm/_logs" \
  "$ROOTFS_DIR/root/.npm/_cacache" \
  "$ROOTFS_DIR/root/.cache" \
  "$ROOTFS_DIR/tmp/npm-cache" \
  "$ROOTFS_DIR/tmp/npm-tmp" \
  "$ROOTFS_DIR/tmp/"* \
  "$ROOTFS_DIR/var/tmp/"* \
  "$ROOTFS_DIR/usr/share/man/"* \
  "$ROOTFS_DIR/usr/share/info/"*

run_root find "$ROOTFS_DIR/usr/share/doc" \( -type f -o -type l \) ! -name copyright -delete
run_root find "$ROOTFS_DIR/usr/share/doc" -type d -empty -delete

run_root find "$ROOTFS_DIR" -type d -name '__pycache__' -prune -exec rm -rf {} +
run_root find "$ROOTFS_DIR" -type f \( -name '*.pyc' -o -name '*.pyo' -o -name '*.js.map' \) -delete

run_root find "$ROOTFS_DIR" -path '*/node_modules/*' -type d \
  \( -name test -o -name tests -o -name example -o -name examples -o -name doc -o -name docs \) \
  -prune -exec rm -rf {} +
run_root find "$ROOTFS_DIR" -path '*/node_modules/*' -type f \
  \( -name '*.test.ts' -o -name '*.test.js' -o -name '*.spec.ts' -o -name '*.spec.js' \) \
  -delete

run_root tee "$ROOTFS_DIR/etc/ciyuanxia-prebuilt-rootfs" >/dev/null <<EOF
format=ciyuanxia-prebuilt-rootfs
codename=$CODENAME
arch=$ROOTFS_ARCH
packages=${PACKAGES[*]}
node=$NODE_VERSION
npm_registry=$NPM_REGISTRY
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo "==> Packing $OUTPUT_PATH"
TMP_OUTPUT="$WORK_DIR/$OUTPUT_NAME"
run_root tar --numeric-owner -C "$ROOTFS_DIR" -czf "$TMP_OUTPUT" .
run_root chown "$(id -u):$(id -g)" "$TMP_OUTPUT"
mv "$TMP_OUTPUT" "$OUTPUT_PATH"

echo "==> Done: $OUTPUT_PATH"
