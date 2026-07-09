import 'dart:convert';

import '../constants.dart';
import 'native_bridge.dart';
import 'preferences_service.dart';

/// Reads and writes messaging platform configuration in openclaw.json.
class MessagePlatformConfigService {
  static const _pluginStatusCacheTtl = Duration(minutes: 10);
  static const _configPath = '/root/.openclaw/openclaw.json';
  static const _feishuChannelId = 'feishu';
  static const _qqbotChannelId = 'qqbot';
  static const _weixinUiChannelId = 'weixin';
  static const _weixinChannelId = 'openclaw-weixin';
  static const _legacyLarkChannelId = 'lark';
  static const _defaultFeishuAccountId = 'default';
  static const qqbotPluginPackage = '@tencent-connect/openclaw-qqbot@latest';
  static const _qqbotPluginId = 'openclaw-qqbot';
  static const _qqbotLegacyPluginIds = <String>[
    'qqbot',
    '@tencent-connect/openclaw-qqbot',
  ];
  static const _qqbotPluginPackagePaths = <String>[
    '/usr/local/lib/node_modules/@tencent-connect/openclaw-qqbot/package.json',
    '/usr/lib/node_modules/@tencent-connect/openclaw-qqbot/package.json',
    '/root/.openclaw/node_modules/@tencent-connect/openclaw-qqbot/package.json',
  ];
  static const qqbotConnectUrl = 'https://q.qq.com/qqbot/openclaw/login.html';
  static const weixinPluginPackage = '@tencent-weixin/openclaw-weixin@latest';
  static const _weixinPluginId = 'openclaw-weixin';
  static const _weixinLegacyChannelIds = <String>[_weixinUiChannelId];
  static const _weixinLegacyPluginIds = <String>[
    'weixin',
    '@tencent/openclaw-weixin',
    '@tencent-weixin/openclaw-weixin',
  ];
  static const _weixinPluginPackagePaths = <String>[
    '/usr/local/lib/node_modules/@tencent-weixin/openclaw-weixin/package.json',
    '/usr/local/lib/node_modules/@tencent/openclaw-weixin/package.json',
    '/usr/lib/node_modules/@tencent-weixin/openclaw-weixin/package.json',
    '/usr/lib/node_modules/@tencent/openclaw-weixin/package.json',
    '/root/.openclaw/node_modules/@tencent-weixin/openclaw-weixin/package.json',
    '/root/.openclaw/node_modules/@tencent/openclaw-weixin/package.json',
    '/root/.openclaw/npm/projects/tencent-weixin-openclaw-weixin-7783ac86ba/package.json',
    '/root/.openclaw/npm/projects/tencent-weixin-openclaw-weixin-7783ac86ba/node_modules/@tencent-weixin/openclaw-weixin/package.json',
  ];
  static const _persistentNpmCacheDir = '/root/.npm/openclaw-cache';
  static const weixinInstallerCommand =
      'export npm_config_registry=${AppConstants.npmRegistryUrl}; '
      'export NPM_CONFIG_REGISTRY=${AppConstants.npmRegistryUrl}; '
      'export npm_config_cache=$_persistentNpmCacheDir; '
      'export npm_config_prefer_offline=true; '
      'export npm_config_prefer_online=false; '
      'openclaw plugins install "$weixinPluginPackage" && '
      'openclaw channels login --channel $_weixinChannelId';

  static String _shellEscape(String s) {
    return "'${s.replaceAll("'", "'\\''")}'";
  }

  static String _wrapOpenclawCommand(String command) {
    return '''
if [ -f /root/.openclaw/bionic-bypass.js ]; then
export NODE_OPTIONS="--require /root/.openclaw/bionic-bypass.js"
fi
export CHOKIDAR_USEPOLLING=true
export NODE_EXTRA_CA_CERTS=/etc/ssl/certs/ca-certificates.crt
export UV_USE_IO_URING=0
export npm_config_registry=${AppConstants.npmRegistryUrl}
export NPM_CONFIG_REGISTRY=${AppConstants.npmRegistryUrl}
export npm_config_audit=false
export npm_config_fund=false
export npm_config_progress=false
export npm_config_update_notifier=false
export npm_config_fetch_retries=5
export npm_config_fetch_retry_mintimeout=2000
export npm_config_fetch_retry_maxtimeout=20000
export npm_config_prefer_offline=true
export npm_config_prefer_online=false
export npm_config_cache=$_persistentNpmCacheDir
mkdir -p /root/.npm $_persistentNpmCacheDir /tmp/npm-tmp
export TMPDIR=/tmp/npm-tmp
$command
''';
  }

  static Future<String> _runOpenclawCommand(
    String command, {
    int timeout = 120,
    String notificationText = 'Running OpenClaw task...',
  }) async {
    return _runWithSetupForeground(() async {
      try {
        await NativeBridge.setupDirs();
      } catch (_) {}
      try {
        await NativeBridge.writeResolv();
      } catch (_) {}

      return NativeBridge.runInProot(
        _wrapOpenclawCommand(command),
        timeout: timeout,
      );
    }, notificationText: notificationText);
  }

