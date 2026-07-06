import 'package:flutter/material.dart';

import '../models/cli_tool.dart';
import 'native_bridge.dart';

class CliToolService {
  static const shellTool = CliToolDefinition(
    id: 'shell',
    name: 'Ubuntu Shell',
    packageName: 'bash',
    executable: 'bash',
    description: '打开 Ubuntu 环境的交互式 Shell，适合执行系统命令和维护运行环境。',
    icon: Icons.terminal,
    color: Colors.blueGrey,
    installCommand: '',
    launchCommand: '',
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
    launchCommand: r'''
[ -r /root/.openclaw/cli-env.sh ] && . /root/.openclaw/cli-env.sh
[ -r /root/.openclaw/cli-env-codebuddy.sh ] && . /root/.openclaw/cli-env-codebuddy.sh
if [ -n "${OPENCLAW_MODEL:-}" ]; then
  exec /usr/local/bin/codebuddy --model "$OPENCLAW_MODEL"
fi
exec /usr/local/bin/codebuddy
''',
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
    launchCommand: r'''
[ -r /root/.openclaw/cli-env.sh ] && . /root/.openclaw/cli-env.sh
[ -r /root/.openclaw/cli-env-qwen-code.sh ] && . /root/.openclaw/cli-env-qwen-code.sh
if [ -n "${OPENCLAW_MODEL:-}" ]; then
  exec /usr/local/bin/qwen --model "$OPENCLAW_MODEL"
fi
exec /usr/local/bin/qwen
''',
    versionCommand: '/usr/local/bin/qwen --version',
  );

  static const hermesTool = CliToolDefinition(
    id: 'hermes-agent',
    name: 'Hermes Agent',
    packageName: 'openclaw-hermes-agent',
    executable: 'hermes',
    description: '内置轻量级终端 Agent，面向快速问答、代码解释和命令行任务规划，使用统一 API 配置。',
    icon: Icons.bolt,
    color: Colors.amber,
    installCommand: _hermesInstallCommand,
    launchCommand: r'''
[ -r /root/.openclaw/cli-env.sh ] && . /root/.openclaw/cli-env.sh
[ -r /root/.openclaw/cli-env-hermes-agent.sh ] && . /root/.openclaw/cli-env-hermes-agent.sh
exec /usr/local/bin/hermes
''',
    versionCommand: '/usr/local/bin/hermes --version',
  );

