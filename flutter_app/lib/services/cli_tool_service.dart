import 'package:flutter/material.dart';

import '../models/cli_tool.dart';
import 'cli_api_config_service.dart';
import 'native_bridge.dart';

class CliToolService {
  static const _statusCacheTtl = Duration(seconds: 20);
  static List<CliToolStatus> _statusCache = const [];
  static DateTime? _statusCacheAt;

  static const shellTool = CliToolDefinition(
    id: 'shell',
    name: 'Ubuntu Shell',
    packageName: 'bash',
    executable: 'bash',
    description: '打开 Ubuntu 环境的交互式 Shell，适合执行系统命令和维护运行环境。',
    icon: Icons.terminal,
    color: Colors.blueGrey,
    installCommand: '',
    launchCommand: r'''
[ -r /root/.openclaw/cli-env.sh ] && . /root/.openclaw/cli-env.sh
mkdir -p "${OPENCLAW_CLI_WORKSPACE:-/root/openclaw-cli-workspace}" "${OPENCLAW_CLI_PROJECTS:-/root/openclaw-cli-workspace/projects}" "${OPENCLAW_CLI_SCRATCH:-/root/openclaw-cli-workspace/scratch}" 2>/dev/null || true
cd "${OPENCLAW_CLI_WORKSPACE:-/root/openclaw-cli-workspace}" 2>/dev/null || cd /root
exec bash -li
''',
    versionCommand: 'bash --version | head -n 1',
  );

  static const codexTool = CliToolDefinition(
    id: 'codex',
    name: 'OpenAI Codex CLI',
    packageName: '@openai/codex',
    executable: 'codex',
    description: 'OpenAI 官方代码智能体 CLI，适合代码修改、仓库分析和自动化开发任务。',
    icon: Icons.auto_awesome,
    color: Colors.green,
    installCommand: _codexInstallCommand,
    launchCommand: 'exec /usr/local/bin/codex --openclaw-cli-mode',
    versionCommand: '/usr/local/bin/codex --version',
  );

  static const codeBuddyTool = CliToolDefinition(
    id: 'codebuddy',
    name: 'CodeBuddy CLI',
    packageName: '@tencent-ai/codebuddy-code',
    executable: 'codebuddy',
    description: '腾讯云 CodeBuddy 命令行编码助手，支持在终端中通过自然语言协作开发。',
    icon: Icons.assistant,
    color: Colors.lightBlue,
    installCommand: _codeBuddyInstallCommand,
    launchCommand: 'exec /usr/local/bin/codebuddy',
    versionCommand: '/usr/local/bin/codebuddy --version',
  );

  static const qwenTool = CliToolDefinition(
    id: 'qwen-code',
    name: 'Qwen Code CLI',
    packageName: '@qwen-code/qwen-code',
    executable: 'qwen',
    description: '通义千问开源代码智能体，支持 OpenAI、Anthropic、Gemini、Qwen 等多协议模型。',
    icon: Icons.hub,
    color: Colors.orange,
    installCommand: _qwenInstallCommand,
    launchCommand: 'exec /usr/local/bin/qwen',
    versionCommand: '/usr/local/bin/qwen --version',
  );

  static const hermesTool = CliToolDefinition(
    id: 'hermes-agent',
    name: 'Hermes Agent',
    packageName: 'hermes-agent',
    executable: 'hermes',
    description: 'Nous Research 官方 Hermes Agent CLI，支持在终端内进行多步开发协作，并复用统一 API 配置。',
    icon: Icons.bolt,
    color: Colors.amber,
    installCommand: _hermesInstallCommand,
    launchCommand: 'exec /usr/local/bin/hermes',
    versionCommand: '/usr/local/bin/hermes --version',
  );

  static const genericTool = CliToolDefinition(
    id: 'generic-agent',
    name: 'Gen CLI (Generic Agent)',
    packageName: '@gen-cli/gen-cli',
    executable: 'generic-agent',
    description: '官方 Gen CLI，优先走原生 Gemini 或 SiliconFlow 模式；遇到 OpenAI 兼容接口时自动切换到内置兼容桥。',
    icon: Icons.smart_toy,
    color: Colors.teal,
    installCommand: _genericInstallCommand,
    launchCommand: 'exec /usr/local/bin/generic-agent',
    versionCommand: '/usr/local/bin/generic-agent --version',
  );

  static const geminiTool = CliToolDefinition(
    id: 'gemini',
    name: 'Gemini CLI',
    packageName: '@google/gemini-cli',
    executable: 'gemini',
    description: 'Google Gemini 命令行工具。若使用第三方 OpenAI 兼容模型，会通过统一配置写入兼容环境变量。',
    icon: Icons.diamond,
    color: Colors.indigo,
    installCommand: _geminiInstallCommand,
    launchCommand: 'exec /usr/local/bin/gemini',
    versionCommand: '/usr/local/bin/gemini --version',
  );

