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
PACKAGES=(ca-certificates git python3 make g++ curl wget lsof)
NODE_VERSION="${NODE_VERSION:-24.15.0}"
OPENCLAW_VERSION="${OPENCLAW_VERSION:-latest}"
QQBOT_PACKAGE="${QQBOT_PACKAGE:-@tencent-connect/openclaw-qqbot@latest}"
WEIXIN_PACKAGE="${WEIXIN_PACKAGE:-@tencent-weixin/openclaw-weixin@latest}"
NPM_REGISTRY="${NPM_REGISTRY:-https://registry.npmmirror.com}"
NPM_DISTURL="${NPM_DISTURL:-https://npmmirror.com/mirrors/node}"

usage() {
  cat <<USAGE
Build an OpenClaw prebuilt Ubuntu rootfs archive.

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
  - The archive includes Ubuntu base packages, Node.js, OpenClaw, and the QQ/
    Weixin bot plugins so first run does not need slow npm/plugin installs.
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
    DEFAULT_MIRROR="http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports"
    ;;
  armhf)
    ROOTFS_ARCH="armhf"
    QEMU_BIN="qemu-arm-static"
    DEFAULT_MIRROR="http://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports"
    ;;
  amd64)
    ROOTFS_ARCH="amd64"
    QEMU_BIN="qemu-x86_64-static"
    DEFAULT_MIRROR="http://mirrors.tuna.tsinghua.edu.cn/ubuntu"
    ;;
  *)
    echo "Unsupported arch: $ARCH" >&2
    exit 2
    ;;
esac

