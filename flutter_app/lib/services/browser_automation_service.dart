import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'browser_script_library_service.dart';
import 'browser_user_script_library_service.dart';
import 'native_bridge.dart';

abstract class BrowserAutomationDelegate {
  String get sessionLabel;

  Future<Map<String, dynamic>> getState();

  Future<Map<String, dynamic>> selfTest();

  Future<Map<String, dynamic>> healthCheck({
    int quietWindowMs = 500,
    int timeoutMs = 10000,
  });

  Future<Map<String, dynamic>> open(String url);

  Future<Map<String, dynamic>> back();

  Future<Map<String, dynamic>> forward();

  Future<Map<String, dynamic>> reload();

  Future<Map<String, dynamic>> listTabs();

  Future<Map<String, dynamic>> newTab({
    String? url,
  });

  Future<Map<String, dynamic>> switchTab({
    required int id,
  });

  Future<Map<String, dynamic>> closeTab({
    int? id,
  });

  Future<Map<String, dynamic>> setUserAgent({
    required String mode,
  });

  Future<Map<String, dynamic>> click({
    required String selector,
  });

  Future<Map<String, dynamic>> type({
    required String selector,
    required String text,
    bool submit,
  });

  Future<Map<String, dynamic>> paste({
    required String selector,
    required String text,
    bool submit,
  });

  Future<Map<String, dynamic>> waitForResource({
    required String pattern,
    int timeoutMs = 10000,
  });

  Future<Map<String, dynamic>> listOverlays({
    int maxItems = 24,
  });

  Future<Map<String, dynamic>> clickAt({
    required double x,
    required double y,
  });

  Future<Map<String, dynamic>> resetTab({
    String? url,
  });

  Future<Map<String, dynamic>> waitForText({
    required String text,
    int timeoutMs = 10000,
  });

  Future<Map<String, dynamic>> waitForSelector({
    required String selector,
    int timeoutMs = 10000,
    bool visible = true,
  });

  Future<Map<String, dynamic>> scroll({
    String? selector,
    String direction = 'down',
    int pixels = 700,
  });

  Future<Map<String, dynamic>> pressKey({
    String? selector,
    required String key,
  });

  Future<Map<String, dynamic>> selectOption({
    required String selector,
    String? value,
    String? label,
    int? index,
  });

  Future<Map<String, dynamic>> extract({
    String? selector,
    String? prompt,
    int maxLength = 4000,
  });

  Future<Map<String, dynamic>> listLinks({
    String? filter,
    int maxItems = 12,
  });

  Future<Map<String, dynamic>> listInteractables({
    String? filter,
    int maxItems = 16,
  });

  Future<Map<String, dynamic>> highlight({
    required String selector,
  });

  Future<Map<String, dynamic>> captureSnapshot({
    String? selector,
    int maxLength = 8000,
  });

  Future<Map<String, dynamic>> eval({
    required String script,
  });
}

class BrowserActionLogEntry {
  final String action;
  final bool ok;
  final String message;
  final Map<String, dynamic> payload;
  final DateTime at;

  const BrowserActionLogEntry({
    required this.action,
    required this.ok,
    required this.message,
    this.payload = const <String, dynamic>{},
    required this.at,
  });

  BrowserAutomationScriptStep toScriptStep() {
    return BrowserAutomationScriptStep(
      action: action,
      payload: payload,
    );
  }
}

class BrowserAutomationService extends ChangeNotifier {
  BrowserAutomationService._();

  static final BrowserAutomationService instance = BrowserAutomationService._();

  static const _prefsTokenKey = 'browser_bridge_token';
  static const _envPath = '/root/.openclaw/browser-bridge.env';
  static const _host = '127.0.0.1';
  static const _port = 38927;
  static final _uuid = Uuid();
  static const _bridgeOnlyActions = {
    'get_state',
    'script_list',
    'script_stage',
    'script_save',
    'script_rename',
    'script_delete',
    'script_clear_pending',
    'script_set_auto_draft',
    'user_script_list',
    'user_script_save',
    'user_script_delete',
  };
  static const _recordableScriptActions = {
    'open',
    'back',
    'forward',
    'reload',
    'click',
    'type',
    'paste',
    'wait_for_text',
    'wait_for_selector',
    'scroll',
    'press_key',
    'select_option',
  };
  static const _runnableScriptActions = {
    ..._recordableScriptActions,
    'extract',
    'list_links',
    'list_interactables',
    'highlight',
    'capture_snapshot',
  };
  static const _toolActionAliases = {
    'browser_self_test': 'self_test',
    'browser_health_check': 'health_check',
    'browser_open': 'open',
    'browser_back': 'back',
    'browser_forward': 'forward',
    'browser_reload': 'reload',
    'browser_tab_list': 'tab_list',
    'browser_tab_new': 'tab_new',
    'browser_tab_switch': 'tab_switch',
    'browser_tab_close': 'tab_close',
    'browser_set_ua': 'set_ua',
    'browser_click': 'click',
    'browser_type': 'type',
    'browser_paste': 'paste',
    'browser_wait_for_resource': 'wait_for_resource',
    'browser_list_overlays': 'list_overlays',
    'browser_click_at': 'click_at',
    'browser_reset_tab': 'reset_tab',
    'browser_wait_for_text': 'wait_for_text',
    'browser_wait_for_selector': 'wait_for_selector',
    'browser_scroll': 'scroll',
    'browser_press_key': 'press_key',
    'browser_select_option': 'select_option',
    'browser_extract': 'extract',
    'browser_list_links': 'list_links',
    'browser_list_interactables': 'list_interactables',
    'browser_highlight': 'highlight',
    'browser_capture_snapshot': 'capture_snapshot',
    'browser_eval': 'eval',
    'browser_script_list': 'script_list',
    'browser_script_stage': 'script_stage',
    'browser_script_save': 'script_save',
    'browser_script_run': 'script_run',
    'browser_script_rename': 'script_rename',
    'browser_script_delete': 'script_delete',
    'browser_script_clear_pending': 'script_clear_pending',
    'browser_set_script_auto_draft': 'script_set_auto_draft',
    'browser_user_script_list': 'user_script_list',
    'browser_user_script_save': 'user_script_save',
    'browser_user_script_delete': 'user_script_delete',
    'browser_get_state': 'get_state',
  };

