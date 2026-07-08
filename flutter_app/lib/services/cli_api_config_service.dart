import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../models/cli_api_config.dart';
import 'native_bridge.dart';

class CliApiConfigService {
  static const _configPath = '/root/.openclaw/app/cli-api-config.json';
  static const _envPath = '/root/.openclaw/cli-env.sh';
  static const _codexProxyPath = '/root/.openclaw/codex-proxy.py';
  static const _codexProxyJsPath = '/root/.openclaw/codex-proxy.js';
  static const _codexProxyEnvPath = '/root/.openclaw/codex-proxy.env';
  static const _codexConfigPath = '/root/.codex/config.toml';
  static const _codexProxyBaseUrl = 'http://127.0.0.1:8787/v1';
  static const _codeBuddyModelsPath = '/root/.codebuddy/models.json';
  static const _codeBuddySettingsPath = '/root/.codebuddy/settings.json';
  static const _qwenSettingsPath = '/root/.qwen/settings.json';
  static const _geminiSettingsPath = '/root/.gemini/settings.json';
  static const _terminalThemePath = '/root/.openclaw/terminal-theme.sh';
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
      } else if (!useGeminiHeaders)
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
      _buildGeminiSettingsJson(activeConfigs['gemini']!),
    );
    await NativeBridge.runInProot(
      'chmod 0755 $_codexProxyPath 2>/dev/null || true; '
      'chmod 0755 $_codexProxyJsPath 2>/dev/null || true; '
      'chmod 0600 $_codexProxyEnvPath 2>/dev/null || true; '
      'chmod 0600 $_codeBuddyModelsPath $_codeBuddySettingsPath '
      '$_qwenSettingsPath $_geminiSettingsPath 2>/dev/null || true; '
      'chmod 0644 $_terminalThemePath 2>/dev/null || true; '
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
      profileName: toolSettings.profileName,
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
      'export OPENCLAW_CLI_ENV_LOADED=1',
      'export TERM="\${TERM:-xterm-256color}"',
      'export COLORTERM="\${COLORTERM:-truecolor}"',
      'export FORCE_COLOR=1',
      'export TMPDIR="\${TMPDIR:-/tmp}"',
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

  static String _buildToolEnvFile(String toolId, CliApiConfig config) {
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

    if (apiKey.isNotEmpty) {
      lines
        ..add('export OPENAI_API_KEY=${_shQuote(apiKey)}')
        ..add('export ANTHROPIC_API_KEY=${_shQuote(apiKey)}')
        ..add('export GEMINI_API_KEY=${_shQuote(apiKey)}')
        ..add('export GOOGLE_API_KEY=${_shQuote(apiKey)}')
        ..add('export QWEN_API_KEY=${_shQuote(apiKey)}')
        ..add('export DASHSCOPE_API_KEY=${_shQuote(apiKey)}')
        ..add('export CODEBUDDY_API_KEY=${_shQuote(apiKey)}')
        ..add('export CHINESE_LLM_API_KEY=${_shQuote(apiKey)}');
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
        ..add('export GEMINI_CLI_NO_BROWSER=1');
    }
    if (toolId == 'codebuddy' && config.baseUrl.trim().isEmpty) {
      lines.add('export CODEBUDDY_INTERNET_ENVIRONMENT=internal');
    }
    lines.add('');
    return lines.join('\n');
  }

  static String _buildCodeBuddyModelsJson(CliApiConfig config) {
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
    final model = config.effectiveToolModel;
    final payload = <String, dynamic>{
      'security': {
        'auth': {
          'selectedType': 'gemini-api-key',
        },
      },
      if (model.isNotEmpty)
        'model': {
          'name': model,
        },
      'telemetry': {
        'enabled': false,
      },
    };
    return '${const JsonEncoder.withIndent('  ').convert(payload)}\n';
  }

  static String _buildCodexToml(CliApiConfig codex) {
    final lines = <String>[];
    final model = codex.effectiveToolModel;
    final baseUrl = codex.baseUrl.trim().isNotEmpty ? _codexProxyBaseUrl : '';
    final effort = codex.reasoningEffort.trim();

    if (model.isNotEmpty) {
      lines.add('model = ${_tomlString(model)}');
    }
    lines
      ..add('disable_response_storage = true')
      ..add('preferred_auth_method = "apikey"')
      ..add('sandbox_mode = "danger-full-access"')
      ..add('approval_policy = "never"')
      ..add('tui.notifications = false')
      ..add('tui.terminal_title = []');
    if (effort.isNotEmpty) {
      lines.add('model_reasoning_effort = ${_tomlString(effort)}');
    }
    if (baseUrl.isNotEmpty) {
      lines
        ..add('model_provider = "openclaw"')
        ..add('')
        ..add('[model_providers.openclaw]')
        ..add('name = "OpenClaw Codex Proxy"')
        ..add('base_url = ${_tomlString(baseUrl)}')
        ..add('env_key = "OPENAI_API_KEY"')
        ..add('wire_api = "responses"')
        ..add('stream_idle_timeout_ms = 300000')
        ..add('request_max_retries = 2')
        ..add('stream_max_retries = 2');
    }

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

  static String _buildCodexProxyEnv(CliApiConfig codex) {
    final lines = <String>[
      'OPENCLAW_CODEX_PROXY_HOST=127.0.0.1',
      'OPENCLAW_CODEX_PROXY_PORT=8787',
    ];
    final upstream = codex.baseUrl.trim();
    if (upstream.isNotEmpty) {
      lines.add(
        'OPENCLAW_CODEX_PROXY_UPSTREAM='
        '${_shQuote(_trimTrailingSlash(upstream))}',
      );
    }
    if (codex.apiKey.trim().isNotEmpty) {
      lines.add('OPENAI_API_KEY=${_shQuote(codex.apiKey.trim())}');
    }
    if (codex.model.trim().isNotEmpty) {
      lines.add('OPENCLAW_CODEX_PROXY_MODEL=${_shQuote(codex.model.trim())}');
    }
    lines.add('');
    return lines.join('\n');
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

        length = int(self.headers.get("content-length", "0") or "0")
        body = self.rfile.read(length) if length else None
        if model and body and self.command.upper() in {"POST", "PUT", "PATCH"}:
            try:
                payload = json.loads(body.decode("utf-8"))
                if isinstance(payload, dict) and isinstance(payload.get("model"), str):
                    payload["model"] = model
                    body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            except Exception:
                pass
        try:
            req = urllib.request.Request(target_url(upstream, self.path), data=body, method=self.command)
            for key, value in self.headers.items():
                if key.lower() in {"host", "content-length", "connection", "accept-encoding", "authorization"}:
                    continue
                req.add_header(key, value)
            if token:
                req.add_header("Authorization", "Bearer " + token)
            with urllib.request.urlopen(req, timeout=300) as resp:
                self.send_response(resp.status)
                for key, value in resp.headers.items():
                    if key.lower() in {"transfer-encoding", "connection", "content-encoding"}:
                        continue
                    self.send_header(key, value)
                self.end_headers()
                while True:
                    chunk = resp.read(8192)
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    self.wfile.flush()
        except urllib.error.HTTPError as error:
            data = error.read()
            self.send_response(error.code)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
        except Exception as error:
            data = str(error).encode("utf-8")
            self.send_response(502)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

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