  static const allTools = [
    shellTool,
    codexTool,
    codeBuddyTool,
    qwenTool,
    hermesTool,
    genericTool,
    geminiTool,
  ];

  static const _commonInstallPrefix = r'''
set -eu
export npm_config_audit=false
export npm_config_fund=false
export npm_config_progress=false
export npm_config_update_notifier=false
export npm_config_foreground_scripts=true
export npm_config_loglevel=notice
export npm_config_cache=/tmp/npm-cache
export npm_config_registry=https://registry.npmmirror.com
export NODE_OPTIONS="${NODE_OPTIONS:---require /root/.openclaw/bionic-bypass.js}"
export NODE_EXTRA_CA_CERTS="${NODE_EXTRA_CA_CERTS:-/etc/ssl/certs/ca-certificates.crt}"
export DEBIAN_FRONTEND=noninteractive
export TMPDIR=/tmp

echo ">>> Architecture: $(uname -m)"
echo ">>> Node: $(node --version 2>/dev/null || echo missing)"
echo ">>> npm: $(npm --version 2>/dev/null || echo missing)"

if ! command -v node >/dev/null 2>&1 || ! command -v npm >/dev/null 2>&1; then
  echo "Node.js and npm are required. Run environment setup first." >&2
  exit 1
fi

if [ "$(uname -m)" != "aarch64" ] && [ "$(uname -m)" != "arm64" ]; then
  echo "This installer is intended for aarch64/arm64 Ubuntu rootfs." >&2
  exit 1
fi

export PIP_DISABLE_PIP_VERSION_CHECK=1
export PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
export PIP_TRUSTED_HOST=pypi.tuna.tsinghua.edu.cn

mkdir -p /root/.openclaw /root/.npm /tmp/npm-cache /tmp/npm-tmp /opt/openclaw-cli /usr/local/bin /usr/local/lib /root/.gen-cli
npm config set audit false --global >/dev/null 2>&1 || true
npm config set fund false --global >/dev/null 2>&1 || true
npm config set update-notifier false --global >/dev/null 2>&1 || true
npm config set registry https://registry.npmmirror.com --global >/dev/null 2>&1 || true

ensure_cli_workspace() {
  [ -r /root/.openclaw/cli-env.sh ] && . /root/.openclaw/cli-env.sh
  mkdir -p \
    "${OPENCLAW_CLI_WORKSPACE:-/root/openclaw-cli-workspace}" \
    "${OPENCLAW_CLI_PROJECTS:-/root/openclaw-cli-workspace/projects}" \
    "${OPENCLAW_CLI_SCRATCH:-/root/openclaw-cli-workspace/scratch}" \
    "${OPENCLAW_CLI_WORKSPACE:-/root/openclaw-cli-workspace}/.gemini" \
    "${OPENCLAW_CLI_WORKSPACE:-/root/openclaw-cli-workspace}/.gen-cli" \
    "${OPENCLAW_CLI_WORKSPACE:-/root/openclaw-cli-workspace}/.agents/skills" \
    2>/dev/null || true
}

install_cli_package() {
  tool_id="$1"
  package_name="$2"
  bin_name="$3"
  target_dir="/opt/openclaw-cli/$tool_id"
  staging_dir="$target_dir.tmp"
  previous_dir="$target_dir.prev"

  rm -rf "$staging_dir" "$previous_dir"
  mkdir -p "$staging_dir"

  npm install \
    --prefix "$staging_dir" \
    --include=optional \
    "$package_name@latest"

  if [ -d "$target_dir" ]; then
    mv "$target_dir" "$previous_dir"
  fi
  mv "$staging_dir" "$target_dir"
  rm -rf "$previous_dir"
  rm -f "/usr/local/bin/$bin_name"
}

resolve_node_entry() {
  tool_id="$1"
  package_name="$2"
  bin_key="$3"
  node -e 'const path=require("node:path"); const toolId=process.argv[1]; const packageName=process.argv[2]; const binKey=process.argv[3]; const pkg=require(`/opt/openclaw-cli/${toolId}/node_modules/${packageName}/package.json`); const entry=(pkg.bin && (typeof pkg.bin === "string" ? pkg.bin : pkg.bin[binKey])) || pkg.main || "dist/index.js"; process.stdout.write(path.isAbsolute(entry) ? entry : `/opt/openclaw-cli/${toolId}/node_modules/${packageName}/${entry}`);' "$tool_id" "$package_name" "$bin_key"
}

write_cli_theme() {
  cat > /root/.openclaw/terminal-theme.sh <<'OPENCLAW_TERMINAL_THEME'
export TERM="${TERM:-xterm-256color}"
export COLORTERM="${COLORTERM:-truecolor}"
export FORCE_COLOR=1
export CLICOLOR=1
export LS_COLORS="${LS_COLORS:-di=01;34:ln=01;36:so=01;35:pi=33:ex=01;32:bd=34;46:cd=34;43:su=37;41:sg=30;43:tw=30;42:ow=34;42}"
alias ls='ls --color=auto'
alias grep='grep --color=auto'
alias egrep='egrep --color=auto'
alias fgrep='fgrep --color=auto'
bind 'set colored-stats on' 2>/dev/null || true
bind 'set colored-completion-prefix on' 2>/dev/null || true
export PS1='\[\e[1;32m\]\u@\h\[\e[0m\]:\[\e[1;34m\]\w\[\e[0m\]\$ '
OPENCLAW_TERMINAL_THEME
  grep -q 'openclaw/terminal-theme.sh' /root/.bashrc 2>/dev/null || {
    printf '\n[ -r /root/.openclaw/terminal-theme.sh ] && . /root/.openclaw/terminal-theme.sh\n' >> /root/.bashrc
  }
}

write_wrapper_header() {
  cat <<'OPENCLAW_WRAPPER_HEADER'
export NODE_OPTIONS="${NODE_OPTIONS:---require /root/.openclaw/bionic-bypass.js}"
export NODE_EXTRA_CA_CERTS="${NODE_EXTRA_CA_CERTS:-/etc/ssl/certs/ca-certificates.crt}"
export TMPDIR="${TMPDIR:-/tmp}"
[ -r /root/.openclaw/terminal-theme.sh ] && . /root/.openclaw/terminal-theme.sh
[ -r /root/.openclaw/cli-env.sh ] && . /root/.openclaw/cli-env.sh
mkdir -p \
  "${OPENCLAW_CLI_WORKSPACE:-/root/openclaw-cli-workspace}" \
  "${OPENCLAW_CLI_PROJECTS:-/root/openclaw-cli-workspace/projects}" \
  "${OPENCLAW_CLI_SCRATCH:-/root/openclaw-cli-workspace/scratch}" \
  "${OPENCLAW_CLI_WORKSPACE:-/root/openclaw-cli-workspace}/.gemini" \
  "${OPENCLAW_CLI_WORKSPACE:-/root/openclaw-cli-workspace}/.gen-cli" \
  "${OPENCLAW_CLI_WORKSPACE:-/root/openclaw-cli-workspace}/.agents/skills" \
  2>/dev/null || true
cd "${OPENCLAW_CLI_WORKSPACE:-/root/openclaw-cli-workspace}" 2>/dev/null || cd /root
OPENCLAW_WRAPPER_HEADER
}

write_node_wrapper() {
  target="$1"
  bin_name="$2"
  real_js="$3"
  cat > "/usr/local/bin/$bin_name" <<OPENCLAW_NODE_WRAPPER
#!/bin/sh
$(write_wrapper_header)
[ -r /root/.openclaw/cli-env-$target.sh ] && . /root/.openclaw/cli-env-$target.sh
openclaw_skip_model_injection=false
case "\${1:-}" in
  --version|-v|-V|version|help|--help|-h)
    openclaw_skip_model_injection=true
    ;;
esac
case "$target" in
  codebuddy)
    if [ "\$openclaw_skip_model_injection" != true ] && [ -n "\${OPENCLAW_MODEL:-}" ]; then
      set -- --model "\$OPENCLAW_MODEL" "\$@"
    fi
    ;;
  qwen-code)
    if [ "\$openclaw_skip_model_injection" != true ] && [ -n "\${OPENCLAW_MODEL:-}" ]; then
      set -- --model "\$OPENCLAW_MODEL" "\$@"
    fi
    ;;
  gemini)
    if [ "\$openclaw_skip_model_injection" != true ] && [ "\${OPENCLAW_API_PROTOCOL:-gemini}" != "gemini" ]; then
      if [ -x /usr/local/bin/gemini-openai-agent ]; then
        exec /usr/local/bin/gemini-openai-agent "\$@"
      fi
      echo "Gemini CLI only supports Gemini protocol directly. Reinstall Gemini CLI to enable the OpenAI-compatible fallback agent, or switch this tool's API protocol to Gemini." >&2
      exit 2
    fi
    if [ "\$openclaw_skip_model_injection" != true ] && [ -n "\${OPENCLAW_MODEL:-}" ]; then
      set -- --model "\$OPENCLAW_MODEL" "\$@"
    fi
    ;;
esac
exec node "$real_js" "\$@"
OPENCLAW_NODE_WRAPPER
  chmod 0755 "/usr/local/bin/$bin_name"
}

write_openai_compatible_agent() {
  bin_name="$1"
  env_tool_id="$2"
  display_name="$3"
  script_path="/usr/local/lib/openclaw-cli-$bin_name.js"
  cat > "$script_path" <<'OPENCLAW_OPENAI_BRIDGE'
#!/usr/bin/env node
const readline = require("readline");

const displayName = process.env.OPENCLAW_TOOL_NAME || "OpenClaw OpenAI Bridge";
const version = process.env.OPENCLAW_BRIDGE_VERSION || "1.0.0";

if (process.argv.includes("--version") || process.argv.includes("-v")) {
  console.log(`${displayName} ${version}`);
  process.exit(0);
}

function env(name, fallback = "") {
  return process.env[name] || fallback;
}

const baseUrl = env("OPENAI_BASE_URL").replace(/\/+$/, "");
const apiKey = env("OPENAI_API_KEY");
const model = env("OPENAI_MODEL") || env("OPENCLAW_MODEL") || "gpt-4o-mini";
const reasoningEffort = env("OPENAI_REASONING_EFFORT") || "";

if (!baseUrl || !apiKey) {
  console.error(`${displayName} 未配置 API。请回到 CLI Tools 页面点击“配置”，填写 API 地址和 Key。`);
  process.exit(2);
}

const rl = readline.createInterface({
  input: process.stdin,
  output: process.stdout,
  prompt: `${displayName}> `,
});

const messages = [
  {
    role: "system",
    content: `${displayName} runs inside Ubuntu hosted by an Android app through PRoot. Default workspace: ${env("OPENCLAW_CLI_WORKSPACE", "/root/openclaw-cli-workspace")}. Prefer ./projects for real projects and ./scratch for temporary work. Reply concisely and help with coding or shell tasks.`,
  },
];

function chatUrl() {
  if (baseUrl.endsWith("/v1")) return `${baseUrl}/chat/completions`;
  return `${baseUrl}/v1/chat/completions`;
}

async function ask(content) {
  messages.push({ role: "user", content });
  const body = {
    model,
    messages,
    stream: false,
  };
  if (reasoningEffort) body.reasoning_effort = reasoningEffort;
  const response = await fetch(chatUrl(), {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`HTTP ${response.status}: ${text.slice(0, 800)}`);
  }
  const json = JSON.parse(text);
  const answer = json.choices?.[0]?.message?.content || "";
  messages.push({ role: "assistant", content: answer });
  return answer;
}

console.log(`${displayName} ${version}`);
console.log(`模型: ${model}`);
console.log("输入 /exit 退出，/clear 清空上下文。");
rl.prompt();
rl.on("line", async (line) => {
  const text = line.trim();
  if (!text) {
    rl.prompt();
    return;
  }
  if (text === "/exit" || text === "exit" || text === "quit") {
    rl.close();
    return;
  }
  if (text === "/clear") {
    messages.splice(1);
    console.log("上下文已清空。");
    rl.prompt();
    return;
  }
  try {
    const answer = await ask(text);
    console.log(`\n${answer}\n`);
  } catch (error) {
    console.error(`请求失败: ${error.message || error}`);
  }
  rl.prompt();
});
OPENCLAW_OPENAI_BRIDGE
  sed -i "s/OpenClaw OpenAI Bridge/$display_name/g" "$script_path"
  chmod 0755 "$script_path"
  cat > "/usr/local/bin/$bin_name" <<OPENCLAW_OPENAI_BRIDGE_WRAPPER
#!/bin/sh
$(write_wrapper_header)
[ -r /root/.openclaw/cli-env-$env_tool_id.sh ] && . /root/.openclaw/cli-env-$env_tool_id.sh
export OPENCLAW_TOOL_NAME="$display_name"
exec node "$script_path" "\$@"
OPENCLAW_OPENAI_BRIDGE_WRAPPER
  chmod 0755 "/usr/local/bin/$bin_name"
}

write_gen_wrapper() {
  real_js="$1"
  cat > /usr/local/bin/generic-agent <<OPENCLAW_GEN_WRAPPER
#!/bin/sh
$(write_wrapper_header)
[ -r /root/.openclaw/cli-env-generic-agent.sh ] && . /root/.openclaw/cli-env-generic-agent.sh
openclaw_skip_model_injection=false
case "\${1:-}" in
  --version|-v|-V|version|help|--help|-h)
    openclaw_skip_model_injection=true
    ;;
esac
openclaw_use_official_gen=false
if [ -z "\${OPENCLAW_API_PROTOCOL:-}" ] || [ "\${OPENCLAW_API_PROTOCOL:-openai}" = "gemini" ] || [ "\${GEMINI_DEFAULT_AUTH_TYPE:-}" = "siliconflow-api-key" ]; then
  openclaw_use_official_gen=true
fi
if [ "\$openclaw_use_official_gen" != true ] && [ "\$openclaw_skip_model_injection" != true ]; then
  if [ -x /usr/local/bin/generic-agent-openai ]; then
    exec /usr/local/bin/generic-agent-openai "\$@"
  fi
  echo "Gen CLI 当前仅直接支持 Gemini API Key 或 SiliconFlow 模式。当前配置会自动走 OpenAI 兼容桥，但兼容桥缺失。" >&2
  exit 2
fi
if [ "\$openclaw_skip_model_injection" != true ] && [ -n "\${OPENCLAW_MODEL:-}" ]; then
  set -- --model "\$OPENCLAW_MODEL" "\$@"
fi
exec node "$real_js" "\$@"
OPENCLAW_GEN_WRAPPER
  chmod 0755 /usr/local/bin/generic-agent
  ln -sf /usr/local/bin/generic-agent /usr/local/bin/gen
}

write_hermes_wrapper() {
  cat > /usr/local/bin/hermes <<'OPENCLAW_HERMES_WRAPPER'
#!/bin/sh
export NODE_EXTRA_CA_CERTS="${NODE_EXTRA_CA_CERTS:-/etc/ssl/certs/ca-certificates.crt}"
export TMPDIR="${TMPDIR:-/tmp}"
[ -r /root/.openclaw/terminal-theme.sh ] && . /root/.openclaw/terminal-theme.sh
[ -r /root/.openclaw/cli-env.sh ] && . /root/.openclaw/cli-env.sh
[ -r /root/.openclaw/cli-env-hermes-agent.sh ] && . /root/.openclaw/cli-env-hermes-agent.sh
if [ -r /root/.hermes/.env ]; then
  set -a
  . /root/.hermes/.env
  set +a
fi
mkdir -p \
  "${OPENCLAW_CLI_WORKSPACE:-/root/openclaw-cli-workspace}" \
  "${OPENCLAW_CLI_PROJECTS:-/root/openclaw-cli-workspace/projects}" \
  "${OPENCLAW_CLI_SCRATCH:-/root/openclaw-cli-workspace/scratch}" \
  "${OPENCLAW_CLI_WORKSPACE:-/root/openclaw-cli-workspace}/.gemini" \
  "${OPENCLAW_CLI_WORKSPACE:-/root/openclaw-cli-workspace}/.gen-cli" \
  "${OPENCLAW_CLI_WORKSPACE:-/root/openclaw-cli-workspace}/.agents/skills" \
  2>/dev/null || true
cd "${OPENCLAW_CLI_WORKSPACE:-/root/openclaw-cli-workspace}" 2>/dev/null || cd /root
exec /opt/openclaw-cli/hermes-agent/venv/bin/hermes "$@"
OPENCLAW_HERMES_WRAPPER
  chmod 0755 /usr/local/bin/hermes
}

write_cli_theme
ensure_cli_workspace
''';