  HttpServer? _server;
  Future<void>? _starting;
  BrowserAutomationDelegate? _delegate;
  String _token = '';
  String _currentUrl = '';
  String _currentTitle = '';
  String _lastError = '';
  String _lastSuccessfulUrl = '';
  bool _loading = false;
  String _lastToolName = '';
  int _activeToolCalls = 0;
  DateTime? _lastToolCallAt;
  int _panelRequestNonce = 0;
  String _pendingOpenUrl = '';
  int _activeTabId = 0;
  String _userAgentMode = 'mobile';
  String _userAgentLabel = '手机';
  bool _autoScriptDraftEnabled = false;
  List<Map<String, dynamic>> _tabs = const <Map<String, dynamic>>[];
  Completer<void>? _delegateReadyCompleter;
  final List<BrowserActionLogEntry> _recentActions = [];
  BrowserAutomationScriptDraft? _pendingScriptDraft;

  bool get isRunning => _server != null;
  bool get isBrowserAttached => _delegate != null;
  bool get isToolCallActive => _activeToolCalls > 0;
  String get lastToolName => _lastToolName;
  String get currentUrl => _currentUrl;
  String get currentTitle => _currentTitle;
  String get lastSuccessfulUrl => _lastSuccessfulUrl;
  bool get loading => _loading;
  String get lastError => _lastError;
  String get bridgeUrl => 'http://$_host:$_port';
  String get sessionLabel => _delegate?.sessionLabel ?? '';
  int get panelRequestNonce => _panelRequestNonce;
  bool get hasPendingPanelRequest => _panelRequestNonce > 0;
  String get pendingOpenUrl => _pendingOpenUrl;
  BrowserAutomationScriptDraft? get pendingScriptDraft => _pendingScriptDraft;
  List<BrowserActionLogEntry> get recentActions =>
      List<BrowserActionLogEntry>.unmodifiable(_recentActions);

  Future<void> ensureStarted() {
    final existing = _starting;
    if (existing != null) {
      return existing;
    }
    final future = _startServer();
    _starting = future;
    future.whenComplete(() {
      if (identical(_starting, future)) {
        _starting = null;
      }
    });
    return future;
  }

  void bindDelegate(BrowserAutomationDelegate delegate) {
    _delegate = delegate;
    final completer = _delegateReadyCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    notifyListeners();
    unawaited(_refreshStateFromDelegate());
  }

  void unbindDelegate(BrowserAutomationDelegate delegate) {
    if (!identical(_delegate, delegate)) {
      return;
    }
    _delegate = null;
    _loading = false;
    notifyListeners();
  }

  void updateObservedState({
    String? url,
    String? title,
    bool? loading,
    String? error,
    List<Map<String, dynamic>>? tabs,
    int? activeTabId,
    String? userAgentMode,
    String? userAgentLabel,
  }) {
    var changed = false;
    if (url != null && url != _currentUrl) {
      _currentUrl = url;
      changed = true;
    }
    if (title != null && title != _currentTitle) {
      _currentTitle = title;
      changed = true;
    }
    if (loading != null && loading != _loading) {
      _loading = loading;
      changed = true;
    }
    if (error != null && error != _lastError) {
      _lastError = error;
      changed = true;
    }
    if (tabs != null) {
      _tabs = List<Map<String, dynamic>>.unmodifiable(
        tabs.map((tab) => Map<String, dynamic>.from(tab)),
      );
      changed = true;
    }
    if (activeTabId != null && activeTabId != _activeTabId) {
      _activeTabId = activeTabId;
      changed = true;
    }
    if (userAgentMode != null && userAgentMode != _userAgentMode) {
      _userAgentMode = userAgentMode;
      changed = true;
    }
    if (userAgentLabel != null && userAgentLabel != _userAgentLabel) {
      _userAgentLabel = userAgentLabel;
      changed = true;
    }
    final remembered = _rememberSuccessfulUrl(
      url: url,
      loading: loading,
      error: error,
    );
    changed = changed || remembered;
    if (changed) {
      notifyListeners();
    }
  }

  String takePendingOpenUrl() {
    final pending = _pendingOpenUrl;
    _pendingOpenUrl = '';
    return pending;
  }

  Future<List<BrowserAutomationScript>> loadScripts() {
    return BrowserScriptLibraryService.loadScripts();
  }

  Future<Map<String, dynamic>> saveRecentScript({
    required String fileName,
    required String description,
    int maxRecentSteps = 16,
    bool overwrite = false,
  }) {
    return _invokeAction('script_save', {
      'fileName': fileName,
      'description': description,
      'maxRecentSteps': maxRecentSteps,
      'overwrite': overwrite,
      'sourceUrl': _currentUrl,
      'sourceTitle': _currentTitle,
    });
  }

