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
    expect(codexConfig, isNot(contains('does not manage Codex')));

    final helper = rootfsFiles['/root/.openclaw/codex-termux-runtime.sh']!;
    expect(helper, contains('configure_codex_termux_runtime()'));
    expect(helper, contains('approvals_reviewer'));
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
    expect(codexConfig, contains('forced_login_method = "api"'));
    expect(codexConfig, isNot(contains('[model_providers.hhhl]')));

    final env = rootfsFiles['/root/.openclaw/cli-env-codex.sh']!;
    expect(env, contains("export OPENAI_API_KEY='sk-test'"));
    expect(env, contains("export OPENAI_MODEL='gpt-5'"));

    final auth = jsonDecode(rootfsFiles['/root/.codex/auth.json']!)
        as Map<String, dynamic>;
    expect(auth['auth_mode'], 'apikey');
    expect(auth['OPENAI_API_KEY'], 'sk-test');
  });

  test('Codex installer contains the same Termux runtime repair', () {
    final installCommand = CliToolService.codexTool.installCommand;
    expect(
      CliToolService.codexTool.launchCommand,
      'exec /root/.openclaw/bin/codex --openclaw-cli-mode',
    );
    expect(installCommand, contains('write_codex_termux_runtime_helper'));
    expect(installCommand, contains('configure_codex_termux_runtime || true'));
    expect(installCommand, contains('approvals_reviewer'));
    expect(installCommand, contains('tui.terminal_title'));
  });
}
