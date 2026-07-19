import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cli_api_config.dart';
import 'native_bridge.dart';

class CliApiModelOption {
  final String id;
  final String upstreamModel;
  final String providerId;
  final String providerName;
  final String providerBaseUrl;
  final String protocol;

  const CliApiModelOption({
    required this.id,
    this.upstreamModel = '',
    this.providerId = '',
    this.providerName = '',
    this.providerBaseUrl = '',
    this.protocol = 'openai',
  });
}

class CliApiConfigService {
  static const _configPath = '/root/.openclaw/app/cli-api-config.json';
  static const _envPath = '/root/.openclaw/cli-env.sh';
  static const cliWorkspacePath = '/root/openclaw-cli-workspace';
  static const _cliWorkspaceProjectsPath = '$cliWorkspacePath/projects';
  static const _cliWorkspaceScratchPath = '$cliWorkspacePath/scratch';
  static const _cliWorkspaceAgentsPath = '$cliWorkspacePath/AGENTS.md';
  static const _cliWorkspaceGeminiPath = '$cliWorkspacePath/GEMINI.md';
  static const _cliWorkspaceContextPath = '$cliWorkspacePath/CONTEXT.md';
  static const _cliWorkspaceGeminiSettingsPath =
      '$cliWorkspacePath/.gemini/settings.json';
  static const _cliWorkspaceGeminiCustomModelsPath =
      '$cliWorkspacePath/.gemini/custom-models.json';
  static const _cliWorkspaceGenCliSettingsPath =
      '$cliWorkspacePath/.gen-cli/settings.json';
  static const _cliWorkspaceSkillPath =
      '$cliWorkspacePath/.agents/skills/openclaw-android-runtime/SKILL.md';
  static const _managedCliBinDir = '/root/.openclaw/bin';
  static const _codexLauncherPath = '$_managedCliBinDir/codex';
  static const _genericAgentLauncherPath =
      '$_managedCliBinDir/generic-agent';
  static const _geminiLauncherPath = '$_managedCliBinDir/gemini';
  static const _hermesLauncherPath = '$_managedCliBinDir/hermes';
  static const _codexProxyEnvPath = '/root/.openclaw/codex-proxy.env';
  static const _codexTermuxRuntimePath =
      '/root/.openclaw/codex-termux-runtime.sh';
  static const _codexConfigPath = '/root/.codex/config.toml';
  static const _codexAuthPath = '/root/.codex/auth.json';
  static const _localApiProxyBaseUrl = 'http://127.0.0.1:9999/v1';
  static const _localApiProxyProfileId = 'openclaw-local-api-proxy';
  static const _localApiProxyProfileName = '本地中转代理';
  static const _localApiProxyApiKey = 'sk-123';
  static const _localApiProxyConfigPath =
      '/root/.openclaw/api2py/data/config.json';
  static const _codeBuddyModelsPath = '/root/.codebuddy/models.json';
  static const _codeBuddySettingsPath = '/root/.codebuddy/settings.json';
  static const _qwenSettingsPath = '/root/.qwen/settings.json';
  static const _geminiSettingsPath = '/root/.gemini/settings.json';
  static const _geminiCustomModelsPath = '/root/.gemini/custom-models.json';
  static const _genCliSettingsPath = '/root/.gen-cli/settings.json';
  static const _hermesConfigPath = '/root/.hermes/config.yaml';
  static const _hermesEnvPath = '/root/.hermes/.env';
  static const _terminalThemePath = '/root/.openclaw/terminal-theme.sh';
  static const _browserBridgeEnvPath = '/root/.openclaw/browser-bridge.env';
  static const _browserMcpPath = '/root/.openclaw/browser-mcp.mjs';
  static const _browserScriptLauncherPath =
      '$_managedCliBinDir/browser-script';
  static const _browserMcpStartupTimeoutSec = 60;
  static const _browserCodexSkillPath =
      '/root/.codex/skills/browser-operator/SKILL.md';
  static const _browserSkillPath =
      '/root/.agents/skills/browser-operator/SKILL.md';
  static const _prefsKey = 'cli_api_config_json';

  static const configurableToolIds = {
    'codex',
    'codebuddy',
    'qwen-code',
    'hermes-agent',
    'generic-agent',
    'gemini',
  };

  static const supportedApiProtocols = <String, String>{
    'openai': 'OpenAI 兼容协议',
    'responses': 'Codex Responses 协议',
    'anthropic': 'Anthropic Messages 协议',
    'ollama': 'Ollama 协议',
  };

  static bool isBuiltinLocalApiProxyProfile(CliApiConfig profile) =>
      _isLocalApiProxyProfile(profile);

  static Future<CliApiConfig> load(String toolId) async {
    final configs = await _loadAll();
    return _resolvedToolConfig(toolId, configs);
  }

  static Future<List<CliApiConfig>> loadSharedProfiles() async {
    final configs = await _loadAll();
    return _sharedProfilesForUi(configs);
  }

  static Future<CliApiConfig> loadToolSettings(String toolId) async {
    final configs = await _loadAll();
    return _toolSettingsFromConfig(toolId, configs);
  }

  static Future<Map<String, CliApiConfig>> loadAll() async {
    final configs = await _loadAll();
    return {
      for (final toolId in configurableToolIds)
        toolId: _resolvedToolConfig(toolId, configs),
    };
  }

  static Future<void> saveSharedProfiles(
    List<CliApiConfig> profiles, {
    String? codexSharedProfileId,
  }) async {
    final configs = await _loadAll();
    configs['sharedProfiles'] = _sharedProfilesJson(profiles);
    final bindCodexProfileId = codexSharedProfileId?.trim() ?? '';
    if (bindCodexProfileId.isNotEmpty &&
        _sharedProfilesForUi(configs)
            .any((item) => item.sharedProfileId == bindCodexProfileId)) {
      final tools = _asMap(configs['tools']);
      final currentCodex = _toolSettingsFromJson(
        'codex',
        _asMapOrNull(tools['codex']),
      );
      tools['codex'] = _toolSettingsJson(
        currentCodex.copyWith(sharedProfileId: bindCodexProfileId),
      );
      configs['tools'] = tools;
    }
    await _persistConfig(configs);
  }

  static Future<void> saveToolSettings(CliApiConfig config) async {
    final configs = await _loadAll();
    final tools = _asMap(configs['tools']);
    configs['tools'] = tools;
    tools[config.toolId] = _toolSettingsJson(config);
    await _persistConfig(configs);
  }

  static Future<void> restoreToolDefaultConfig(String toolId) async {
    final normalizedToolId = toolId.trim();
    if (!configurableToolIds.contains(normalizedToolId)) {
      throw Exception('不支持恢复默认配置的工具：$toolId');
    }
    final configs = await _loadAll();
    final tools = _asMap(configs['tools']);
    configs['tools'] = tools;
    tools[normalizedToolId] =
        _toolSettingsJson(CliApiConfig(toolId: normalizedToolId));
    await _persistConfig(configs);
  }

  static Future<void> save(
    CliApiConfig config, {
    bool asSharedProfile = false,
  }) async {
    if (asSharedProfile) {
      final profiles = await loadSharedProfiles();
      final nextProfiles = List<CliApiConfig>.from(profiles);
      final index = nextProfiles.indexWhere(
        (item) => item.sharedProfileId == config.sharedProfileId,
      );
      final normalized = _normalizedSharedProfile(config);
      if (index >= 0) {
        nextProfiles[index] = normalized;
      } else {
        nextProfiles.add(normalized);
      }
      await saveSharedProfiles(nextProfiles);
      return;
    }
    await saveToolSettings(config);
  }

  static Future<List<String>> fetchModels({
    required String toolId,
    required String baseUrl,
    required String apiKey,
    String apiProtocol = '',
  }) async {
    final protocol = apiProtocol.trim().isEmpty ? 'openai' : apiProtocol.trim();
    final endpoint = _modelsEndpoint(baseUrl, protocol: protocol);
    if (endpoint == null) {
      throw Exception('请先填写 API 地址');
    }
    if (apiKey.trim().isEmpty) {
      throw Exception('请先填写 API Key');
    }

    final useAnthropicHeaders = protocol == 'anthropic';
    final useGeminiHeaders = protocol == 'gemini';
    final headers = <String, String>{
      'Accept': 'application/json',
      if (useAnthropicHeaders) ...{
        'x-api-key': apiKey.trim(),
        'anthropic-version': '2023-06-01',
      } else if (useGeminiHeaders)
        'x-goog-api-key': apiKey.trim()
      else
        'Authorization': 'Bearer ${apiKey.trim()}',
    };
    if (useAnthropicHeaders) {
      headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    }

    final response = await http
        .get(endpoint, headers: headers)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('模型列表获取失败：HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final models = _extractModelIds(decoded).toSet().toList()..sort();
    if (models.isEmpty) {
      throw Exception('模型列表为空或响应格式不支持');
    }
    return models;
  }

  static Future<List<CliApiModelOption>> fetchModelOptions({
    required String toolId,
    required String baseUrl,
    required String apiKey,
    String apiProtocol = '',
  }) async {
    final protocol = apiProtocol.trim().isEmpty ? 'openai' : apiProtocol.trim();
    final endpoint = _modelsEndpoint(baseUrl, protocol: protocol);
    if (endpoint == null) {
      throw Exception('请先填写 API 地址');
    }
    if (apiKey.trim().isEmpty) {
      throw Exception('请先填写 API Key');
    }

    final useAnthropicHeaders = protocol == 'anthropic';
    final useGeminiHeaders = protocol == 'gemini';
    final headers = <String, String>{
      'Accept': 'application/json',
      if (useAnthropicHeaders) ...{
        'x-api-key': apiKey.trim(),
        'anthropic-version': '2023-06-01',
      } else if (useGeminiHeaders)
        'x-goog-api-key': apiKey.trim()
      else
        'Authorization': 'Bearer ${apiKey.trim()}',
    };
    if (useAnthropicHeaders) {
      headers['Authorization'] = 'Bearer ${apiKey.trim()}';
    }

    final response = await http
        .get(endpoint, headers: headers)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('模型列表获取失败：HTTP ${response.statusCode}');
    }

    final decoded = jsonDecode(response.body);
    final models = _extractModelOptions(decoded).toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    final unique = <String, CliApiModelOption>{};
    for (final model in models) {
      unique.putIfAbsent(
        '${model.id}|${model.providerId}|${model.upstreamModel}',
        () => model,
      );
    }
    if (unique.isEmpty) {
      throw Exception('模型列表为空或响应格式不支持');
    }
    return unique.values.toList();
  }

  static Future<void> regenerateRuntimeFiles({
    Map<String, dynamic>? configs,
  }) async {
    final allConfigs = configs ?? await _loadAll();
    final activeConfigs = {
      for (final toolId in configurableToolIds)
        toolId: _resolvedToolConfig(toolId, allConfigs),
    };
    final codex = activeConfigs['codex'] ?? const CliApiConfig(toolId: 'codex');
    final gemini =
        activeConfigs['gemini'] ?? const CliApiConfig(toolId: 'gemini');

    Future<void> writeRootfsFile(String path, String content) async {
      final ok = await NativeBridge.writeRootfsFile(path, content);
      if (!ok) {
        throw Exception('RootFS 配置写入失败：$path');
      }
    }

    await _writePrefsConfig(allConfigs);
    await writeRootfsFile(
      _configPath,
      const JsonEncoder.withIndent('  ').convert(allConfigs),
    );
    await writeRootfsFile(
      _localApiProxyConfigPath,
      await _buildLocalApiProxyConfig(allConfigs),
    );
    await writeRootfsFile(_envPath, _buildGlobalEnvFile());
    await writeRootfsFile(
      _terminalThemePath,
      _buildTerminalThemeSh(),
    );
    await writeRootfsFile(
      _cliWorkspaceAgentsPath,
      _buildCliWorkspaceAgentsMd(),
    );
    await writeRootfsFile(
      _cliWorkspaceGeminiPath,
      _buildCliWorkspaceGeminiMd(),
    );
    await writeRootfsFile(
      _cliWorkspaceContextPath,
      _buildCliWorkspaceContextMd(),
    );
    await writeRootfsFile(
      _cliWorkspaceGeminiSettingsPath,
      _buildCliWorkspaceGeminiSettingsJson(gemini),
    );
    await writeRootfsFile(
      _cliWorkspaceGeminiCustomModelsPath,
      _buildGeminiCustomModelsJson(gemini),
    );
    await writeRootfsFile(
      _cliWorkspaceGenCliSettingsPath,
      _buildGenCliSettingsJson(activeConfigs['generic-agent']!),
    );
    await writeRootfsFile(
      _genCliSettingsPath,
      _buildGenCliSettingsJson(activeConfigs['generic-agent']!),
    );
    await writeRootfsFile(
      _cliWorkspaceSkillPath,
      _buildCliWorkspaceSkill(),
    );
    for (final entry in activeConfigs.entries) {
      await writeRootfsFile(
        _toolEnvPath(entry.key),
        _buildToolEnvFile(entry.key, entry.value),
      );
    }
    await writeRootfsFile(
      _codexProxyEnvPath,
      '# OpenClaw legacy Codex proxy is disabled. Use local api2py relay on 127.0.0.1:9999.\n',
    );
    await writeRootfsFile(
      _codexTermuxRuntimePath,
      _buildCodexTermuxRuntimeSh(),
    );
    await writeRootfsFile(
      _browserMcpPath,
      _buildBrowserMcpScript(),
    );
    await writeRootfsFile(
      _browserScriptLauncherPath,
      _buildBrowserScriptLauncherSh(),
    );
    await writeRootfsFile(
      _browserSkillPath,
      _buildBrowserSkill(),
    );
    await writeRootfsFile(
      _browserCodexSkillPath,
      _buildBrowserSkill(),
    );
    await writeRootfsFile(
      _codexLauncherPath,
      _buildCodexLauncherSh(),
    );
    await writeRootfsFile(
      _genericAgentLauncherPath,
      _buildGenericAgentLauncherSh(),
    );
    await writeRootfsFile(
      _geminiLauncherPath,
      _buildGeminiLauncherSh(),
    );
    await writeRootfsFile(
      _hermesLauncherPath,
      _buildHermesLauncherSh(),
    );
    await writeRootfsFile(_codexConfigPath, _buildCodexToml(codex));
    await writeRootfsFile(_codexAuthPath, _buildCodexAuthJson(codex));
    await writeRootfsFile(
      _codeBuddyModelsPath,
      _buildCodeBuddyModelsJson(activeConfigs['codebuddy']!),
    );
    await writeRootfsFile(
      _codeBuddySettingsPath,
      _buildCodeBuddySettingsJson(activeConfigs['codebuddy']!),
    );
    await writeRootfsFile(
      _qwenSettingsPath,
      _buildQwenSettingsJson(activeConfigs['qwen-code']!),
    );
    await writeRootfsFile(
      _geminiSettingsPath,
      _buildGeminiSettingsJson(gemini),
    );
    await writeRootfsFile(
      _geminiCustomModelsPath,
      _buildGeminiCustomModelsJson(gemini),
    );
    await writeRootfsFile(
      _hermesConfigPath,
      _buildHermesConfigYaml(activeConfigs['hermes-agent']!),
    );
    await writeRootfsFile(
      _hermesEnvPath,
      _buildHermesEnvFile(activeConfigs['hermes-agent']!),
    );
    await NativeBridge.runInProot(
      'mkdir -p $cliWorkspacePath $_cliWorkspaceProjectsPath '
      '$_cliWorkspaceScratchPath "$cliWorkspacePath/.gemini" '
      '"$cliWorkspacePath/.gen-cli" '
      '"$cliWorkspacePath/.agents/skills/openclaw-android-runtime" '
      '$_managedCliBinDir '
      '/root/.codex /root/.gemini /root/.codebuddy /root/.qwen '
      '/root/.gen-cli /root/.hermes /root/.config 2>/dev/null || true; '
      'chmod 0755 $_codexTermuxRuntimePath 2>/dev/null || true; '
      'chmod 0755 $_browserMcpPath 2>/dev/null || true; '
      'chmod 0755 $_browserScriptLauncherPath 2>/dev/null || true; '
      'chmod 0755 $_codexLauncherPath $_genericAgentLauncherPath '
      '$_geminiLauncherPath $_hermesLauncherPath 2>/dev/null || true; '
      'chmod 0644 $_codexProxyEnvPath 2>/dev/null || true; '
      'chmod 0600 $_browserBridgeEnvPath 2>/dev/null || true; '
      'chmod 0600 $_codexConfigPath $_codexAuthPath $_codeBuddyModelsPath '
      '$_codeBuddySettingsPath $_qwenSettingsPath $_geminiSettingsPath '
      '$_geminiCustomModelsPath $_cliWorkspaceGeminiCustomModelsPath '
      '$_genCliSettingsPath $_hermesConfigPath '
      '$_hermesEnvPath 2>/dev/null || true; '
      'chmod 0644 $_terminalThemePath 2>/dev/null || true; '
      'chmod 0644 $_cliWorkspaceAgentsPath $_cliWorkspaceGeminiPath '
      '$_cliWorkspaceContextPath $_cliWorkspaceGeminiSettingsPath '
      '$_cliWorkspaceGenCliSettingsPath '
      '$_cliWorkspaceSkillPath $_browserSkillPath $_browserCodexSkillPath '
      '2>/dev/null || true; '
      'grep -q "openclaw/terminal-theme.sh" /root/.bashrc 2>/dev/null || '
      'printf "\\n[ -r /root/.openclaw/terminal-theme.sh ] && . /root/.openclaw/terminal-theme.sh\\n" >> /root/.bashrc; '
      'chmod 0600 /root/.openclaw/cli-env*.sh 2>/dev/null || true; '
      'chmod 0755 '
      '/opt/openclaw-cli/codex/node_modules/@openai/codex-linux-arm64/'
      'vendor/aarch64-unknown-linux-musl/bin/codex '
      '/opt/openclaw-cli/codex/node_modules/@openai/codex-linux-arm64/'
      'vendor/aarch64-unknown-linux-musl/bin/codex-code-mode-host '
      '2>/dev/null || true; '
      '$_codexTermuxRuntimePath >/dev/null 2>&1 || true',
      timeout: 10,
    );
  }