  static Future<String> _runOpenclawCommandWithRetries(
    List<String> commands, {
    int timeout = 120,
    String notificationText = 'Running OpenClaw task...',
  }) async {
    Object? lastError;
    for (final command in commands) {
      try {
        return await _runOpenclawCommand(
          command,
          timeout: timeout,
          notificationText: notificationText,
        );
      } catch (error) {
        lastError = error;
      }
    }
    throw Exception('Command failed after retries: $lastError');
  }

  static int _setupForegroundDepth = 0;

  static Future<T> _runWithSetupForeground<T>(
    Future<T> Function() action, {
    required String notificationText,
  }) async {
    final shouldStart = _setupForegroundDepth == 0;
    _setupForegroundDepth += 1;
    if (shouldStart) {
      try {
        await NativeBridge.startSetupService();
        await NativeBridge.updateSetupNotification(notificationText);
      } catch (_) {}
    } else {
      try {
        await NativeBridge.updateSetupNotification(notificationText);
      } catch (_) {}
    }

    try {
      return await action();
    } finally {
      _setupForegroundDepth =
          (_setupForegroundDepth - 1).clamp(0, 1 << 20).toInt();
      if (_setupForegroundDepth == 0) {
        try {
          await NativeBridge.stopSetupService();
        } catch (_) {}
      }
    }
  }

  static bool _isNonEmptyString(dynamic value) =>
      value is String && value.trim().isNotEmpty;

  static Future<PreferencesService> _loadPrefs() async {
    final prefs = PreferencesService();
    await prefs.init();
    return prefs;
  }

  static bool _isPluginCacheFresh(int? timestampMs) {
    if (timestampMs == null || timestampMs <= 0) {
      return false;
    }
    final age = DateTime.now().millisecondsSinceEpoch - timestampMs;
    return age >= 0 && age <= _pluginStatusCacheTtl.inMilliseconds;
  }

  static Future<bool?> _readCachedPluginInstalled(String pluginKey) async {
    final prefs = await _loadPrefs();
    switch (pluginKey) {
      case _qqbotPluginId:
        if (!_isPluginCacheFresh(prefs.qqbotPluginCheckedAt)) {
          return null;
        }
        return prefs.qqbotPluginInstalled;
      case _weixinPluginId:
        if (!_isPluginCacheFresh(prefs.weixinPluginCheckedAt)) {
          return null;
        }
        return prefs.weixinPluginInstalled;
      default:
        return null;
    }
  }

  static Future<void> _writeCachedPluginInstalled(
    String pluginKey,
    bool installed,
  ) async {
    final prefs = await _loadPrefs();
    final now = DateTime.now().millisecondsSinceEpoch;
    switch (pluginKey) {
      case _qqbotPluginId:
        prefs.qqbotPluginInstalled = installed;
        prefs.qqbotPluginCheckedAt = now;
        break;
      case _weixinPluginId:
        prefs.weixinPluginInstalled = installed;
        prefs.weixinPluginCheckedAt = now;
        break;
    }
  }

  static Future<void> invalidatePluginStatusCache(String pluginKey) async {
    final prefs = await _loadPrefs();
    switch (pluginKey) {
      case _qqbotPluginId:
        prefs.qqbotPluginInstalled = null;
        prefs.qqbotPluginCheckedAt = null;
        break;
      case _weixinPluginId:
        prefs.weixinPluginInstalled = null;
        prefs.weixinPluginCheckedAt = null;
        break;
    }
  }

  static Future<void> markWeixinPluginInstalledFromInstaller() async {
    await _setPluginEntryEnabled(
      _weixinPluginId,
      enabled: true,
      cleanupAliases: <String>[_weixinPluginId, ..._weixinLegacyPluginIds],
    );
    await _writeCachedPluginInstalled(_weixinPluginId, true);
  }

  static Map<String, dynamic>? _extractFeishuUiConfig(dynamic raw) {
    if (raw is! Map) return null;
    final channel = Map<String, dynamic>.from(raw);

    String? appId;
    String? appSecret;
    String? botName;
    String? domain;

    final accounts = channel['accounts'];
    if (accounts is Map && accounts.isNotEmpty) {
      final accountMap = Map<String, dynamic>.from(accounts);
      final preferredAccountId = (channel['defaultAccount'] as String?) ??
          (accountMap.containsKey(_defaultFeishuAccountId)
              ? _defaultFeishuAccountId
              : accountMap.keys.first);
      final account = accountMap[preferredAccountId];
      if (account is Map) {
        final normalizedAccount = Map<String, dynamic>.from(account);
        appId = normalizedAccount['appId'] as String?;
        appSecret = normalizedAccount['appSecret'] as String?;
        botName = normalizedAccount['botName'] as String?;
        domain = normalizedAccount['domain'] as String?;
      }
    }

    appId ??= channel['appId'] as String?;
    appSecret ??= channel['appSecret'] as String?;
    botName ??= channel['botName'] as String?;
    domain ??= channel['domain'] as String?;

    if (!_isNonEmptyString(appId) && !_isNonEmptyString(appSecret)) {
      return null;
    }

    return {
      if (_isNonEmptyString(appId)) 'appId': appId!.trim(),
      if (_isNonEmptyString(appSecret)) 'appSecret': appSecret!.trim(),
      if (_isNonEmptyString(botName)) 'botName': botName!.trim(),
      'domain': _isNonEmptyString(domain) ? domain!.trim() : 'feishu',
    };
  }