MIRROR="${MIRROR:-$DEFAULT_MIRROR}"
BASE_NAME="ubuntu-base-${UBUNTU_VERSION}-base-${ROOTFS_ARCH}.tar.gz"
BASE_URLS=(
  "https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cdimage/ubuntu-base/releases/24.04/release/$BASE_NAME"
  "https://mirrors.ustc.edu.cn/ubuntu-cdimage/ubuntu-base/releases/24.04/release/$BASE_NAME"
  "https://mirrors.aliyun.com/ubuntu-cdimage/ubuntu-base/releases/24.04/release/$BASE_NAME"
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
    -e OPENCLAW_VERSION="$OPENCLAW_VERSION" \
    -e QQBOT_PACKAGE="$QQBOT_PACKAGE" \
    -e WEIXIN_PACKAGE="$WEIXIN_PACKAGE" \
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

echo "==> Building prebuilt rootfs: $OUTPUT_NAME"
echo "    Ubuntu base: ${BASE_URLS[0]}"
echo "    Mirror:      $MIRROR"

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
run_root tee "$ROOTFS_DIR/etc/apt/sources.list" >/dev/null <<EOF
deb $MIRROR $CODENAME main restricted universe multiverse
deb $MIRROR ${CODENAME}-updates main restricted universe multiverse
deb $MIRROR ${CODENAME}-backports main restricted universe multiverse
deb $MIRROR ${CODENAME}-security main restricted universe multiverse
EOF

run_root tee "$ROOTFS_DIR/etc/apt/apt.conf.d/01-openclaw-proot" >/dev/null <<'EOF'
APT::Sandbox::User "root";
Acquire::Languages "none";
Acquire::Retries "3";
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
chroot_run apt-get update
chroot_run apt-get install -y --no-install-recommends "${PACKAGES[@]}"

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
disturl=$NPM_DISTURL
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

OPENCLAW_SPEC="openclaw@$OPENCLAW_VERSION"
if [[ "$OPENCLAW_VERSION" == "latest" ]]; then
  OPENCLAW_SPEC="openclaw@latest"
fi

echo "==> Installing OpenClaw: $OPENCLAW_SPEC"
chroot_run bash -lc "npm_config_registry=$(shell_quote "$NPM_REGISTRY") NPM_CONFIG_REGISTRY=$(shell_quote "$NPM_REGISTRY") npm_config_disturl=$(shell_quote "$NPM_DISTURL") npm_config_audit=false npm_config_fund=false npm_config_progress=false npm_config_update_notifier=false npm_config_cache=/tmp/npm-cache TMPDIR=/tmp/npm-tmp npm install -g --omit=dev --force $(shell_quote "$OPENCLAW_SPEC")"
chroot_run openclaw --version

install_openclaw_plugin() {
  local package_spec="$1"
  local fallback_spec="$2"
  echo "==> Installing OpenClaw plugin: $package_spec"
  chroot_run bash -lc "export npm_config_registry=$(shell_quote "$NPM_REGISTRY"); export NPM_CONFIG_REGISTRY=$(shell_quote "$NPM_REGISTRY"); export npm_config_disturl=$(shell_quote "$NPM_DISTURL"); export npm_config_audit=false; export npm_config_fund=false; export npm_config_progress=false; export npm_config_update_notifier=false; export npm_config_cache=/tmp/npm-cache; export TMPDIR=/tmp/npm-tmp; openclaw plugins install $(shell_quote "$package_spec") || npm install -g --omit=dev --force $(shell_quote "$fallback_spec")"
}

repair_qqbot_plugin_runtime() {
  echo "==> Repairing QQBot plugin runtime metadata"
  chroot_run node <<'NODE'
const fs = require('fs');
const path = require('path');

const qqbotTools = ['qqbot_channel_api', 'qqbot_remind'];
const englishReply =
  'Something went wrong while processing your request. Please try again, or use /new to start a fresh session.';
const chineseReply =
  '⚠️ 处理请求时发生错误。请重试，或发送 /new 新建会话。也可能是当前 API 地址、Key、模型名或模型映射配置错误，请检查后重试。';
const packageRoots = new Set([
  '/usr/local/lib/node_modules/@tencent-connect/openclaw-qqbot',
  '/usr/lib/node_modules/@tencent-connect/openclaw-qqbot',
  '/root/.openclaw/node_modules/@tencent-connect/openclaw-qqbot',
  '/root/.openclaw/extensions/openclaw-qqbot',
]);

function addProjectRoots(baseDir) {
  if (!fs.existsSync(baseDir)) return;
  for (const entry of fs.readdirSync(baseDir, { withFileTypes: true })) {
    if (!entry.isDirectory()) continue;
    const candidate = path.join(
      baseDir,
      entry.name,
      'node_modules',
      '@tencent-connect',
      'openclaw-qqbot',
    );
    if (fs.existsSync(candidate)) {
      packageRoots.add(candidate);
    }
  }
}

function normalizeManifestLikeObject(target) {
  let changed = false;
  if (!Array.isArray(target.channels)) {
    target.channels = [];
    changed = true;
  }
  if (!target.channels.includes('qqbot')) {
    target.channels.push('qqbot');
    changed = true;
  }
  if (!target.channelConfigs || typeof target.channelConfigs !== 'object') {
    target.channelConfigs = {};
    changed = true;
  }
  const qqbotConfig =
    target.channelConfigs.qqbot && typeof target.channelConfigs.qqbot === 'object'
      ? target.channelConfigs.qqbot
      : {};
  const preferOver = Array.isArray(qqbotConfig.preferOver)
    ? qqbotConfig.preferOver.map(String).filter(Boolean)
    : [];
  if (!preferOver.includes('qqbot')) {
    preferOver.push('qqbot');
    changed = true;
  }
  qqbotConfig.preferOver = preferOver;
  target.channelConfigs.qqbot = qqbotConfig;
  if (!target.contracts || typeof target.contracts !== 'object') {
    target.contracts = {};
    changed = true;
  }
  const tools = Array.isArray(target.contracts.tools)
    ? target.contracts.tools.map(String).filter(Boolean)
    : [];
  for (const tool of qqbotTools) {
    if (!tools.includes(tool)) {
      tools.push(tool);
      changed = true;
    }
  }
  target.contracts.tools = tools;
  return changed;
}

function patchJsonFile(filePath, mutate) {
  if (!fs.existsSync(filePath)) return false;
  let json;
  try {
    json = JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (_) {
    return false;
  }
  const changed = mutate(json) === true;
  if (changed) {
    fs.writeFileSync(filePath, JSON.stringify(json, null, 2));
  }
  return changed;
}

function patchTextFile(filePath) {
  if (!fs.existsSync(filePath)) return false;
  let content;
  try {
    content = fs.readFileSync(filePath, 'utf8');
  } catch (_) {
    return false;
  }
  if (!content.includes(englishReply)) {
    return false;
  }
  fs.writeFileSync(filePath, content.split(englishReply).join(chineseReply));
  return true;
}

function patchGatewayFile(filePath) {
  if (!fs.existsSync(filePath)) return false;
  let content;
  try {
    content = fs.readFileSync(filePath, 'utf8');
  } catch (_) {
    return false;
  }

  let changed = false;

  const progressHelpersNeedle = `let timeoutId = null;
                        let toolOnlyTimeoutId = null;`;
  const progressHelpersReplacement = `let timeoutId = null;
                        let toolOnlyTimeoutId = null;
                        const progressReplyIntervalMs = 3000;
                        const maxProgressReplies = 3;
                        let progressReplyTimer = null;
                        let progressReplyCount = 0;
                        let progressReplySending = false;
                        let failureReplySent = false;
                        const stopProgressReplies = () => {
                            if (progressReplyTimer) {
                                clearInterval(progressReplyTimer);
                                progressReplyTimer = null;
                            }
                        };
                        const sendProgressReply = async () => {
                            if (hasBlockResponse || toolFallbackSent || failureReplySent || progressReplySending) {
                                return;
                            }
                            if (progressReplyCount >= maxProgressReplies) {
                                stopProgressReplies();
                                return;
                            }
                            progressReplySending = true;
                            try {
                                const progressText = progressReplyCount === 0
                                    ? '⏳ 正在生成中，请稍候...'
                                    : '⏳ 仍在生成中，请稍候...';
                                await sendErrorMessage(progressText);
                                progressReplyCount++;
                                if (progressReplyCount >= maxProgressReplies) {
                                    stopProgressReplies();
                                }
                            }
                            catch (progressErr) {
                                log?.error(\`[qqbot:\${account.accountId}] Failed to send progress reply: \${progressErr}\`);
                            }
                            finally {
                                progressReplySending = false;
                            }
                        };
                        const startProgressReplies = () => {
                            if (progressReplyTimer || maxProgressReplies <= 0) {
                                return;
                            }
                            progressReplyTimer = setInterval(() => {
                                void sendProgressReply();
                            }, progressReplyIntervalMs);
                        };
                        const sendFailureReply = async (errorText) => {
                            if (hasBlockResponse || toolFallbackSent || failureReplySent) {
                                return;
                            }
                            failureReplySent = true;
                            stopProgressReplies();
                            try {
                                await sendErrorMessage(errorText);
                            }
                            catch (sendErr) {
                                log?.error(\`[qqbot:\${account.accountId}] Failed to send failure reply: \${sendErr}\`);
                            }
                        };`;
  if (content.includes(progressHelpersNeedle) &&
      !content.includes("const progressReplyIntervalMs = 3000;")) {
    content = content.replace(progressHelpersNeedle, progressHelpersReplacement);
    changed = true;
  }

  const progressStartNeedle = `const dispatchPromise = pluginRuntime.channel.reply.dispatchReplyWithBufferedBlockDispatcher({`;
  if (content.includes(progressStartNeedle) &&
      !content.includes("startProgressReplies();\n                        const dispatchPromise =")) {
    content = content.replace(
      progressStartNeedle,
      `startProgressReplies();
                        const dispatchPromise = pluginRuntime.channel.reply.dispatchReplyWithBufferedBlockDispatcher({`,
    );
    changed = true;
  }

  const stopOnBlockNeedle = `typing.keepAlive?.stop();`;
  if (content.includes(stopOnBlockNeedle) &&
      !content.includes(`typing.keepAlive?.stop();
                                    stopProgressReplies();`)) {
    content = content.replace(
      stopOnBlockNeedle,
      `typing.keepAlive?.stop();
                                    stopProgressReplies();`,
    );
    changed = true;
  }

  const onErrorNeedle = `                                    if (errMsg.includes("401") || errMsg.includes("key") || errMsg.includes("auth")) {
                                        log?.error(\`[qqbot:\${account.accountId}] AI auth error: \${errMsg}\`);
                                    }
                                    else {
                                        log?.error(\`[qqbot:\${account.accountId}] AI process error: \${errMsg}\`);
                                    }`;
  const onErrorReplacement = `                                    if (errMsg.includes("401") || errMsg.includes("key") || errMsg.includes("auth")) {
                                        log?.error(\`[qqbot:\${account.accountId}] AI auth error: \${errMsg}\`);
                                        await sendFailureReply("⚠️ 本次生成失败，可能是 API 地址、Key、模型名或模型映射配置错误，请检查后重试。");
                                    }
                                    else {
                                        log?.error(\`[qqbot:\${account.accountId}] AI process error: \${errMsg}\`);
                                        await sendFailureReply("⚠️ 本次生成失败，未能返回结果。请重试，也可能是当前 API 地址、Key、模型名或模型映射配置错误。");
                                    }`;
  if (content.includes(onErrorNeedle) &&
      !content.includes("await sendFailureReply(\"⚠️ 本次生成失败")) {
    content = content.replace(onErrorNeedle, onErrorReplacement);
    changed = true;
  }

  const dispatchCatchNeedle = `                            log?.error(\`[qqbot:\${account.accountId}] Dispatch failed: \${err}\${!hasResponse ? " (no response received)" : ""}\`);
                        }
                        finally {`;
  const dispatchCatchReplacement = `                            log?.error(\`[qqbot:\${account.accountId}] Dispatch failed: \${err}\${!hasResponse ? " (no response received)" : ""}\`);
                            if (!hasBlockResponse && !toolFallbackSent) {
                                await sendFailureReply("⚠️ 本次生成超时或失败，未能返回结果。请重试，也可能是当前 API 地址、Key、模型名或模型映射配置错误。");
                            }
                        }
                        finally {
                            stopProgressReplies();`;
  if (content.includes(dispatchCatchNeedle) &&
      !content.includes('本次生成超时或失败，未能返回结果')) {
    content = content.replace(dispatchCatchNeedle, dispatchCatchReplacement);
    changed = true;
  }

  const outerCatchNeedle = `                        if (errStr.includes("Unable to resolve plugin runtime module") || errStr.includes("root-alias.cjs")) {
                            try {
                                await sendErrorMessage("⚠️ AI 服务暂时不可用：openclaw 框架运行时模块加载失败。\\n\\n请管理员执行：\\nnpm install -g openclaw@latest\\nopenclaw gateway restart\\n\\n斜杠命令（如 /bot-ping）不受影响。");
                            }
                            catch { /* best-effort */ }
                        }`;
  const outerCatchReplacement = `                        if (errStr.includes("Unable to resolve plugin runtime module") || errStr.includes("root-alias.cjs")) {
                            try {
                                await sendErrorMessage("⚠️ AI 服务暂时不可用：openclaw 框架运行时模块加载失败。\\n\\n请管理员执行：\\nnpm install -g openclaw@latest\\nopenclaw gateway restart\\n\\n斜杠命令（如 /bot-ping）不受影响。");
                            }
                            catch { /* best-effort */ }
                        }
                        else {
                            await sendFailureReply("⚠️ 本次生成失败，未能返回结果。请重试，也可能是当前 API 地址、Key、模型名或模型映射配置错误。");
                        }`;
  if (content.includes(outerCatchNeedle) &&
      !content.includes("else {\n                            await sendFailureReply")) {
    content = content.replace(outerCatchNeedle, outerCatchReplacement);
    changed = true;
  }

  const silentFinallyNeedle = `                            if (toolDeliverCount > 0 && !hasBlockResponse && !toolFallbackSent) {
                                toolFallbackSent = true;
                                log?.error(\`[qqbot:\${account.accountId}] Dispatch completed with \${toolDeliverCount} tool deliver(s) but no block deliver, sending fallback\`);
                                await sendToolFallback();
                            }
                            // 销毁 debouncer，flush 剩余缓冲的文本`;
  const silentFinallyReplacement = `                            if (toolDeliverCount > 0 && !hasBlockResponse && !toolFallbackSent) {
                                toolFallbackSent = true;
                                log?.error(\`[qqbot:\${account.accountId}] Dispatch completed with \${toolDeliverCount} tool deliver(s) but no block deliver, sending fallback\`);
                                await sendToolFallback();
                            }
                            if (!hasBlockResponse && !toolFallbackSent && !failureReplySent) {
                                await sendFailureReply("⚠️ 本次生成结束时没有返回任何可发送内容，请重试，也可能是当前 API 地址、Key、模型名或模型映射配置错误。");
                            }
                            // 销毁 debouncer，flush 剩余缓冲的文本`;
  if (content.includes(silentFinallyNeedle) &&
      !content.includes('本次生成结束时没有返回任何可发送内容')) {
    content = content.replace(silentFinallyNeedle, silentFinallyReplacement);
    changed = true;
  }

  if (!changed) return false;
  fs.writeFileSync(filePath, content);
  return true;
}

function walkAndPatchText(rootDir) {
  const stack = [rootDir];
  while (stack.length > 0) {
    const current = stack.pop();
    let entries = [];
    try {
      entries = fs.readdirSync(current, { withFileTypes: true });
    } catch (_) {
      continue;
    }
    for (const entry of entries) {
      const fullPath = path.join(current, entry.name);
      if (entry.isDirectory()) {
        stack.push(fullPath);
        continue;
      }
      if (!/\.(?:cjs|mjs|js|json)$/i.test(entry.name)) {
        continue;
      }
      patchTextFile(fullPath);
      if (entry.name === 'gateway.js') {
        patchGatewayFile(fullPath);
      }
    }
  }
}

addProjectRoots('/root/.openclaw/npm/projects');
addProjectRoots('/root/.openclaw/extensions');

for (const rootDir of packageRoots) {
  if (!fs.existsSync(rootDir)) continue;
  patchJsonFile(path.join(rootDir, 'openclaw.plugin.json'), (json) =>
    normalizeManifestLikeObject(json),
  );
  patchJsonFile(path.join(rootDir, 'package.json'), (json) => {
    if (!json.openclaw || typeof json.openclaw !== 'object') {
      json.openclaw = {};
    }
    return normalizeManifestLikeObject(json.openclaw);
  });
  walkAndPatchText(rootDir);
}
NODE
}

install_openclaw_plugin "$QQBOT_PACKAGE" "@tencent-connect/openclaw-qqbot"
repair_qqbot_plugin_runtime
install_openclaw_plugin "$WEIXIN_PACKAGE" "@tencent-weixin/openclaw-weixin"

echo "==> Enabling bundled messaging plugins"
chroot_run node <<'NODE'
const fs = require('fs');
const path = require('path');
const configPath = '/root/.openclaw/openclaw.json';
let config = {};
try {
  config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
} catch (_) {}
config.plugins = config.plugins && typeof config.plugins === 'object' ? config.plugins : {};
config.plugins.entries = config.plugins.entries && typeof config.plugins.entries === 'object'
  ? config.plugins.entries
  : {};
for (const alias of [
  'qqbot',
  '@tencent-connect/openclaw-qqbot',
  'weixin',
  '@tencent/openclaw-weixin',
  '@tencent-weixin/openclaw-weixin',
]) {
  delete config.plugins.entries[alias];
}
config.plugins.entries['openclaw-qqbot'] = {
  ...(config.plugins.entries['openclaw-qqbot'] || {}),
  enabled: true,
};
config.plugins.entries['openclaw-weixin'] = {
  ...(config.plugins.entries['openclaw-weixin'] || {}),
  enabled: true,
};
fs.mkdirSync(path.dirname(configPath), { recursive: true });
fs.writeFileSync(configPath, JSON.stringify(config, null, 2));
NODE

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
  "$ROOTFS_DIR/root/.npm/_logs" \
  "$ROOTFS_DIR/root/.cache" \
  "$ROOTFS_DIR/tmp/npm-cache" \
  "$ROOTFS_DIR/tmp/npm-tmp" \
  "$ROOTFS_DIR/tmp/"* \
  "$ROOTFS_DIR/var/tmp/"*

run_root tee "$ROOTFS_DIR/etc/openclaw-prebuilt-rootfs" >/dev/null <<EOF
format=openclaw-prebuilt-rootfs
codename=$CODENAME
arch=$ROOTFS_ARCH
packages=${PACKAGES[*]}
node=$NODE_VERSION
openclaw=$OPENCLAW_VERSION
qqbot=$QQBOT_PACKAGE
weixin=$WEIXIN_PACKAGE
npm_registry=$NPM_REGISTRY
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
EOF

echo "==> Packing $OUTPUT_PATH"
TMP_OUTPUT="$WORK_DIR/$OUTPUT_NAME"
run_root tar --numeric-owner -C "$ROOTFS_DIR" -czf "$TMP_OUTPUT" .
run_root chown "$(id -u):$(id -g)" "$TMP_OUTPUT"
mv "$TMP_OUTPUT" "$OUTPUT_PATH"

echo "==> Done: $OUTPUT_PATH"