  static const _codexInstallCommand = _commonInstallPrefix +
      r'''
echo ">>> Installing OpenAI Codex CLI from npm..."
install_cli_package codex @openai/codex codex
cat > /usr/local/bin/codex <<'OPENCLAW_CODEX_WRAPPER'
#!/bin/sh
export NODE_OPTIONS="${NODE_OPTIONS:---require /root/.openclaw/bionic-bypass.js}"
export NODE_EXTRA_CA_CERTS="${NODE_EXTRA_CA_CERTS:-/etc/ssl/certs/ca-certificates.crt}"
export TMPDIR="${TMPDIR:-/tmp}"
[ -r /root/.openclaw/terminal-theme.sh ] && . /root/.openclaw/terminal-theme.sh
[ -r /root/.openclaw/cli-env.sh ] && . /root/.openclaw/cli-env.sh
[ -r /root/.openclaw/cli-env-codex.sh ] && . /root/.openclaw/cli-env-codex.sh
mkdir -p \
  "${OPENCLAW_CLI_WORKSPACE:-/root/openclaw-cli-workspace}" \
  "${OPENCLAW_CLI_PROJECTS:-/root/openclaw-cli-workspace/projects}" \
  "${OPENCLAW_CLI_SCRATCH:-/root/openclaw-cli-workspace/scratch}" \
  "${OPENCLAW_CLI_WORKSPACE:-/root/openclaw-cli-workspace}/.gemini" \
  "${OPENCLAW_CLI_WORKSPACE:-/root/openclaw-cli-workspace}/.gen-cli" \
  "${OPENCLAW_CLI_WORKSPACE:-/root/openclaw-cli-workspace}/.agents/skills" \
  2>/dev/null || true
cd "${OPENCLAW_CLI_WORKSPACE:-/root/openclaw-cli-workspace}" 2>/dev/null || cd /root
openclaw_managed_auth=false
openclaw_toml_quote() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}
if [ -r /root/.openclaw/codex-proxy.env ] && grep -q '^OPENCLAW_CODEX_PROXY_ENABLED=1$' /root/.openclaw/codex-proxy.env 2>/dev/null; then
  openclaw_managed_auth=true
  pkill -f "/root/.openclaw/codex-proxy.py" >/dev/null 2>&1 || true
  pkill -f "/root/.openclaw/codex-proxy.js" >/dev/null 2>&1 || true
  if command -v python3 >/dev/null 2>&1 && [ -r /root/.openclaw/codex-proxy.py ]; then
    nohup python3 /root/.openclaw/codex-proxy.py >/tmp/openclaw-codex-proxy.log 2>&1 &
  elif command -v node >/dev/null 2>&1 && [ -r /root/.openclaw/codex-proxy.js ]; then
    nohup node /root/.openclaw/codex-proxy.js >/tmp/openclaw-codex-proxy.log 2>&1 &
  fi
  sleep 0.5
fi

openclaw_passthrough=false
openclaw_has_sandbox_arg=false
openclaw_has_no_alt_screen=false
openclaw_cli_mode=false
if [ "${1:-}" = "--openclaw-cli-mode" ]; then
  openclaw_cli_mode=true
  shift
fi
for arg in "$@"; do
  case "$arg" in
    --help|-h|--version|-V|version|help|login|logout|mcp|plugin|update|doctor|completion|sandbox|debug|apply|resume|archive|delete|unarchive|fork|cloud|features)
      openclaw_passthrough=true
      ;;
    --sandbox|-s|--ask-for-approval|-a|--dangerously-bypass-approvals-and-sandbox)
      openclaw_has_sandbox_arg=true
      ;;
    --no-alt-screen)
      openclaw_has_no_alt_screen=true
      ;;
  esac
done
if [ "$openclaw_passthrough" != true ] && [ "$openclaw_has_sandbox_arg" != true ]; then
  set -- --dangerously-bypass-approvals-and-sandbox "$@"
fi
if [ "$openclaw_passthrough" != true ] && [ "$openclaw_cli_mode" = true ] && [ "$openclaw_has_no_alt_screen" != true ]; then
  set -- --no-alt-screen "$@"
fi
if [ "$openclaw_passthrough" != true ] && [ "$openclaw_managed_auth" = true ]; then
  set -- -c 'preferred_auth_method="apikey"' "$@"
  set -- -c 'model_provider="openclaw"' "$@"
  set -- -c 'model_providers.openclaw.name="OpenClaw"' "$@"
  set -- -c 'model_providers.openclaw.base_url="http://127.0.0.1:8787/v1"' "$@"
  set -- -c 'model_providers.openclaw.wire_api="responses"' "$@"
  set -- -c 'model_providers.openclaw.env_key="OPENAI_API_KEY"' "$@"
  if [ -n "${OPENAI_MODEL:-}" ]; then
    openclaw_model="$(openclaw_toml_quote "$OPENAI_MODEL")"
    set -- -c "model=\"$openclaw_model\"" "$@"
  fi
  if [ -n "${OPENAI_REASONING_EFFORT:-}" ]; then
    openclaw_effort="$(openclaw_toml_quote "$OPENAI_REASONING_EFFORT")"
    set -- -c "model_reasoning_effort=\"$openclaw_effort\"" "$@"
  fi
fi
exec node /opt/openclaw-cli/codex/node_modules/@openai/codex/bin/codex.js "$@"
OPENCLAW_CODEX_WRAPPER
chmod 0755 /usr/local/bin/codex
hash -r
/usr/local/bin/codex --version
echo ">>> CODEX_CLI_INSTALL_COMPLETE"
''';