  static Map<String, dynamic> _buildFeishuStoredConfig(
    Map<String, dynamic> payload,
  ) {
    final appId = (payload['appId'] as String? ?? '').trim();
    final appSecret = (payload['appSecret'] as String? ?? '').trim();
    final botName = (payload['botName'] as String? ?? '').trim();
    final domain = (payload['domain'] as String? ?? 'feishu').trim();

    return {
      'enabled': true,
      'dmPolicy': 'pairing',
      'defaultAccount': _defaultFeishuAccountId,
      if (domain.isNotEmpty) 'domain': domain,
      'accounts': {
        _defaultFeishuAccountId: {
          'appId': appId,
          'appSecret': appSecret,
          if (botName.isNotEmpty) 'botName': botName,
        },
      },
    };
  }

  static Map<String, dynamic> _normalizeUiConfig({
    required String channelId,
    required dynamic value,
  }) {
    if (channelId == _feishuChannelId || channelId == _legacyLarkChannelId) {
      return _extractFeishuUiConfig(value) ?? <String, dynamic>{};
    }
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  static Map<String, dynamic> _storagePayloadForSave({
    required String channelId,
    required Map<String, dynamic> payload,
  }) {
    if (channelId == _feishuChannelId) {
      return _buildFeishuStoredConfig(payload);
    }
    return payload;
  }

  static String _canonicalChannelIdForStorage(String channelId) {
    if (channelId == _weixinUiChannelId) {
      return _weixinChannelId;
    }
    return channelId;
  }

  static Future<Map<String, dynamic>?> _readQqbotLocalConfig() async {
    final prefs = await _loadPrefs();
    final appId = prefs.qqbotAppId?.trim();
    final appSecret = prefs.qqbotAppSecret?.trim();
    if ((appId == null || appId.isEmpty) &&
        (appSecret == null || appSecret.isEmpty)) {
      return null;
    }

    return {
      if (appId != null && appId.isNotEmpty) 'appId': appId,
      if (appSecret != null && appSecret.isNotEmpty) 'appSecret': appSecret,
      'configured': true,
    };
  }

  static Future<void> _saveQqbotLocalConfig({
    required String appId,
    required String appSecret,
  }) async {
    final prefs = await _loadPrefs();
    prefs.qqbotAppId = appId.trim();
    prefs.qqbotAppSecret = appSecret.trim();
  }

  static Future<void> _clearQqbotLocalConfig() async {
    final prefs = await _loadPrefs();
    prefs.qqbotAppId = null;
    prefs.qqbotAppSecret = null;
  }

  static bool _pluginEntryEnabled(
    Map<String, dynamic> config,
    List<String> aliases,
  ) {
    final plugins = _normalizeMutableConfig(config['plugins']);
    final entries = _normalizeMutableConfig(plugins['entries']);
    for (final alias in aliases) {
      final entry = _normalizeMutableConfig(entries[alias]);
      if (entry['enabled'] == true) {
        return true;
      }
    }
    return false;
  }

  static Future<bool> _rootfsFileExists(String path) async {
    try {
      final content = await NativeBridge.readRootfsFile(path);
      return content != null && content.trim().isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _anyRootfsFileExists(List<String> paths) async {
    for (final path in paths) {
      if (await _rootfsFileExists(path)) {
        return true;
      }
    }
    return false;
  }

  static Future<bool> _isPluginInstalledFast({
    required String pluginId,
    required List<String> aliases,
    required List<String> packagePaths,
    List<String> packageNames = const <String>[],
  }) async {
    final config = await _readMutableConfig();
    final enabled = _pluginEntryEnabled(config, <String>[pluginId, ...aliases]);
    final packageExists = await _anyRootfsFileExists(packagePaths);
    if (enabled && packageExists) {
      return true;
    }
    if (packageExists) {
      return true;
    }
    return _isPluginInstalledInOpenClawProjects(packageNames);
  }

  static Future<bool> _isPluginInstalledInOpenClawProjects(
    List<String> packageNames,
  ) async {
    if (packageNames.isEmpty) {
      return false;
    }

    final escapeRegex = RegExp(r'([.[\]{}()*+?^$|\\])');
    final escapedNames = packageNames
        .map((name) => name.replaceAllMapped(escapeRegex, (match) {
              return '\\${match.group(0)}';
            }))
        .join('|');
    final grepPattern =
        '"name"[[:space:]]*:[[:space:]]*"($escapedNames)"';
    final command = '''
find /root/.openclaw/npm/projects -maxdepth 6 -type f -name package.json -print 2>/dev/null |
  xargs grep -lE ${_shellEscape(grepPattern)} >/dev/null 2>&1
''';

    try {
      await NativeBridge.runInProot(command, timeout: 20);
      return true;
    } catch (_) {
      return false;
    }
  }

  static Map<String, dynamic> _normalizeMutableConfig(dynamic value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(value);
    }
    if (value is Map) {
      return value.map((key, item) => MapEntry(key.toString(), item));
    }
    return <String, dynamic>{};
  }

  static List<String> _normalizeStringList(dynamic value) {
    if (value is List) {
      return value
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList();
    }
    return <String>[];
  }

  static String _configJson(dynamic value) => jsonEncode(value);

  static Map<String, String?> _extractQqbotCredentials(
    Map<String, dynamic> channel,
  ) {
    String? appId = channel['appId'] as String?;
    String? appSecret = channel['clientSecret'] as String?;
    appSecret ??= channel['appSecret'] as String?;

    final accounts = channel['accounts'];
    if ((!_isNonEmptyString(appId) || !_isNonEmptyString(appSecret)) &&
        accounts is Map) {
      for (final account in accounts.values) {
        if (account is! Map) {
          continue;
        }
        final normalizedAccount = Map<String, dynamic>.from(account);
        appId ??= normalizedAccount['appId'] as String?;
        appSecret ??= normalizedAccount['clientSecret'] as String?;
        appSecret ??= normalizedAccount['appSecret'] as String?;
        if (_isNonEmptyString(appId) && _isNonEmptyString(appSecret)) {
          break;
        }
      }
    }

    return {
      'appId': _isNonEmptyString(appId) ? appId!.trim() : null,
      'appSecret': _isNonEmptyString(appSecret) ? appSecret!.trim() : null,
    };
  }

  static bool _setPluginEntryEnabledInConfig(
    Map<String, dynamic> config,
    String pluginId, {
    required bool enabled,
    required List<String> cleanupAliases,
  }) {
    final before = _configJson(config);
    final plugins = _normalizeMutableConfig(config['plugins']);
    final entries = _normalizeMutableConfig(plugins['entries']);

    for (final alias in cleanupAliases) {
      if (alias != pluginId) {
        entries.remove(alias);
      }
    }

    if (enabled) {
      final entry = _normalizeMutableConfig(entries[pluginId]);
      entry['enabled'] = true;
      entries[pluginId] = entry;
    } else {
      entries.remove(pluginId);
    }

    final allow = _normalizeStringList(plugins['allow'])
      ..removeWhere((item) => cleanupAliases.contains(item));
    if (enabled && !allow.contains(pluginId)) {
      allow.add(pluginId);
    }

    if (entries.isEmpty) {
      plugins.remove('entries');
    } else {
      plugins['entries'] = entries;
    }

    if (allow.isEmpty) {
      plugins.remove('allow');
    } else {
      plugins['allow'] = allow;
    }

    if (plugins.isEmpty) {
      config.remove('plugins');
    } else {
      config['plugins'] = plugins;
    }

    return before != _configJson(config);
  }

  static bool _migrateWeixinChannelConfigInConfig(Map<String, dynamic> config) {
    final before = _configJson(config);
    final channels = _normalizeMutableConfig(config['channels']);
    final canonicalChannel = _normalizeMutableConfig(channels[_weixinChannelId]);

    for (final legacyId in _weixinLegacyChannelIds) {
      final legacyChannel = _normalizeMutableConfig(channels[legacyId]);
      if (legacyChannel.isEmpty) {
        channels.remove(legacyId);
        continue;
      }
      if (canonicalChannel.isEmpty) {
        channels[_weixinChannelId] = legacyChannel;
      }
      channels.remove(legacyId);
    }

    if (channels.isEmpty) {
      config.remove('channels');
    } else {
      config['channels'] = channels;
    }
    return before != _configJson(config);
  }

  static bool _normalizeQqbotChannelConfigInConfig(
    Map<String, dynamic> config, {
    String? appId,
    String? appSecret,
  }) {
    final before = _configJson(config);
    final channels = _normalizeMutableConfig(config['channels']);
    final existing = _normalizeMutableConfig(channels[_qqbotChannelId]);
    final extracted = _extractQqbotCredentials(existing);

    final normalizedAppId =
        _isNonEmptyString(appId) ? appId!.trim() : extracted['appId'];
    final normalizedAppSecret = _isNonEmptyString(appSecret)
        ? appSecret!.trim()
        : extracted['appSecret'];

    if (_isNonEmptyString(normalizedAppId) &&
        _isNonEmptyString(normalizedAppSecret)) {
      existing['enabled'] = true;
      existing['appId'] = normalizedAppId;
      existing['clientSecret'] = normalizedAppSecret;
      existing.remove('appSecret');
      existing.remove('accounts');
      channels[_qqbotChannelId] = existing;
      config['channels'] = channels;
    } else if (existing.remove('appSecret') != null) {
      channels[_qqbotChannelId] = existing;
      config['channels'] = channels;
    }

    return before != _configJson(config);
  }

  static bool _hasNonEmptyMap(dynamic value) {
    if (value is! Map) {
      return false;
    }
    return value.isNotEmpty;
  }

  static bool _hasQqbotChannelConfig(Map<String, dynamic> channels) {
    final channel = _normalizeMutableConfig(channels[_qqbotChannelId]);
    if (_isNonEmptyString(channel['appId']) &&
        _isNonEmptyString(channel['clientSecret'])) {
      return true;
    }
    if (_isNonEmptyString(channel['appId']) &&
        _isNonEmptyString(channel['appSecret'])) {
      return true;
    }
    return _hasNonEmptyMap(channel['accounts']);
  }

  static Future<Map<String, dynamic>> _readMutableConfig() async {
    try {
      final content = await NativeBridge.readRootfsFile(_configPath);
      if (content == null || content.trim().isEmpty) {
        return <String, dynamic>{};
      }
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        return Map<String, dynamic>.from(decoded);
      }
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return <String, dynamic>{};
  }

  static Future<void> _writeMutableConfig(Map<String, dynamic> config) async {
    await NativeBridge.writeRootfsFile(
      _configPath,
      const JsonEncoder.withIndent('  ').convert(config),
    );
  }

  static Future<T> _withTemporarilyRemovedChannels<T>(
    List<String> channelIds,
    Future<T> Function() action,
  ) async {
    if (channelIds.isEmpty) {
      return action();
    }

    final config = await _readMutableConfig();
    final channels = _normalizeMutableConfig(config['channels']);
    final removedChannels = <String, dynamic>{};

    for (final channelId in channelIds) {
      if (channels.containsKey(channelId)) {
        removedChannels[channelId] = channels.remove(channelId);
      }
    }

    if (removedChannels.isNotEmpty) {
      if (channels.isEmpty) {
        config.remove('channels');
      } else {
        config['channels'] = channels;
      }
      await _writeMutableConfig(config);
    }

    try {
      return await action();
    } finally {
      if (removedChannels.isNotEmpty) {
        final restoreConfig = await _readMutableConfig();
        final restoreChannels = _normalizeMutableConfig(
          restoreConfig['channels'],
        );
        var changed = false;

        for (final entry in removedChannels.entries) {
          if (!restoreChannels.containsKey(entry.key)) {
            restoreChannels[entry.key] = entry.value;
            changed = true;
          }
        }

        if (changed) {
          restoreConfig['channels'] = restoreChannels;
          await _writeMutableConfig(restoreConfig);
        }

      }
    }
  }

  static Future<void> _setPluginEntryEnabled(
    String pluginId, {
    required bool enabled,
    required List<String> cleanupAliases,
  }) async {
    final config = await _readMutableConfig();
    final changed = _setPluginEntryEnabledInConfig(
      config,
      pluginId,
      enabled: enabled,
      cleanupAliases: cleanupAliases,
    );
    if (!changed) {
      return;
    }
    await _writeMutableConfig(config);
  }

  static Future<String> _installPluginWithRepair({
    required String primaryPackage,
    required String fallbackPackage,
    required List<String> uninstallCommands,
    required String installNotificationText,
    required String repairNotificationText,
    List<String> temporaryDisabledChannelIds = const <String>[],
  }) async {
    return _withTemporarilyRemovedChannels(temporaryDisabledChannelIds, () async {
      try {
        return await _runOpenclawCommandWithRetries(
          <String>[
            'openclaw plugins install "$primaryPackage"',
            'openclaw plugins install $fallbackPackage',
          ],
          timeout: 1800,
          notificationText: installNotificationText,
        );
      } catch (_) {
        await _runOpenclawCommand(
          '${uninstallCommands.join('; ')}; true',
          timeout: 120,
          notificationText: repairNotificationText,
        );
        return _runOpenclawCommandWithRetries(
          <String>[
            'openclaw plugins install "$primaryPackage"',
            'openclaw plugins install $fallbackPackage',
          ],
          timeout: 1800,
          notificationText: installNotificationText,
        );
      }
    });
  }

  static Future<void> _normalizeQqbotChannelConfig({
    required String appId,
    required String appSecret,
  }) async {
    final config = await _readMutableConfig();
    final changed = _normalizeQqbotChannelConfigInConfig(
      config,
      appId: appId,
      appSecret: appSecret,
    );
    if (!changed) {
      return;
    }
    await _writeMutableConfig(config);
  }

  static Future<void> repairMessagingPluginConfigIfNeeded() async {
    final config = await _readMutableConfig();
    final before = _configJson(config);
    _migrateWeixinChannelConfigInConfig(config);
    final qqbotLocal = await _readQqbotLocalConfig();
    final hasQqbotLocal = qqbotLocal != null;
    if (hasQqbotLocal) {
      _normalizeQqbotChannelConfigInConfig(
        config,
        appId: qqbotLocal['appId'] as String?,
        appSecret: qqbotLocal['appSecret'] as String?,
      );
    } else {
      _normalizeQqbotChannelConfigInConfig(config);
    }
    final channels = _normalizeMutableConfig(config['channels']);
    final enableQqbot = _hasQqbotChannelConfig(channels) || hasQqbotLocal;
    final enableWeixin = _hasNonEmptyMap(channels[_weixinChannelId]);

    if (enableQqbot) {
      _setPluginEntryEnabledInConfig(
        config,
        _qqbotPluginId,
        enabled: true,
        cleanupAliases: <String>[_qqbotPluginId, ..._qqbotLegacyPluginIds],
      );
    }
    if (enableWeixin) {
      _setPluginEntryEnabledInConfig(
        config,
        _weixinPluginId,
        enabled: true,
        cleanupAliases: <String>[_weixinPluginId, ..._weixinLegacyPluginIds],
      );
    }

    if (before == _configJson(config)) {
      return;
    }
    await _writeMutableConfig(config);
  }

  /// Ensure messaging plugins required by current channel credentials are installed
  /// before the gateway starts.
  static Future<void> ensureMessagingPluginsForStartup() async {
    final config = await _readMutableConfig();
    final channels = _normalizeMutableConfig(config['channels']);

    final hasQqbotLocal = await _readQqbotLocalConfig() != null;
    final hasQqbotConfig = _hasQqbotChannelConfig(channels);
    final shouldEnsureQqbot = hasQqbotConfig || hasQqbotLocal;
    final hasWeixin = _hasNonEmptyMap(channels[_weixinChannelId]);

    if (shouldEnsureQqbot) {
      await ensureQqbotPluginInstalled();
    }
    if (hasWeixin) {
      await ensureWeixinPluginInstalled();
    }
  }

  static Future<Map<String, dynamic>> readConfig() async {
    try {
      final content = await NativeBridge.readRootfsFile(_configPath);
      final platforms = <String, dynamic>{};
      if (content != null && content.isNotEmpty) {
        final config = jsonDecode(content) as Map<String, dynamic>;
        final channels = config['channels'] as Map<String, dynamic>?;
        if (channels != null) {
          for (final entry in channels.entries) {
            final key = switch (entry.key) {
              _legacyLarkChannelId => _feishuChannelId,
              _weixinChannelId => _weixinUiChannelId,
              _ => entry.key,
            };
            final normalized = _normalizeUiConfig(
              channelId: entry.key,
              value: entry.value,
            );
            if (key == _qqbotChannelId && normalized.isEmpty) {
              platforms[key] = {'configured': true};
              continue;
            }
            if (normalized.isNotEmpty || !platforms.containsKey(key)) {
              platforms[key] = normalized;
            }
          }
        }
      }

      final qqbotLocal = await _readQqbotLocalConfig();
      if (qqbotLocal != null) {
        platforms[_qqbotChannelId] = {
          ...(platforms[_qqbotChannelId] as Map<String, dynamic>? ??
              const <String, dynamic>{}),
          ...qqbotLocal,
        };
      }

      return {'platforms': platforms};
    } catch (_) {
      final qqbotLocal = await _readQqbotLocalConfig();
      return {
        'platforms': {
          if (qqbotLocal != null) _qqbotChannelId: qqbotLocal,
        },
      };
    }
  }

  static Future<void> migrateFeishuConfigIfNeeded() async {
    try {
      final content = await NativeBridge.readRootfsFile(_configPath);
      if (content == null || content.isEmpty) return;

      final config = jsonDecode(content) as Map<String, dynamic>;
      final channels = (config['channels'] as Map?)?.cast<String, dynamic>() ??
          <String, dynamic>{};

      final existingFeishu = channels[_feishuChannelId];
      final legacyLark = channels[_legacyLarkChannelId];
      final normalized = _extractFeishuUiConfig(existingFeishu) ??
          _extractFeishuUiConfig(legacyLark);

      var changed = false;
      if (normalized != null) {
        final canonical = _buildFeishuStoredConfig(normalized);
        if (jsonEncode(existingFeishu) != jsonEncode(canonical)) {
          channels[_feishuChannelId] = canonical;
          changed = true;
        }
      }

      if (channels.remove(_legacyLarkChannelId) != null) {
        changed = true;
      }

      if (!changed) return;

      config['channels'] = channels;
      await NativeBridge.writeRootfsFile(
        _configPath,
        const JsonEncoder.withIndent('  ').convert(config),
      );
    } catch (_) {
      // Non-fatal: the user can still re-save the channel manually.
    }
  }

  static Future<void> saveChannelConfig({
    required String channelId,
    required Map<String, dynamic> payload,
  }) async {
    if (channelId == _qqbotChannelId) {
      await configureQqbot(
        appId: payload['appId'] as String? ?? '',
        appSecret: payload['appSecret'] as String? ?? '',
      );
      return;
    }

    final storageChannelId = _canonicalChannelIdForStorage(channelId);
    final channelIdJson = jsonEncode(storageChannelId);
    final storedPayload = _storagePayloadForSave(
      channelId: channelId,
      payload: payload,
    );
    final payloadJson = jsonEncode(storedPayload);
    final cleanupLegacy = channelId == _feishuChannelId
        ? 'delete c.channels["$_legacyLarkChannelId"];'
        : '';

    final script = '''
const fs = require("fs");
const p = "$_configPath";
let c = {};
try { c = JSON.parse(fs.readFileSync(p, "utf8")); } catch {}
if (!c.channels) c.channels = {};
c.channels[$channelIdJson] = $payloadJson;
$cleanupLegacy
fs.mkdirSync(require("path").dirname(p), { recursive: true });
fs.writeFileSync(p, JSON.stringify(c, null, 2));
''';

    try {
      await NativeBridge.runInProot(
        'node -e ${_shellEscape(script)}',
        timeout: 15,
      );
    } catch (_) {
      await _saveChannelConfigDirect(
        channelId: channelId,
        payload: storedPayload,
      );
    }
  }

  static Future<void> _saveChannelConfigDirect({
    required String channelId,
    required Map<String, dynamic> payload,
  }) async {
    Map<String, dynamic> config = {};
    try {
      final content = await NativeBridge.readRootfsFile(_configPath);
      if (content != null && content.isNotEmpty) {
        config = jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (_) {
      // Start fresh if config is missing or invalid.
    }

    final before = _configJson(config);
    config['channels'] ??= <String, dynamic>{};
    final storageChannelId = _canonicalChannelIdForStorage(channelId);
    (config['channels'] as Map<String, dynamic>)[storageChannelId] = payload;
    if (channelId == _feishuChannelId) {
      (config['channels'] as Map<String, dynamic>).remove(_legacyLarkChannelId);
    }

    if (before == _configJson(config)) {
      return;
    }
    const encoder = JsonEncoder.withIndent('  ');
    await NativeBridge.writeRootfsFile(_configPath, encoder.convert(config));
  }

  static Future<void> removeChannelConfig({
    required String channelId,
  }) async {
    if (channelId == _qqbotChannelId) {
      await _clearQqbotLocalConfig();
      return;
    }

    final storageChannelId = _canonicalChannelIdForStorage(channelId);
    final channelIdJson = jsonEncode(storageChannelId);

    final script = '''
const fs = require("fs");
const p = "$_configPath";
let c = {};
try { c = JSON.parse(fs.readFileSync(p, "utf8")); } catch {}
if (c.channels) {
  delete c.channels[$channelIdJson];
}
fs.mkdirSync(require("path").dirname(p), { recursive: true });
fs.writeFileSync(p, JSON.stringify(c, null, 2));
''';

    try {
      await NativeBridge.runInProot(
        'node -e ${_shellEscape(script)}',
        timeout: 15,
      );
    } catch (_) {
      await _removeChannelConfigDirect(channelId: channelId);
    }
  }

  static Future<void> _removeChannelConfigDirect({
    required String channelId,
  }) async {
    Map<String, dynamic> config = {};
    try {
      final content = await NativeBridge.readRootfsFile(_configPath);
      if (content != null && content.isNotEmpty) {
        config = jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (_) {
      // Nothing to remove if config is missing or invalid.
    }

    final before = _configJson(config);
    final channels = config['channels'] as Map<String, dynamic>?;
    channels?.remove(_canonicalChannelIdForStorage(channelId));

    if (before == _configJson(config)) {
      return;
    }
    const encoder = JsonEncoder.withIndent('  ');
    await NativeBridge.writeRootfsFile(_configPath, encoder.convert(config));
  }

  static Future<bool> isQqbotPluginInstalled() async {
    final cached = await _readCachedPluginInstalled(_qqbotPluginId);
    if (cached != null) {
      return cached;
    }

    final fastInstalled = await _isPluginInstalledFast(
      pluginId: _qqbotPluginId,
      aliases: _qqbotLegacyPluginIds,
      packagePaths: _qqbotPluginPackagePaths,
      packageNames: const <String>['@tencent-connect/openclaw-qqbot'],
    );
    await _writeCachedPluginInstalled(_qqbotPluginId, fastInstalled);
    return fastInstalled;
  }

  static Future<bool> isWeixinPluginInstalled() async {
    final cached = await _readCachedPluginInstalled(_weixinPluginId);
    if (cached != null) {
      return cached;
    }

    final fastInstalled = await _isPluginInstalledFast(
      pluginId: _weixinPluginId,
      aliases: _weixinLegacyPluginIds,
      packagePaths: _weixinPluginPackagePaths,
      packageNames: const <String>[
        '@tencent-weixin/openclaw-weixin',
        '@tencent/openclaw-weixin',
      ],
    );
    await _writeCachedPluginInstalled(_weixinPluginId, fastInstalled);
    return fastInstalled;
  }

  static Future<void> ensureQqbotPluginInstalled() async {
    await invalidatePluginStatusCache(_qqbotPluginId);
    final installed = await isQqbotPluginInstalled();
    if (installed) {
      await _setPluginEntryEnabled(
        _qqbotPluginId,
        enabled: true,
        cleanupAliases: <String>[_qqbotPluginId, ..._qqbotLegacyPluginIds],
      );
      await _writeCachedPluginInstalled(_qqbotPluginId, true);
      return;
    }

    await _installPluginWithRepair(
      primaryPackage: qqbotPluginPackage,
      fallbackPackage: '@tencent-connect/openclaw-qqbot',
      uninstallCommands: const <String>[
        'openclaw plugins uninstall qqbot >/dev/null 2>&1 || true',
        'openclaw plugins uninstall openclaw-qqbot >/dev/null 2>&1 || true',
      ],
      installNotificationText: 'Installing QQ plugin...',
      repairNotificationText: 'Repairing QQ plugin installation...',
      temporaryDisabledChannelIds: const <String>[_qqbotChannelId],
    );
    await _setPluginEntryEnabled(
      _qqbotPluginId,
      enabled: true,
      cleanupAliases: <String>[_qqbotPluginId, ..._qqbotLegacyPluginIds],
    );
    await _writeCachedPluginInstalled(_qqbotPluginId, true);
  }

  static Future<void> ensureWeixinPluginInstalled() async {
    await invalidatePluginStatusCache(_weixinPluginId);
    final installed = await isWeixinPluginInstalled();
    if (installed) {
      await _setPluginEntryEnabled(
        _weixinPluginId,
        enabled: true,
        cleanupAliases: <String>[_weixinPluginId, ..._weixinLegacyPluginIds],
      );
      await _writeCachedPluginInstalled(_weixinPluginId, true);
      return;
    }

    await _installPluginWithRepair(
      primaryPackage: weixinPluginPackage,
      fallbackPackage: '@tencent-weixin/openclaw-weixin',
      uninstallCommands: const <String>[
        'openclaw plugins uninstall openclaw-weixin >/dev/null 2>&1 || true',
        'openclaw plugins uninstall weixin >/dev/null 2>&1 || true',
      ],
      installNotificationText: 'Installing Weixin plugin...',
      repairNotificationText: 'Repairing Weixin plugin installation...',
      temporaryDisabledChannelIds: const <String>[
        _weixinChannelId,
        _weixinUiChannelId,
      ],
    );
    await _setPluginEntryEnabled(
      _weixinPluginId,
      enabled: true,
      cleanupAliases: <String>[_weixinPluginId, ..._weixinLegacyPluginIds],
    );
    await _writeCachedPluginInstalled(_weixinPluginId, true);
  }

  static String _buildWeixinPluginConfigScript() {
    return '''
const fs = require('fs');
const p = '$_configPath';
let c = {};
try { c = JSON.parse(fs.readFileSync(p, 'utf8')); } catch {}
c.plugins = c.plugins && typeof c.plugins === 'object' ? c.plugins : {};
c.plugins.entries = c.plugins.entries && typeof c.plugins.entries === 'object' ? c.plugins.entries : {};
for (const key of ['weixin', '@tencent/openclaw-weixin', '@tencent-weixin/openclaw-weixin']) {
  delete c.plugins.entries[key];
}
c.plugins.entries['$_weixinPluginId'] = {
  ...(c.plugins.entries['$_weixinPluginId'] || {}),
  enabled: true,
};
const allow = Array.isArray(c.plugins.allow) ? c.plugins.allow.filter(Boolean) : [];
if (!allow.includes('$_weixinPluginId')) {
  allow.push('$_weixinPluginId');
}
c.plugins.allow = allow;
fs.mkdirSync('/root/.openclaw', { recursive: true });
fs.writeFileSync(p, JSON.stringify(c, null, 2));
''';
  }

  static String _buildWeixinPreInstallCleanupScript() {
    return '''
const fs = require('fs');
const p = '$_configPath';
let c = {};
try { c = JSON.parse(fs.readFileSync(p, 'utf8')); } catch {}
if (c.channels && typeof c.channels === 'object') {
  delete c.channels['$_weixinUiChannelId'];
  delete c.channels['$_weixinChannelId'];
  if (Object.keys(c.channels).length === 0) {
    delete c.channels;
  }
}
fs.mkdirSync('/root/.openclaw', { recursive: true });
fs.writeFileSync(p, JSON.stringify(c, null, 2));
''';
  }

  static String buildWeixinInstallerTerminalCommand({bool loginOnly = false}) {
    final installStep = loginOnly
        ? 'echo ">>> Weixin plugin already installed, skipping package download..."'
        : '''
node <<'NODE'
${_buildWeixinPreInstallCleanupScript()}
NODE
echo ">>> Installing Weixin plugin from mirrored npm registry..."
openclaw plugins install "$weixinPluginPackage" || (
  echo ">>> First install attempt failed, retrying with package name fallback..."
  openclaw plugins install @tencent-weixin/openclaw-weixin
)
''';

    return '''
export npm_config_registry=${AppConstants.npmRegistryUrl}
export NPM_CONFIG_REGISTRY=${AppConstants.npmRegistryUrl}
export npm_config_audit=false
export npm_config_fund=false
export npm_config_progress=false
export npm_config_update_notifier=false
export npm_config_fetch_retries=5
export npm_config_fetch_retry_mintimeout=2000
export npm_config_fetch_retry_maxtimeout=20000
export npm_config_prefer_offline=true
export npm_config_prefer_online=false
export npm_config_cache=$_persistentNpmCacheDir
export CHOKIDAR_USEPOLLING=true
export UV_USE_IO_URING=0
mkdir -p /root/.npm $_persistentNpmCacheDir /tmp/npm-tmp
export TMPDIR=/tmp/npm-tmp
$installStep
node <<'NODE'
${
      _buildWeixinPluginConfigScript()
    }
NODE
echo ">>> Starting Weixin login flow..."
echo ">>> If a QR code link appears below, open it on another device and scan with WeChat."
openclaw channels login --channel $_weixinChannelId
''';
  }

  static Future<void> configureQqbot({
    required String appId,
    required String appSecret,
  }) async {
    final normalizedAppId = appId.trim();
    final normalizedAppSecret = appSecret.trim();
    final token = '$normalizedAppId:$normalizedAppSecret';

    await ensureQqbotPluginInstalled();
    await _runOpenclawCommandWithRetries(
      <String>[
        'openclaw channels add --channel qqbot --token ${_shellEscape(token)}',
        'openclaw channels add --channel qqbot --token ${_shellEscape(token)} --force',
      ],
      timeout: 240,
    );
    await _normalizeQqbotChannelConfig(
      appId: normalizedAppId,
      appSecret: normalizedAppSecret,
    );
    await _setPluginEntryEnabled(
      _qqbotPluginId,
      enabled: true,
      cleanupAliases: <String>[_qqbotPluginId, ..._qqbotLegacyPluginIds],
    );
    await _saveQqbotLocalConfig(
      appId: normalizedAppId,
      appSecret: normalizedAppSecret,
    );
  }
}
