import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cli_api_config.dart';
import 'native_bridge.dart';

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
  static const _codexProxyPath = '/root/.openclaw/codex-proxy.py';
  static const _codexProxyJsPath = '/root/.openclaw/codex-proxy.js';
  static const _codexProxyEnvPath = '/root/.openclaw/codex-proxy.env';
  static const _codexConfigPath = '/root/.codex/config.toml';
  static const _codexProxyBaseUrl = 'http://127.0.0.1:8787/v1';
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

  static Future<CliApiConfig> load(String toolId) async {
    final configs = await _loadAll();
    return _resolvedToolConfig(toolId, configs);
  }

  static Future<List<CliApiConfig>> loadSharedProfiles() async {
    final configs = await _loadAll();
    return _sharedProfilesFromConfig(configs);
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

  static Future<void> saveSharedProfiles(List<CliApiConfig> profiles) async {
    final configs = await _loadAll();
    configs['sharedProfiles'] = _sharedProfilesJson(profiles);
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
    final codexProxyEnvMode =
        _shouldManageToolRuntime(codex) ? '0600' : '0000';

    await _writePrefsConfig(allConfigs);
    await NativeBridge.writeRootfsFile(
      _configPath,
      const JsonEncoder.withIndent('  ').convert(allConfigs),
    );
    await NativeBridge.writeRootfsFile(_envPath, _buildGlobalEnvFile());
    await NativeBridge.writeRootfsFile(
      _terminalThemePath,
      _buildTerminalThemeSh(),
    );
    await NativeBridge.writeRootfsFile(
      _cliWorkspaceAgentsPath,
      _buildCliWorkspaceAgentsMd(),
    );
    await NativeBridge.writeRootfsFile(
      _cliWorkspaceGeminiPath,
      _buildCliWorkspaceGeminiMd(),
    );
    await NativeBridge.writeRootfsFile(
      _cliWorkspaceContextPath,
      _buildCliWorkspaceContextMd(),
    );
    await NativeBridge.writeRootfsFile(
      _cliWorkspaceGeminiSettingsPath,
      _buildCliWorkspaceGeminiSettingsJson(gemini),
    );
    await NativeBridge.writeRootfsFile(
      _cliWorkspaceGeminiCustomModelsPath,
      _buildGeminiCustomModelsJson(gemini),
    );
    await NativeBridge.writeRootfsFile(
      _cliWorkspaceGenCliSettingsPath,
      _buildGenCliSettingsJson(activeConfigs['generic-agent']!),
    );
    await NativeBridge.writeRootfsFile(
      _genCliSettingsPath,
      _buildGenCliSettingsJson(activeConfigs['generic-agent']!),
    );
    await NativeBridge.writeRootfsFile(
      _cliWorkspaceSkillPath,
      _buildCliWorkspaceSkill(),
    );
    for (final entry in activeConfigs.entries) {
      await NativeBridge.writeRootfsFile(
        _toolEnvPath(entry.key),
        _buildToolEnvFile(entry.key, entry.value),
      );
    }
    await NativeBridge.writeRootfsFile(_codexProxyPath, _buildCodexProxyPy());
    await NativeBridge.writeRootfsFile(
      _codexProxyJsPath,
      _buildCodexProxyJs(),
    );
    await NativeBridge.writeRootfsFile(
      _codexProxyEnvPath,
      _buildCodexProxyEnv(codex),
    );
    await NativeBridge.writeRootfsFile(
      _browserMcpPath,
      _buildBrowserMcpScript(),
    );
    await NativeBridge.writeRootfsFile(
      _browserSkillPath,
      _buildBrowserSkill(),
    );
    await NativeBridge.writeRootfsFile(
      _browserCodexSkillPath,
      _buildBrowserSkill(),
    );
    await NativeBridge.writeRootfsFile(
      _codexLauncherPath,
      _buildCodexLauncherSh(),
    );
    await NativeBridge.writeRootfsFile(
      _genericAgentLauncherPath,
      _buildGenericAgentLauncherSh(),
    );
    await NativeBridge.writeRootfsFile(
      _geminiLauncherPath,
      _buildGeminiLauncherSh(),
    );
    await NativeBridge.writeRootfsFile(
      _hermesLauncherPath,
      _buildHermesLauncherSh(),
    );
    await NativeBridge.writeRootfsFile(_codexConfigPath, _buildCodexToml(codex));
    await NativeBridge.writeRootfsFile(
      _codeBuddyModelsPath,
      _buildCodeBuddyModelsJson(activeConfigs['codebuddy']!),
    );
    await NativeBridge.writeRootfsFile(
      _codeBuddySettingsPath,
      _buildCodeBuddySettingsJson(activeConfigs['codebuddy']!),
    );
    await NativeBridge.writeRootfsFile(
      _qwenSettingsPath,
      _buildQwenSettingsJson(activeConfigs['qwen-code']!),
    );
    await NativeBridge.writeRootfsFile(
      _geminiSettingsPath,
      _buildGeminiSettingsJson(gemini),
    );
    await NativeBridge.writeRootfsFile(
      _geminiCustomModelsPath,
      _buildGeminiCustomModelsJson(gemini),
    );
    await NativeBridge.writeRootfsFile(
      _hermesConfigPath,
      _buildHermesConfigYaml(activeConfigs['hermes-agent']!),
    );
    await NativeBridge.writeRootfsFile(
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
      'chmod 0755 $_codexProxyPath 2>/dev/null || true; '
      'chmod 0755 $_codexProxyJsPath 2>/dev/null || true; '
      'chmod 0755 $_browserMcpPath 2>/dev/null || true; '
      'chmod 0755 $_codexLauncherPath $_genericAgentLauncherPath '
      '$_geminiLauncherPath $_hermesLauncherPath 2>/dev/null || true; '
      'chmod $codexProxyEnvMode $_codexProxyEnvPath 2>/dev/null || true; '
      'chmod 0600 $_browserBridgeEnvPath 2>/dev/null || true; '
      'chmod 0600 $_codexConfigPath $_codeBuddyModelsPath '
      '$_codeBuddySettingsPath $_qwenSettingsPath $_geminiSettingsPath '
      '$_geminiCustomModelsPath $_cliWorkspaceGeminiCustomModelsPath '
      '$_genCliSettingsPath $_hermesConfigPath '
      '$_hermesEnvPath 2>/dev/null || true; '
      'chmod 0644 $_terminalThemePath 2>/dev/null || true; '
      'chmod 0644 $_cliWorkspaceAgentsPath $_cliWorkspaceGeminiPath '
      '$_cliWorkspaceContextPath $_cliWorkspaceGeminiSettingsPath '
      '$_cliWorkspaceGenCliSettingsPath '
      '$_cliWorkspaceSkillPath '
      '2>/dev/null || true; '
      'grep -q "openclaw/terminal-theme.sh" /root/.bashrc 2>/dev/null || '
      'printf "\\n[ -r /root/.openclaw/terminal-theme.sh ] && . /root/.openclaw/terminal-theme.sh\\n" >> /root/.bashrc; '
      'chmod 0600 /root/.openclaw/cli-env*.sh 2>/dev/null || true',
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
    } catch (_) {
      // Rootfs may not exist yet during first-run preconfiguration.
      // The setup flow calls regenerateRuntimeFiles() again after extraction.
    }
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
    final profile = _sharedProfileById(
      _sharedProfilesFromConfig(config),
      toolSettings.sharedProfileId,
    );
    return CliApiConfig(
      toolId: toolId,
      sharedProfileId: toolSettings.sharedProfileId,
      profileName: toolSettings.profileName.trim().isNotEmpty
          ? toolSettings.profileName
          : (profile?.profileName ?? ''),
      apiProtocol: profile?.effectiveApiProtocol ?? toolSettings.apiProtocol,
      baseUrl: profile?.baseUrl ?? '',
      apiKey: profile?.apiKey ?? '',
      model: toolSettings.model,
      reasoningEffort: toolSettings.reasoningEffort,
      modelMapping: toolSettings.modelMapping,
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
      model: settings.model,
      reasoningEffort: settings.reasoningEffort,
      modelMapping: settings.modelMapping,
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
    for (var i = 0; i < profiles.length; i++) {
      final profile = _normalizedSharedProfile(
        profiles[i].copyWith(
          profileName:
              profiles[i].profileName.trim().isEmpty ? 'API ${i + 1}' : null,
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
      'model': config.model.trim(),
      'reasoningEffort': config.reasoningEffort.trim(),
      'modelMapping': config.modelMapping.trim(),
      'codexModelMapping': config.modelMapping.trim(),
      'profileName': config.profileName.trim(),
    };
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
      'mkdir -p "\${OPENCLAW_CLI_WORKSPACE:-$cliWorkspacePath}" '
      '"\${OPENCLAW_CLI_PROJECTS:-$_cliWorkspaceProjectsPath}" '
      '"\${OPENCLAW_CLI_SCRATCH:-$_cliWorkspaceScratchPath}" '
      '"\${OPENCLAW_CLI_WORKSPACE:-$cliWorkspacePath}/.gemini" '
      '"\${OPENCLAW_CLI_WORKSPACE:-$cliWorkspacePath}/.gen-cli" '
      '"\${OPENCLAW_CLI_WORKSPACE:-$cliWorkspacePath}/.agents/skills" '
      '"\${CODEX_HOME:-/root/.codex}" '
      '"\${GEMINI_CONFIG_DIR:-/root/.gemini}" '
      '"\${XDG_CONFIG_HOME:-/root/.config}" '
      '2>/dev/null || true',
      '',
    ].join('\n');
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

  static String _toolEnvPath(String toolId) =>
      '/root/.openclaw/cli-env-$toolId.sh';

  static bool _shouldManageToolRuntime(CliApiConfig config) {
    return config.sharedProfileId.trim().isNotEmpty &&
        config.baseUrl.trim().isNotEmpty;
  }

  static String _buildToolEnvFile(String toolId, CliApiConfig config) {
    if (!_shouldManageToolRuntime(config)) {
      return [
        '# Generated by OpenClaw app.',
        '# No shared API selected for this tool.',
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
    final openAiBaseUrl = toolId == 'codex' && baseUrl.isNotEmpty
        ? _codexProxyBaseUrl
        : _trimTrailingSlash(baseUrl);
    final protocol = _normalizedProtocol(config.effectiveApiProtocol);

    if (apiKey.isNotEmpty) {
      lines
        ..add('export OPENAI_API_KEY=${_shQuote(apiKey)}')
        ..add('export ANTHROPIC_API_KEY=${_shQuote(apiKey)}')
        ..add('export SILICONFLOW_API_KEY=${_shQuote(apiKey)}')
        ..add('export QWEN_API_KEY=${_shQuote(apiKey)}')
        ..add('export DASHSCOPE_API_KEY=${_shQuote(apiKey)}')
        ..add('export CODEBUDDY_API_KEY=${_shQuote(apiKey)}')
        ..add('export CHINESE_LLM_API_KEY=${_shQuote(apiKey)}');
      if (protocol == 'gemini') {
        lines
          ..add('export GEMINI_API_KEY=${_shQuote(apiKey)}')
          ..add('export GOOGLE_API_KEY=${_shQuote(apiKey)}');
      }
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
    if (toolId == 'generic-agent') {
      if (config.effectiveApiProtocol == 'gemini') {
        lines.add(
          'export GEMINI_DEFAULT_AUTH_TYPE=${_shQuote('gemini-api-key')}',
        );
      } else {
        lines.add(
          'export GEMINI_DEFAULT_AUTH_TYPE=${_shQuote('siliconflow-api-key')}',
        );
        if (openAiBaseUrl.isNotEmpty) {
          lines.add('export SILICONFLOW_BASE_URL=${_shQuote(openAiBaseUrl)}');
        }
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
    final baseUrl = _trimTrailingSlash(config.baseUrl);
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
          'CODEBUDDY_BASE_URL': _trimTrailingSlash(config.baseUrl),
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
    final baseUrl = _trimTrailingSlash(config.baseUrl);
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
    final baseUrl = _trimTrailingSlash(config.baseUrl);
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
    String? selectedAuthType;
    if (_shouldManageToolRuntime(config)) {
      if (_normalizedProtocol(config.effectiveApiProtocol) == 'gemini') {
        selectedAuthType = 'gemini-api-key';
      } else {
        selectedAuthType = 'siliconflow-api-key';
      }
    }
    final payload = <String, dynamic>{
      if (selectedAuthType != null) 'selectedAuthType': selectedAuthType,
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
        '# No shared API selected for Hermes Agent.',
        '# Hermes will keep using its own setup flow until you bind a shared API.',
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
      '  base_url: ${_yamlString(_trimTrailingSlash(config.baseUrl))}',
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
        'OPENAI_BASE_URL=${_shQuote(_trimTrailingSlash(config.baseUrl))}',
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
    const providerId = 'openclaw';
    const providerName = 'OpenClaw Codex Proxy';
    lines
      ..add('disable_response_storage = true')
      ..add('sandbox_mode = "danger-full-access"')
      ..add('approval_policy = "never"')
      ..add('tui.notifications = false')
      ..add('tui.terminal_title = []');

    if (_shouldManageToolRuntime(codex)) {
      final model = codex.effectiveToolModel;
      final effort = codex.reasoningEffort.trim();

      lines.add('preferred_auth_method = "apikey"');
      lines.add('model_provider = ${_tomlString(providerId)}');
      if (model.isNotEmpty) {
        lines.add('model = ${_tomlString(model)}');
      }
      if (effort.isNotEmpty) {
        lines.add('model_reasoning_effort = ${_tomlString(effort)}');
      }
      lines
        ..add('')
        ..add('[model_providers.$providerId]')
        ..add('name = ${_tomlString(providerName)}')
        ..add('base_url = ${_tomlString(_codexProxyBaseUrl)}')
        ..add('wire_api = "responses"')
        ..add('env_key = "OPENAI_API_KEY"')
        ..add('stream_idle_timeout_ms = 300000')
        ..add('request_max_retries = 2')
        ..add('stream_max_retries = 2');
    }

    lines
      ..add('')
      ..add('[mcp_servers.openclaw_browser]')
      ..add('enabled = true')
      ..add('command = "node"')
      ..add('args = [${_tomlString(_browserMcpPath)}]')
      ..add('startup_timeout_sec = 20')
      ..add('tool_timeout_sec = 120')
      ..add('')
      ..add('[projects.${_tomlString(cliWorkspacePath)}]')
      ..add('trust_level = "trusted"')
      ..add('')
      ..add('[projects.${_tomlString(_cliWorkspaceProjectsPath)}]')
      ..add('trust_level = "trusted"')
      ..add('')
      ..add('[projects.${_tomlString(_cliWorkspaceScratchPath)}]')
      ..add('trust_level = "trusted"')
      ..add('')
      ..add('[projects."/root"]')
      ..add('trust_level = "trusted"');

    if (lines.isEmpty) {
      lines.add('# OpenClaw CLI config is empty. Configure Codex in the app.');
    }
    lines.add('');
    return lines.join('\n');
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

  static String _buildCodexProxyEnv(CliApiConfig codex) {
    final lines = <String>[
      'OPENCLAW_CODEX_PROXY_HOST=127.0.0.1',
      'OPENCLAW_CODEX_PROXY_PORT=8787',
    ];
    if (!_shouldManageToolRuntime(codex)) {
      lines
        ..add('OPENCLAW_CODEX_PROXY_ENABLED=0')
        ..add('');
      return lines.join('\n');
    }
    lines.add('OPENCLAW_CODEX_PROXY_ENABLED=1');
    final upstream = codex.baseUrl.trim();
    final model = codex.model.trim().isNotEmpty
        ? codex.model.trim()
        : codex.effectiveToolModel;
    if (upstream.isNotEmpty) {
      lines.add(
        'OPENCLAW_CODEX_PROXY_UPSTREAM='
        '${_shQuote(_trimTrailingSlash(upstream))}',
      );
    }
    if (codex.apiKey.trim().isNotEmpty) {
      lines.add('OPENAI_API_KEY=${_shQuote(codex.apiKey.trim())}');
    }
    if (model.isNotEmpty) {
      lines.add('OPENCLAW_CODEX_PROXY_MODEL=${_shQuote(model)}');
    }
    lines.add('');
    return lines.join('\n');
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
    name: "browser_get_state",
    description:
      "Return the current browser state including title, URL, loading flag, and the last bridge error.",
    inputSchema: {
      type: "object",
      properties: {},
      additionalProperties: false,
    },
  },
];

const TOOL_TO_ACTION = {
  browser_open: "open",
  browser_back: "back",
  browser_forward: "forward",
  browser_reload: "reload",
  browser_click: "click",
  browser_type: "type",
  browser_wait_for_text: "wait_for_text",
  browser_extract: "extract",
  browser_list_links: "list_links",
  browser_list_interactables: "list_interactables",
  browser_highlight: "highlight",
  browser_capture_snapshot: "capture_snapshot",
  browser_eval: "eval",
  browser_get_state: "get_state",
};

const HEADER_DELIMITER = Buffer.from("\\r\\n\\r\\n");
let stdinBuffer = Buffer.alloc(0);

function write(message) {
  const payload = Buffer.from(JSON.stringify(message), "utf8");
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
        version: "1.0.0",
      },
      instructions:
        "Use the OpenClaw browser tools for deterministic page navigation, clicking, typing, waiting, and extraction inside the in-app browser panel.",
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
    const action = TOOL_TO_ACTION[toolName];
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
      const result = await callBridge(action, params.arguments || {});
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

function pumpStdin() {
  while (true) {
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

    let message;
    try {
      message = JSON.parse(payloadText);
    } catch (error) {
      fail(null, -32700, "Invalid JSON received by browser MCP adapter", {
        detail: error instanceof Error ? error.message : String(error),
      });
      continue;
    }

    onRequest(message).catch((error) => {
      fail(message?.id ?? null, -32000, "Unhandled browser MCP adapter error", {
        detail: error instanceof Error ? error.message : String(error),
      });
    });
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

  static String _buildBrowserSkill() {
    return '''
---
name: browser-operator
description: Control the OpenClaw in-app browser panel from Codex CLI using deterministic browser tools.
---

Use this skill when the user asks you to inspect a webpage, click through a flow, fill a web form, or extract page content from OpenClaw's in-app browser.

Rules:
1. Start with `browser_get_state` so you know whether the browser panel is attached.
2. If the tool reports that the browser panel is unavailable, stop and tell the user to open the browser panel from the terminal screen.
3. Prefer `browser_open`, `browser_wait_for_text`, `browser_list_interactables`, `browser_highlight`, `browser_click`, `browser_type`, and `browser_extract` over `browser_eval`.
4. Use stable CSS selectors. Avoid fragile positional selectors unless there is no better choice.
5. Before any action that could submit a form, log in, send a message, spend money, or change user data, ask for confirmation.
6. After a navigation or form submit, wait with `browser_wait_for_text` before assuming the page is ready.
7. When extracting content, keep the result focused. Use `selector` whenever possible instead of dumping the whole page.
8. If the next selector is unclear, call `browser_list_interactables` or `browser_list_links` first and choose from the returned candidates.
9. If a selector is risky, call `browser_highlight` before clicking so the user can visually confirm the target.

Typical flow:
1. `browser_open`
2. `browser_wait_for_text`
3. `browser_list_interactables`
4. `browser_highlight`
5. `browser_click` or `browser_type`
6. `browser_capture_snapshot` or `browser_extract`
7. Fall back to `browser_eval` only if the built-in actions are insufficient.
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
      'anthropic' => 'anthropic',
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
mkdir -p \
  "\${OPENCLAW_CLI_WORKSPACE:-$cliWorkspacePath}" \
  "\${OPENCLAW_CLI_PROJECTS:-$_cliWorkspaceProjectsPath}" \
  "\${OPENCLAW_CLI_SCRATCH:-$_cliWorkspaceScratchPath}" \
  "\${OPENCLAW_CLI_WORKSPACE:-$cliWorkspacePath}/.gemini" \
  "\${OPENCLAW_CLI_WORKSPACE:-$cliWorkspacePath}/.gen-cli" \
  "\${OPENCLAW_CLI_WORKSPACE:-$cliWorkspacePath}/.agents/skills" \
  "\${CODEX_HOME:-/root/.codex}" \
  "\${GEMINI_CONFIG_DIR:-/root/.gemini}" \
  "\${XDG_CONFIG_HOME:-/root/.config}" \
  2>/dev/null || true
cd "\${OPENCLAW_CLI_WORKSPACE:-$cliWorkspacePath}" 2>/dev/null || cd /root
''';
  }

  static String _buildCodexLauncherSh() {
    return '''${_buildCliLauncherHeader('/root/.openclaw/cli-env-codex.sh')}
openclaw_managed_auth=false
if [ -r /root/.openclaw/codex-proxy.env ] && grep -q '^OPENCLAW_CODEX_PROXY_ENABLED=1\$' /root/.openclaw/codex-proxy.env 2>/dev/null; then
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

CODEX_JS="/opt/openclaw-cli/codex/node_modules/@openai/codex/bin/codex.js"
[ -f "\$CODEX_JS" ] || {
  echo "Codex CLI entrypoint not found: \$CODEX_JS" >&2
  exit 1
}

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
GEN_REAL="\$(node -e 'const path=require("node:path"); const pkg=require("/opt/openclaw-cli/generic-agent/node_modules/@gen-cli/gen-cli/package.json"); const entry=(pkg.bin && (typeof pkg.bin === "string" ? pkg.bin : pkg.bin.gen)) || pkg.main || "dist/index.js"; process.stdout.write(path.isAbsolute(entry) ? entry : `/opt/openclaw-cli/generic-agent/node_modules/@gen-cli/gen-cli/\${entry}`);' 2>/dev/null)"
[ -n "\$GEN_REAL" ] && [ -f "\$GEN_REAL" ] || {
  echo "Gen CLI entrypoint not found." >&2
  exit 1
}
openclaw_skip_model_injection=false
case "\${1:-}" in
  --version|-v|-V|version|help|--help|-h)
    openclaw_skip_model_injection=true
    ;;
esac
if [ "\$openclaw_skip_model_injection" != true ] && [ -n "\${OPENCLAW_API_PROTOCOL:-}" ]; then
  if [ "\${OPENCLAW_API_PROTOCOL}" = "gemini" ]; then
    export GEMINI_DEFAULT_AUTH_TYPE="\${GEMINI_DEFAULT_AUTH_TYPE:-gemini-api-key}"
  else
    export GEMINI_DEFAULT_AUTH_TYPE="\${GEMINI_DEFAULT_AUTH_TYPE:-siliconflow-api-key}"
  fi
fi
if [ "\$openclaw_skip_model_injection" != true ] && [ -n "\${OPENCLAW_MODEL:-}" ]; then
  set -- --model "\$OPENCLAW_MODEL" "\$@"
fi
exec node "\$GEN_REAL" "\$@"
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
exec /opt/openclaw-cli/hermes-agent/venv/bin/hermes "\$@"
''';
  }

  static String _buildCodexProxyPy() {
    return r'''#!/usr/bin/env python3
import http.server
import json
import os
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

ENV_FILE = Path("/root/.openclaw/codex-proxy.env")


def load_env():
    values = {}
    if ENV_FILE.exists():
        for line in ENV_FILE.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#") or "=" not in line:
                continue
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip().strip('"').strip("'")
    return values


def config():
    values = load_env()
    upstream = (
        values.get("OPENCLAW_CODEX_PROXY_UPSTREAM")
        or os.environ.get("OPENCLAW_CODEX_PROXY_UPSTREAM")
        or ""
    ).rstrip("/")
    token = values.get("OPENAI_API_KEY") or os.environ.get("OPENAI_API_KEY") or ""
    model = (
        values.get("OPENCLAW_CODEX_PROXY_MODEL")
        or os.environ.get("OPENCLAW_UPSTREAM_MODEL")
        or ""
    )
    host = values.get("OPENCLAW_CODEX_PROXY_HOST") or "127.0.0.1"
    port = int(values.get("OPENCLAW_CODEX_PROXY_PORT") or "8787")
    return upstream, token, model, host, port


def target_url(upstream, path):
    if not upstream:
        raise RuntimeError("OPENCLAW_CODEX_PROXY_UPSTREAM is not configured")
    upstream_path = urllib.parse.urlsplit(upstream).path.rstrip("/")
    if upstream_path.endswith("/v1") and path.startswith("/v1/"):
        return upstream + path[3:]
    return upstream + path


def join_input_text(value):
    if isinstance(value, str):
        return value
    if isinstance(value, list):
        parts = []
        for item in value:
            if isinstance(item, str):
                parts.append(item)
                continue
            if not isinstance(item, dict):
                continue
            if item.get("type") == "input_text":
                parts.append(str(item.get("text") or ""))
            elif item.get("type") == "message":
                parts.append(join_input_text(item.get("content")))
        return "\n".join(part for part in parts if part)
    if isinstance(value, dict):
        if value.get("type") == "input_text":
            return str(value.get("text") or "")
        if value.get("type") == "message":
            return join_input_text(value.get("content"))
    return ""


def responses_to_chat(payload, forced_model, path):
    model = forced_model or payload.get("model") or ""
    input_value = payload.get("input")
    messages = []
    if isinstance(input_value, list):
        for item in input_value:
            if not isinstance(item, dict):
                continue
            role = item.get("role") or "user"
            content = join_input_text(item.get("content"))
            if not content:
                content = join_input_text(item)
            if content:
                messages.append({"role": role, "content": content})
    else:
        text = join_input_text(input_value)
        if text:
            messages.append({"role": "user", "content": text})

    if not messages:
        instructions = str(payload.get("instructions") or "").strip()
        if instructions:
            messages.append({"role": "user", "content": instructions})

    request = {
        "model": model,
        "messages": messages,
        "stream": bool(payload.get("stream")),
    }
    if payload.get("temperature") is not None:
        request["temperature"] = payload.get("temperature")
    if payload.get("max_output_tokens") is not None:
        request["max_tokens"] = payload.get("max_output_tokens")
    if payload.get("top_p") is not None:
        request["top_p"] = payload.get("top_p")
    if isinstance(payload.get("tools"), list):
        request["tools"] = payload.get("tools")
    if isinstance(payload.get("tool_choice"), (str, dict)):
        request["tool_choice"] = payload.get("tool_choice")
    if payload.get("reasoning") is not None:
        request["reasoning"] = payload.get("reasoning")
    if path.endswith("/chat/completions"):
        request["stream"] = bool(payload.get("stream"))
    return request


def chat_to_responses(payload, original_model):
    choices = payload.get("choices") or []
    first = choices[0] if choices else {}
    message = first.get("message") if isinstance(first, dict) else {}
    text = ""
    if isinstance(message, dict):
        content = message.get("content")
        if isinstance(content, str):
            text = content
        elif isinstance(content, list):
            parts = []
            for item in content:
                if isinstance(item, dict) and item.get("type") == "text":
                    parts.append(str(item.get("text") or ""))
            text = "\n".join(part for part in parts if part)
    response_id = payload.get("id") or "resp_openclaw"
    model = payload.get("model") or original_model or ""
    usage = payload.get("usage") or {}
    return {
        "id": response_id,
        "object": "response",
        "created_at": payload.get("created") or 0,
        "status": "completed",
        "model": model,
        "output": [
            {
                "id": f"{response_id}_output_0",
                "type": "message",
                "role": "assistant",
                "content": [
                    {
                        "type": "output_text",
                        "text": text,
                        "annotations": [],
                    },
                ],
            },
        ],
        "usage": {
            "input_tokens": usage.get("prompt_tokens") or 0,
            "output_tokens": usage.get("completion_tokens") or 0,
            "total_tokens": usage.get("total_tokens") or 0,
        },
    }


def build_models_response(model):
    model_id = model or "openclaw-model"
    return {
        "object": "list",
        "data": [
            {
                "id": model_id,
                "object": "model",
                "created": 0,
                "owned_by": "openclaw",
            },
        ],
    }


def send_json(handler, status, payload):
    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
    handler.send_response(status)
    handler.send_header("Content-Type", "application/json")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)
    handler.wfile.flush()


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        return

    def _proxy(self):
        upstream, token, model, _, _ = config()
        parsed_path = urllib.parse.urlsplit(self.path).path
        if parsed_path == "/health":
            send_json(self, 200, {"ok": True, "upstream": upstream, "model": model, "has_key": bool(token)})
            return
        if self.command.upper() == "GET" and parsed_path == "/v1/models":
            send_json(self, 200, build_models_response(model))
            return

        length = int(self.headers.get("content-length", "0") or "0")
        body = self.rfile.read(length) if length else None
        target_path = self.path
        original_model = model
        if body and self.command.upper() in {"POST", "PUT", "PATCH"}:
            try:
                payload = json.loads(body.decode("utf-8"))
                if isinstance(payload, dict):
                    if parsed_path == "/v1/responses":
                        payload = responses_to_chat(payload, model, parsed_path)
                        target_path = "/v1/chat/completions"
                    elif model and isinstance(payload.get("model"), str):
                        payload["model"] = model
                    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            except Exception:
                pass
        try:
            req = urllib.request.Request(target_url(upstream, target_path), data=body, method=self.command)
            for key, value in self.headers.items():
                if key.lower() in {"host", "content-length", "connection", "accept-encoding", "authorization"}:
                    continue
                req.add_header(key, value)
            if token:
                req.add_header("Authorization", "Bearer " + token)
            with urllib.request.urlopen(req, timeout=300) as resp:
                data = resp.read()
                if parsed_path == "/v1/responses":
                    try:
                        payload = json.loads(data.decode("utf-8"))
                        send_json(self, resp.status, chat_to_responses(payload, original_model))
                        return
                    except Exception:
                        pass
                self.send_response(resp.status)
                for key, value in resp.headers.items():
                    if key.lower() in {"transfer-encoding", "connection", "content-encoding", "content-length"}:
                        continue
                    self.send_header(key, value)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)
                self.wfile.flush()
        except urllib.error.HTTPError as error:
            data = error.read()
            self.send_response(error.code)
            self.send_header("Content-Type", error.headers.get("Content-Type", "application/json"))
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            self.wfile.flush()
        except Exception as error:
            data = str(error).encode("utf-8")
            self.send_response(502)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            self.wfile.flush()

    def do_GET(self):
        self._proxy()

    def do_POST(self):
        self._proxy()


if __name__ == "__main__":
    _, _, _, host, port = config()
    http.server.ThreadingHTTPServer((host, port), Handler).serve_forever()
''';
  }

  static String _buildCodexProxyJs() {
    return r'''#!/usr/bin/env node
const http = require("http");
const https = require("https");
const fs = require("fs");
const { URL } = require("url");

const envFile = "/root/.openclaw/codex-proxy.env";

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
    upstream: (
      values.OPENCLAW_CODEX_PROXY_UPSTREAM ||
      process.env.OPENCLAW_CODEX_PROXY_UPSTREAM ||
      ""
    ).replace(/\/+$/, ""),
    token: values.OPENAI_API_KEY || process.env.OPENAI_API_KEY || "",
    model:
      values.OPENCLAW_CODEX_PROXY_MODEL ||
      process.env.OPENCLAW_UPSTREAM_MODEL ||
      "",
    host: values.OPENCLAW_CODEX_PROXY_HOST || "127.0.0.1",
    port: Number(values.OPENCLAW_CODEX_PROXY_PORT || 8787),
  };
}

function targetUrl(upstream, path) {
  if (!upstream) throw new Error("OPENCLAW_CODEX_PROXY_UPSTREAM is not configured");
  const upstreamPath = new URL(upstream).pathname.replace(/\/+$/, "");
  if (upstreamPath.endsWith("/v1") && path.startsWith("/v1/")) {
    return upstream + path.slice(3);
  }
  return upstream + path;
}

function sendJson(res, status, payload) {
  const body = Buffer.from(JSON.stringify(payload));
  res.writeHead(status, {
    "content-type": "application/json",
    "content-length": body.length,
  });
  res.end(body);
}

const server = http.createServer((clientReq, clientRes) => {
  const cfg = config();
  const requestUrl = new URL(clientReq.url, `http://${cfg.host}:${cfg.port}`);
  if (requestUrl.pathname === "/health") {
    sendJson(clientRes, 200, {
      ok: true,
      upstream: cfg.upstream,
      model: cfg.model,
      has_key: Boolean(cfg.token),
    });
    return;
  }

  let target;
  try {
    target = new URL(targetUrl(cfg.upstream, clientReq.url));
  } catch (error) {
    sendJson(clientRes, 502, { error: String(error.message || error) });
    return;
  }

  const headers = { ...clientReq.headers };
  delete headers.host;
  delete headers.connection;
  delete headers["accept-encoding"];
  delete headers.authorization;
  if (cfg.token) headers.authorization = `Bearer ${cfg.token}`;

  const bodyChunks = [];
  clientReq.on("data", (chunk) => bodyChunks.push(chunk));
  clientReq.on("end", () => {
    let body = Buffer.concat(bodyChunks);
    if (cfg.model && body.length && ["POST", "PUT", "PATCH"].includes(clientReq.method || "")) {
      try {
        const payload = JSON.parse(body.toString("utf8"));
        if (payload && typeof payload === "object" && typeof payload.model === "string") {
          payload.model = cfg.model;
          body = Buffer.from(JSON.stringify(payload));
          headers["content-length"] = body.length;
        }
      } catch (_) {}
    }

    const transport = target.protocol === "https:" ? https : http;
    const upstreamReq = transport.request(
      target,
      {
        method: clientReq.method,
        headers,
      },
      (upstreamRes) => {
        const responseHeaders = { ...upstreamRes.headers };
        delete responseHeaders["transfer-encoding"];
        delete responseHeaders.connection;
        delete responseHeaders["content-encoding"];
        clientRes.writeHead(upstreamRes.statusCode || 502, responseHeaders);
        upstreamRes.pipe(clientRes);
      },
    );

    upstreamReq.on("error", (error) => {
      sendJson(clientRes, 502, { error: String(error.message || error) });
    });
    upstreamReq.end(body);
  });
});

const cfg = config();
server.listen(cfg.port, cfg.host);
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
    if (segments.isEmpty) {
      return uri.replace(pathSegments: ['v1', 'models']);
    }
    if (segments.last == 'models') {
      return uri;
    }
    return uri.replace(pathSegments: [...segments, 'models']);
  }

  static List<String> _extractModelIds(dynamic decoded) {
    final result = <String>[];
    void addModel(dynamic item) {
      if (item is String && item.trim().isNotEmpty) {
        result.add(item.trim());
        return;
      }
      if (item is Map) {
        final id = item['id'] ?? item['name'] ?? item['model'];
        if (id is String && id.trim().isNotEmpty) {
          result.add(id.trim());
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
}