  static const _codeBuddyInstallCommand = _commonInstallPrefix +
      r'''
echo ">>> Installing CodeBuddy CLI from npm..."
install_cli_package codebuddy @tencent-ai/codebuddy-code codebuddy
write_node_wrapper codebuddy codebuddy /opt/openclaw-cli/codebuddy/node_modules/@tencent-ai/codebuddy-code/bin/codebuddy
if [ -d /opt/openclaw-cli/codebuddy/node_modules/@tencent-ai/codebuddy-code/dist ]; then
  DIST_DIR=/opt/openclaw-cli/codebuddy/node_modules/@tencent-ai/codebuddy-code/dist
  for f in "$DIST_DIR"/codebuddy.js "$DIST_DIR"/codebuddy-headless.js; do
    [ -f "$f" ] || continue
    sed -i 's#this.DEFAULT_OUTPUT_DIR="/tmp/codebuddy/tasks"#this.DEFAULT_OUTPUT_DIR=(process.env.TMPDIR||"/tmp")+"/codebuddy/tasks"#g' "$f" || true
  done
fi
ln -sf /usr/local/bin/codebuddy /usr/local/bin/cbc
hash -r
/usr/local/bin/codebuddy --version || true
echo ">>> CODEBUDDY_CLI_INSTALL_COMPLETE"
''';