  static const genericTool = CliToolDefinition(
    id: 'generic-agent',
    name: 'Generic Agent',
    packageName: 'openclaw-generic-agent',
    executable: 'generic-agent',
    description: '通用 OpenAI 兼容 Agent，可直接连接任意中转 API，用于普通对话、代码生成和脚本辅助。',
    icon: Icons.smart_toy,
    color: Colors.teal,
    installCommand: _genericInstallCommand,
    launchCommand: r'''
[ -r /root/.openclaw/cli-env.sh ] && . /root/.openclaw/cli-env.sh
[ -r /root/.openclaw/cli-env-generic-agent.sh ] && . /root/.openclaw/cli-env-generic-agent.sh
exec /usr/local/bin/generic-agent
''',
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
    launchCommand: r'''
[ -r /root/.openclaw/cli-env.sh ] && . /root/.openclaw/cli-env.sh
[ -r /root/.openclaw/cli-env-gemini.sh ] && . /root/.openclaw/cli-env-gemini.sh
if [ "${OPENCLAW_API_PROTOCOL:-gemini}" != "gemini" ]; then
  if [ -x /usr/local/bin/gemini-openai-agent ]; then
    exec /usr/local/bin/gemini-openai-agent
  fi
  echo "Gemini CLI 的官方运行时只支持 Gemini 协议。OpenAI 兼容协议需要回到 CLI Tools 页面更新 Gemini CLI 以安装兜底 Agent。" >&2
  exit 2
fi
if [ -n "${OPENCLAW_MODEL:-}" ]; then
  exec /usr/local/bin/gemini --model "$OPENCLAW_MODEL"
fi
exec /usr/local/bin/gemini
''',
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

mkdir -p /root/.openclaw /root/.npm /tmp/npm-cache /tmp/npm-tmp /opt/openclaw-cli /usr/local/bin /usr/local/lib
npm config set audit false --global >/dev/null 2>&1 || true
npm config set fund false --global >/dev/null 2>&1 || true
npm config set update-notifier false --global >/dev/null 2>&1 || true
npm config set registry https://registry.npmmirror.com --global >/dev/null 2>&1 || true

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

write_node_wrapper() {
  target="$1"
  bin_name="$2"
  real_js="$3"
  cat > "/usr/local/bin/$bin_name" <<OPENCLAW_NODE_WRAPPER
#!/bin/sh
export NODE_OPTIONS="\${NODE_OPTIONS:---require /root/.openclaw/bionic-bypass.js}"
export NODE_EXTRA_CA_CERTS="\${NODE_EXTRA_CA_CERTS:-/etc/ssl/certs/ca-certificates.crt}"
export TMPDIR="\${TMPDIR:-/tmp}"
[ -r /root/.openclaw/terminal-theme.sh ] && . /root/.openclaw/terminal-theme.sh
[ -r /root/.openclaw/cli-env.sh ] && . /root/.openclaw/cli-env.sh
[ -r /root/.openclaw/cli-env-$target.sh ] && . /root/.openclaw/cli-env-$target.sh
case "$target" in
  codebuddy)
    if [ -n "\${OPENCLAW_MODEL:-}" ] && [ "\${1:-}" != "--version" ] && [ "\${1:-}" != "-v" ] && [ "\${1:-}" != "--help" ] && [ "\${1:-}" != "-h" ]; then
      set -- --model "\$OPENCLAW_MODEL" "\$@"
    fi
    ;;
  gemini)
    if [ "\${OPENCLAW_API_PROTOCOL:-gemini}" != "gemini" ] && [ "\${1:-}" != "--version" ] && [ "\${1:-}" != "-v" ] && [ "\${1:-}" != "--help" ] && [ "\${1:-}" != "-h" ]; then
      if [ -x /usr/local/bin/gemini-openai-agent ]; then
        exec /usr/local/bin/gemini-openai-agent "\$@"
      fi
      echo "Gemini CLI only supports Gemini protocol directly. Reinstall Gemini CLI to enable the OpenAI-compatible fallback agent, or switch this tool's API protocol to Gemini." >&2
      exit 2
    fi
    if [ -n "\${OPENCLAW_MODEL:-}" ] && [ "\${1:-}" != "--version" ] && [ "\${1:-}" != "-v" ] && [ "\${1:-}" != "--help" ] && [ "\${1:-}" != "-h" ]; then
      set -- --model "\$OPENCLAW_MODEL" "\$@"
    fi
    ;;
esac
exec node "$real_js" "\$@"
OPENCLAW_NODE_WRAPPER
  chmod 0755 "/usr/local/bin/$bin_name"
}

write_generic_agent() {
  bin_name="$1"
  env_tool_id="$2"
  tool_id="$3"
  display_name="$4"
  script_path="/usr/local/lib/openclaw-cli-$bin_name.js"
  cat > "$script_path" <<'OPENCLAW_GENERIC_AGENT'
#!/usr/bin/env node
const readline = require("readline");

const toolId = process.env.OPENCLAW_TOOL_ID || "generic-agent";
const displayName = process.env.OPENCLAW_TOOL_NAME || "Generic Agent";
const version = "1.0.0";

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
    content: `${displayName} running inside OpenClaw. Reply concisely and help with coding or shell tasks.`,
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
OPENCLAW_GENERIC_AGENT
  sed -i "s/Generic Agent/$display_name/g; s/generic-agent/$tool_id/g" "$script_path"
  chmod 0755 "$script_path"
  cat > "/usr/local/bin/$bin_name" <<OPENCLAW_GENERIC_AGENT_WRAPPER
#!/bin/sh
export NODE_OPTIONS="\${NODE_OPTIONS:---require /root/.openclaw/bionic-bypass.js}"
export NODE_EXTRA_CA_CERTS="\${NODE_EXTRA_CA_CERTS:-/etc/ssl/certs/ca-certificates.crt}"
export TMPDIR="\${TMPDIR:-/tmp}"
[ -r /root/.openclaw/terminal-theme.sh ] && . /root/.openclaw/terminal-theme.sh
[ -r /root/.openclaw/cli-env.sh ] && . /root/.openclaw/cli-env.sh
[ -r /root/.openclaw/cli-env-$env_tool_id.sh ] && . /root/.openclaw/cli-env-$env_tool_id.sh
exec node "$script_path" "\$@"
OPENCLAW_GENERIC_AGENT_WRAPPER
  chmod 0755 "/usr/local/bin/$bin_name"
}