  static Future<Map<String, dynamic>> _loadAll() async {
    final prefsConfig = await _readPrefsConfig();
    if (prefsConfig.isNotEmpty) {
      final normalized = _normalizeConfig(prefsConfig);
      if (!_deepEquals(prefsConfig, normalized)) {
        await _writePrefsConfig(normalized);
      }
      return normalized;
    }

    try {
      final content = await NativeBridge.readRootfsFile(_configPath);
      if (content == null || content.trim().isEmpty) {
        return _emptyConfig();
      }
      final decoded = jsonDecode(content);
      final config = _normalizeConfig(_asMap(decoded));
      await _writePrefsConfig(config);
      return config;
    } catch (_) {
      return _emptyConfig();
    }
  }

  static Future<Map<String, dynamic>> _readPrefsConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final content = prefs.getString(_prefsKey);
      if (content == null || content.trim().isEmpty) {
        return <String, dynamic>{};
      }
      return _normalizeConfig(_asMap(jsonDecode(content)));
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Future<void> _writePrefsConfig(Map<String, dynamic> config) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _prefsKey,
      const JsonEncoder.withIndent('  ').convert(config),
    );
  }

  static Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map<String, dynamic>) {
      return value;
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return <String, dynamic>{};
  }

  static Map<String, dynamic>? _asMapOrNull(dynamic value) {
    if (value == null) return null;
    return _asMap(value);
  }

  static Future<void> _persistConfig(Map<String, dynamic> config) async {
    final normalized = _normalizeConfig(config);
    await _writePrefsConfig(normalized);
    try {
      await regenerateRuntimeFiles(configs: normalized);
    } catch (error) {
      // Rootfs may not exist yet during first-run preconfiguration.
      // The setup flow calls regenerateRuntimeFiles() again after extraction.
      final rootfsReady = await _isRootfsReady();
      if (!rootfsReady) {
        return;
      }
      throw Exception('配置已保存到应用，但同步 Ubuntu RootFS 失败：$error');
    }
    await _stopLegacyCodexProxyProcess();
  }

  static Future<bool> _isRootfsReady() async {
    try {
      final osRelease = await NativeBridge.readRootfsFile('/etc/os-release');
      return osRelease != null && osRelease.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _stopLegacyCodexProxyProcess() async {
    const command = r'''
pkill -f "[c]odex-proxy.py" >/dev/null 2>&1 || true
pkill -f "[c]odex-proxy.js" >/dev/null 2>&1 || true
openclaw_kill_codex_proxy_port() {
  pkill -f "[c]odex-proxy.py" >/dev/null 2>&1 || true
  pkill -f "[c]odex-proxy.js" >/dev/null 2>&1 || true
  command -v python3 >/dev/null 2>&1 || return 0
  python3 - <<'PY' >/dev/null 2>&1 || true
import os
import signal

target_port = format(8787, "04X")
inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table, "r", encoding="utf-8") as handle:
            next(handle, None)
            for line in handle:
                parts = line.split()
                if len(parts) > 9 and parts[1].rsplit(":", 1)[-1].upper() == target_port:
                    inodes.add(parts[9])
    except OSError:
        pass

if inodes:
    for pid in filter(str.isdigit, os.listdir("/proc")):
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    link = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if link.startswith("socket:[") and link[8:-1] in inodes:
                    try:
                        os.kill(int(pid), signal.SIGTERM)
                    except OSError:
                        pass
                    break
        except OSError:
            pass
PY
}
openclaw_kill_codex_proxy_port
'''
;
    await NativeBridge.runInProot(command, timeout: 10);
  }

  static Map<String, dynamic> _emptyConfig() => <String, dynamic>{
        'sharedProfiles': <Map<String, dynamic>>[],
        'tools': <String, dynamic>{},
      };

  static Map<String, dynamic> _normalizeConfig(Map<String, dynamic> raw) {
    final hasSharedProfiles = raw['sharedProfiles'] is List;
    return hasSharedProfiles ? _normalizeModernConfig(raw) : _migrateLegacyConfig(raw);
  }

  static Map<String, dynamic> _normalizeModernConfig(Map<String, dynamic> raw) {
    final config = _emptyConfig();
    final sharedProfiles = <CliApiConfig>[];
    final rawProfiles = raw['sharedProfiles'];
    if (rawProfiles is List) {
      for (var i = 0; i < rawProfiles.length; i++) {
        sharedProfiles.add(
          _normalizedSharedProfile(
            CliApiConfig.fromJson(
              'shared',
              _asMapOrNull(rawProfiles[i]),
            ).copyWith(
              profileName: CliApiConfig.fromJson(
                'shared',
                _asMapOrNull(rawProfiles[i]),
              ).profileName.trim().isEmpty
                  ? 'API ${i + 1}'
                  : null,
              sharedProfileId: _sharedProfileIdFromJson(
                _asMapOrNull(rawProfiles[i]),
                index: i,
              ),
            ),
          ),
        );
      }
    }
    config['sharedProfiles'] = _sharedProfilesJson(sharedProfiles);

    final tools = _asMap(raw['tools']);
    final normalizedTools = <String, dynamic>{};
    for (final toolId in configurableToolIds) {
      normalizedTools[toolId] = _toolSettingsJson(
        _toolSettingsFromJson(toolId, _asMapOrNull(tools[toolId])),
      );
    }
    config['tools'] = normalizedTools;
    return config;
  }

  static Map<String, dynamic> _migrateLegacyConfig(Map<String, dynamic> raw) {
    final tools = _asMap(raw['tools']);
    final sharedProfiles = <CliApiConfig>[];
    final sharedByKey = <String, String>{};
    final normalizedTools = <String, dynamic>{};

    for (final toolId in configurableToolIds) {
      final toolJson = _asMapOrNull(tools[toolId]);
      if (toolJson == null || toolJson.isEmpty) {
        normalizedTools[toolId] = _toolSettingsJson(CliApiConfig(toolId: toolId));
        continue;
      }

      final profiles = _legacyProfilesFromJson(toolId, toolJson);
      final activeIndex = _activeProfileIndexFromJson(toolJson)
          .clamp(0, profiles.length - 1)
          .toInt();
      for (var i = 0; i < profiles.length; i++) {
        final sharedId = _ensureSharedProfile(
          sharedProfiles,
          sharedByKey,
          profiles[i],
          fallbackLabel: profiles[i].profileName.trim().isEmpty
              ? '${toolId.toUpperCase()} API ${i + 1}'
              : profiles[i].profileName.trim(),
        );
        if (i == activeIndex) {
          normalizedTools[toolId] = _toolSettingsJson(
            CliApiConfig(
              toolId: toolId,
              sharedProfileId: sharedId,
              model: profiles[i].model,
              reasoningEffort: profiles[i].reasoningEffort,
              modelMapping: profiles[i].modelMapping,
            ),
          );
        }
      }
      normalizedTools.putIfAbsent(
        toolId,
        () => _toolSettingsJson(CliApiConfig(toolId: toolId)),
      );
    }

    return <String, dynamic>{
      'sharedProfiles': _sharedProfilesJson(sharedProfiles),
      'tools': normalizedTools,
    };
  }

  static List<CliApiConfig> _sharedProfilesFromConfig(Map<String, dynamic> config) {
    final rawProfiles = config['sharedProfiles'];
    if (rawProfiles is! List) {
      return const [];
    }
    return [
      for (var i = 0; i < rawProfiles.length; i++)
        _normalizedSharedProfile(
          CliApiConfig.fromJson('shared', _asMapOrNull(rawProfiles[i])).copyWith(
            profileName: CliApiConfig.fromJson('shared', _asMapOrNull(rawProfiles[i]))
                    .profileName
                    .trim()
                    .isEmpty
                ? 'API ${i + 1}'
                : null,
            sharedProfileId: _sharedProfileIdFromJson(
              _asMapOrNull(rawProfiles[i]),
              index: i,
            ),
          ),
        ),
    ];
  }

  static List<CliApiConfig> _sharedProfilesForUi(Map<String, dynamic> config) {
    final profiles = _sharedProfilesFromConfig(config)
        .where((profile) => !_isLocalApiProxyProfile(profile))
        .toList();
    return <CliApiConfig>[
      _localApiProxyProfile(),
      ...profiles,
    ];
  }

  static CliApiConfig _toolSettingsFromConfig(
    String toolId,
    Map<String, dynamic> config,
  ) {
    final tools = _asMap(config['tools']);
    return _toolSettingsFromJson(toolId, _asMapOrNull(tools[toolId]));
  }

  static CliApiConfig _resolvedToolConfig(
    String toolId,
    Map<String, dynamic> config,
  ) {
    final toolSettings = _toolSettingsFromConfig(toolId, config);
    final sharedProfiles = _sharedProfilesForUi(config);
    final profile = _sharedProfileById(
          sharedProfiles,
          toolSettings.sharedProfileId,
        ) ??
        (toolSettings.sharedProfileId.trim().isEmpty && sharedProfiles.length == 1
            ? sharedProfiles.single
            : null);
    return CliApiConfig(
      toolId: toolId,
      sharedProfileId: toolSettings.sharedProfileId.trim().isNotEmpty
          ? toolSettings.sharedProfileId
          : (profile?.sharedProfileId ?? ''),
      profileName: toolSettings.profileName.trim().isNotEmpty
          ? toolSettings.profileName
          : (profile?.profileName ?? ''),
      apiProtocol: _preferNonEmpty(
        toolSettings.apiProtocol,
        profile?.effectiveApiProtocol ?? '',
      ),
      baseUrl: _preferNonEmpty(toolSettings.baseUrl, profile?.baseUrl ?? ''),
      apiKey: _preferNonEmpty(toolSettings.apiKey, profile?.apiKey ?? ''),
      model: _preferNonEmpty(toolSettings.model, profile?.model ?? ''),
      reasoningEffort: _preferNonEmpty(
        toolSettings.reasoningEffort,
        profile?.reasoningEffort ?? '',
      ),
      modelMapping: _preferNonEmpty(
        toolSettings.modelMapping,
        profile?.modelMapping ?? '',
      ),
    );
  }

  static CliApiConfig _toolSettingsFromJson(
    String toolId,
    Map<String, dynamic>? json,
  ) {
    final settings = CliApiConfig.fromJson(toolId, json);
    return CliApiConfig(
      toolId: toolId,
      sharedProfileId: settings.sharedProfileId,
      baseUrl: settings.baseUrl,
      apiKey: settings.apiKey,
      model: settings.model,
      reasoningEffort: settings.reasoningEffort,
      modelMapping: settings.modelMapping,
      apiProtocol: settings.apiProtocol,
      profileName: settings.profileName,
    );
  }

  static List<CliApiConfig> _legacyProfilesFromJson(
    String toolId,
    Map<String, dynamic>? json,
  ) {
    if (json == null || json.isEmpty) {
      return [CliApiConfig(toolId: toolId, profileName: '默认')];
    }
    final rawProfiles = json['profiles'];
    if (rawProfiles is List) {
      final profiles = rawProfiles
          .map((item) => CliApiConfig.fromJson(toolId, _asMapOrNull(item)))
          .toList();
      if (profiles.isNotEmpty) return profiles;
    }
    final legacy = CliApiConfig.fromJson(toolId, json);
    return [
      legacy.copyWith(
        profileName: legacy.profileName.trim().isEmpty ? '默认' : null,
      ),
    ];
  }

  static int _activeProfileIndexFromJson(Map<String, dynamic>? json) {
    final value = json?['activeProfileIndex'];
    if (value is int) return value;
    if (value is num) return value.toInt();
    return 0;
  }

  static String _ensureSharedProfile(
    List<CliApiConfig> sharedProfiles,
    Map<String, String> sharedByKey,
    CliApiConfig profile, {
    required String fallbackLabel,
  }) {
    final dedupeKey = _sharedProfileDedupeKey(profile);
    if (dedupeKey.isNotEmpty) {
      final existing = sharedByKey[dedupeKey];
      if (existing != null) {
        return existing;
      }
    }

    final sharedId = profile.sharedProfileId.trim().isNotEmpty
        ? profile.sharedProfileId.trim()
        : _newSharedProfileId(sharedProfiles.length);
    final normalized = _normalizedSharedProfile(
      profile.copyWith(
        sharedProfileId: sharedId,
        profileName:
            profile.profileName.trim().isEmpty ? fallbackLabel : profile.profileName,
      ),
    );
    sharedProfiles.add(normalized);
    if (dedupeKey.isNotEmpty) {
      sharedByKey[dedupeKey] = sharedId;
    }
    return sharedId;
  }

  static CliApiConfig _normalizedSharedProfile(CliApiConfig profile) {
    return CliApiConfig(
      toolId: 'shared',
      sharedProfileId: profile.sharedProfileId.trim(),
      profileName: profile.profileName.trim(),
      apiProtocol: profile.effectiveApiProtocol,
      baseUrl: profile.baseUrl.trim(),
      apiKey: profile.apiKey.trim(),
    );
  }

  static String _sharedProfileDedupeKey(CliApiConfig profile) {
    final protocol = profile.effectiveApiProtocol.trim();
    final baseUrl = profile.baseUrl.trim();
    final apiKey = profile.apiKey.trim();
    if (protocol.isEmpty && baseUrl.isEmpty && apiKey.isEmpty) {
      return '';
    }
    return '$protocol|$baseUrl|$apiKey';
  }

  static String _sharedProfileIdFromJson(
    Map<String, dynamic>? json, {
    required int index,
  }) {
    final existing = CliApiConfig.fromJson('shared', json).sharedProfileId.trim();
    return existing.isNotEmpty ? existing : _newSharedProfileId(index);
  }

  static String _newSharedProfileId(int index) =>
      'shared-${index + 1}-${DateTime.now().millisecondsSinceEpoch}';

  static CliApiConfig? _sharedProfileById(
    List<CliApiConfig> profiles,
    String sharedProfileId,
  ) {
    final id = sharedProfileId.trim();
    if (id.isEmpty) {
      return null;
    }
    for (final profile in profiles) {
      if (profile.sharedProfileId.trim() == id) {
        return profile;
      }
    }
    return null;
  }

  static List<Map<String, dynamic>> _sharedProfilesJson(
    List<CliApiConfig> profiles,
  ) {
    final normalized = <Map<String, dynamic>>[];
    var userProfileIndex = 0;
    for (var i = 0; i < profiles.length; i++) {
      if (_isLocalApiProxyProfile(profiles[i])) {
        continue;
      }
      userProfileIndex += 1;
      final profile = _normalizedSharedProfile(
        profiles[i].copyWith(
          profileName:
              profiles[i].profileName.trim().isEmpty
                  ? 'API $userProfileIndex'
                  : null,
          sharedProfileId: profiles[i].sharedProfileId.trim().isEmpty
              ? _newSharedProfileId(i)
              : profiles[i].sharedProfileId.trim(),
        ),
      );
      normalized.add(profile.toJson());
    }
    return normalized;
  }

  static Map<String, dynamic> _toolSettingsJson(CliApiConfig config) {
    return <String, dynamic>{
      'sharedProfileId': config.sharedProfileId.trim(),
      'baseUrl': config.baseUrl.trim(),
      'apiKey': config.apiKey.trim(),
      'model': config.model.trim(),
      'reasoningEffort': config.reasoningEffort.trim(),
      'modelMapping': config.modelMapping.trim(),
      'codexModelMapping': config.modelMapping.trim(),
      'apiProtocol': config.apiProtocol.trim(),
      'profileName': config.profileName.trim(),
    };
  }

  static String _preferNonEmpty(String primary, String fallback) {
    final normalizedPrimary = primary.trim();
    if (normalizedPrimary.isNotEmpty) {
      return normalizedPrimary;
    }
    return fallback.trim();
  }

  static bool _deepEquals(dynamic left, dynamic right) {
    final encoder = const JsonEncoder();
    return encoder.convert(left) == encoder.convert(right);
  }

  static String _buildGlobalEnvFile() {
    return [
      '# Generated by OpenClaw app. Safe to source from CLI wrappers.',
      'export HOME=${_shQuote('/root')}',
      'export USER=${_shQuote('root')}',
      'export LOGNAME=${_shQuote('root')}',
      'export XDG_CONFIG_HOME=${_shQuote('/root/.config')}',
      'export CODEX_HOME=${_shQuote('/root/.codex')}',
      'export GEMINI_CONFIG_DIR=${_shQuote('/root/.gemini')}',
      'export OPENCLAW_CLI_ENV_LOADED=1',
      'export OPENCLAW_CLI_WORKSPACE=${_shQuote(cliWorkspacePath)}',
      'export OPENCLAW_CLI_PROJECTS=${_shQuote(_cliWorkspaceProjectsPath)}',
      'export OPENCLAW_CLI_SCRATCH=${_shQuote(_cliWorkspaceScratchPath)}',
      'export OPENCLAW_RUNTIME_PLATFORM=${_shQuote('android-ubuntu-proot')}',
      'export OPENCLAW_RUNTIME_DESCRIPTION='
          '${_shQuote('Ubuntu rootfs running inside an Android app through PRoot')}',
      'export TERM="\${TERM:-xterm-256color}"',
      'export COLORTERM="\${COLORTERM:-truecolor}"',
      'export FORCE_COLOR=1',
      'export TMPDIR="\${TMPDIR:-/tmp}"',
      'export PATH=${_shQuote(_managedCliBinDir)}:/usr/local/bin:/usr/bin:/bin:\${PATH:-}',
      'mkdir -p "\${OPENCLAW_CLI_WORKSPACE:-$cliWorkspacePath}" "\${OPENCLAW_CLI_PROJECTS:-$_cliWorkspaceProjectsPath}" "\${OPENCLAW_CLI_SCRATCH:-$_cliWorkspaceScratchPath}" "\${OPENCLAW_CLI_WORKSPACE:-$cliWorkspacePath}/.gemini" "\${OPENCLAW_CLI_WORKSPACE:-$cliWorkspacePath}/.gen-cli" "\${OPENCLAW_CLI_WORKSPACE:-$cliWorkspacePath}/.agents/skills" "\${CODEX_HOME:-/root/.codex}" "\${GEMINI_CONFIG_DIR:-/root/.gemini}" "\${XDG_CONFIG_HOME:-/root/.config}" 2>/dev/null || true',
      '',
    ].join('\n');
  }

  static Future<String> _buildLocalApiProxyConfig(
    Map<String, dynamic> config,
  ) async {
    final existingConfig = await _readLocalApiProxyConfig();
    final proxyConfig = _mergeLocalApiProxyConfig(config, existingConfig);
    return '${const JsonEncoder.withIndent('  ').convert(proxyConfig)}\n';
  }

  static Future<Map<String, dynamic>> _readLocalApiProxyConfig() async {
    try {
      final content = await NativeBridge.readRootfsFile(_localApiProxyConfigPath);
      if (content == null || content.trim().isEmpty) {
        return <String, dynamic>{};
      }
      final decoded = jsonDecode(content);
      return _asMap(decoded);
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Map<String, dynamic> _mergeLocalApiProxyConfig(
    Map<String, dynamic> config,
    Map<String, dynamic> existingConfig,
  ) {
    final sharedProfiles = _sharedProfilesFromConfig(config);
    final providers = _asMap(existingConfig['providers']);
    final providerIdsBySharedId = <String, String>{};

    for (var i = 0; i < sharedProfiles.length; i++) {
      final profile = sharedProfiles[i];
      if (profile.baseUrl.trim().isEmpty || _isLocalApiProxyProfile(profile)) {
        continue;
      }
      final providerId = _apiProxyProviderId(profile, index: i);
      providerIdsBySharedId[profile.sharedProfileId] = providerId;
      providers[providerId] = _apiProxyProviderJson(
        profile,
        fallbackName: 'API ${i + 1}',
      );
    }

    final mappings = _asMap(existingConfig['model_mappings']);
    final appManagedAliases = <String>{};

    final activeConfigs = {
      for (final toolId in configurableToolIds)
        toolId: _resolvedToolConfig(toolId, config),
    };
    for (final entry in activeConfigs.entries) {
      final toolConfig = entry.value;
      if (toolConfig.baseUrl.trim().isEmpty ||
          _isLocalApiProxyProfile(toolConfig)) {
        continue;
      }
      var providerId = providerIdsBySharedId[toolConfig.sharedProfileId];
      if (providerId == null || !providers.containsKey(providerId)) {
        providerId = _apiProxyProviderId(toolConfig, index: providers.length);
        providers[providerId] = _apiProxyProviderJson(
          toolConfig,
          fallbackName: entry.key,
        );
      }
      final alias = toolConfig.effectiveToolModel.trim();
      final actualModel = toolConfig.model.trim().isNotEmpty
          ? toolConfig.model.trim()
          : alias;
      if (alias.isEmpty || actualModel.isEmpty) {
        continue;
      }
      appManagedAliases.add(alias);
      final existingMapping = _asMap(mappings[alias]);
      mappings[alias] = <String, dynamic>{
        ...existingMapping,
        'provider': providerId,
        'model': actualModel,
        'protocol': _apiProxyClientProtocol(toolConfig.effectiveApiProtocol),
      };
    }

    final server = _asMap(existingConfig['server']);
    server['host'] = '127.0.0.1';
    server['port'] = 9999;

    final proxyConfig = Map<String, dynamic>.from(existingConfig);
    proxyConfig['server'] = server;
    proxyConfig['providers'] = providers;
    proxyConfig['model_mappings'] = mappings;
    proxyConfig['prefix_routes'] = _asMap(existingConfig['prefix_routes']);
    proxyConfig['default_provider'] = _selectLocalApiProxyDefaultProvider(
      existingConfig['default_provider'],
      providers,
    );
    proxyConfig.putIfAbsent('force_default_provider', () => false);
    final authTokens = _asStringList(existingConfig['auth_tokens']);
    proxyConfig['auth_tokens'] = authTokens.isEmpty
        ? <String>[_localApiProxyApiKey]
        : authTokens;
    proxyConfig['admin_tokens'] = _asList(existingConfig['admin_tokens']);
    proxyConfig['pricing'] = _asMap(existingConfig['pricing']);
    proxyConfig.putIfAbsent('log_max', () => 500);
    proxyConfig.putIfAbsent('debug_requests', () => false);
    proxyConfig['allow_local_unauthenticated'] = true;
    proxyConfig['admin_account'] = _asMap(existingConfig['admin_account']);
    proxyConfig['concurrency'] = _mergeLocalApiProxyConcurrency(
      _asMap(existingConfig['concurrency']),
    );
    proxyConfig['openclaw_app_managed_model_aliases'] = appManagedAliases.toList()
      ..sort();
    return proxyConfig;
  }

  static Map<String, dynamic> _apiProxyProviderJson(
    CliApiConfig profile, {
    required String fallbackName,
  }) {
    return <String, dynamic>{
        'name': profile.profileName.trim().isEmpty
            ? fallbackName
            : profile.profileName.trim(),
        'type': _apiProxyProviderType(profile.effectiveApiProtocol),
        'base_url': _trimTrailingSlash(profile.baseUrl),
        'api_key': profile.apiKey.trim(),
        'enabled': true,
      };
  }

  static String _selectLocalApiProxyDefaultProvider(
    dynamic current,
    Map<String, dynamic> providers,
  ) {
    final defaultProvider = current is String ? current.trim() : '';
    if (defaultProvider.isNotEmpty && providers.containsKey(defaultProvider)) {
      return defaultProvider;
    }
    return providers.keys.isEmpty ? '' : providers.keys.first;
  }

  static Map<String, dynamic> _mergeLocalApiProxyConcurrency(
    Map<String, dynamic> existing,
  ) {
    return <String, dynamic>{
        'max_upstream': 64,
        'http_max_connections': 100,
        'http_max_keepalive': 40,
        'connect_timeout': 10.0,
        'read_timeout': 300.0,
        'write_queue_size': 1000,
        'max_body_bytes': 8000000,
        'server_limit_concurrency': 96,
      }..addAll(existing);
  }

  static List<dynamic> _asList(dynamic value) {
    if (value is List) {
      return List<dynamic>.from(value);
    }
    return <dynamic>[];
  }

  static List<String> _asStringList(dynamic value) {
    if (value is! List) {
      return <String>[];
    }
    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  static String _apiProxyProviderId(CliApiConfig profile, {required int index}) {
    final source = profile.sharedProfileId.trim().isNotEmpty
        ? profile.sharedProfileId.trim()
        : (profile.profileName.trim().isNotEmpty
            ? profile.profileName.trim()
            : 'provider-${index + 1}');
    final normalized = source
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9_.-]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return normalized.isNotEmpty ? normalized : 'provider-${index + 1}';
  }

  static String _apiProxyProviderType(String protocol) {
    final normalized = _normalizedProtocol(protocol);
    return normalized == 'gemini' ? 'openai' : normalized;
  }

  static String _apiProxyClientProtocol(String protocol) {
    final normalized = _normalizedProtocol(protocol);
    return normalized == 'gemini' || normalized == 'ollama'
        ? 'openai'
        : normalized;
  }

  static CliApiConfig _localApiProxyProfile() {
    return const CliApiConfig(
      toolId: 'shared',
      sharedProfileId: _localApiProxyProfileId,
      profileName: _localApiProxyProfileName,
      apiProtocol: 'openai',
      baseUrl: _localApiProxyBaseUrl,
      apiKey: _localApiProxyApiKey,
    );
  }

  static bool _isLocalApiProxyProfile(CliApiConfig profile) {
    if (profile.sharedProfileId.trim() == _localApiProxyProfileId) {
      return true;
    }
    return _isLocalApiProxyBaseUrl(profile.baseUrl);
  }

  static bool _isLocalApiProxyBaseUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null) {
      return false;
    }
    final scheme = uri.scheme.toLowerCase();
    final host = uri.host.toLowerCase();
    final port = uri.hasPort ? uri.port : (scheme == 'https' ? 443 : 80);
    final path = _trimTrailingSlash(uri.path.trim());
    return scheme == 'http' &&
        (host == '127.0.0.1' || host == 'localhost') &&
        port == 9999 &&
        (path.isEmpty || path == '/v1');
  }

  static String _buildTerminalThemeSh() {
    return r'''
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
''';
  }

  static String _buildCodexTermuxRuntimeSh() {
    return r'''#!/bin/sh

codex_set_top_level_toml_key() {
  file="$1"
  key="$2"
  value="$3"
  line="$key = $value"
  tmp="$file.tmp.$$"
  [ -f "$file" ] || : > "$file"
  awk -v key="$key" -v line="$line" '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    {
      left = $0
      sub(/[[:space:]]*=.*/, "", left)
      if (trim(left) == key) {
        next
      }
      if (!inserted && $0 ~ /^[[:space:]]*\[/) {
        print line
        inserted = 1
      }
      print
    }
    END {
      if (!inserted) {
        print line
      }
    }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

codex_remove_toml_key() {
  file="$1"
  key="$2"
  tmp="$file.tmp.$$"
  [ -f "$file" ] || return 0
  awk -v key="$key" '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    {
      left = $0
      sub(/[[:space:]]*=.*/, "", left)
      if (trim(left) == key) {
        next
      }
      print
    }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

codex_remove_toml_section() {
  file="$1"
  section_name="$2"
  section="[$section_name]"
  tmp="$file.tmp.$$"
  [ -f "$file" ] || return 0
  awk -v section="$section" '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    {
      probe = trim($0)
      if (probe ~ /^\[/) {
        if (probe == section) {
          skip = 1
          next
        }
        skip = 0
      }
      if (!skip) {
        print
      }
    }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

codex_toml_string() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g; s/^/"/; s/$/"/'
}

codex_configure_model_provider() {
  file="$1"
  provider_id="${2:-hhhl}"
  base_url="$3"
  [ -n "$base_url" ] || return 0

  codex_set_top_level_toml_key "$file" "model_provider" "$(codex_toml_string "$provider_id")"
  codex_remove_toml_section "$file" "model_providers.$provider_id"
  {
    printf '\n[model_providers.%s]\n' "$provider_id"
    printf 'name = %s\n' "$(codex_toml_string "$provider_id")"
    printf 'base_url = %s\n' "$(codex_toml_string "$base_url")"
    printf 'wire_api = "responses"\n'
    printf 'env_key = "OPENAI_API_KEY"\n'
    printf 'stream_idle_timeout_ms = 300000\n'
    printf 'request_max_retries = 2\n'
    printf 'stream_max_retries = 2\n'
  } >> "$file"
}

codex_configure_browser_mcp() {
  file="$1"
  mcp_script="${2:-/root/.openclaw/browser-mcp.mjs}"
  codex_remove_toml_section "$file" "mcp_servers.openclaw_browser"
  {
    printf '\n[mcp_servers.openclaw_browser]\n'
    printf 'command = "node"\n'
    printf 'args = [%s]\n' "$(codex_toml_string "$mcp_script")"
    printf 'startup_timeout_sec = 60\n'
    printf 'tool_timeout_sec = 120\n'
  } >> "$file"
}

codex_replace_or_append_property() {
  file="$1"
  key="$2"
  value="$3"
  line="$key = $value"
  tmp="$file.tmp.$$"
  [ -f "$file" ] || : > "$file"
  awk -v key="$key" -v line="$line" '
    function trim(s) {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", s)
      return s
    }
    {
      probe = $0
      sub(/^[#[:space:]]*/, "", probe)
      left = probe
      sub(/[[:space:]]*=.*/, "", left)
      if (trim(left) == key) {
        if (!done) {
          print line
          done = 1
        }
        next
      }
      print
    }
    END {
      if (!done) {
        print line
      }
    }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

configure_codex_termux_runtime() {
  codex_config="${CODEX_HOME:-/root/.codex}/config.toml"
  termux_config="${HOME:-/root}/.termux/termux.properties"
  mkdir -p "$(dirname "$codex_config")" "$(dirname "$termux_config")" 2>/dev/null || true
  touch "$codex_config" "$termux_config" 2>/dev/null || true
  codex_remove_toml_key "$codex_config" "approvals_reviewer"
  codex_provider_base_url="${CODEX_BASE_URL:-${OPENAI_BASE_URL:-}}"
  if [ -n "$codex_provider_base_url" ]; then
    codex_configure_model_provider "$codex_config" "hhhl" "$codex_provider_base_url"
  fi
  codex_configure_browser_mcp "$codex_config" "/root/.openclaw/browser-mcp.mjs"
  codex_model="${CODEX_MODEL:-${OPENAI_MODEL:-${OPENCLAW_MODEL:-}}}"
  if [ -n "$codex_model" ]; then
    codex_set_top_level_toml_key "$codex_config" "model" "$(codex_toml_string "$codex_model")"
  fi
  codex_effort="${CODEX_REASONING_EFFORT:-${OPENAI_REASONING_EFFORT:-${OPENCLAW_REASONING_EFFORT:-}}}"
  if [ -n "$codex_effort" ]; then
    codex_set_top_level_toml_key "$codex_config" "model_reasoning_effort" "$(codex_toml_string "$codex_effort")"
  fi
  codex_set_top_level_toml_key "$codex_config" "sandbox_mode" "\"danger-full-access\""
  codex_set_top_level_toml_key "$codex_config" "approval_policy" "\"never\""
  codex_set_top_level_toml_key "$codex_config" "tui.notifications" "false"
  codex_set_top_level_toml_key "$codex_config" "tui.terminal_title" "[]"
  if [ -n "${OPENAI_API_KEY:-}" ]; then
    codex_set_top_level_toml_key "$codex_config" "preferred_auth_method" "\"apikey\""
  fi

  codex_replace_or_append_property "$termux_config" "disable-terminal-session-change-toast" "true"
  codex_replace_or_append_property "$termux_config" "bell-character" "ignore"
  chmod 0600 "$codex_config" 2>/dev/null || true
  chmod 0644 "$termux_config" 2>/dev/null || true
}

case "${0##*/}" in
  codex-termux-runtime.sh)
    configure_codex_termux_runtime
    ;;
esac
''';
  }

  static String _toolEnvPath(String toolId) =>
      '/root/.openclaw/cli-env-$toolId.sh';

  static bool _shouldManageToolRuntime(CliApiConfig config) {
    return config.baseUrl.trim().isNotEmpty;
  }

  static String _buildToolEnvFile(String toolId, CliApiConfig config) {
    if (!_shouldManageToolRuntime(config)) {
      if (toolId == 'codex' && config.apiKey.trim().isNotEmpty) {
        return [
          '# Generated by OpenClaw app. Codex uses the official OpenAI API endpoint.',
          'export OPENCLAW_TOOL_ID=${_shQuote(toolId)}',
          'export OPENAI_API_KEY=${_shQuote(config.apiKey.trim())}',
          if (config.effectiveToolModel.trim().isNotEmpty)
            'export OPENAI_MODEL=${_shQuote(config.effectiveToolModel.trim())}',
          if (config.reasoningEffort.trim().isNotEmpty)
            'export OPENAI_REASONING_EFFORT=${_shQuote(config.reasoningEffort.trim())}',
          '',
        ].join('\n');
      }
      return [
        '# Generated by OpenClaw app.',
        '# No valid API base URL is configured for this tool.',
        '# The CLI will use its own official login state or default config.',
        '',
      ].join('\n');
    }

    final lines = <String>[
      '# Generated by OpenClaw app. Contains user API configuration.',
      'export OPENCLAW_TOOL_ID=${_shQuote(toolId)}',
      'export OPENCLAW_API_PROTOCOL=${_shQuote(config.effectiveApiProtocol)}',
    ];
    final baseUrl = config.baseUrl.trim();
    final apiKey = config.apiKey.trim();
    final serviceModel = config.model.trim();
    final toolModel = config.effectiveToolModel;
    final effort = config.reasoningEffort.trim();
    final openAiBaseUrl = baseUrl.isNotEmpty ? _localApiProxyBaseUrl : '';
    final protocol = _normalizedProtocol(config.effectiveApiProtocol);

    if (apiKey.isNotEmpty) {
      lines
        ..add('export OPENAI_API_KEY=${_shQuote(apiKey)}')
        ..add('export ANTHROPIC_API_KEY=${_shQuote(apiKey)}')
        ..add('export GEMINI_API_KEY=${_shQuote(apiKey)}')
        ..add('export GOOGLE_API_KEY=${_shQuote(apiKey)}')
        ..add('export SILICONFLOW_API_KEY=${_shQuote(apiKey)}')
        ..add('export QWEN_API_KEY=${_shQuote(apiKey)}')
        ..add('export DASHSCOPE_API_KEY=${_shQuote(apiKey)}')
        ..add('export CODEBUDDY_API_KEY=${_shQuote(apiKey)}')
        ..add('export CHINESE_LLM_API_KEY=${_shQuote(apiKey)}');
    } else if (toolId == 'codex' && openAiBaseUrl.isNotEmpty) {
      lines.add('export OPENAI_API_KEY=${_shQuote(_localApiProxyApiKey)}');
    }
    if (openAiBaseUrl.isNotEmpty) {
      lines
        ..add('export OPENAI_BASE_URL=${_shQuote(openAiBaseUrl)}')
        ..add('export CODEX_BASE_URL=${_shQuote(openAiBaseUrl)}')
        ..add('export ANTHROPIC_BASE_URL=${_shQuote(openAiBaseUrl)}')
        ..add('export GEMINI_BASE_URL=${_shQuote(openAiBaseUrl)}')
        ..add('export GOOGLE_GEMINI_BASE_URL=${_shQuote(openAiBaseUrl)}')
        ..add('export CODEBUDDY_BASE_URL=${_shQuote(openAiBaseUrl)}')
        ..add(
          'export OPENCLAW_CODEBUDDY_CHAT_URL='
          '${_shQuote(_chatCompletionsUrl(openAiBaseUrl))}',
        )
        ..add('export CHINESE_LLM_BASE_URL=${_shQuote(openAiBaseUrl)}');
    }
    if (toolModel.isNotEmpty) {
      lines
        ..add('export OPENAI_MODEL=${_shQuote(toolModel)}')
        ..add('export CODEX_MODEL=${_shQuote(toolModel)}')
        ..add('export ANTHROPIC_MODEL=${_shQuote(toolModel)}')
        ..add('export GEMINI_MODEL=${_shQuote(toolModel)}')
        ..add('export QWEN_MODEL=${_shQuote(toolModel)}')
        ..add('export CODEBUDDY_MODEL=${_shQuote(toolModel)}')
        ..add('export CODEBUDDY_BIG_SLOW_MODEL=${_shQuote(toolModel)}')
        ..add('export CODEBUDDY_SMALL_FAST_MODEL=${_shQuote(toolModel)}')
        ..add('export CODEBUDDY_CODE_SUBAGENT_MODEL=${_shQuote(toolModel)}')
        ..add('export CHINESE_LLM_MODEL=${_shQuote(toolModel)}')
        ..add('export OPENCLAW_MODEL=${_shQuote(toolModel)}');
    }
    if (serviceModel.isNotEmpty) {
      lines.add('export OPENCLAW_UPSTREAM_MODEL=${_shQuote(serviceModel)}');
    }
    if (effort.isNotEmpty) {
      lines
        ..add('export OPENAI_REASONING_EFFORT=${_shQuote(effort)}')
        ..add('export CODEX_REASONING_EFFORT=${_shQuote(effort)}')
        ..add('export QWEN_REASONING_EFFORT=${_shQuote(effort)}')
        ..add('export GEMINI_REASONING_EFFORT=${_shQuote(effort)}')
        ..add('export OPENCLAW_REASONING_EFFORT=${_shQuote(effort)}');
    }
    if (toolId == 'gemini') {
      lines
        ..add('export GOOGLE_GENAI_USE_VERTEXAI=false')
        ..add(
          'export GEMINI_DEFAULT_AUTH_TYPE=${_shQuote(_geminiAuthType(config))}',
        )
        ..add('export GEMINI_CLI_NO_BROWSER=1');
      if (protocol != 'gemini') {
        lines.add('unset GEMINI_API_KEY GOOGLE_API_KEY 2>/dev/null || true');
      }
      final customAlias = _geminiCustomModelAlias(config);
      if (customAlias.isNotEmpty) {
        lines.add(
          'export OPENCLAW_GEMINI_MODEL_ALIAS=${_shQuote(customAlias)}',
        );
      }
    }
    if (toolId == 'codebuddy' && config.baseUrl.trim().isEmpty) {
      lines.add('export CODEBUDDY_INTERNET_ENVIRONMENT=internal');
    }
    lines.add('');
    return lines.join('\n');
  }

  static String _buildCodeBuddyModelsJson(CliApiConfig config) {
    if (!_shouldManageToolRuntime(config)) {
      return '${const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
            'models': const <Map<String, dynamic>>[],
            'availableModels': const <String>[],
          })}\n';
    }
    final model = config.effectiveToolModel;
    final baseUrl = config.baseUrl.trim().isEmpty ? '' : _localApiProxyBaseUrl;
    final modelId = model.isEmpty ? 'openclaw-model' : model;
    final payload = <String, dynamic>{
      'models': [
        {
          'id': modelId,
          'name': modelId,
          'vendor': 'OpenAI',
          'apiKey': r'${CODEBUDDY_API_KEY}',
          if (baseUrl.isNotEmpty) 'url': _chatCompletionsUrl(baseUrl),
          'supportsToolCall': true,
          'supportsImages': true,
          'supportsReasoning': config.reasoningEffort.trim().isNotEmpty,
          'relatedModels': {
            'lite': modelId,
            'reasoning': modelId,
            'subagent': modelId,
          },
        },
      ],
      'availableModels': [modelId],
    };
    return '${const JsonEncoder.withIndent('  ').convert(payload)}\n';
  }

  static String _buildCodeBuddySettingsJson(CliApiConfig config) {
    if (!_shouldManageToolRuntime(config)) {
      return '${const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
            'permissions': {
              'defaultMode': 'bypassPermissions',
            },
          })}\n';
    }
    final payload = <String, dynamic>{
      'env': {
        if (config.apiKey.trim().isNotEmpty)
          'CODEBUDDY_API_KEY': config.apiKey.trim(),
        if (config.baseUrl.trim().isNotEmpty)
          'CODEBUDDY_BASE_URL': _localApiProxyBaseUrl,
        if (config.effectiveToolModel.isNotEmpty) ...{
          'OPENCLAW_MODEL': config.effectiveToolModel,
          'CODEBUDDY_MODEL': config.effectiveToolModel,
          'CODEBUDDY_BIG_SLOW_MODEL': config.effectiveToolModel,
          'CODEBUDDY_SMALL_FAST_MODEL': config.effectiveToolModel,
          'CODEBUDDY_CODE_SUBAGENT_MODEL': config.effectiveToolModel,
        },
        if (config.baseUrl.trim().isEmpty)
          'CODEBUDDY_INTERNET_ENVIRONMENT': 'internal',
      },
      'permissions': {
        'defaultMode': 'bypassPermissions',
      },
    };
    return '${const JsonEncoder.withIndent('  ').convert(payload)}\n';
  }

  static String _buildQwenSettingsJson(CliApiConfig config) {
    if (!_shouldManageToolRuntime(config)) {
      return '${const JsonEncoder.withIndent('  ').convert(<String, dynamic>{})}\n';
    }
    final protocol = _normalizedProtocol(config.effectiveApiProtocol);
    final envKey = _apiKeyEnvKey(protocol);
    final model = config.effectiveToolModel;
    final baseUrl = config.baseUrl.trim().isEmpty ? '' : _localApiProxyBaseUrl;
    final modelId = model.isEmpty ? 'openclaw-model' : model;
    final modelEntry = <String, dynamic>{
      'id': modelId,
      'name': modelId,
      'description': 'OpenClaw configured model',
      'envKey': envKey,
      if (baseUrl.isNotEmpty) 'baseUrl': baseUrl,
      if (config.reasoningEffort.trim().isNotEmpty)
        'generationConfig': {
          'extra_body': {
            'reasoning_effort': config.reasoningEffort.trim(),
          },
        },
    };
    final payload = <String, dynamic>{
      'modelProviders': {
        protocol: [modelEntry],
      },
      'env': {
        if (config.apiKey.trim().isNotEmpty) envKey: config.apiKey.trim(),
        if (protocol == 'openai' && baseUrl.isNotEmpty)
          'OPENAI_BASE_URL': baseUrl,
        if (protocol == 'openai') 'OPENAI_MODEL': modelId,
        if (protocol == 'anthropic') 'ANTHROPIC_MODEL': modelId,
        if (protocol == 'gemini') 'GEMINI_MODEL': modelId,
      },
      'security': {
        'auth': {
          'selectedType': protocol,
        },
      },
      'model': {
        'name': modelId,
      },
    };
    return '${const JsonEncoder.withIndent('  ').convert(payload)}\n';
  }

  static String _buildGeminiSettingsJson(CliApiConfig config) {
    if (!_shouldManageToolRuntime(config)) {
      return '${const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
            'telemetry': {
              'enabled': false,
            },
          })}\n';
    }
    final selectedModel = _geminiSelectedModel(config);
    final payload = <String, dynamic>{
      'security': {
        'auth': {
          'selectedType': _geminiAuthType(config),
        },
      },
      if (selectedModel.isNotEmpty)
        'model': {
          'name': selectedModel,
        },
      'telemetry': {
        'enabled': false,
      },
    };
    return '${const JsonEncoder.withIndent('  ').convert(payload)}\n';
  }

  static String _buildGeminiCustomModelsJson(CliApiConfig config) {
    if (!_geminiUsesCustomModelRouting(config)) {
      return '${const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
            'version': 1,
            'models': const <Map<String, dynamic>>[],
          })}\n';
    }
    final alias = _geminiCustomModelAlias(config);
    final defaultModel = config.model.trim().isNotEmpty
        ? config.model.trim()
        : config.effectiveToolModel.trim();
    final baseUrl = config.baseUrl.trim().isEmpty ? '' : _localApiProxyBaseUrl;
    final displayName = config.profileName.trim().isNotEmpty
        ? config.profileName.trim()
        : alias;
    final payload = <String, dynamic>{
      'version': 1,
      'models': [
        {
          'name': alias,
          'baseUrl': baseUrl,
          'apiKey': config.apiKey.trim(),
          'defaultModel': defaultModel,
          'displayName': displayName,
          'description': 'OpenClaw configured model - $baseUrl',
          'createdAt': '1970-01-01T00:00:00.000Z',
        },
      ],
      'defaultModel': alias,
    };
    return '${const JsonEncoder.withIndent('  ').convert(payload)}\n';
  }

  static String _buildGenCliSettingsJson(CliApiConfig config) {
    final payload = <String, dynamic>{
      'contextFileName': ['AGENTS.md', 'GEMINI.md', 'CONTEXT.md'],
      'telemetry': {
        'enabled': false,
      },
      'usageStatisticsEnabled': false,
    };
    return '${const JsonEncoder.withIndent('  ').convert(payload)}\n';
  }

  static String _buildHermesConfigYaml(CliApiConfig config) {
    if (!_shouldManageToolRuntime(config)) {
      return [
        '# Generated by OpenClaw app.',
        '# No valid API base URL is configured for Hermes Agent.',
        '# Hermes will keep using its own setup flow until a usable API is configured.',
        '',
      ].join('\n');
    }
    final model = config.effectiveToolModel.trim().isEmpty
        ? config.model.trim()
        : config.effectiveToolModel.trim();
    final lines = <String>[
      '# Generated by OpenClaw app. Hermes Agent runtime config.',
      'model:',
      '  provider: custom',
      '  base_url: ${_yamlString(_localApiProxyBaseUrl)}',
      if (model.isNotEmpty) '  default: ${_yamlString(model)}',
    ];
    if (config.reasoningEffort.trim().isNotEmpty) {
      lines
        ..add('agent:')
        ..add(
          '  reasoning_effort: ${_yamlString(config.reasoningEffort.trim())}',
        );
    }
    lines.add('');
    return lines.join('\n');
  }

  static String _buildHermesEnvFile(CliApiConfig config) {
    if (!_shouldManageToolRuntime(config)) {
      return [
        '# Generated by OpenClaw app.',
        '# Hermes Agent is currently using its own runtime state.',
        '',
      ].join('\n');
    }
    final lines = <String>[
      '# Generated by OpenClaw app. Hermes Agent environment.',
      if (config.apiKey.trim().isNotEmpty)
        'OPENAI_API_KEY=${_shQuote(config.apiKey.trim())}',
      if (config.baseUrl.trim().isNotEmpty)
        'OPENAI_BASE_URL=${_shQuote(_localApiProxyBaseUrl)}',
      if (config.effectiveToolModel.trim().isNotEmpty)
        'OPENAI_MODEL=${_shQuote(config.effectiveToolModel.trim())}',
      if (config.reasoningEffort.trim().isNotEmpty)
        'OPENAI_REASONING_EFFORT=${_shQuote(config.reasoningEffort.trim())}',
      '',
    ];
    return lines.join('\n');
  }

  static String _buildCodexToml(CliApiConfig codex) {
    final lines = <String>[];
    const providerId = 'hhhl';
    final managesRuntime = _shouldManageToolRuntime(codex);
    final apiKey = codex.apiKey.trim();
    final model = codex.effectiveToolModel.trim();
    final baseUrl = managesRuntime ? _localApiProxyBaseUrl : '';
    final effort = codex.reasoningEffort.trim();

    lines.add('# Generated by OpenClaw app. Safe to regenerate.');
    if (baseUrl.isNotEmpty) {
      lines.add('model_provider = ${_tomlString(providerId)}');
    }
    if (model.isNotEmpty) {
      lines.add('model = ${_tomlString(model)}');
    }
    lines.add('disable_response_storage = true');
    if (managesRuntime || apiKey.isNotEmpty) {
      lines.add('preferred_auth_method = "apikey"');
    }
    if (effort.isNotEmpty) {
      lines.add('model_reasoning_effort = ${_tomlString(effort)}');
    }
    lines
      ..add('sandbox_mode = "danger-full-access"')
      ..add('approval_policy = "never"')
      ..add('tui.notifications = false')
      ..add('tui.terminal_title = []');
    if (model.isNotEmpty) {
      lines
        ..add('')
        ..add('[tui.model_availability_nux]')
        ..add('${_tomlString(model)} = 4');
    }
    lines
      ..add('')
      ..add('[mcp_servers.openclaw_browser]')
      ..add('command = "node"')
      ..add('args = [${_tomlString(_browserMcpPath)}]')
      ..add('startup_timeout_sec = $_browserMcpStartupTimeoutSec')
      ..add('tool_timeout_sec = 120');
    if (baseUrl.isNotEmpty) {
      lines
        ..add('')
        ..add('[model_providers.$providerId]')
        ..add('name = ${_tomlString(providerId)}')
        ..add('base_url = ${_tomlString(baseUrl)}')
        ..add('wire_api = "responses"')
        ..add('env_key = "OPENAI_API_KEY"')
        ..add('stream_idle_timeout_ms = 300000')
        ..add('request_max_retries = 2')
        ..add('stream_max_retries = 2')
        ..add('')
        ..add('[projects.${_tomlString(cliWorkspacePath)}]')
        ..add('trust_level = "trusted"')
        ..add('')
        ..add('[projects.${_tomlString(_cliWorkspaceProjectsPath)}]')
        ..add('trust_level = "trusted"')
        ..add('')
        ..add('[projects.${_tomlString(_cliWorkspaceScratchPath)}]')
        ..add('trust_level = "trusted"');
    }

    lines.add('');
    return lines.join('\n');
  }

  static String _buildCodexAuthJson(CliApiConfig codex) {
    final apiKey = codex.apiKey.trim();
    final useApiAuth = _shouldManageToolRuntime(codex) || apiKey.isNotEmpty;
    final effectiveApiKey = apiKey.isNotEmpty
        ? apiKey
        : useApiAuth
            ? _localApiProxyApiKey
            : '';
    return '${const JsonEncoder.withIndent('  ').convert(<String, dynamic>{
          if (effectiveApiKey.isNotEmpty) 'OPENAI_API_KEY': effectiveApiKey,
        })}\n';
  }

  static String _shQuote(String value) {
    return "'${value.replaceAll("'", r"'\''")}'";
  }

  static String _tomlString(String value) {
    return jsonEncode(value);
  }

  static String _yamlString(String value) {
    return jsonEncode(value);
  }

  static String _buildBrowserMcpScript() {
    return '''
#!/usr/bin/env node

import { readFile } from "node:fs/promises";
import process from "node:process";

const ENV_PATH = ${jsonEncode(_browserBridgeEnvPath)};
const JSON_RPC_VERSION = "2.0";
const PROTOCOL_VERSION = "2025-06-18";

const TOOL_DEFS = [
  {
    name: "browser_self_test",
    description:
      "Open the OpenClaw in-app browser panel if needed and verify the bridge, WebView loading, and JavaScript execution using a local test page.",
    inputSchema: {
      type: "object",
      properties: {},
      additionalProperties: false,
    },
  },
  {
    name: "browser_health_check",
    description: "Wait until JavaScript, DOM readiness, DOM quiet time, and WebView resource activity indicate that the current page is ready after hydration.",
    inputSchema: {
      type: "object",
      properties: {
        quietWindowMs: { type: "integer", description: "Required quiet window in milliseconds; default 500." },
        timeoutMs: { type: "integer", description: "Maximum wait in milliseconds; default 10000." },
      },
      additionalProperties: false,
    },
  },
  {
    name: "browser_reset_tab",
    description: "Replace the active browser tab with a fresh WebView session, clearing stuck navigation. Optionally open a URL after reset.",
    inputSchema: {
      type: "object",
      properties: { url: { type: "string", description: "Optional URL to open after reset." } },
      additionalProperties: false,
    },
  },
  {
    name: "browser_control",
    description:
      "Stable single-entry browser automation tool. Use this when fine-grained browser tools are not exposed reliably; pass action such as open, tab_new, set_ua, list_interactables, type, click, capture_snapshot, or a browser_* tool name, plus payload.",
    inputSchema: {
      type: "object",
      properties: {
        action: {
          type: "string",
          description:
            "Bridge action or browser_* tool name, for example open, browser_open, tab_new, browser_set_ua, list_interactables, browser_type, click, or capture_snapshot.",
        },
        tool: {
          type: "string",
          description: "Alias for action.",
        },
        payload: {
          type: "object",
          description: "Payload for the selected action.",
          additionalProperties: true,
        },
        arguments: {
          type: "object",
          description: "Alias for payload, useful when copying an existing MCP tool call.",
          additionalProperties: true,
        },
      },
      additionalProperties: true,
    },
  },
  {
    name: "browser_open",
    description:
      "Open a URL in the OpenClaw in-app browser panel. Use this before clicking or extracting page content.",
    inputSchema: {
      type: "object",
      properties: {
        url: {
          type: "string",
          description: "The absolute URL to open. If the scheme is missing, https is assumed by the app.",
        },
      },
      required: ["url"],
      additionalProperties: false,
    },
  },
  {
    name: "browser_back",
    description: "Navigate one step back in the in-app browser history.",
    inputSchema: {
      type: "object",
      properties: {},
      additionalProperties: false,
    },
  },
  {
    name: "browser_forward",
    description: "Navigate one step forward in the in-app browser history.",
    inputSchema: {
      type: "object",
      properties: {},
      additionalProperties: false,
    },
  },
  {
    name: "browser_reload",
    description: "Reload the current in-app browser page.",
    inputSchema: {
      type: "object",
      properties: {},
      additionalProperties: false,
    },
  },
  {
    name: "browser_tab_list",
    description:
      "List all in-app browser tabs and the active tab. Use this before switching tabs.",
    inputSchema: {
      type: "object",
      properties: {},
      additionalProperties: false,
    },
  },
  {
    name: "browser_tab_new",
    description:
      "Open a new in-app browser tab. Optionally provide a URL to load in the new tab.",
    inputSchema: {
      type: "object",
      properties: {
        url: {
          type: "string",
          description: "Optional URL to open in the new tab.",
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: "browser_tab_switch",
    description: "Switch the active in-app browser tab by numeric tab id.",
    inputSchema: {
      type: "object",
      properties: {
        id: {
          type: "integer",
          description: "Browser tab id returned by browser_tab_list.",
        },
      },
      required: ["id"],
      additionalProperties: false,
    },
  },
  {
    name: "browser_tab_close",
    description:
      "Close a browser tab by numeric tab id. If id is omitted, closes the active tab.",
    inputSchema: {
      type: "object",
      properties: {
        id: {
          type: "integer",
          description: "Optional browser tab id returned by browser_tab_list.",
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: "browser_set_ua",
    description:
      "Switch the active browser tab user agent and reload the current page. Use desktop when a website shows a mobile layout unexpectedly.",
    inputSchema: {
      type: "object",
      properties: {
        mode: {
          type: "string",
          enum: ["desktop", "mobile"],
          description: "User-agent mode for the active tab.",
        },
      },
      required: ["mode"],
      additionalProperties: false,
    },
  },
  {
    name: "browser_click",
    description: "Click an element in the current page using a CSS selector.",
    inputSchema: {
      type: "object",
      properties: {
        selector: {
          type: "string",
          description: "CSS selector for the target element.",
        },
      },
      required: ["selector"],
      additionalProperties: false,
    },
  },
  {
    name: "browser_type",
    description:
      "Type text into a form field or editable element selected by CSS selector.",
    inputSchema: {
      type: "object",
      properties: {
        selector: {
          type: "string",
          description: "CSS selector for the editable element.",
        },
        text: {
          type: "string",
          description: "Text to insert into the target element.",
        },
        submit: {
          type: "boolean",
          description: "Whether to submit after typing.",
        },
      },
      required: ["selector", "text"],
      additionalProperties: false,
    },
  },
  {
    name: "browser_paste",
    description: "Paste text into a CSS-selected editable element using input, change, and composition events so React-style controlled fields stay synchronized.",
    inputSchema: {
      type: "object",
      properties: {
        selector: { type: "string", description: "CSS selector for the editable element." },
        text: { type: "string", description: "Text to paste." },
        submit: { type: "boolean", description: "Whether to submit after pasting." },
      },
      required: ["selector", "text"],
      additionalProperties: false,
    },
  },
  {
    name: "browser_wait_for_resource",
    description: "Wait for a loaded WebView resource whose URL contains a pattern, then return its URL and timing metadata.",
    inputSchema: {
      type: "object",
      properties: {
        pattern: { type: "string", description: "Case-insensitive substring to match against resource URLs." },
        timeoutMs: { type: "integer", description: "Maximum wait time in milliseconds." },
      },
      required: ["pattern"],
      additionalProperties: false,
    },
  },
  {
    name: "browser_list_overlays",
    description: "List currently visible dialogs, menus, listboxes, portals, and positioned overlays with text, role, z-index, and viewport bounds.",
    inputSchema: {
      type: "object",
      properties: { maxItems: { type: "integer", description: "Maximum overlays to return; default 24." } },
      additionalProperties: false,
    },
  },
  {
    name: "browser_click_at",
    description: "Click the element at viewport coordinates returned by an inspector or overlay query. Prefer selector clicks whenever possible.",
    inputSchema: {
      type: "object",
      properties: {
        x: { type: "number", description: "Viewport X coordinate." },
        y: { type: "number", description: "Viewport Y coordinate." },
      },
      required: ["x", "y"],
      additionalProperties: false,
    },
  },
  {
    name: "browser_wait_for_text",
    description:
      "Wait until specific text appears on the current page, useful after navigation or form submission.",
    inputSchema: {
      type: "object",
      properties: {
        text: {
          type: "string",
          description: "Text that must appear on the page.",
        },
        timeoutMs: {
          type: "integer",
          description: "Maximum wait time in milliseconds.",
          minimum: 500,
          maximum: 120000,
        },
      },
      required: ["text"],
      additionalProperties: false,
    },
  },
  {
    name: "browser_wait_for_selector",
    description:
      "Wait until a CSS selector exists, and by default is visible, on the current page.",
    inputSchema: {
      type: "object",
      properties: {
        selector: {
          type: "string",
          description: "CSS selector that must appear on the page.",
        },
        timeoutMs: {
          type: "integer",
          description: "Maximum wait time in milliseconds.",
          minimum: 500,
          maximum: 120000,
        },
        visible: {
          type: "boolean",
          description: "Whether the element must also be visible. Defaults to true.",
        },
      },
      required: ["selector"],
      additionalProperties: false,
    },
  },
  {
    name: "browser_scroll",
    description:
      "Scroll the page or a scrollable CSS-selected element. Useful before searching for below-the-fold controls.",
    inputSchema: {
      type: "object",
      properties: {
        selector: {
          type: "string",
          description: "Optional CSS selector for a scrollable element. Omit to scroll the page.",
        },
        direction: {
          type: "string",
          enum: ["down", "up", "left", "right", "top", "bottom"],
          description: "Scroll direction. Defaults to down.",
        },
        pixels: {
          type: "integer",
          description: "Scroll distance in pixels for relative directions.",
          minimum: 50,
          maximum: 5000,
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: "browser_press_key",
    description:
      "Press a keyboard key on the active element or a CSS-selected element, such as Enter, Escape, Tab, or ArrowDown.",
    inputSchema: {
      type: "object",
      properties: {
        selector: {
          type: "string",
          description: "Optional CSS selector to focus before pressing the key.",
        },
        key: {
          type: "string",
          description: "Keyboard key value, for example Enter, Escape, Tab, ArrowDown, or a single character.",
        },
      },
      required: ["key"],
      additionalProperties: false,
    },
  },
  {
    name: "browser_select_option",
    description:
      "Select an option in a native HTML select element by value, visible label, or zero-based index.",
    inputSchema: {
      type: "object",
      properties: {
        selector: {
          type: "string",
          description: "CSS selector for the select element.",
        },
        value: {
          type: "string",
          description: "Option value to select.",
        },
        label: {
          type: "string",
          description: "Visible option label or text to select.",
        },
        index: {
          type: "integer",
          description: "Zero-based option index to select.",
          minimum: 0,
        },
      },
      required: ["selector"],
      additionalProperties: false,
    },
  },
  {
    name: "browser_extract",
    description:
      "Extract readable text, HTML, and top links from the current page or from a CSS-selected subtree.",
    inputSchema: {
      type: "object",
      properties: {
        selector: {
          type: "string",
          description: "Optional CSS selector limiting extraction to one subtree.",
        },
        prompt: {
          type: "string",
          description: "Optional note describing what should be extracted.",
        },
        maxLength: {
          type: "integer",
          description: "Maximum number of characters to return for text and HTML.",
          minimum: 256,
          maximum: 16000,
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: "browser_list_links",
    description:
      "List visible links on the current page so Codex can choose a target before clicking.",
    inputSchema: {
      type: "object",
      properties: {
        filter: {
          type: "string",
          description: "Optional text filter applied to link text, href, and aria-label.",
        },
        maxItems: {
          type: "integer",
          description: "Maximum number of links to return.",
          minimum: 1,
          maximum: 40,
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: "browser_list_interactables",
    description:
      "List visible buttons, inputs, links, and other interactable elements together with suggested selectors.",
    inputSchema: {
      type: "object",
      properties: {
        filter: {
          type: "string",
          description: "Optional text filter applied to tag, role, type, text, aria, placeholder, and selector.",
        },
        maxItems: {
          type: "integer",
          description: "Maximum number of interactable elements to return.",
          minimum: 1,
          maximum: 60,
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: "browser_highlight",
    description:
      "Temporarily highlight a target element in the in-app browser so the user can visually confirm the selector.",
    inputSchema: {
      type: "object",
      properties: {
        selector: {
          type: "string",
          description: "CSS selector for the element that should be highlighted.",
        },
      },
      required: ["selector"],
      additionalProperties: false,
    },
  },
  {
    name: "browser_capture_snapshot",
    description:
      "Capture a structured page snapshot including title, URL, text, HTML, and top links.",
    inputSchema: {
      type: "object",
      properties: {
        selector: {
          type: "string",
          description: "Optional CSS selector limiting the snapshot to one subtree.",
        },
        maxLength: {
          type: "integer",
          description: "Maximum number of characters returned for text and HTML.",
          minimum: 512,
          maximum: 32000,
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: "browser_eval",
    description:
      "Run a small JavaScript snippet inside the current page and return its serialized result.",
    inputSchema: {
      type: "object",
      properties: {
        script: {
          type: "string",
          description: "JavaScript source code executed inside an IIFE.",
        },
      },
      required: ["script"],
      additionalProperties: false,
    },
  },
  {
    name: "browser_script_list",
    description:
      "List saved OpenClaw browser automation scripts and the current pending-save draft, including filenames, descriptions, quick commands, and run metadata.",
    inputSchema: {
      type: "object",
      properties: {
        filter: {
          type: "string",
          description: "Optional text filter for filename, description, source URL, or id.",
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: "browser_script_stage",
    description:
      "Update the script assistant pending-save draft after completing a reusable browser workflow. Codex should provide an auto-filled filename, purpose description, and explicit steps when possible.",
    inputSchema: {
      type: "object",
      properties: {
        fileName: {
          type: "string",
          description: "Auto-filled pending script filename, for example login-dashboard.browser.json.",
        },
        description: {
          type: "string",
          description: "Short purpose summary explaining when to reuse this script.",
        },
        steps: {
          type: "array",
          description:
            "Optional ordered reusable steps. Each step accepts action or browser_* tool plus payload or arguments. If omitted, recent repeatable browser actions are staged.",
          items: {
            type: "object",
            properties: {
              action: { type: "string" },
              tool: { type: "string" },
              payload: { type: "object" },
              arguments: { type: "object" },
              note: { type: "string" },
            },
            additionalProperties: true,
          },
        },
        variables: {
          type: "array",
          description:
            "Optional variable names used as {{name}} placeholders in step payload strings.",
          items: { type: "string" },
        },
        maxRecentSteps: {
          type: "integer",
          description: "Maximum recent repeatable actions to stage when steps are omitted.",
          minimum: 1,
          maximum: 40,
        },
        sourceUrl: {
          type: "string",
          description: "Optional source URL for the pending script draft.",
        },
        sourceTitle: {
          type: "string",
          description: "Optional source page title for the pending script draft.",
        },
      },
      required: ["fileName", "description"],
      additionalProperties: false,
    },
  },
  {
    name: "browser_script_save",
    description:
      "Save a reusable browser automation script. Provide explicit steps when possible; if steps are omitted, the app saves recent repeatable browser actions.",
    inputSchema: {
      type: "object",
      properties: {
        id: {
          type: "string",
          description: "Optional existing script id to overwrite.",
        },
        fileName: {
          type: "string",
          description: "User-facing script filename, for example daily-login.browser.json.",
        },
        description: {
          type: "string",
          description: "Short description of what the script is for.",
        },
        steps: {
          type: "array",
          description:
            "Optional ordered steps. Each step accepts action or browser_* tool plus payload or arguments.",
          items: {
            type: "object",
            properties: {
              action: { type: "string" },
              tool: { type: "string" },
              payload: { type: "object" },
              arguments: { type: "object" },
              note: { type: "string" },
            },
            additionalProperties: true,
          },
        },
        variables: {
          type: "array",
          description:
            "Optional variable names used as {{name}} placeholders in step payload strings.",
          items: { type: "string" },
        },
        maxRecentSteps: {
          type: "integer",
          description: "Maximum recent repeatable actions to save when steps are omitted.",
          minimum: 1,
          maximum: 40,
        },
        sourceUrl: {
          type: "string",
          description: "Optional source URL for the script record.",
        },
        sourceTitle: {
          type: "string",
          description: "Optional source page title for the script record.",
        },
        overwrite: {
          type: "boolean",
          description: "Whether a matching filename may be overwritten.",
        },
      },
      required: ["fileName", "description"],
      additionalProperties: false,
    },
  },
  {
    name: "browser_script_run",
    description:
      "Run a saved browser automation script by id or filename. The browser panel opens automatically when possible.",
    inputSchema: {
      type: "object",
      properties: {
        id: {
          type: "string",
          description: "Saved script id.",
        },
        fileName: {
          type: "string",
          description: "Saved script filename, used when id is unknown.",
        },
        variables: {
          type: "object",
          description: "Values for {{name}} placeholders inside script step payloads.",
        },
        stopOnError: {
          type: "boolean",
          description: "Whether to stop at the first failing step. Defaults to true.",
        },
      },
      additionalProperties: false,
    },
  },
  {
    name: "browser_script_rename",
    description:
      "Rename a saved browser automation script and update its description.",
    inputSchema: {
      type: "object",
      properties: {
        id: { type: "string", description: "Saved script id." },
        fileName: { type: "string", description: "New script filename." },
        description: { type: "string", description: "New script description." },
      },
      required: ["id", "fileName"],
      additionalProperties: false,
    },
  },
  {
    name: "browser_script_delete",
    description: "Delete a saved browser automation script by id.",
    inputSchema: {
      type: "object",
      properties: {
        id: { type: "string", description: "Saved script id." },
      },
      required: ["id"],
      additionalProperties: false,
    },
  },
  {
    name: "browser_script_clear_pending",
    description: "Clear the script assistant pending-save browser script draft.",
    inputSchema: {
      type: "object",
      properties: {},
      additionalProperties: false,
    },
  },
  {
    name: "browser_user_script_list",
    description: "List traditional website user scripts stored locally in the script assistant. These are separate from Codex browser automation workflows.",
    inputSchema: { type: "object", properties: {}, additionalProperties: false },
  },
  {
    name: "browser_user_script_save",
    description: "Save JavaScript generated for a traditional website user script. Saving never executes the code; the user must confirm execution in the script assistant.",
    inputSchema: {
      type: "object",
      properties: {
        id: { type: "string", description: "Existing script id to update; omit to create." },
        name: { type: "string", description: "Script name." },
        description: { type: "string", description: "Purpose description." },
        code: { type: "string", description: "Complete JavaScript source; Tampermonkey metadata comments are allowed." },
        matches: { type: "array", items: { type: "string" }, description: "Optional URL match patterns." },
      },
      required: ["name", "code"],
      additionalProperties: false,
    },
  },
  {
    name: "browser_set_script_auto_draft",
    description: "Enable or disable automatic pending browser-script drafts for this app session. Disabled by default.",
    inputSchema: {
      type: "object",
      properties: { enabled: { type: "boolean", description: "Whether successful recordable actions should create a pending draft." } },
      required: ["enabled"],
      additionalProperties: false,
    },
  },
  {
    name: "browser_get_state",
    description:
      "Return the current browser state including title, URL, tabs, active tab id, user-agent mode, loading flag, and the last bridge error.",
    inputSchema: {
      type: "object",
      properties: {},
      additionalProperties: false,
    },
  },
];

const TOOL_TO_ACTION = {
  browser_self_test: "self_test",
  browser_health_check: "health_check",
  browser_reset_tab: "reset_tab",
  browser_open: "open",
  browser_back: "back",
  browser_forward: "forward",
  browser_reload: "reload",
  browser_tab_list: "tab_list",
  browser_tab_new: "tab_new",
  browser_tab_switch: "tab_switch",
  browser_tab_close: "tab_close",
  browser_set_ua: "set_ua",
  browser_click: "click",
  browser_type: "type",
  browser_paste: "paste",
  browser_wait_for_resource: "wait_for_resource",
  browser_list_overlays: "list_overlays",
  browser_click_at: "click_at",
  browser_wait_for_text: "wait_for_text",
  browser_wait_for_selector: "wait_for_selector",
  browser_scroll: "scroll",
  browser_press_key: "press_key",
  browser_select_option: "select_option",
  browser_extract: "extract",
  browser_list_links: "list_links",
  browser_list_interactables: "list_interactables",
  browser_highlight: "highlight",
  browser_capture_snapshot: "capture_snapshot",
  browser_eval: "eval",
  browser_script_list: "script_list",
  browser_script_stage: "script_stage",
  browser_script_save: "script_save",
  browser_script_run: "script_run",
  browser_script_rename: "script_rename",
  browser_script_delete: "script_delete",
  browser_script_clear_pending: "script_clear_pending",
  browser_user_script_list: "user_script_list",
  browser_user_script_save: "user_script_save",
  browser_set_script_auto_draft: "script_set_auto_draft",
  browser_get_state: "get_state",
};

function normalizeBridgeAction(value) {
  const raw = String(value || "").trim();
  if (!raw) {
    return "";
  }
  return TOOL_TO_ACTION[raw] || raw;
}

function objectPayload(value) {
  if (value && typeof value === "object" && !Array.isArray(value)) {
    return value;
  }
  return {};
}

const HEADER_DELIMITER = Buffer.from("\\r\\n\\r\\n");
const NEWLINE = Buffer.from("\\n");
let stdinBuffer = Buffer.alloc(0);
let outputMode = "line";

function write(message) {
  const payload = Buffer.from(JSON.stringify(message), "utf8");
  if (outputMode !== "content-length") {
    process.stdout.write(payload.toString("utf8") + "\\n");
    return;
  }
  const header = Buffer.from(
    `Content-Length: \${payload.length}\\r\\nContent-Type: application/json\\r\\n\\r\\n`,
    "utf8",
  );
  process.stdout.write(Buffer.concat([header, payload]));
}

function reply(id, result) {
  write({ jsonrpc: JSON_RPC_VERSION, id, result });
}

function fail(id, code, message, data = undefined) {
  write({
    jsonrpc: JSON_RPC_VERSION,
    id,
    error: { code, message, ...(data === undefined ? {} : { data }) },
  });
}

async function readBridgeEnv() {
  const content = await readFile(ENV_PATH, "utf8");
  const values = {};
  for (const rawLine of content.split(/\\r?\\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#")) {
      continue;
    }
    const splitIndex = line.indexOf("=");
    if (splitIndex <= 0) {
      continue;
    }
    const key = line.slice(0, splitIndex).trim();
    let value = line.slice(splitIndex + 1).trim();
    if (
      (value.startsWith("'") && value.endsWith("'")) ||
      (value.startsWith('"') && value.endsWith('"'))
    ) {
      value = value.slice(1, -1);
    }
    values[key] = value;
  }
  return values;
}

async function callBridge(action, payload) {
  const env = await readBridgeEnv();
  const baseUrl = (env.OPENCLAW_BROWSER_BRIDGE_URL || "").trim();
  const token = (env.OPENCLAW_BROWSER_BRIDGE_TOKEN || "").trim();
  if (!baseUrl || !token) {
    throw new Error(
      "OpenClaw browser bridge is not ready. Open the browser panel in the app first.",
    );
  }

  const response = await fetch(`\${baseUrl}/\${action}`, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: `Bearer \${token}`,
    },
    body: JSON.stringify(payload || {}),
  });
  const text = await response.text();
  let decoded = {};
  if (text.trim().length > 0) {
    decoded = JSON.parse(text);
  }
  if (!response.ok) {
    throw new Error(decoded.message || `Bridge request failed: HTTP \${response.status}`);
  }
  return decoded;
}

function asToolContent(result) {
  return [
    {
      type: "text",
      text: JSON.stringify(result, null, 2),
    },
  ];
}

async function onRequest(message) {
  const id = message.id ?? null;
  const method = (message.method || "").trim();

  if (method === "initialize") {
    reply(id, {
      protocolVersion: PROTOCOL_VERSION,
      capabilities: {
        tools: {
          listChanged: false,
        },
      },
      serverInfo: {
        name: "openclaw-browser",
        version: "1.5.0",
      },
      instructions:
        "Use the OpenClaw browser tools for deterministic page navigation, scrolling, clicking, typing, selection, waiting, extraction, and reusable saved browser scripts inside the in-app browser panel. If individual tools are not exposed, use browser_control with action and payload. After completing a reusable workflow, update the script assistant pending-save draft with browser_script_stage.",
    });
    return;
  }

  if (method === "notifications/initialized") {
    return;
  }

  if (method === "ping") {
    reply(id, {});
    return;
  }

  if (method === "tools/list") {
    reply(id, { tools: TOOL_DEFS });
    return;
  }

  if (method === "tools/call") {
    const params = message.params || {};
    const toolName = (params.name || "").trim();
    const toolArguments = objectPayload(params.arguments || {});
    let action = TOOL_TO_ACTION[toolName];
    let payload = toolArguments;
    if (toolName === "browser_control") {
      action = normalizeBridgeAction(toolArguments.action || toolArguments.tool);
      payload = objectPayload(toolArguments.payload ?? toolArguments.arguments);
      if (Object.keys(payload).length === 0) {
        const {
          action: _action,
          tool: _tool,
          payload: _payload,
          arguments: _arguments,
          ...rest
        } = toolArguments;
        payload = objectPayload(rest);
      }
      if (!action) {
        reply(id, {
          content: asToolContent({
            ok: false,
            message: "browser_control requires an action.",
          }),
          structuredContent: {
            ok: false,
            message: "browser_control requires an action.",
          },
          isError: true,
        });
        return;
      }
    }
    if (!action) {
      reply(id, {
        content: asToolContent({
          ok: false,
          message: `Unsupported browser tool: \${toolName}`,
        }),
        isError: true,
      });
      return;
    }
    try {
      const result = await callBridge(action, payload);
      reply(id, {
        content: asToolContent(result),
        structuredContent: result,
        isError: result.ok === false,
      });
    } catch (error) {
      const result = {
        ok: false,
        message: error instanceof Error ? error.message : String(error),
      };
      reply(id, {
        content: asToolContent(result),
        structuredContent: result,
        isError: true,
      });
    }
    return;
  }

  fail(id, -32601, `Method not found: \${method}`);
}

function parseHeaders(text) {
  const headers = {};
  for (const line of text.split("\\r\\n")) {
    if (!line.trim()) continue;
    const index = line.indexOf(":");
    if (index <= 0) continue;
    headers[line.slice(0, index).trim().toLowerCase()] = line
      .slice(index + 1)
      .trim();
  }
  return headers;
}

function dispatchPayload(payloadText) {
  if (!payloadText.trim()) {
    return;
  }

  let message;
  try {
    message = JSON.parse(payloadText);
  } catch (error) {
    fail(null, -32700, "Invalid JSON received by browser MCP adapter", {
      detail: error instanceof Error ? error.message : String(error),
    });
    return;
  }

  onRequest(message).catch((error) => {
    fail(message?.id ?? null, -32000, "Unhandled browser MCP adapter error", {
      detail: error instanceof Error ? error.message : String(error),
    });
  });
}

function pumpStdin() {
  while (true) {
    const preview = stdinBuffer
      .slice(0, Math.min(stdinBuffer.length, 64))
      .toString("utf8");
    if (/^\\s*Content-Length:/i.test(preview)) {
      outputMode = "content-length";
      const headerEnd = stdinBuffer.indexOf(HEADER_DELIMITER);
      if (headerEnd < 0) {
        return;
      }

      const headerText = stdinBuffer.slice(0, headerEnd).toString("utf8");
      const headers = parseHeaders(headerText);
      const contentLength = Number.parseInt(headers["content-length"] || "", 10);
      if (!Number.isFinite(contentLength) || contentLength < 0) {
        fail(null, -32700, "Missing or invalid Content-Length in browser MCP adapter input");
        stdinBuffer = Buffer.alloc(0);
        return;
      }

      const frameStart = headerEnd + HEADER_DELIMITER.length;
      const frameEnd = frameStart + contentLength;
      if (stdinBuffer.length < frameEnd) {
        return;
      }

      const payloadText = stdinBuffer.slice(frameStart, frameEnd).toString("utf8");
      stdinBuffer = stdinBuffer.slice(frameEnd);
      dispatchPayload(payloadText);
      continue;
    }

    outputMode = "line";
    const newlineIndex = stdinBuffer.indexOf(NEWLINE);
    if (newlineIndex < 0) {
      return;
    }
    const payloadText = stdinBuffer.slice(0, newlineIndex).toString("utf8");
    stdinBuffer = stdinBuffer.slice(newlineIndex + NEWLINE.length);
    dispatchPayload(payloadText);
  }
}

process.stdin.on("data", (chunk) => {
  const bufferChunk = Buffer.isBuffer(chunk) ? chunk : Buffer.from(chunk);
  stdinBuffer = Buffer.concat([stdinBuffer, bufferChunk]);
  pumpStdin();
});

process.stdin.on("end", () => {
  process.exit(0);
});
''';
  }

  static String _buildBrowserScriptLauncherSh() {
    return '''
#!/usr/bin/env sh
set -eu

ENV_PATH=${_shQuote(_browserBridgeEnvPath)}

usage() {
  cat <<'USAGE'
Usage:
  browser-script state
  browser-script self-test
  browser-script call <action-or-browser_tool> [json-payload]
  browser-script control <action-or-browser_tool> [json-payload]
  browser-script open <url>
  browser-script tabs
  browser-script new-tab [url]
  browser-script switch-tab <tab-id>
  browser-script close-tab [tab-id]
  browser-script ua <desktop|mobile>
  browser-script interactables [filter] [maxItems]
  browser-script snapshot [selector] [maxLength]
  browser-script click <selector>
  browser-script type <selector> <text> [submit]
  browser-script wait-selector <selector> [timeoutMs]
  browser-script wait-text <text> [timeoutMs]
  browser-script scroll [direction] [pixels] [selector]
  browser-script press-key <key> [selector]
  browser-script list [filter]
  browser-script show <script-id-or-filename>
  browser-script stage <file-name> <description>
  browser-script run <script-id>
  browser-script delete <script-id>
  browser-script clear-pending
USAGE
}

if [ -r "\$ENV_PATH" ]; then
  . "\$ENV_PATH"
fi

base_url="\${OPENCLAW_BROWSER_BRIDGE_URL:-}"
token="\${OPENCLAW_BROWSER_BRIDGE_TOKEN:-}"
if [ -z "\$base_url" ] || [ -z "\$token" ]; then
  echo "OpenClaw browser bridge is not ready. Open the Codex browser panel first." >&2
  exit 1
fi

command_name="\${1:-list}"
if [ "\$#" -gt 0 ]; then
  shift
fi

case "\$command_name" in
  state|get-state)
    bridge_action="get_state"
    payload="{}"
    ;;
  self-test|self_test)
    bridge_action="self_test"
    payload="{}"
    ;;
  call|control|action)
    bridge_action="\${1:-}"
    [ -n "\$bridge_action" ] || { usage >&2; exit 2; }
    payload="\${2:-{}}"
    ;;
  open)
    url="\${1:-}"
    [ -n "\$url" ] || { usage >&2; exit 2; }
    bridge_action="open"
    payload=\$(node -e 'process.stdout.write(JSON.stringify({ url: process.argv[1] || "" }))' "\$url")
    ;;
  tabs|tab-list)
    bridge_action="tab_list"
    payload="{}"
    ;;
  new-tab|tab-new)
    url="\${1:-}"
    bridge_action="tab_new"
    payload=\$(node -e 'const payload = {}; if (process.argv[1]) payload.url = process.argv[1]; process.stdout.write(JSON.stringify(payload));' "\$url")
    ;;
  switch-tab|tab-switch)
    tab_id="\${1:-}"
    [ -n "\$tab_id" ] || { usage >&2; exit 2; }
    bridge_action="tab_switch"
    payload=\$(node -e 'const id = Number.parseInt(process.argv[1] || "", 10); process.stdout.write(JSON.stringify({ id: Number.isFinite(id) ? id : 0 }))' "\$tab_id")
    ;;
  close-tab|tab-close)
    tab_id="\${1:-}"
    bridge_action="tab_close"
    payload=\$(node -e 'const id = Number.parseInt(process.argv[1] || "", 10); const payload = {}; if (Number.isFinite(id)) payload.id = id; process.stdout.write(JSON.stringify(payload));' "\$tab_id")
    ;;
  ua|user-agent|set-ua)
    mode="\${1:-}"
    [ -n "\$mode" ] || { usage >&2; exit 2; }
    bridge_action="set_ua"
    payload=\$(node -e 'process.stdout.write(JSON.stringify({ mode: process.argv[1] || "" }))' "\$mode")
    ;;
  interactables|list-interactables)
    filter="\${1:-}"
    max_items="\${2:-}"
    bridge_action="list_interactables"
    payload=\$(node -e 'const maxItems = Number.parseInt(process.argv[2] || "", 10); const payload = { filter: process.argv[1] || "" }; if (Number.isFinite(maxItems)) payload.maxItems = maxItems; process.stdout.write(JSON.stringify(payload));' "\$filter" "\$max_items")
    ;;
  snapshot|capture-snapshot)
    selector="\${1:-}"
    max_length="\${2:-}"
    bridge_action="capture_snapshot"
    payload=\$(node -e 'const maxLength = Number.parseInt(process.argv[2] || "", 10); const payload = {}; if (process.argv[1]) payload.selector = process.argv[1]; if (Number.isFinite(maxLength)) payload.maxLength = maxLength; process.stdout.write(JSON.stringify(payload));' "\$selector" "\$max_length")
    ;;
  click)
    selector="\${1:-}"
    [ -n "\$selector" ] || { usage >&2; exit 2; }
    bridge_action="click"
    payload=\$(node -e 'process.stdout.write(JSON.stringify({ selector: process.argv[1] || "" }))' "\$selector")
    ;;
  type)
    selector="\${1:-}"
    text="\${2:-}"
    submit="\${3:-false}"
    [ -n "\$selector" ] || { usage >&2; exit 2; }
    bridge_action="type"
    payload=\$(node -e 'const submit = /^(1|true|yes|submit)\$/i.test(process.argv[3] || ""); process.stdout.write(JSON.stringify({ selector: process.argv[1] || "", text: process.argv[2] || "", submit }))' "\$selector" "\$text" "\$submit")
    ;;
  wait-selector|wait_for_selector)
    selector="\${1:-}"
    timeout_ms="\${2:-}"
    [ -n "\$selector" ] || { usage >&2; exit 2; }
    bridge_action="wait_for_selector"
    payload=\$(node -e 'const timeoutMs = Number.parseInt(process.argv[2] || "", 10); const payload = { selector: process.argv[1] || "" }; if (Number.isFinite(timeoutMs)) payload.timeoutMs = timeoutMs; process.stdout.write(JSON.stringify(payload));' "\$selector" "\$timeout_ms")
    ;;
  wait-text|wait_for_text)
    text="\${1:-}"
    timeout_ms="\${2:-}"
    [ -n "\$text" ] || { usage >&2; exit 2; }
    bridge_action="wait_for_text"
    payload=\$(node -e 'const timeoutMs = Number.parseInt(process.argv[2] || "", 10); const payload = { text: process.argv[1] || "" }; if (Number.isFinite(timeoutMs)) payload.timeoutMs = timeoutMs; process.stdout.write(JSON.stringify(payload));' "\$text" "\$timeout_ms")
    ;;
  scroll)
    direction="\${1:-down}"
    pixels="\${2:-}"
    selector="\${3:-}"
    bridge_action="scroll"
    payload=\$(node -e 'const pixels = Number.parseInt(process.argv[2] || "", 10); const payload = { direction: process.argv[1] || "down" }; if (Number.isFinite(pixels)) payload.pixels = pixels; if (process.argv[3]) payload.selector = process.argv[3]; process.stdout.write(JSON.stringify(payload));' "\$direction" "\$pixels" "\$selector")
    ;;
  press-key|press_key)
    key="\${1:-}"
    selector="\${2:-}"
    [ -n "\$key" ] || { usage >&2; exit 2; }
    bridge_action="press_key"
    payload=\$(node -e 'const payload = { key: process.argv[1] || "" }; if (process.argv[2]) payload.selector = process.argv[2]; process.stdout.write(JSON.stringify(payload));' "\$key" "\$selector")
    ;;
  list)
    filter="\${1:-}"
    bridge_action="script_list"
    payload=\$(node -e 'process.stdout.write(JSON.stringify({ filter: process.argv[1] || "" }))' "\$filter")
    ;;
  show)
    filter="\${1:-}"
    [ -n "\$filter" ] || { usage >&2; exit 2; }
    bridge_action="script_list"
    payload=\$(node -e 'process.stdout.write(JSON.stringify({ filter: process.argv[1] || "" }))' "\$filter")
    ;;
  stage)
    file_name="\${1:-}"
    description="\${2:-}"
    [ -n "\$file_name" ] || { usage >&2; exit 2; }
    [ -n "\$description" ] || { usage >&2; exit 2; }
    bridge_action="script_stage"
    payload=\$(node -e 'process.stdout.write(JSON.stringify({ fileName: process.argv[1] || "", description: process.argv[2] || "" }))' "\$file_name" "\$description")
    ;;
  run)
    script_id="\${1:-}"
    [ -n "\$script_id" ] || { usage >&2; exit 2; }
    bridge_action="script_run"
    payload=\$(node -e 'process.stdout.write(JSON.stringify({ id: process.argv[1] || "" }))' "\$script_id")
    ;;
  delete)
    script_id="\${1:-}"
    [ -n "\$script_id" ] || { usage >&2; exit 2; }
    bridge_action="script_delete"
    payload=\$(node -e 'process.stdout.write(JSON.stringify({ id: process.argv[1] || "" }))' "\$script_id")
    ;;
  clear-pending|discard-pending)
    bridge_action="script_clear_pending"
    payload="{}"
    ;;
  -h|--help|help)
    usage
    exit 0
    ;;
  *)
    usage >&2
    exit 2
    ;;
esac

node - "\$base_url" "\$token" "\$bridge_action" "\$payload" <<'NODE'
const [baseUrl, token, action, payloadText] = process.argv.slice(2);
const ACTION_ALIASES = {
  browser_control: "browser_control",
  browser_self_test: "self_test",
  browser_health_check: "health_check",
  browser_reset_tab: "reset_tab",
  browser_open: "open",
  browser_back: "back",
  browser_forward: "forward",
  browser_reload: "reload",
  browser_tab_list: "tab_list",
  browser_tab_new: "tab_new",
  browser_tab_switch: "tab_switch",
  browser_tab_close: "tab_close",
  browser_set_ua: "set_ua",
  browser_click: "click",
  browser_type: "type",
  browser_paste: "paste",
  browser_wait_for_resource: "wait_for_resource",
  browser_list_overlays: "list_overlays",
  browser_click_at: "click_at",
  browser_wait_for_text: "wait_for_text",
  browser_wait_for_selector: "wait_for_selector",
  browser_scroll: "scroll",
  browser_press_key: "press_key",
  browser_select_option: "select_option",
  browser_extract: "extract",
  browser_list_links: "list_links",
  browser_list_interactables: "list_interactables",
  browser_highlight: "highlight",
  browser_capture_snapshot: "capture_snapshot",
  browser_eval: "eval",
  browser_script_list: "script_list",
  browser_script_stage: "script_stage",
  browser_script_save: "script_save",
  browser_script_run: "script_run",
  browser_script_rename: "script_rename",
  browser_script_delete: "script_delete",
  browser_script_clear_pending: "script_clear_pending",
  browser_user_script_list: "user_script_list",
  browser_user_script_save: "user_script_save",
  browser_get_state: "get_state",
};

(async () => {
  let normalizedAction = ACTION_ALIASES[String(action || "").trim()] || String(action || "").trim();
  if (!normalizedAction) {
    console.error("Missing browser bridge action.");
    process.exitCode = 2;
    return;
  }

  let payload = {};
  try {
    payload = payloadText ? JSON.parse(payloadText) : {};
  } catch (error) {
    console.error("Invalid browser-script payload:", error instanceof Error ? error.message : String(error));
    process.exitCode = 1;
    return;
  }

  if (normalizedAction === "browser_control") {
    const nestedActionRaw = String(
      payload.action || payload.tool || "",
    ).trim();
    const nestedAction =
      ACTION_ALIASES[nestedActionRaw] || nestedActionRaw;
    if (!nestedAction) {
      console.error("browser_control requires an action.");
      process.exitCode = 2;
      return;
    }
    if (nestedAction === "browser_control") {
      console.error("browser_control cannot call itself.");
      process.exitCode = 2;
      return;
    }
    normalizedAction = nestedAction;
    if (payload && typeof payload === "object" && !Array.isArray(payload)) {
      const {
        action: _action,
        tool: _tool,
        payload: nestedPayload,
        arguments: nestedArguments,
        ...rest
      } = payload;
      if (nestedPayload && typeof nestedPayload === "object" && !Array.isArray(nestedPayload)) {
        payload = nestedPayload;
      } else if (
        nestedArguments &&
        typeof nestedArguments === "object" &&
        !Array.isArray(nestedArguments)
      ) {
        payload = nestedArguments;
      } else {
        payload = rest;
      }
    } else {
      payload = {};
    }
  }

  const response = await fetch(baseUrl.replace(/\\/\$/, "") + "/" + normalizedAction, {
    method: "POST",
    headers: {
      "content-type": "application/json",
      authorization: "Bearer " + token,
    },
    body: JSON.stringify(payload),
  });
  const text = await response.text();
  let decoded = {};
  if (text.trim()) {
    decoded = JSON.parse(text);
  }
  console.log(JSON.stringify(decoded, null, 2));
  if (!response.ok || decoded.ok === false) {
    process.exitCode = 1;
  }
})().catch((error) => {
  console.error(error instanceof Error ? error.message : String(error));
  process.exitCode = 1;
});
NODE
''';
  }

  static String _buildBrowserSkill() {
    return '''
---
name: browser-operator
description: Control the OpenClaw in-app browser panel from Codex CLI using deterministic browser tools.
---

Use this skill when the user asks you to inspect a webpage, click through a flow, fill a web form, or extract page content from OpenClaw's in-app browser.

Rules:
1. Start with `browser_get_state` so you know whether the browser panel is attached.
2. Use `browser_self_test` for the local bridge page, then use `browser_health_check` after external navigation or a form submit; it verifies JavaScript, DOM, hydration quiet time, and recent resource activity.
3. If the tool reports that the browser panel is unavailable, stop and tell the user to open the browser panel from the terminal screen.
4. If fine-grained MCP tools are not exposed reliably, use `browser_control` with an `action` plus `payload`, for example `{ "action": "type", "payload": { "selector": "#email", "text": "user@example.com" } }`.
5. If MCP tools are unavailable, use the shell fallback: `browser-script call <action-or-browser_tool> '<json-payload>'`, or shortcuts such as `browser-script interactables`, `browser-script snapshot`, `browser-script type`, and `browser-script click`.
6. The default user agent is mobile. Use `browser_set_ua` with `desktop` only when the task requires a desktop layout; it reloads the active page.
7. Prefer `browser_open`, `browser_health_check`, `browser_wait_for_text`, `browser_wait_for_selector`, `browser_wait_for_resource`, `browser_scroll`, `browser_list_interactables`, `browser_list_overlays`, `browser_highlight`, `browser_click`, `browser_paste`, `browser_type`, `browser_select_option`, `browser_press_key`, and `browser_extract` over `browser_eval`.
7. Use stable CSS selectors. Avoid fragile positional selectors unless there is no better choice.
8. Before any action that could submit a form, log in, send a message, spend money, or change user data, ask for confirmation.
10. After navigation or form submission, call `browser_health_check` and then wait for a specific selector, text, or resource. Use `browser_reset_tab` if a page stays stuck.
10. When extracting content, keep the result focused. Use `selector` whenever possible instead of dumping the whole page.
11. If the next selector is unclear, call `browser_list_interactables` or `browser_list_links` first and choose from the returned candidates.
12. If a selector is risky, call `browser_highlight` before clicking so the user can visually confirm the target.
13. Use `browser_scroll` for below-the-fold content before falling back to broad extraction.
14. Use `browser_press_key` for keyboard-driven UI and `browser_select_option` for native dropdowns.
15. Before repeating a known workflow, call `browser_script_list` and prefer `browser_script_run` when a matching script exists.
17. Automatic script drafts are disabled by default to avoid noisy output. Call `browser_script_stage` only when the user asks to preserve a reusable workflow; `browser_set_script_auto_draft` can opt in for the session.
17. Prefer explicit reusable steps in `browser_script_stage`. If the exact steps are already in the recent action log, staging without steps is acceptable, but still provide the filename and purpose description.
18. Saved scripts replay deterministic browser actions. Do not save secrets in descriptions, filenames, or variable names; use `{{name}}` placeholders for values that should change per run.
19. For login, API-key creation, payment, posting, deletion, or other sensitive flows, stage reusable navigation and form structure only; replace passwords, tokens, one-time codes, and user-specific values with placeholders.
20. Use `browser_tab_list` before switching if you need to preserve several open pages during a long workflow.
21. Use `browser_tab_new` for starting an unrelated page, `browser_tab_switch` for returning to a saved context, and `browser_tab_close` only after the page state is no longer needed.
23. For portal menus, inspect `browser_list_overlays`, then use a stable selector or the returned bounds with `browser_click_at` as a last resort.
24. Traditional website scripts (for example Tampermonkey-style JavaScript) are separate from Codex replay workflows. Generate source only when the user asks, then save it with `browser_user_script_save`; never execute generated user-script code automatically.

Typical flow:
1. `browser_open`
2. `browser_wait_for_text` or `browser_wait_for_selector`
3. `browser_list_interactables`
4. `browser_tab_list` or `browser_tab_new` when the task spans multiple pages
5. `browser_scroll` if the needed element is not visible
6. `browser_highlight`
7. `browser_click`, `browser_type`, `browser_select_option`, or `browser_press_key`
8. `browser_capture_snapshot` or `browser_extract`
9. `browser_script_stage` with an auto filename, purpose description, and reusable steps so the user can save it from the script assistant.
10. Fall back to `browser_eval` only if the built-in actions are insufficient.
11. If any listed tool is missing from the callable tools, run the same step through `browser_control`.

Script flow:
1. `browser_script_list` with a short filter from the user request.
2. `browser_script_run` when a saved script matches.
3. If no script matches, perform the workflow manually with browser tools.
4. After the manual workflow succeeds, call `browser_script_stage` and set `fileName` such as `site-task.browser.json`, plus a concise `description` explaining when to reuse it.
5. If `browser_script_stage` is missing, use `browser_control` with `{ "action": "script_stage", "payload": ... }` or `browser-script stage <file-name> <description>`.
6. Use `browser_script_save` only when the user explicitly asks Codex to save directly instead of placing the result in the pending-save area.
''';
  }

  static String _buildCliWorkspaceAgentsMd() {
    return '''
# OpenClaw CLI Workspace

- 当前运行环境是 Android 应用中的 Ubuntu rootfs，通过 PRoot 提供 Linux 用户空间。
- 默认开发目录是 `${cliWorkspacePath}`，生成的项目、代码、脚本和临时文件优先放在这里。
- 如需新建工程，请优先使用 `./projects`；临时文件和实验内容请优先使用 `./scratch`。
- `/storage/emulated/0` 和 `/sdcard` 映射到 Android 共享存储，但权限、性能和路径行为通常不如当前工作区稳定。
- 不要默认假设这里有 systemd、Docker、KVM、桌面会话或完整内核能力；需要时先自行检测。
''';
  }

  static String _buildCliWorkspaceGeminiMd() {
    return '''
# OpenClaw Android Ubuntu Context

- This CLI session runs inside an Ubuntu rootfs hosted by an Android app through PRoot.
- Use `${cliWorkspacePath}` as the default working directory for generated code and project files.
- Prefer `./projects` for long-lived repositories and `./scratch` for throwaway experiments.
- Android shared storage may be available at `/storage/emulated/0` and `/sdcard`, but it is slower and more permission-sensitive than the workspace.
- Verify assumptions before relying on systemd, Docker, kernel modules, or full desktop integrations.
''';
  }

  static String _buildCliWorkspaceContextMd() {
    return '''
# OpenClaw CLI Context

- Runtime: Ubuntu rootfs hosted inside an Android app through PRoot.
- Primary workspace: `${cliWorkspacePath}`.
- Put persistent projects under `./projects`.
- Put short-lived tests and generated scratch files under `./scratch`.
- Shared Android storage may exist at `/storage/emulated/0` and `/sdcard`, but it is slower and less predictable than the workspace.
- Confirm support before depending on systemd, Docker, kernel modules, nested virtualization, or desktop-only integrations.
''';
  }

  static String _buildCliWorkspaceGeminiSettingsJson(CliApiConfig config) {
    final payload = <String, dynamic>{
      if (_shouldManageToolRuntime(config))
        'security': {
          'auth': {
            'selectedType': _geminiAuthType(config),
          },
        },
      if (_shouldManageToolRuntime(config) &&
          _geminiSelectedModel(config).isNotEmpty)
        'model': {
          'name': _geminiSelectedModel(config),
        },
      'context': {
        'fileName': ['AGENTS.md', 'GEMINI.md', 'CONTEXT.md'],
      },
      'skills': {
        'enabled': true,
      },
      'experimental': {
        'enableAgents': true,
      },
    };
    return '${const JsonEncoder.withIndent('  ').convert(payload)}\n';
  }

  static String _geminiSelectedModel(CliApiConfig config) {
    if (_geminiUsesCustomModelRouting(config)) {
      final alias = _geminiCustomModelAlias(config);
      if (alias.isNotEmpty) {
        return alias;
      }
    }
    return config.effectiveToolModel.trim();
  }

  static String _geminiCustomModelAlias(CliApiConfig config) {
    if (!_geminiUsesCustomModelRouting(config)) {
      return '';
    }
    final preferred = config.profileName.trim();
    final source = preferred.isNotEmpty
        ? preferred
        : _trimTrailingSlash(config.baseUrl);
    final normalized = source
        .toLowerCase()
        .replaceAll(RegExp(r'^https?://'), '')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return normalized.isNotEmpty ? normalized : 'openclaw';
  }

  static String _buildCliWorkspaceSkill() {
    return '''
---
name: openclaw-android-runtime
description: Use when environment assumptions matter. Explains that the CLI runs inside Android-hosted Ubuntu via PRoot and that `${cliWorkspacePath}` is the default development workspace.
---

Rules:
1. Treat the runtime as Ubuntu in PRoot on Android, not as a full VM or desktop Linux machine.
2. Default working directory: `${cliWorkspacePath}`.
3. Put generated projects under `./projects` and short-lived experiments under `./scratch` unless the user asks for another path.
4. Android shared storage mounts (`/storage/emulated/0`, `/sdcard`) can be slower and more permission-sensitive than the workspace.
5. Verify support before relying on systemd, Docker, nested virtualization, kernel modules, or GUI-only tooling.
''';
  }

  static String _trimTrailingSlash(String value) {
    var result = value.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }

  static String _chatCompletionsUrl(String baseUrl) {
    final trimmed = _trimTrailingSlash(baseUrl);
    if (trimmed.isEmpty) return '';
    if (trimmed.endsWith('/chat/completions')) return trimmed;
    if (trimmed.endsWith('/v1')) return '$trimmed/chat/completions';
    return '$trimmed/v1/chat/completions';
  }

  static String _normalizedProtocol(String protocol) {
    final normalized = protocol.trim().toLowerCase();
    return switch (normalized) {
      'chat' || 'chat_completions' => 'openai',
      'response' || 'codex' => 'responses',
      'responses' => 'responses',
      'anthropic' => 'anthropic',
      'ollama' => 'ollama',
      'gemini' => 'gemini',
      _ => 'openai',
    };
  }

  static String _apiKeyEnvKey(String protocol) {
    return switch (_normalizedProtocol(protocol)) {
      'anthropic' => 'ANTHROPIC_API_KEY',
      'gemini' => 'GEMINI_API_KEY',
      _ => 'OPENAI_API_KEY',
    };
  }

  static bool _geminiUsesCustomModelRouting(CliApiConfig config) {
    return _shouldManageToolRuntime(config) &&
        _normalizedProtocol(config.effectiveApiProtocol) != 'gemini';
  }

  static String _geminiAuthType(CliApiConfig config) {
    return _geminiUsesCustomModelRouting(config)
        ? 'chinese-llm'
        : 'gemini-api-key';
  }

  static String _buildCliLauncherHeader(String toolEnvPath) {
    return '''
#!/bin/sh
export HOME="/root"
export USER="root"
export LOGNAME="root"
export XDG_CONFIG_HOME="/root/.config"
export CODEX_HOME="/root/.codex"
export GEMINI_CONFIG_DIR="/root/.gemini"
export NODE_OPTIONS="\${NODE_OPTIONS:---require /root/.openclaw/bionic-bypass.js}"
export NODE_EXTRA_CA_CERTS="\${NODE_EXTRA_CA_CERTS:-/etc/ssl/certs/ca-certificates.crt}"
export TMPDIR="\${TMPDIR:-/tmp}"
[ -r /root/.openclaw/terminal-theme.sh ] && . /root/.openclaw/terminal-theme.sh
[ -r /root/.openclaw/cli-env.sh ] && . /root/.openclaw/cli-env.sh
[ -r $toolEnvPath ] && . $toolEnvPath
mkdir -p "\${OPENCLAW_CLI_WORKSPACE:-$cliWorkspacePath}" "\${OPENCLAW_CLI_PROJECTS:-$_cliWorkspaceProjectsPath}" "\${OPENCLAW_CLI_SCRATCH:-$_cliWorkspaceScratchPath}" "\${OPENCLAW_CLI_WORKSPACE:-$cliWorkspacePath}/.gemini" "\${OPENCLAW_CLI_WORKSPACE:-$cliWorkspacePath}/.gen-cli" "\${OPENCLAW_CLI_WORKSPACE:-$cliWorkspacePath}/.agents/skills" "\${CODEX_HOME:-/root/.codex}" "\${GEMINI_CONFIG_DIR:-/root/.gemini}" "\${XDG_CONFIG_HOME:-/root/.config}" 2>/dev/null || true
cd "\${OPENCLAW_CLI_WORKSPACE:-$cliWorkspacePath}" 2>/dev/null || cd /root
''';
  }

  static String _buildCodexLauncherSh() {
    return '''${_buildCliLauncherHeader('/root/.openclaw/cli-env-codex.sh')}
[ -r /root/.openclaw/codex-termux-runtime.sh ] && . /root/.openclaw/codex-termux-runtime.sh
if command -v configure_codex_termux_runtime >/dev/null 2>&1; then
  configure_codex_termux_runtime || true
fi

CODEX_JS="/opt/openclaw-cli/codex/node_modules/@openai/codex/bin/codex.js"
CODEX_NATIVE="/opt/openclaw-cli/codex/node_modules/@openai/codex-linux-arm64/vendor/aarch64-unknown-linux-musl/bin/codex"
[ -f "\$CODEX_JS" ] || {
  echo "Codex CLI entrypoint not found: \$CODEX_JS" >&2
  echo "Reinstall Codex from the CLI tools page." >&2
  exit 1
}
[ -x "\$CODEX_NATIVE" ] || {
  echo "Codex native runtime not found or not executable: \$CODEX_NATIVE" >&2
  echo "Reinstall Codex from the CLI tools page to repair the linux-arm64 runtime." >&2
  exit 1
}

repair_codex_api_auth() {
  [ -n "\${OPENAI_API_KEY:-}" ] || return 0
  mkdir -p "\${CODEX_HOME:-/root/.codex}" 2>/dev/null || true
  if command -v python3 >/dev/null 2>&1; then
    CODEX_AUTH_FILE="\${CODEX_HOME:-/root/.codex}/auth.json" \
    OPENAI_API_KEY="\${OPENAI_API_KEY:-}" \
    python3 - <<'PY'
import json
import os

path = os.environ.get("CODEX_AUTH_FILE") or "/root/.codex/auth.json"
api_key = os.environ.get("OPENAI_API_KEY", "").strip()
if not api_key:
    raise SystemExit(0)

data = {}
try:
    with open(path, "r", encoding="utf-8") as handle:
        loaded = json.load(handle)
        if isinstance(loaded, dict):
            data = loaded
except Exception:
    data = {}

data = {key: value for key, value in data.items()
        if key == "OPENAI_API_KEY"}
data["OPENAI_API_KEY"] = api_key

tmp_path = f"{path}.tmp"
with open(tmp_path, "w", encoding="utf-8") as handle:
    json.dump(data, handle, indent=2)
    handle.write("\\n")
os.replace(tmp_path, path)
try:
    os.chmod(path, 0o600)
except OSError:
    pass
PY
  elif command -v node >/dev/null 2>&1; then
    CODEX_AUTH_FILE="\${CODEX_HOME:-/root/.codex}/auth.json" \
    OPENAI_API_KEY="\${OPENAI_API_KEY:-}" \
    node - <<'NODE'
const fs = require("fs");
const path = process.env.CODEX_AUTH_FILE || "/root/.codex/auth.json";
const apiKey = (process.env.OPENAI_API_KEY || "").trim();
if (!apiKey) process.exit(0);
const data = { OPENAI_API_KEY: apiKey };
fs.writeFileSync(`\${path}.tmp`, `\${JSON.stringify(data, null, 2)}\n`, {
  mode: 0o600,
});
fs.renameSync(`\${path}.tmp`, path);
try {
  fs.chmodSync(path, 0o600);
} catch {}
NODE
  fi
}
repair_codex_api_auth || true
if command -v configure_codex_termux_runtime >/dev/null 2>&1; then
  configure_codex_termux_runtime || true
fi

openclaw_passthrough=false
openclaw_has_sandbox_arg=false
openclaw_has_no_alt_screen=false
openclaw_cli_mode=false
if [ "\${1:-}" = "--openclaw-cli-mode" ]; then
  openclaw_cli_mode=true
  shift
fi
for arg in "\$@"; do
  case "\$arg" in
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
if [ "\$openclaw_passthrough" != true ] && [ "\$openclaw_has_sandbox_arg" != true ]; then
  set -- --dangerously-bypass-approvals-and-sandbox "\$@"
fi
if [ "\$openclaw_passthrough" != true ] && [ "\$openclaw_cli_mode" = true ] && [ "\$openclaw_has_no_alt_screen" != true ]; then
  set -- --no-alt-screen "\$@"
fi
exec node "\$CODEX_JS" "\$@"
''';
  }

  static String _buildGenericAgentLauncherSh() {
    return '''${_buildCliLauncherHeader('/root/.openclaw/cli-env-generic-agent.sh')}
GEN_REAL="/usr/local/bin/generic-agent"
[ -x "\$GEN_REAL" ] || {
  echo "Generic Agent entrypoint not found." >&2
  exit 1
}
exec "\$GEN_REAL" "\$@"
''';
  }

  static String _buildGeminiLauncherSh() {
    return '''${_buildCliLauncherHeader('/root/.openclaw/cli-env-gemini.sh')}
GEMINI_REAL="\$(node -e 'const path=require("node:path"); const pkg=require("/opt/openclaw-cli/gemini/node_modules/@google/gemini-cli/package.json"); const entry=(pkg.bin && (typeof pkg.bin === "string" ? pkg.bin : pkg.bin.gemini)) || pkg.main || "dist/index.js"; process.stdout.write(path.isAbsolute(entry) ? entry : `/opt/openclaw-cli/gemini/node_modules/@google/gemini-cli/\${entry}`);' 2>/dev/null)"
[ -n "\$GEMINI_REAL" ] && [ -f "\$GEMINI_REAL" ] || {
  echo "Gemini CLI entrypoint not found." >&2
  exit 1
}
openclaw_skip_model_injection=false
case "\${1:-}" in
  --version|-v|-V|version|help|--help|-h)
    openclaw_skip_model_injection=true
    ;;
esac
if [ "\$openclaw_skip_model_injection" != true ]; then
  if [ -n "\${OPENCLAW_GEMINI_MODEL_ALIAS:-}" ]; then
    set -- --model "\$OPENCLAW_GEMINI_MODEL_ALIAS" "\$@"
  elif [ -n "\${OPENCLAW_MODEL:-}" ]; then
    set -- --model "\$OPENCLAW_MODEL" "\$@"
  fi
fi
exec node "\$GEMINI_REAL" "\$@"
''';
  }

  static String _buildHermesLauncherSh() {
    return '''${_buildCliLauncherHeader('/root/.openclaw/cli-env-hermes-agent.sh')}
if [ -r /root/.hermes/.env ]; then
  set -a
  . /root/.hermes/.env
  set +a
fi
HERMES_VENV=/opt/openclaw-cli/hermes-agent/venv
if [ -x "\$HERMES_VENV/bin/python" ]; then
  exec "\$HERMES_VENV/bin/python" -m hermes_cli.main "\$@"
fi
echo "Hermes Agent runtime entrypoint is missing. Reinstall Hermes Agent from the CLI tools page." >&2
exit 127
''';
  }

  static String _buildClaudeProxyJs() {
    return r'''#!/usr/bin/env node
const http = require("http");
const https = require("https");
const fs = require("fs");
const { URL } = require("url");

const envFile = "/root/.openclaw/claude-proxy.env";

function loadEnv() {
  const values = {};
  if (!fs.existsSync(envFile)) return values;
  for (const rawLine of fs.readFileSync(envFile, "utf8").split(/\r?\n/)) {
    const line = rawLine.trim();
    if (!line || line.startsWith("#") || !line.includes("=")) continue;
    const index = line.indexOf("=");
    const key = line.slice(0, index).trim();
    let value = line.slice(index + 1).trim();
    if (
      (value.startsWith("'") && value.endsWith("'")) ||
      (value.startsWith('"') && value.endsWith('"'))
    ) {
      value = value.slice(1, -1);
    }
    values[key] = value;
  }
  return values;
}

function config() {
  const values = loadEnv();
  return {
    protocol: (
      values.OPENCLAW_CLAUDE_PROXY_PROTOCOL ||
      process.env.OPENCLAW_CLAUDE_PROXY_PROTOCOL ||
      "anthropic"
    ).toLowerCase(),
    upstream: (
      values.OPENCLAW_CLAUDE_PROXY_UPSTREAM ||
      process.env.OPENCLAW_CLAUDE_PROXY_UPSTREAM ||
      ""
    ).replace(/\/+$/, ""),
    token:
      values.OPENCLAW_CLAUDE_PROXY_API_KEY ||
      process.env.OPENCLAW_CLAUDE_PROXY_API_KEY ||
      "",
    model:
      values.OPENCLAW_CLAUDE_PROXY_MODEL ||
      process.env.OPENCLAW_CLAUDE_PROXY_MODEL ||
      "",
    reasoningEffort:
      values.OPENCLAW_CLAUDE_PROXY_REASONING_EFFORT ||
      process.env.OPENCLAW_CLAUDE_PROXY_REASONING_EFFORT ||
      "",
    host: values.OPENCLAW_CLAUDE_PROXY_HOST || "127.0.0.1",
    port: Number(values.OPENCLAW_CLAUDE_PROXY_PORT || 8788),
  };
}

function sendJson(res, status, payload) {
  const body = Buffer.from(JSON.stringify(payload));
  res.writeHead(status, {
    "content-type": "application/json",
    "content-length": body.length,
    connection: "close",
  });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    req.on("data", (chunk) => chunks.push(chunk));
    req.on("end", () => resolve(Buffer.concat(chunks)));
    req.on("error", reject);
  });
}

function joinText(content) {
  if (typeof content === "string") return content;
  if (!Array.isArray(content)) return "";
  return content
    .map((item) => {
      if (!item || typeof item !== "object") return "";
      if (item.type === "text") return item.text || "";
      if (item.type === "tool_result") {
        return typeof item.content === "string"
          ? item.content
          : joinText(item.content || []);
      }
      return "";
    })
    .filter(Boolean)
    .join("\n");
}

function anthropicMessagesToOpenAi(payload, cfg) {
  const messages = [];
  const system = joinText(payload.system || "");
  if (system) messages.push({ role: "system", content: system });

  for (const message of payload.messages || []) {
    const role = message.role === "assistant" ? "assistant" : "user";
    const content = message.content;
    if (Array.isArray(content)) {
      const text = joinText(content);
      const toolCalls = content
        .filter((item) => item && item.type === "tool_use")
        .map((item) => ({
          id: item.id,
          type: "function",
          function: {
            name: item.name || "",
            arguments: JSON.stringify(item.input || {}),
          },
        }));
      const toolResults = content.filter((item) => item && item.type === "tool_result");
      if (role === "assistant") {
        const converted = { role, content: text || null };
        if (toolCalls.length) converted.tool_calls = toolCalls;
        messages.push(converted);
      } else {
        if (text) messages.push({ role, content: text });
        for (const result of toolResults) {
          messages.push({
            role: "tool",
            tool_call_id: result.tool_use_id || result.id || "tool_call",
            content: joinText(result.content || ""),
          });
        }
      }
    } else {
      messages.push({ role, content: String(content || "") });
    }
  }

  const request = {
    model: cfg.model || payload.model,
    messages,
    stream: false,
  };
  if (payload.max_tokens) request.max_tokens = payload.max_tokens;
  if (payload.temperature !== undefined) request.temperature = payload.temperature;
  if (payload.top_p !== undefined) request.top_p = payload.top_p;
  if (cfg.reasoningEffort) request.reasoning_effort = cfg.reasoningEffort;
  if (Array.isArray(payload.tools) && payload.tools.length) {
    request.tools = payload.tools.map((tool) => ({
      type: "function",
      function: {
        name: tool.name,
        description: tool.description || "",
        parameters: tool.input_schema || { type: "object", properties: {} },
      },
    }));
    request.tool_choice = "auto";
  }
  return request;
}

function openAiToAnthropic(payload, openai, cfg) {
  const choice = (openai.choices || [])[0] || {};
  const message = choice.message || {};
  const content = [];
  if (message.content) {
    content.push({ type: "text", text: String(message.content) });
  }
  for (const call of message.tool_calls || []) {
    let input = {};
    try {
      input = JSON.parse(call.function?.arguments || "{}");
    } catch (_) {
      input = { raw: call.function?.arguments || "" };
    }
    content.push({
      type: "tool_use",
      id: call.id || `toolu_${Date.now()}`,
      name: call.function?.name || "",
      input,
    });
  }
  const finish = choice.finish_reason || "stop";
  return {
    id: openai.id || `msg_${Date.now()}`,
    type: "message",
    role: "assistant",
    model: cfg.model || payload.model || openai.model || "",
    content,
    stop_reason: finish === "tool_calls" ? "tool_use" : finish === "length" ? "max_tokens" : "end_turn",
    stop_sequence: null,
    usage: {
      input_tokens: openai.usage?.prompt_tokens || 0,
      output_tokens: openai.usage?.completion_tokens || 0,
    },
  };
}

function sse(res, event, data) {
  res.write(`event: ${event}\n`);
  res.write(`data: ${JSON.stringify(data)}\n\n`);
}

function sendAnthropicSse(res, message) {
  res.writeHead(200, {
    "content-type": "text/event-stream; charset=utf-8",
    "cache-control": "no-cache",
    connection: "close",
  });
  sse(res, "message_start", {
    type: "message_start",
    message: { ...message, content: [] },
  });
  message.content.forEach((block, index) => {
    if (block.type === "text") {
      sse(res, "content_block_start", {
        type: "content_block_start",
        index,
        content_block: { type: "text", text: "" },
      });
      if (block.text) {
        sse(res, "content_block_delta", {
          type: "content_block_delta",
          index,
          delta: { type: "text_delta", text: block.text },
        });
      }
    } else if (block.type === "tool_use") {
      sse(res, "content_block_start", {
        type: "content_block_start",
        index,
        content_block: {
          type: "tool_use",
          id: block.id,
          name: block.name,
          input: {},
        },
      });
      sse(res, "content_block_delta", {
        type: "content_block_delta",
        index,
        delta: {
          type: "input_json_delta",
          partial_json: JSON.stringify(block.input || {}),
        },
      });
    }
    sse(res, "content_block_stop", { type: "content_block_stop", index });
  });
  sse(res, "message_delta", {
    type: "message_delta",
    delta: {
      stop_reason: message.stop_reason || "end_turn",
      stop_sequence: null,
    },
    usage: { output_tokens: message.usage?.output_tokens || 0 },
  });
  sse(res, "message_stop", { type: "message_stop" });
  res.end();
}

function targetUrl(upstream, path, protocol) {
  if (!upstream) throw new Error("Claude proxy upstream is not configured");
  const upstreamPath = new URL(upstream).pathname.replace(/\/+$/, "");
  if (protocol === "openai") {
    if (upstreamPath.endsWith("/v1")) return upstream + "/chat/completions";
    return upstream + "/v1/chat/completions";
  }
  if (upstreamPath.endsWith("/v1") && path.startsWith("/v1/")) {
    return upstream + path.slice(3);
  }
  return upstream + path;
}

function proxyAnthropic(req, res, body, cfg) {
  let target;
  try {
    target = new URL(targetUrl(cfg.upstream, req.url, "anthropic"));
  } catch (error) {
    sendJson(res, 502, { error: String(error.message || error) });
    return;
  }
  const headers = { ...req.headers };
  delete headers.host;
  delete headers.connection;
  delete headers["content-length"];
  delete headers["accept-encoding"];
  delete headers.authorization;
  delete headers["x-api-key"];
  if (cfg.token) {
    headers["x-api-key"] = cfg.token;
    headers.authorization = `Bearer ${cfg.token}`;
  }
  headers["anthropic-version"] = headers["anthropic-version"] || "2023-06-01";
  if (body.length) headers["content-length"] = body.length;

  const transport = target.protocol === "https:" ? https : http;
  const upstreamReq = transport.request(
    target,
    { method: req.method, headers },
    (upstreamRes) => {
      const responseHeaders = { ...upstreamRes.headers };
      delete responseHeaders["transfer-encoding"];
      delete responseHeaders.connection;
      delete responseHeaders["content-encoding"];
      res.writeHead(upstreamRes.statusCode || 502, responseHeaders);
      upstreamRes.pipe(res);
    },
  );
  upstreamReq.on("error", (error) => {
    sendJson(res, 502, { error: String(error.message || error) });
  });
  upstreamReq.end(body);
}

async function handleOpenAi(req, res, body, cfg) {
  const pathname = new URL(req.url, "http://local").pathname;
  if (req.method === "GET" && pathname === "/v1/models") {
    sendJson(res, 200, {
      object: "list",
      data: cfg.model ? [{ id: cfg.model, object: "model" }] : [],
    });
    return;
  }
  if (req.method === "POST" && pathname === "/v1/messages/count_tokens") {
    let payload = {};
    try {
      payload = JSON.parse(body.toString("utf8") || "{}");
    } catch (_) {}
    const text = JSON.stringify(payload);
    sendJson(res, 200, { input_tokens: Math.max(1, Math.ceil(text.length / 4)) });
    return;
  }
  if (req.method !== "POST" || pathname !== "/v1/messages") {
    sendJson(res, 404, { error: "Only /v1/messages is supported in OpenAI compatibility mode" });
    return;
  }
  let payload;
  try {
    payload = JSON.parse(body.toString("utf8") || "{}");
  } catch (error) {
    sendJson(res, 400, { error: "Invalid JSON body" });
    return;
  }

  const openaiRequest = anthropicMessagesToOpenAi(payload, cfg);
  const wantsStream = payload.stream === true;
  let response;
  try {
    response = await fetch(targetUrl(cfg.upstream, req.url, "openai"), {
      method: "POST",
      headers: {
        "content-type": "application/json",
        authorization: cfg.token ? `Bearer ${cfg.token}` : "",
      },
      body: JSON.stringify(openaiRequest),
    });
  } catch (error) {
    sendJson(res, 502, { error: String(error.message || error) });
    return;
  }
  const text = await response.text();
  if (!response.ok) {
    res.writeHead(response.status, {
      "content-type": response.headers.get("content-type") || "application/json",
      "content-length": Buffer.byteLength(text),
      connection: "close",
    });
    res.end(text);
    return;
  }
  let openai;
  try {
    openai = JSON.parse(text);
  } catch (_) {
    sendJson(res, 502, { error: "OpenAI upstream returned non-JSON response" });
    return;
  }
  const anthropic = openAiToAnthropic(payload, openai, cfg);
  if (wantsStream) {
    sendAnthropicSse(res, anthropic);
  } else {
    sendJson(res, 200, anthropic);
  }
}

const server = http.createServer(async (req, res) => {
  const cfg = config();
  const requestUrl = new URL(req.url, `http://${cfg.host}:${cfg.port}`);
  if (requestUrl.pathname === "/health") {
    sendJson(res, 200, {
      ok: true,
      protocol: cfg.protocol,
      upstream: cfg.upstream,
      model: cfg.model,
      has_key: Boolean(cfg.token),
    });
    return;
  }
  const body = await readBody(req);
  if (cfg.protocol === "openai") {
    await handleOpenAi(req, res, body, cfg);
  } else {
    proxyAnthropic(req, res, body, cfg);
  }
});

const cfg = config();
server.listen(cfg.port, cfg.host);
''';
  }

  static Uri? _modelsEndpoint(String baseUrl, {String protocol = 'openai'}) {
    final trimmed = baseUrl.trim();
    if (trimmed.isEmpty) return null;
    final normalized = trimmed.endsWith('/')
        ? trimmed.substring(0, trimmed.length - 1)
        : trimmed;
    final uri = Uri.tryParse(normalized);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;

    final segments = uri.pathSegments.where((item) => item.isNotEmpty).toList();
    if (protocol == 'gemini') {
      if (segments.isNotEmpty && segments.last == 'models') {
        return uri;
      }
      if (segments.contains('v1beta') || segments.contains('v1')) {
        return uri.replace(pathSegments: [...segments, 'models']);
      }
      return uri.replace(pathSegments: ['v1beta', 'models']);
    }
    if (protocol == 'anthropic') {
      if (segments.isNotEmpty && segments.last == 'models') {
        return uri;
      }
      return uri.replace(pathSegments: [...segments, 'models']);
    }
    if (protocol == 'ollama') {
      if (segments.length >= 2 &&
          segments[segments.length - 2] == 'api' &&
          segments.last == 'tags') {
        return uri;
      }
      if (segments.isNotEmpty && segments.last == 'models') {
        return uri;
      }
      if (segments.isNotEmpty && segments.last == 'v1') {
        return uri.replace(pathSegments: [...segments, 'models']);
      }
      return uri.replace(pathSegments: ['api', 'tags']);
    }
    if (segments.isEmpty) {
      return uri.replace(pathSegments: ['v1', 'models']);
    }
    if (segments.last == 'models') {
      return uri;
    }
    return uri.replace(pathSegments: [...segments, 'models']);
  }

  static List<String> _extractModelIds(dynamic decoded) {
    return _extractModelOptions(decoded).map((item) => item.id).toList();
  }

  static List<CliApiModelOption> _extractModelOptions(dynamic decoded) {
    final result = <CliApiModelOption>[];
    void addModel(dynamic item) {
      if (item is String && item.trim().isNotEmpty) {
        result.add(CliApiModelOption(id: item.trim()));
        return;
      }
      if (item is Map) {
        final id = item['id'] ?? item['name'] ?? item['model'];
        if (id is String && id.trim().isNotEmpty) {
          result.add(
            CliApiModelOption(
              id: id.trim(),
              upstreamModel: _stringValue(item['upstream_model']).isNotEmpty
                  ? _stringValue(item['upstream_model'])
                  : id.trim(),
              providerId: _stringValue(item['owned_by']).isNotEmpty
                  ? _stringValue(item['owned_by'])
                  : _stringValue(item['provider']),
              providerName: _stringValue(item['provider_name']),
              providerBaseUrl: _stringValue(item['provider_base_url']),
              protocol: _stringValue(item['protocol']).isNotEmpty
                  ? _stringValue(item['protocol'])
                  : 'openai',
            ),
          );
        }
      }
    }

    if (decoded is Map) {
      final data = decoded['data'] ?? decoded['models'];
      if (data is List) {
        for (final item in data) {
          addModel(item);
        }
      } else {
        addModel(data);
      }
    } else if (decoded is List) {
      for (final item in decoded) {
        addModel(item);
      }
    }
    return result;
  }

  static String _stringValue(dynamic value) => value is String ? value.trim() : '';
}