  static const _qwenInstallCommand = _commonInstallPrefix +
      r'''
echo ">>> Installing Qwen Code CLI from npm..."
install_cli_package qwen-code @qwen-code/qwen-code qwen
write_node_wrapper qwen-code qwen /opt/openclaw-cli/qwen-code/node_modules/@qwen-code/qwen-code/cli-entry.js
hash -r
/usr/local/bin/qwen --version || true
echo ">>> QWEN_CODE_CLI_INSTALL_COMPLETE"
''';

  static const _geminiInstallCommand = _commonInstallPrefix +
      r'''
echo ">>> Installing Gemini CLI from npm..."
install_cli_package gemini @google/gemini-cli gemini
GEMINI_REAL="$(resolve_node_entry gemini @google/gemini-cli gemini)"
if [ ! -f "$GEMINI_REAL" ]; then
  echo "Gemini CLI entrypoint not found: $GEMINI_REAL" >&2
  find /opt/openclaw-cli/gemini/node_modules/@google/gemini-cli -maxdepth 3 -type f 2>/dev/null | sort >&2 || true
  exit 1
fi
write_node_wrapper gemini gemini "$GEMINI_REAL"
write_openai_compatible_agent gemini-openai-agent gemini "Gemini OpenAI Bridge"
hash -r
/usr/local/bin/gemini --version || true
echo ">>> GEMINI_CLI_INSTALL_COMPLETE"
''';

