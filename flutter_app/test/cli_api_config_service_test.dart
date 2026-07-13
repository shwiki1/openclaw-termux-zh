import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/constants.dart';
import 'package:openclaw/services/cli_api_config_service.dart';
import 'package:openclaw/services/cli_tool_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel(AppConstants.channelName);
  late Map<String, String> rootfsFiles;
  late List<String> prootCommands;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    rootfsFiles = <String, String>{};
    prootCommands = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      final arguments = Map<String, dynamic>.from(
        call.arguments as Map? ?? const <String, dynamic>{},
      );
      switch (call.method) {
        case 'readRootfsFile':
          return rootfsFiles[arguments['path'] as String];
        case 'writeRootfsFile':
          rootfsFiles[arguments['path'] as String] =
              arguments['content'] as String;
          return true;
        case 'runInProot':
          prootCommands.add(arguments['command'] as String);
          return '';
        default:
          throw MissingPluginException('Unhandled method: ${call.method}');
      }
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('regenerateRuntimeFiles writes Termux-safe Codex defaults', () async {
    await CliApiConfigService.regenerateRuntimeFiles(
      configs: <String, dynamic>{
        'sharedProfiles': <dynamic>[],
        'tools': <String, dynamic>{},
      },
    );

    final codexConfig = rootfsFiles['/root/.codex/config.toml']!;
    expect(codexConfig, contains('sandbox_mode = "danger-full-access"'));
    expect(codexConfig, contains('approval_policy = "never"'));
    expect(codexConfig, contains('tui.notifications = false'));
    expect(codexConfig, contains('tui.terminal_title = []'));
    expect(codexConfig, contains('[mcp_servers.openclaw_browser]'));
    expect(codexConfig, contains('command = "node"'));
    expect(
      codexConfig,
      contains('args = ["/root/.openclaw/browser-mcp.mjs"]'),
    );
    expect(codexConfig, contains('startup_timeout_sec = 60'));
    expect(codexConfig, isNot(contains('does not manage Codex')));

    final helper = rootfsFiles['/root/.openclaw/codex-termux-runtime.sh']!;
    expect(helper, contains('configure_codex_termux_runtime()'));
    expect(helper, contains('codex_configure_model_provider()'));
    expect(helper, contains('codex_configure_browser_mcp()'));
    expect(helper, contains('mcp_servers.openclaw_browser'));
    expect(helper, contains('approvals_reviewer'));
    expect(helper, contains('model_provider'));
    expect(helper, contains('disable-terminal-session-change-toast'));
    expect(helper, contains('bell-character'));

    final launcher = rootfsFiles['/root/.openclaw/bin/codex']!;
    expect(
      launcher,
      contains('[ -r /root/.openclaw/codex-termux-runtime.sh ]'),
    );
    expect(launcher, contains('configure_codex_termux_runtime || true'));

    expect(
      prootCommands.single,
      contains('/root/.openclaw/codex-termux-runtime.sh'),
    );

    final browserMcp = rootfsFiles['/root/.openclaw/browser-mcp.mjs']!;
    expect(browserMcp, contains('browser_get_state'));
    expect(browserMcp, contains('browser_control'));
    expect(browserMcp, contains('browser_open'));
    expect(browserMcp, contains('browser_wait_for_selector'));
    expect(browserMcp, contains('browser_scroll'));
    expect(browserMcp, contains('browser_press_key'));
    expect(browserMcp, contains('browser_select_option'));
    expect(browserMcp, contains('browser_script_list'));
    expect(browserMcp, contains('browser_script_save'));
    expect(browserMcp, contains('browser_script_run'));
    expect(browserMcp, contains('browser_script_rename'));
    expect(browserMcp, contains('browser_script_delete'));
    expect(browserMcp, contains('browser_wait_for_selector: "wait_for_selector"'));
    expect(browserMcp, contains('browser_scroll: "scroll"'));
    expect(browserMcp, contains('browser_press_key: "press_key"'));
    expect(browserMcp, contains('browser_select_option: "select_option"'));
    expect(browserMcp, contains('browser_script_run: "script_run"'));
    expect(browserMcp, contains('function normalizeBridgeAction'));
    expect(browserMcp, contains('toolName === "browser_control"'));
    expect(browserMcp, contains('version: "1.3.0"'));
    expect(
      browserMcp,
      contains('process.stdout.write(payload.toString("utf8") + "\\n")'),
    );
    expect(browserMcp, contains('Content-Length:'));

    final browserScriptLauncher =
        rootfsFiles['/root/.openclaw/bin/browser-script']!;
    expect(
      browserScriptLauncher,
      contains('browser-script call <action-or-browser_tool> [json-payload]'),
    );
    expect(
      browserScriptLauncher,
      contains('browser-script interactables [filter] [maxItems]'),
    );
    expect(browserScriptLauncher, contains('browser-script run <script-id>'));
    expect(browserScriptLauncher, contains('bridge_action="capture_snapshot"'));
    expect(browserScriptLauncher, contains('bridge_action="script_run"'));
    expect(browserScriptLauncher, contains('const ACTION_ALIASES = {'));
    expect(browserScriptLauncher, contains('browser_type: "type"'));
    expect(browserScriptLauncher, contains('OPENCLAW_BROWSER_BRIDGE_TOKEN'));

    final browserSkill =
        rootfsFiles['/root/.codex/skills/browser-operator/SKILL.md']!;
    expect(browserSkill, contains('browser_get_state'));
    expect(browserSkill, contains('browser_control'));
    expect(browserSkill, contains('browser-script call'));
    expect(browserSkill, contains('browser_wait_for_selector'));
    expect(browserSkill, contains('browser_scroll'));
    expect(browserSkill, contains('browser_press_key'));
    expect(browserSkill, contains('browser_select_option'));
    expect(browserSkill, contains('browser_script_list'));
    expect(browserSkill, contains('browser_script_save'));
    expect(browserSkill, contains('browser_script_run'));
  });

  test('Codex API key without custom base URL still uses API auth', () async {
    await CliApiConfigService.regenerateRuntimeFiles(
      configs: <String, dynamic>{
        'sharedProfiles': <dynamic>[],
        'tools': <String, dynamic>{
          'codex': <String, dynamic>{
            'apiKey': 'sk-test',
            'model': 'gpt-5',
            'reasoningEffort': 'high',
          },
        },
      },
    );

    final codexConfig = rootfsFiles['/root/.codex/config.toml']!;
    expect(codexConfig, contains('model = "gpt-5"'));
    expect(codexConfig, contains('preferred_auth_method = "apikey"'));
    expect(codexConfig, isNot(contains('forced_login_method')));
    expect(codexConfig, isNot(contains('[model_providers.hhhl]')));

    final env = rootfsFiles['/root/.openclaw/cli-env-codex.sh']!;
    expect(env, contains("export OPENAI_API_KEY='sk-test'"));
    expect(env, contains("export OPENAI_MODEL='gpt-5'"));

    final auth = jsonDecode(rootfsFiles['/root/.codex/auth.json']!)
        as Map<String, dynamic>;
    expect(auth['auth_mode'], 'apikey');
    expect(auth['OPENAI_API_KEY'], 'sk-test');
  });

  test('Codex custom API writes current model provider config shape', () async {
    await CliApiConfigService.regenerateRuntimeFiles(
      configs: <String, dynamic>{
        'sharedProfiles': <dynamic>[
          <String, dynamic>{
            'sharedProfileId': 'shared-main',
            'profileName': 'Main API',
            'apiProtocol': 'openai',
            'baseUrl': 'https://proxy.example.com/v1',
            'apiKey': 'sk-proxy',
          },
        ],
        'tools': <String, dynamic>{
          'codex': <String, dynamic>{
            'sharedProfileId': 'shared-main',
            'model': 'gpt-5.5',
            'reasoningEffort': 'xhigh',
          },
        },
      },
    );

    final codexConfig = rootfsFiles['/root/.codex/config.toml']!;
    expect(codexConfig, contains('model_provider = "hhhl"'));
    expect(codexConfig, contains('model = "gpt-5.5"'));
    expect(codexConfig, contains('preferred_auth_method = "apikey"'));
    expect(codexConfig, isNot(contains('forced_login_method')));
    expect(codexConfig, contains('[model_providers.hhhl]'));
    expect(codexConfig, contains('name = "hhhl"'));
    expect(codexConfig, contains('base_url = "http://127.0.0.1:8787/v1"'));
    expect(codexConfig, contains('wire_api = "responses"'));
    expect(codexConfig, contains('env_key = "OPENAI_API_KEY"'));
    expect(codexConfig, contains('stream_idle_timeout_ms = 300000'));
    expect(codexConfig, contains('[mcp_servers.openclaw_browser]'));
    expect(
      codexConfig,
      contains('args = ["/root/.openclaw/browser-mcp.mjs"]'),
    );
    expect(codexConfig, contains('startup_timeout_sec = 60'));

    final env = rootfsFiles['/root/.openclaw/cli-env-codex.sh']!;
    expect(env, contains("export OPENAI_API_KEY='sk-proxy'"));
    expect(
      env,
      contains("export OPENAI_BASE_URL='http://127.0.0.1:8787/v1'"),
    );
    expect(
      env,
      contains("export CODEX_BASE_URL='http://127.0.0.1:8787/v1'"),
    );
    expect(env, contains("export OPENAI_MODEL='gpt-5.5'"));

    final proxyEnv = rootfsFiles['/root/.openclaw/codex-proxy.env']!;
    expect(
      proxyEnv,
      contains("OPENCLAW_CODEX_PROXY_UPSTREAM='https://proxy.example.com/v1'"),
    );
    expect(proxyEnv, contains("OPENAI_API_KEY='sk-proxy'"));

    final helper = rootfsFiles['/root/.openclaw/codex-termux-runtime.sh']!;
    expect(helper, contains('OPENCLAW_CODEX_PROXY_UPSTREAM'));
    expect(
      helper,
      contains('codex_configure_model_provider "\$codex_config" "hhhl"'),
    );
    expect(
      helper,
      contains(
        'codex_configure_browser_mcp "\$codex_config" "/root/.openclaw/browser-mcp.mjs"',
      ),
    );
  });

  test('Codex installer contains the same Termux runtime repair', () {
    final installCommand = CliToolService.codexTool.installCommand;
    expect(
      CliToolService.codexTool.launchCommand,
      'exec /root/.openclaw/bin/codex --openclaw-cli-mode',
    );
    expect(installCommand, contains('write_codex_termux_runtime_helper'));
    expect(installCommand, contains('configure_codex_termux_runtime || true'));
    expect(installCommand, contains('codex_configure_model_provider()'));
    expect(installCommand, contains('codex_configure_browser_mcp()'));
    expect(installCommand, contains('mcp_servers.openclaw_browser'));
    expect(installCommand, contains('startup_timeout_sec = 60'));
    expect(installCommand, contains('approvals_reviewer'));
    expect(installCommand, contains('tui.terminal_title'));
  });
}