write_cli_theme
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
if [ -r /root/.openclaw/codex-proxy.env ]; then
  proxy_healthy=false
  if command -v python3 >/dev/null 2>&1; then
    if python3 - <<'OPENCLAW_CODEX_PROXY_HEALTH' >/dev/null 2>&1
import urllib.request
urllib.request.urlopen("http://127.0.0.1:8787/health", timeout=1).read()
OPENCLAW_CODEX_PROXY_HEALTH
    then
      proxy_healthy=true
    fi
  elif command -v node >/dev/null 2>&1; then
    if node -e 'fetch("http://127.0.0.1:8787/health", {signal: AbortSignal.timeout(1000)}).then(r => process.exit(r.ok ? 0 : 1)).catch(() => process.exit(1))' >/dev/null 2>&1; then
      proxy_healthy=true
    fi
  fi
  if [ "$proxy_healthy" != true ]; then
    if command -v python3 >/dev/null 2>&1 && [ -r /root/.openclaw/codex-proxy.py ]; then
      nohup python3 /root/.openclaw/codex-proxy.py >/tmp/openclaw-codex-proxy.log 2>&1 &
    elif command -v node >/dev/null 2>&1 && [ -r /root/.openclaw/codex-proxy.js ]; then
      nohup node /root/.openclaw/codex-proxy.js >/tmp/openclaw-codex-proxy.log 2>&1 &
    fi
    sleep 0.3
  fi
fi

openclaw_passthrough=false
openclaw_has_sandbox_arg=false
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
  esac
done
if [ "$openclaw_passthrough" != true ] && [ "$openclaw_has_sandbox_arg" != true ]; then
  set -- --dangerously-bypass-approvals-and-sandbox "$@"
fi
if [ "$openclaw_passthrough" != true ] && [ "$openclaw_cli_mode" = true ]; then
  set -- --no-alt-screen "$@"
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
write_node_wrapper gemini gemini /opt/openclaw-cli/gemini/node_modules/@google/gemini-cli/bundle/gemini.js
write_generic_agent gemini-openai-agent gemini generic-agent "Gemini OpenAI Agent"
hash -r
/usr/local/bin/gemini --version || true
echo ">>> GEMINI_CLI_INSTALL_COMPLETE"
''';

  static const _hermesInstallCommand = _commonInstallPrefix +
      r'''
echo ">>> Installing OpenClaw Hermes Agent..."
write_generic_agent hermes hermes-agent hermes-agent "Hermes Agent"
hash -r
/usr/local/bin/hermes --version
echo ">>> HERMES_AGENT_INSTALL_COMPLETE"
''';

  static const _genericInstallCommand = _commonInstallPrefix +
      r'''
echo ">>> Installing OpenClaw Generic Agent..."
write_generic_agent generic-agent generic-agent generic-agent "Generic Agent"
hash -r
/usr/local/bin/generic-agent --version
echo ">>> GENERIC_AGENT_INSTALL_COMPLETE"
''';

  static Future<List<CliToolStatus>> checkAllStatuses() async {
    final statuses = <CliToolStatus>[];
    for (final tool in allTools) {
      statuses.add(await checkStatus(tool));
    }
    return statuses;
  }

  static Future<CliToolStatus> checkStatus(CliToolDefinition tool) async {
    if (tool.id == shellTool.id) {
      return _checkShellStatus();
    }

    final command = '''
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
      final version = installed
          ? lines
              .skip(markerIndex + 1)
              .firstWhere((line) => !line.startsWith('__'), orElse: () => '')
          : '';
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

  static Future<CliToolStatus> _checkShellStatus() async {
    try {
      final output = await NativeBridge.runInProot(
        'bash --version | head -n 1',
        timeout: 20,
      );
      final version = output
          .split('\n')
          .map((line) => line.trim())
          .firstWhere((line) => line.isNotEmpty, orElse: () => 'bash');
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

  static Future<void> prepareInstallAssets(CliToolDefinition _) async {}
}