  static const _hermesInstallCommand = _commonInstallPrefix +
      r'''
echo ">>> Installing Hermes Agent from PyPI..."
if ! command -v python3 >/dev/null 2>&1; then
  echo "python3 is required. Run environment setup first." >&2
  exit 1
fi
HERMES_TARGET=/opt/openclaw-cli/hermes-agent
HERMES_STAGING="$HERMES_TARGET.tmp"
HERMES_PREVIOUS="$HERMES_TARGET.prev"
rm -rf "$HERMES_STAGING" "$HERMES_PREVIOUS"
if ! python3 -m venv "$HERMES_STAGING/venv"; then
  apt-get update
  apt-get install -y python3-venv python3-pip
  python3 -m venv "$HERMES_STAGING/venv"
fi
"$HERMES_STAGING/venv/bin/python" -m pip install -U pip setuptools wheel
"$HERMES_STAGING/venv/bin/python" -m pip install -U hermes-agent
if [ -d "$HERMES_TARGET" ]; then
  mv "$HERMES_TARGET" "$HERMES_PREVIOUS"
fi
mv "$HERMES_STAGING" "$HERMES_TARGET"
rm -rf "$HERMES_PREVIOUS"
write_hermes_wrapper
hash -r
/usr/local/bin/hermes --version || true
echo ">>> HERMES_AGENT_INSTALL_COMPLETE"
''';