  Future<Map<String, dynamic>> savePendingScript({
    required String fileName,
    required String description,
    bool overwrite = false,
  }) {
    final draft = _pendingScriptDraft;
    if (draft == null) {
      return Future.value({
        'ok': false,
        'message': 'There is no pending browser script draft to save.',
      });
    }
    return _invokeAction('script_save', {
      'fileName': fileName,
      'description': description,
      'steps': [for (final step in draft.steps) step.toJson()],
      'variables': draft.variables,
      'sourceUrl': draft.sourceUrl,
      'sourceTitle': draft.sourceTitle,
      'overwrite': overwrite,
      'clearPending': true,
    });
  }

  Future<Map<String, dynamic>> clearPendingScriptDraft() {
    return _invokeAction('script_clear_pending', const <String, dynamic>{});
  }

  Future<Map<String, dynamic>> runPageScript(String script) {
    return _invokeAction('eval', {'script': script});
  }

  Future<Map<String, dynamic>> runScript(String id) {
    return _invokeAction('script_run', {'id': id});
  }

  Future<Map<String, dynamic>> renameScript({
    required String id,
    required String fileName,
    required String description,
  }) {
    return _invokeAction('script_rename', {
      'id': id,
      'fileName': fileName,
      'description': description,
    });
  }

  Future<Map<String, dynamic>> deleteScript(String id) {
    return _invokeAction('script_delete', {'id': id});
  }

  Future<void> _startServer() async {
    if (_server != null) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final savedToken = prefs.getString(_prefsTokenKey)?.trim() ?? '';
    _token = savedToken.isNotEmpty ? savedToken : _uuid.v4();
    if (savedToken != _token) {
      await prefs.setString(_prefsTokenKey, _token);
    }

    final server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      _port,
      shared: true,
    );
    server.idleTimeout = const Duration(minutes: 10);
    _server = server;
    _writeEnvFile();
    notifyListeners();