  static const _genericInstallCommand = _commonInstallPrefix +
      r'''
echo ">>> Installing Gen CLI from npm..."
install_cli_package generic-agent @gen-cli/gen-cli gen
GEN_REAL="$(resolve_node_entry generic-agent @gen-cli/gen-cli gen)"
if [ ! -f "$GEN_REAL" ]; then
  echo "Gen CLI entrypoint not found: $GEN_REAL" >&2
  find /opt/openclaw-cli/generic-agent/node_modules/@gen-cli/gen-cli -maxdepth 3 -type f 2>/dev/null | sort >&2 || true
  exit 1
fi
write_gen_wrapper "$GEN_REAL"
write_openai_compatible_agent generic-agent-openai generic-agent "Gen CLI OpenAI Bridge"
hash -r
/usr/local/bin/generic-agent --version || true
echo ">>> GENERIC_AGENT_INSTALL_COMPLETE"
''';

  static List<CliToolStatus> get cachedStatuses =>
      List<CliToolStatus>.unmodifiable(_statusCache);

  static Future<List<CliToolStatus>> checkAllStatuses({
    bool includeVersionDetails = true,
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        includeVersionDetails &&
        _statusCache.isNotEmpty &&
        _statusCacheAt != null &&
        DateTime.now().difference(_statusCacheAt!) <= _statusCacheTtl) {
      return cachedStatuses;
    }

    final statuses = await Future.wait(
      allTools.map(
        (tool) => checkStatus(
          tool,
          includeVersionDetails: includeVersionDetails,
        ),
      ),
    );
    final mergedStatuses = _mergeStatusesWithCache(statuses);
    _statusCache = mergedStatuses;
    _statusCacheAt = DateTime.now();
    return List<CliToolStatus>.unmodifiable(mergedStatuses);
  }