    server.listen((request) async {
      try {
        await _handleRequest(request);
      } catch (error) {
        _writeJson(
          request.response,
          statusCode: HttpStatus.internalServerError,
          body: {
            'ok': false,
            'message': 'Bridge failure: $error',
          },
        );
      }
    });
  }

  Future<void> _refreshStateFromDelegate() async {
    final delegate = _delegate;
    if (delegate == null) {
      return;
    }
    try {
      final state = await delegate.getState();
      _mergeState(state);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _writeEnvFile() async {
    final content = StringBuffer()
      ..writeln('OPENCLAW_BROWSER_BRIDGE_URL=$bridgeUrl')
      ..writeln("OPENCLAW_BROWSER_BRIDGE_TOKEN='$_token'");
    try {
      await NativeBridge.writeRootfsFile(_envPath, content.toString());
      await NativeBridge.runInProot(
        'chmod 0600 $_envPath 2>/dev/null || true',
        timeout: 10,
      );
    } catch (_) {}
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.method == 'GET' && request.uri.path == '/health') {
      _writeJson(
        request.response,
        body: {
          'ok': true,
          'bridgeUrl': bridgeUrl,
          'browserAttached': isBrowserAttached,
          'state': _snapshot(),
        },
      );
      return;
    }

    if (!_isAuthorized(request)) {
      _writeJson(
        request.response,
        statusCode: HttpStatus.unauthorized,
        body: {
          'ok': false,
          'message': 'Unauthorized browser bridge request',
        },
      );
      return;
    }

    if (request.method == 'GET' && request.uri.path == '/state') {
      _writeJson(
        request.response,
        body: {
          'ok': true,
          'state': _snapshot(),
        },
      );
      return;
    }

    if (request.method != 'POST') {
      _writeJson(
        request.response,
        statusCode: HttpStatus.methodNotAllowed,
        body: {
          'ok': false,
          'message': 'Unsupported method ${request.method}',
        },
      );
      return;
    }

    final action = request.uri.pathSegments.isNotEmpty
        ? request.uri.pathSegments.last.trim()
        : '';
    final normalizedAction = _normalizeAction(action);
    if (normalizedAction.isEmpty) {
      _writeJson(
        request.response,
        statusCode: HttpStatus.notFound,
        body: {
          'ok': false,
          'message': 'Missing action name',
        },
      );
      return;
    }

    final payload = await _readJsonBody(request);
    final result = await _invokeAction(normalizedAction, payload);
    _writeJson(request.response, body: result);
  }

  bool _isAuthorized(HttpRequest request) {
    final token = _token.trim();
    if (token.isEmpty) {
      return false;
    }
    final auth = request.headers.value(HttpHeaders.authorizationHeader) ?? '';
    return auth == 'Bearer $token';
  }

  Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
    final body = await utf8.decoder.bind(request).join();
    if (body.trim().isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) {
      return decoded;
    }
    if (decoded is Map) {
      return decoded.map(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    return <String, dynamic>{};
  }

  Future<Map<String, dynamic>> _invokeAction(
    String action,
    Map<String, dynamic> payload,
  ) async {
    final needsDelegate = !_bridgeOnlyActions.contains(action);
    final delegate = needsDelegate
        ? await _ensureDelegateForAction(
            action: action,
            payload: payload,
          )
        : null;
    if (needsDelegate && delegate == null) {
      return {
        'ok': false,
        'message': hasPendingPanelRequest
            ? 'Browser panel is being opened. Keep the app in foreground and try again in a moment.'
            : 'Browser panel is not attached. Open the browser panel first.',
        'state': _snapshot(),
      };
    }

    _activeToolCalls += 1;
    _lastToolName = action;
    _lastToolCallAt = DateTime.now().toUtc();
    notifyListeners();

    try {
      final state = needsDelegate
          ? await _invokeBrowserDelegateAction(delegate!, action, payload)
          : await _invokeScriptLibraryAction(action, payload);

      _mergeState(state);
      _recordAction(
        action: action,
        ok: state['ok'] != false,
        message: _stringOrFallback(
          state['message'],
          fallback: 'Browser action "$action" completed.',
        ),
        payload: _recordableScriptActions.contains(action)
            ? _jsonMap(payload)
            : const <String, dynamic>{},
      );
      return {
        'ok': state['ok'] != false,
        'message': _stringOrFallback(
          state['message'],
          fallback: 'Browser action "$action" completed.',
        ),
        'state': _snapshot(),
        'result': state,
      };
    } catch (error) {
      _lastError = error.toString();
      _recordAction(
        action: action,
        ok: false,
        message: _lastError,
        payload: _recordableScriptActions.contains(action)
            ? _jsonMap(payload)
            : const <String, dynamic>{},
      );
      return {
        'ok': false,
        'message': _lastError,
        'state': _snapshot(),
      };
    } finally {
      if (_activeToolCalls > 0) {
        _activeToolCalls -= 1;
      }
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> _invokeBrowserDelegateAction(
    BrowserAutomationDelegate delegate,
    String action,
    Map<String, dynamic> payload,
  ) async {
    switch (action) {
      case 'get_state':
        return delegate.getState();
      case 'self_test':
        return delegate.selfTest();
      case 'health_check':
        return delegate.healthCheck(
          quietWindowMs: _int(payload['quietWindowMs'], fallback: 500),
          timeoutMs: _int(payload['timeoutMs'], fallback: 10000),
        );
      case 'open':
        return delegate.open(_string(payload['url']));
      case 'back':
        return delegate.back();
      case 'forward':
        return delegate.forward();
      case 'reload':
        return delegate.reload();
      case 'tab_list':
        return delegate.listTabs();
      case 'tab_new':
        return delegate.newTab(
          url: _nullableString(payload['url']),
        );
      case 'tab_switch':
        return delegate.switchTab(
          id: _int(payload['id'] ?? payload['tabId'], fallback: 0),
        );
      case 'tab_close':
        return delegate.closeTab(
          id: payload.containsKey('id') || payload.containsKey('tabId')
              ? _int(payload['id'] ?? payload['tabId'], fallback: 0)
              : null,
        );
      case 'set_ua':
        return delegate.setUserAgent(
          mode: _string(payload['mode']),
        );
      case 'click':
        return delegate.click(
          selector: _string(payload['selector']),
        );
      case 'type':
        return delegate.type(
          selector: _string(payload['selector']),
          text: _string(payload['text']),
          submit: payload['submit'] == true,
        );
      case 'paste':
        return delegate.paste(
          selector: _string(payload['selector']),
          text: _string(payload['text']),
          submit: payload['submit'] == true,
        );
      case 'wait_for_resource':
        return delegate.waitForResource(
          pattern: _string(payload['pattern']),
          timeoutMs: _int(payload['timeoutMs'], fallback: 10000),
        );
      case 'list_overlays':
        return delegate.listOverlays(
          maxItems: _int(payload['maxItems'], fallback: 24),
        );
      case 'click_at':
        return delegate.clickAt(
          x: (payload['x'] as num?)?.toDouble() ?? double.nan,
          y: (payload['y'] as num?)?.toDouble() ?? double.nan,
        );
      case 'reset_tab':
        return delegate.resetTab(url: _nullableString(payload['url']));
      case 'wait_for_text':
        return delegate.waitForText(
          text: _string(payload['text']),
          timeoutMs: _int(payload['timeoutMs'], fallback: 10000),
        );
      case 'wait_for_selector':
        return delegate.waitForSelector(
          selector: _string(payload['selector']),
          timeoutMs: _int(payload['timeoutMs'], fallback: 10000),
          visible: payload['visible'] != false,
        );
      case 'scroll':
        return delegate.scroll(
          selector: _nullableString(payload['selector']),
          direction: _stringOrFallback(
            payload['direction'],
            fallback: 'down',
          ),
          pixels: _int(payload['pixels'], fallback: 700),
        );
      case 'press_key':
        return delegate.pressKey(
          selector: _nullableString(payload['selector']),
          key: _string(payload['key']),
        );
      case 'select_option':
        return delegate.selectOption(
          selector: _string(payload['selector']),
          value: _nullableString(payload['value']),
          label: _nullableString(payload['label']),
          index: payload.containsKey('index')
              ? _int(payload['index'], fallback: -1)
              : null,
        );
      case 'extract':
        return delegate.extract(
          selector: _nullableString(payload['selector']),
          prompt: _nullableString(payload['prompt']),
          maxLength: _int(payload['maxLength'], fallback: 4000),
        );
      case 'list_links':
        return delegate.listLinks(
          filter: _nullableString(payload['filter']),
          maxItems: _int(payload['maxItems'], fallback: 12),
        );
      case 'list_interactables':
        return delegate.listInteractables(
          filter: _nullableString(payload['filter']),
          maxItems: _int(payload['maxItems'], fallback: 16),
        );
      case 'highlight':
        return delegate.highlight(
          selector: _string(payload['selector']),
        );
      case 'capture_snapshot':
        return delegate.captureSnapshot(
          selector: _nullableString(payload['selector']),
          maxLength: _int(payload['maxLength'], fallback: 8000),
        );
      case 'eval':
        return delegate.eval(
          script: _string(payload['script']),
        );
      case 'script_run':
        return _runSavedScript(delegate, payload);
      default:
        return {
          'ok': false,
          'message': 'Unsupported browser action: $action',
          'state': _snapshot(),
        };
    }
  }

  Future<Map<String, dynamic>> _invokeScriptLibraryAction(
    String action,
    Map<String, dynamic> payload,
  ) async {
    switch (action) {
      case 'get_state':
        return {
          'ok': true,
          'message': 'Browser state loaded.',
          ..._snapshot(),
        };
      case 'script_list':
        return _listScripts(payload);
      case 'script_stage':
        return _stageScriptDraft(payload);
      case 'script_save':
        return _saveScript(payload);
      case 'script_rename':
        return _renameScript(payload);
      case 'script_delete':
        return _deleteScript(payload);
      case 'script_clear_pending':
        return _clearPendingScriptDraft();
      case 'script_set_auto_draft':
        _autoScriptDraftEnabled = payload['enabled'] == true;
        if (!_autoScriptDraftEnabled) {
          _pendingScriptDraft = null;
        }
        notifyListeners();
        return {
          'ok': true,
          'message': _autoScriptDraftEnabled
              ? 'Automatic browser script drafts are enabled.'
              : 'Automatic browser script drafts are disabled.',
          'autoScriptDraftEnabled': _autoScriptDraftEnabled,
        };
      case 'user_script_list':
        final scripts = await BrowserUserScriptLibraryService.loadScripts();
        return {
          'ok': true,
          'message': 'Traditional website scripts loaded.',
          'scripts': [for (final script in scripts) script.toJson()],
        };
      case 'user_script_save':
        final matches = _stringList(payload['matches']);
        final script = await BrowserUserScriptLibraryService.saveScript(
          id: _nullableString(payload['id']),
          name: _string(payload['name']),
          description: _string(payload['description']),
          code: _string(payload['code']),
          matches: matches,
        );
        return {
          'ok': true,
          'message': 'Traditional website script saved. It will not run until the user confirms it in the script assistant.',
          'script': script.toJson(),
        };
      case 'user_script_delete':
        await BrowserUserScriptLibraryService.deleteScript(_string(payload['id']));
        return {'ok': true, 'message': 'Traditional website script deleted.'};
      default:
        return {
          'ok': false,
          'message': 'Unsupported browser script action: $action',
          'state': _snapshot(),
        };
    }
  }

  Future<Map<String, dynamic>> _listScripts(
    Map<String, dynamic> payload,
  ) async {
    final filter = _nullableString(payload['filter'])?.toLowerCase() ?? '';
    final scripts = await BrowserScriptLibraryService.loadScripts();
    final filtered = filter.isEmpty
        ? scripts
        : scripts.where((script) {
            final haystack = [
              script.id,
              script.fileName,
              script.description,
              script.sourceUrl,
              script.sourceTitle,
            ].join(' ').toLowerCase();
            return haystack.contains(filter);
          }).toList();
    return {
      'ok': true,
      'message': filtered.isEmpty
          ? 'No browser scripts matched the request.'
          : 'Browser scripts loaded.',
      'count': filtered.length,
      'scripts': [
        for (final script in filtered) script.toJson(includeCommand: true),
      ],
      'pendingDraft': _pendingScriptDraft?.toJson(),
    };
  }

  Future<Map<String, dynamic>> _stageScriptDraft(
    Map<String, dynamic> payload,
  ) async {
    final explicitSteps = _scriptStepsFromPayload(payload['steps']);
    final steps = explicitSteps.isNotEmpty
        ? explicitSteps
        : _recentScriptSteps(
            maxSteps: _int(payload['maxRecentSteps'], fallback: 16),
          );
    if (steps.isEmpty) {
      return {
        'ok': false,
        'message':
            'No repeatable browser actions are available to stage. Provide explicit steps or run repeatable browser actions first.',
      };
    }

    final sourceUrl = _stringOrFallback(payload['sourceUrl'], fallback: _currentUrl);
    final sourceTitle = _stringOrFallback(
      payload['sourceTitle'],
      fallback: _currentTitle,
    );
    final draft = BrowserAutomationScriptDraft(
      fileName: BrowserAutomationScript.normalizeFileName(
        _stringOrFallback(
          payload['fileName'],
          fallback: _defaultDraftFileName(
            description: _string(payload['description']),
            sourceTitle: sourceTitle,
            sourceUrl: sourceUrl,
          ),
        ),
      ),
      description: _stringOrFallback(
        payload['description'],
        fallback: _defaultDraftDescription(
          steps: steps,
          sourceTitle: sourceTitle,
          sourceUrl: sourceUrl,
        ),
      ),
      steps: steps,
      variables: _stringList(payload['variables']),
      sourceUrl: sourceUrl,
      sourceTitle: sourceTitle,
      updatedAt: DateTime.now().toUtc(),
      autoGenerated: payload['autoGenerated'] == true,
    );
    _pendingScriptDraft = draft;
    return {
      'ok': true,
      'message': 'Browser script draft staged: ${draft.fileName}',
      'pendingDraft': draft.toJson(),
    };
  }

  Future<Map<String, dynamic>> _clearPendingScriptDraft() async {
    final hadDraft = _pendingScriptDraft != null;
    _pendingScriptDraft = null;
    return {
      'ok': true,
      'message': hadDraft
          ? 'Pending browser script draft cleared.'
          : 'There was no pending browser script draft.',
      'pendingDraft': null,
    };
  }

  Future<Map<String, dynamic>> _saveScript(
    Map<String, dynamic> payload,
  ) async {
    final explicitSteps = _scriptStepsFromPayload(payload['steps']);
    final recentSteps = _recentScriptSteps(
      maxSteps: _int(payload['maxRecentSteps'], fallback: 16),
    );
    final pendingDraft = _pendingScriptDraft;
    final steps = explicitSteps.isNotEmpty
        ? explicitSteps
        : recentSteps.isNotEmpty
            ? recentSteps
            : pendingDraft?.steps ?? const <BrowserAutomationScriptStep>[];
    if (steps.isEmpty) {
      return {
        'ok': false,
        'message':
            'No repeatable browser actions are available to save. Run browser_open, click, type, wait, scroll, key, or select actions first.',
      };
    }

    final script = await BrowserScriptLibraryService.saveScript(
      id: _string(payload['id']),
      fileName: _stringOrFallback(
        payload['fileName'],
        fallback: pendingDraft?.fileName ??
            'browser-script-${DateTime.now().millisecondsSinceEpoch}.browser.json',
      ),
      description: _stringOrFallback(
        payload['description'],
        fallback: pendingDraft?.description ?? 'Reusable browser automation script',
      ),
      steps: steps,
      variables: payload.containsKey('variables')
          ? _stringList(payload['variables'])
          : pendingDraft?.variables ?? const <String>[],
      sourceUrl: _stringOrFallback(
        payload['sourceUrl'],
        fallback: pendingDraft?.sourceUrl ?? _currentUrl,
      ),
      sourceTitle: _stringOrFallback(
        payload['sourceTitle'],
        fallback: pendingDraft?.sourceTitle ?? _currentTitle,
      ),
      overwrite: payload['overwrite'] == true,
    );
    if (payload['clearPending'] == true) {
      _pendingScriptDraft = null;
    }
    return {
      'ok': true,
      'message': 'Browser script saved: ${script.fileName}',
      'script': script.toJson(includeCommand: true),
    };
  }

  Future<Map<String, dynamic>> _renameScript(
    Map<String, dynamic> payload,
  ) async {
    final id = _string(payload['id']);
    final fileName = _string(payload['fileName']);
    if (id.isEmpty || fileName.isEmpty) {
      return {
        'ok': false,
        'message': 'Provide both id and fileName to rename a browser script.',
      };
    }
    final script = await BrowserScriptLibraryService.renameScript(
      id: id,
      fileName: fileName,
      description: payload.containsKey('description')
          ? _string(payload['description'])
          : null,
    );
    if (script == null) {
      return {
        'ok': false,
        'message': 'Browser script was not found: $id',
      };
    }
    return {
      'ok': true,
      'message': 'Browser script renamed: ${script.fileName}',
      'script': script.toJson(includeCommand: true),
    };
  }

  Future<Map<String, dynamic>> _deleteScript(
    Map<String, dynamic> payload,
  ) async {
    final id = _string(payload['id']);
    if (id.isEmpty) {
      return {
        'ok': false,
        'message': 'Provide id to delete a browser script.',
      };
    }
    final deleted = await BrowserScriptLibraryService.deleteScript(id);
    return {
      'ok': deleted,
      'message': deleted
          ? 'Browser script deleted.'
          : 'Browser script was not found: $id',
    };
  }

  Future<Map<String, dynamic>> _runSavedScript(
    BrowserAutomationDelegate delegate,
    Map<String, dynamic> payload,
  ) async {
    final script = await BrowserScriptLibraryService.findScript(
      id: _string(payload['id']),
      fileName: _string(payload['fileName']),
    );
    if (script == null) {
      return {
        'ok': false,
        'message': 'Browser script was not found.',
      };
    }

    final variables = _stringMap(payload['variables']);
    final stopOnError = payload['stopOnError'] != false;
    final stepResults = <Map<String, dynamic>>[];
    for (var i = 0; i < script.steps.length; i++) {
      final step = script.steps[i];
      final action = _normalizeAction(step.action);
      if (!_runnableScriptActions.contains(action)) {
        final result = {
          'index': i + 1,
          'action': step.action,
          'ok': false,
          'message': 'Saved scripts cannot run browser action: ${step.action}',
        };
        stepResults.add(result);
        if (stopOnError) {
          return {
            'ok': false,
            'message': result['message'],
            'script': script.toJson(includeCommand: true),
            'steps': stepResults,
            'state': _snapshot(),
          };
        }
        continue;
      }

      final resolvedPayload = _resolveScriptVariables(step.payload, variables);
      final state = await _invokeBrowserDelegateAction(
        delegate,
        action,
        resolvedPayload,
      );
      _mergeState(state);
      final ok = state['ok'] != false;
      final message = _stringOrFallback(
        state['message'],
        fallback: 'Browser script step completed.',
      );
      _recordAction(
        action: action,
        ok: ok,
        message: message,
        payload: _recordableScriptActions.contains(action)
            ? resolvedPayload
            : const <String, dynamic>{},
      );
      stepResults.add({
        'index': i + 1,
        'action': action,
        'ok': ok,
        'message': message,
        'result': state,
      });
      if (!ok && stopOnError) {
        return {
          'ok': false,
          'message': 'Browser script stopped at step ${i + 1}: $message',
          'script': script.toJson(includeCommand: true),
          'steps': stepResults,
          'state': _snapshot(),
        };
      }
    }

    final updated = await BrowserScriptLibraryService.markRun(script.id);
    return {
      'ok': true,
      'message': 'Browser script completed: ${script.fileName}',
      'script': (updated ?? script).toJson(includeCommand: true),
      'steps': stepResults,
      'state': _snapshot(),
    };
  }

  List<BrowserAutomationScriptStep> _recentScriptSteps({
    required int maxSteps,
  }) {
    final safeMaxSteps = maxSteps.clamp(1, 40).toInt();
    return _recentActions
        .where((entry) => entry.ok)
        .where((entry) => _recordableScriptActions.contains(entry.action))
        .take(safeMaxSteps)
        .map((entry) => entry.toScriptStep())
        .toList()
        .reversed
        .toList();
  }

  List<BrowserAutomationScriptStep> _scriptStepsFromPayload(Object? rawSteps) {
    if (rawSteps is! List) {
      return const <BrowserAutomationScriptStep>[];
    }
    final steps = <BrowserAutomationScriptStep>[];
    for (final rawStep in rawSteps) {
      if (rawStep is! Map) {
        continue;
      }
      final json = rawStep.map((key, value) => MapEntry(key.toString(), value));
      final action = _normalizeAction(
        json['action']?.toString() ?? json['tool']?.toString() ?? '',
      );
      final payload = json.containsKey('payload')
          ? _jsonMap(json['payload'])
          : _jsonMap(json['arguments']);
      if (action.isEmpty || !_runnableScriptActions.contains(action)) {
        continue;
      }
      steps.add(
        BrowserAutomationScriptStep(
          action: action,
          payload: payload,
          note: json['note']?.toString().trim() ?? '',
        ),
      );
    }
    return steps;
  }

  String _normalizeAction(String action) {
    final normalized = action.trim();
    if (normalized.isEmpty) {
      return '';
    }
    return _toolActionAliases[normalized] ?? normalized;
  }

  Map<String, dynamic> _resolveScriptVariables(
    Map<String, dynamic> payload,
    Map<String, String> variables,
  ) {
    final resolved = _resolveScriptValue(payload, variables);
    return resolved is Map<String, dynamic> ? resolved : <String, dynamic>{};
  }

  Object? _resolveScriptValue(Object? value, Map<String, String> variables) {
    if (value is String) {
      var resolved = value;
      for (final entry in variables.entries) {
        resolved = resolved.replaceAll('{{${entry.key}}}', entry.value);
      }
      return resolved;
    }
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): _resolveScriptValue(entry.value, variables),
      };
    }
    if (value is Iterable) {
      return [for (final item in value) _resolveScriptValue(item, variables)];
    }
    return value;
  }

  Future<BrowserAutomationDelegate?> _ensureDelegateForAction({
    required String action,
    required Map<String, dynamic> payload,
  }) async {
    final existing = _delegate;
    if (existing != null) {
      return existing;
    }

    final preferredUrl = switch (action) {
      'open' => _string(payload['url']),
      'self_test' => 'about:blank',
      _ => '',
    };
    _requestBrowserPanel(initialUrl: preferredUrl);

    final completer = _delegateReadyCompleter;
    if (completer == null || completer.isCompleted) {
      _delegateReadyCompleter = Completer<void>();
    }

    try {
      await _delegateReadyCompleter!.future.timeout(
        const Duration(seconds: 8),
      );
    } catch (_) {
      return _delegate;
    }
    return _delegate;
  }

  void _requestBrowserPanel({String initialUrl = ''}) {
    final normalizedUrl = _panelBootstrapUrl(initialUrl);
    if (normalizedUrl.isNotEmpty) {
      _pendingOpenUrl = normalizedUrl;
    }
    _panelRequestNonce += 1;
    notifyListeners();
  }

  void _mergeState(Map<String, dynamic> state) {
    final normalizedUrl = _nullableString(state['url']);
    final normalizedTitle = _nullableString(state['title']);
    if (normalizedUrl != null) {
      _currentUrl = normalizedUrl;
    }
    if (normalizedTitle != null) {
      _currentTitle = normalizedTitle;
    }
    if (state.containsKey('loading')) {
      _loading = state['loading'] == true;
    }
    if (state.containsKey('error')) {
      _lastError = state['error']?.toString().trim() ?? '';
    }
    final tabs = state['tabs'];
    if (tabs is List) {
      _tabs = List<Map<String, dynamic>>.unmodifiable(
        tabs.whereType<Map>().map(
              (tab) => tab.map(
                (key, value) => MapEntry(key.toString(), value),
              ),
            ),
      );
    }
    if (state.containsKey('activeTabId')) {
      _activeTabId = _int(state['activeTabId'], fallback: _activeTabId);
    }
    final userAgentMode = _nullableString(state['userAgentMode']);
    if (userAgentMode != null) {
      _userAgentMode = userAgentMode;
    }
    final userAgentLabel = _nullableString(state['userAgentLabel']);
    if (userAgentLabel != null) {
      _userAgentLabel = userAgentLabel;
    }
    _rememberSuccessfulUrl();
  }

  Map<String, dynamic> _snapshot() {
    return {
      'bridgeUrl': bridgeUrl,
      'browserAttached': isBrowserAttached,
      'sessionLabel': sessionLabel,
      'url': _currentUrl,
      'title': _currentTitle,
      'lastSuccessfulUrl': _lastSuccessfulUrl,
      'tabs': _tabs,
      'activeTabId': _activeTabId,
      'userAgentMode': _userAgentMode,
      'userAgentLabel': _userAgentLabel,
      'loading': _loading,
      'lastError': _lastError,
      'activeToolCalls': _activeToolCalls,
      'lastToolName': _lastToolName,
      'lastToolCallAt': _lastToolCallAt?.toIso8601String(),
      'pendingScriptDraft': _pendingScriptDraft?.toJson(),
      'recentActions': [
        for (final entry in _recentActions)
          {
            'action': entry.action,
            'ok': entry.ok,
            'message': entry.message,
            'payload': entry.payload,
            'at': entry.at.toIso8601String(),
          },
      ],
    };
  }

  String _panelBootstrapUrl(String initialUrl) {
    final requestedUrl = initialUrl.trim();
    if (requestedUrl.isNotEmpty) {
      return requestedUrl;
    }
    final rememberedUrl = _lastSuccessfulUrl.trim();
    if (_isRestorableUrl(rememberedUrl)) {
      return rememberedUrl;
    }
    final currentUrl = _currentUrl.trim();
    if (_lastError.trim().isEmpty && _isRestorableUrl(currentUrl)) {
      return currentUrl;
    }
    return '';
  }

  bool _rememberSuccessfulUrl({
    String? url,
    bool? loading,
    String? error,
  }) {
    final candidate = (url ?? _currentUrl).trim();
    if (candidate.isEmpty ||
        !_isRestorableUrl(candidate) ||
        (loading ?? _loading) ||
        (error ?? _lastError).trim().isNotEmpty) {
      return false;
    }
    if (candidate == _lastSuccessfulUrl) {
      return false;
    }
    _lastSuccessfulUrl = candidate;
    return true;
  }

  bool _isRestorableUrl(String value) {
    final uri = Uri.tryParse(value.trim());
    if (uri == null || !uri.hasScheme) {
      return false;
    }
    final scheme = uri.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https';
  }

  void _recordAction({
    required String action,
    required bool ok,
    required String message,
    Map<String, dynamic> payload = const <String, dynamic>{},
  }) {
    _recentActions.insert(
      0,
      BrowserActionLogEntry(
        action: action,
        ok: ok,
        message: message,
        payload: payload,
        at: DateTime.now().toUtc(),
      ),
    );
    if (_recentActions.length > 20) {
      _recentActions.removeRange(20, _recentActions.length);
    }
    if (ok &&
        _autoScriptDraftEnabled &&
        _recordableScriptActions.contains(action)) {
      _refreshAutoPendingScriptDraft();
    }
  }

  void _refreshAutoPendingScriptDraft() {
    final existing = _pendingScriptDraft;
    final latestActionAt = _latestSuccessfulRecordableActionAt();
    if (existing != null &&
        !existing.autoGenerated &&
        latestActionAt != null &&
        existing.updatedAt.isAfter(latestActionAt)) {
      return;
    }
    final steps = _recentScriptSteps(maxSteps: 16);
    if (steps.isEmpty) {
      return;
    }
    _pendingScriptDraft = BrowserAutomationScriptDraft(
      fileName: BrowserAutomationScript.normalizeFileName(
        _defaultDraftFileName(
          sourceTitle: _currentTitle,
          sourceUrl: _currentUrl,
        ),
      ),
      description: _defaultDraftDescription(
        steps: steps,
        sourceTitle: _currentTitle,
        sourceUrl: _currentUrl,
      ),
      steps: steps,
      sourceUrl: _currentUrl,
      sourceTitle: _currentTitle,
      updatedAt: DateTime.now().toUtc(),
      autoGenerated: true,
    );
  }

  DateTime? _latestSuccessfulRecordableActionAt() {
    for (final entry in _recentActions) {
      if (entry.ok && _recordableScriptActions.contains(entry.action)) {
        return entry.at;
      }
    }
    return null;
  }

  String _defaultDraftFileName({
    String description = '',
    String sourceTitle = '',
    String sourceUrl = '',
  }) {
    final candidates = [
      description,
      sourceTitle,
      Uri.tryParse(sourceUrl.trim())?.host ?? '',
      'browser-task',
    ];
    var slug = candidates
        .map((item) => item.trim().toLowerCase())
        .firstWhere((item) => item.isNotEmpty, orElse: () => 'browser-task')
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    if (slug.isEmpty) {
      slug = 'browser-task';
    }
    if (slug.length > 48) {
      slug = slug.substring(0, 48).replaceAll(RegExp(r'-$'), '');
    }
    return '$slug.browser.json';
  }

  String _defaultDraftDescription({
    required List<BrowserAutomationScriptStep> steps,
    String sourceTitle = '',
    String sourceUrl = '',
  }) {
    final title = sourceTitle.trim();
    final host = Uri.tryParse(sourceUrl.trim())?.host ?? '';
    final target = title.isNotEmpty
        ? title
        : host.isNotEmpty
            ? host
            : '当前网页';
    final actions = steps
        .map((step) => step.action)
        .where((action) => action.isNotEmpty)
        .toSet()
        .take(4)
        .join(', ');
    final actionNote = actions.isEmpty ? '' : '，包含 $actions';
    return '复用 $target 的浏览器操作流程，共 ${steps.length} 步$actionNote。';
  }

  void _writeJson(
    HttpResponse response, {
    int statusCode = HttpStatus.ok,
    required Map<String, dynamic> body,
  }) {
    response.statusCode = statusCode;
    response.headers.contentType = ContentType.json;
    response.write(const JsonEncoder.withIndent('  ').convert(body));
    unawaited(response.close());
  }

  static Map<String, dynamic> _jsonMap(Object? value) {
    final safe = _jsonSafe(value);
    if (safe is Map<String, dynamic>) {
      return safe;
    }
    if (safe is Map) {
      return safe.map((key, item) => MapEntry(key.toString(), item));
    }
    return <String, dynamic>{};
  }

  static Object? _jsonSafe(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): _jsonSafe(entry.value),
      };
    }
    if (value is Iterable) {
      return [for (final item in value) _jsonSafe(item)];
    }
    return value.toString();
  }

  static List<String> _stringList(Object? value) {
    if (value is! List) {
      return const <String>[];
    }
    return value
        .map((item) => item.toString().trim())
        .where((item) => item.isNotEmpty)
        .toSet()
        .toList();
  }

  static Map<String, String> _stringMap(Object? value) {
    if (value is! Map) {
      return const <String, String>{};
    }
    return {
      for (final entry in value.entries)
        if (entry.key.toString().trim().isNotEmpty)
          entry.key.toString().trim(): entry.value.toString(),
    };
  }

  static String _string(Object? value) {
    return value?.toString().trim() ?? '';
  }

  static String? _nullableString(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : text;
  }

  static int _int(Object? value, {required int fallback}) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static String _stringOrFallback(
    Object? value, {
    required String fallback,
  }) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? fallback : text;
  }
}