  static Future<CliToolStatus> checkStatus(
    CliToolDefinition tool, {
    bool includeVersionDetails = true,
  }) async {
    if (tool.id == shellTool.id) {
      return _checkShellStatus(includeVersionDetails: includeVersionDetails);
    }

    final command = includeVersionDetails
        ? '''
set +e
set -o pipefail
if command -v ${tool.executable} >/dev/null 2>&1; then
  version_output="\$(${tool.versionCommand} 2>&1 | head -n 1)"
  version_status=\$?
  if [ \$version_status -eq 0 ]; then
    echo "__OPENCLAW_CLI_INSTALLED__"
    echo "\$version_output"
  else
    echo "__OPENCLAW_CLI_BROKEN__"
    echo "\$version_output"
  fi
else
  echo "__OPENCLAW_CLI_NOT_INSTALLED__"
fi
'''
        : '''
set +e
if command -v ${tool.executable} >/dev/null 2>&1; then
  echo "__OPENCLAW_CLI_INSTALLED__"
else
  echo "__OPENCLAW_CLI_NOT_INSTALLED__"
fi
''';

    try {
      final output = await NativeBridge.runInProot(command, timeout: 30);
      final lines = output
          .split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      final installed = lines.contains('__OPENCLAW_CLI_INSTALLED__');
      final broken = lines.contains('__OPENCLAW_CLI_BROKEN__');
      final markerIndex =
          lines.indexWhere((line) => line.startsWith('__OPENCLAW_CLI_'));
      final cached = _cachedStatusFor(tool.id);
      final version = installed && includeVersionDetails
          ? lines
              .skip(markerIndex + 1)
              .firstWhere((line) => !line.startsWith('__'), orElse: () => '')
          : (cached?.version ?? '');
      final error = broken
          ? lines
              .skip(markerIndex + 1)
              .where((line) => !line.startsWith('__'))
              .join('\n')
          : null;
      return CliToolStatus(
        tool: tool,
        installed: installed,
        version: version.isEmpty ? null : version,
        error: error?.isEmpty == true ? null : error,
      );
    } catch (error) {
      return CliToolStatus(
        tool: tool,
        installed: false,
        error: error.toString(),
      );
    }
  }

  static Future<CliToolStatus> _checkShellStatus({
    bool includeVersionDetails = true,
  }) async {
    try {
      final version = includeVersionDetails
          ? (await NativeBridge.runInProot(
              'bash --version | head -n 1',
              timeout: 20,
            ))
              .split('\n')
              .map((line) => line.trim())
              .firstWhere((line) => line.isNotEmpty, orElse: () => 'bash')
          : (_cachedStatusFor(shellTool.id)?.version ?? 'bash');
      return CliToolStatus(
        tool: shellTool,
        installed: true,
        version: version,
      );
    } catch (error) {
      return CliToolStatus(
        tool: shellTool,
        installed: false,
        error: error.toString(),
      );
    }
  }

  static Future<void> prepareInstallAssets(CliToolDefinition _) async {
    await CliApiConfigService.regenerateRuntimeFiles();
  }

  static CliToolStatus? _cachedStatusFor(String toolId) {
    for (final status in _statusCache) {
      if (status.tool.id == toolId) {
        return status;
      }
    }
    return null;
  }

  static List<CliToolStatus> _mergeStatusesWithCache(
    List<CliToolStatus> statuses,
  ) {
    return statuses.map((status) {
      final cached = _cachedStatusFor(status.tool.id);
      return CliToolStatus(
        tool: status.tool,
        installed: status.installed,
        version: status.version ?? cached?.version,
        error: status.error,
      );
    }).toList(growable: false);
  }
}
