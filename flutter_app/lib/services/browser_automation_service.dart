import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import 'native_bridge.dart';

abstract class BrowserAutomationDelegate {
  String get sessionLabel;

  Future<Map<String, dynamic>> getState();

  Future<Map<String, dynamic>> open(String url);

  Future<Map<String, dynamic>> back();

  Future<Map<String, dynamic>> forward();

  Future<Map<String, dynamic>> reload();

  Future<Map<String, dynamic>> click({
    required String selector,
  });

  Future<Map<String, dynamic>> type({
    required String selector,
    required String text,
    bool submit,
  });

  Future<Map<String, dynamic>> waitForText({
    required String text,
    int timeoutMs,
  });

  Future<Map<String, dynamic>> extract({
    String? selector,
    String? prompt,
    int maxLength,
  });

  Future<Map<String, dynamic>> listLinks({
    String? filter,
    int maxItems,
  });

  Future<Map<String, dynamic>> listInteractables({
    String? filter,
    int maxItems,
  });

  Future<Map<String, dynamic>> highlight({
    required String selector,
  });

  Future<Map<String, dynamic>> captureSnapshot({
    String? selector,
    int maxLength,
  });

  Future<Map<String, dynamic>> eval({
    required String script,
  });
}

class BrowserActionLogEntry {
  final String action;
  final bool ok;
  final String message;
  final DateTime at;

  const BrowserActionLogEntry({
    required this.action,
    required this.ok,
    required this.message,
    required this.at,
  });
}

class BrowserAutomationService extends ChangeNotifier {
  BrowserAutomationService._();

  static final BrowserAutomationService instance = BrowserAutomationService._();

  static const _prefsTokenKey = 'browser_bridge_token';
  static const _envPath = '/root/.openclaw/browser-bridge.env';
  static const _host = '127.0.0.1';
  static const _port = 38927;
  static final _uuid = Uuid();

  HttpServer? _server;
  Future<void>? _starting;
  BrowserAutomationDelegate? _delegate;
  String _token = '';
  String _currentUrl = '';
  String _currentTitle = '';
  String _lastError = '';
  bool _loading = false;
  String _lastToolName = '';
  int _activeToolCalls = 0;
  DateTime? _lastToolCallAt;
  int _panelRequestNonce = 0;
  String _pendingOpenUrl = '';
  Completer<void>? _delegateReadyCompleter;
  final List<BrowserActionLogEntry> _recentActions = [];

  bool get isRunning => _server != null;
  bool get isBrowserAttached => _delegate != null;
  bool get isToolCallActive => _activeToolCalls > 0;
  String get lastToolName => _lastToolName;
  String get currentUrl => _currentUrl;
  String get currentTitle => _currentTitle;
  bool get loading => _loading;
  String get lastError => _lastError;
  String get bridgeUrl => 'http://$_host:$_port';
  String get sessionLabel => _delegate?.sessionLabel ?? '';
  int get panelRequestNonce => _panelRequestNonce;
  bool get hasPendingPanelRequest => _panelRequestNonce > 0;
  String get pendingOpenUrl => _pendingOpenUrl;
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
    if (changed) {
      notifyListeners();
    }
  }

  String takePendingOpenUrl() {
    final pending = _pendingOpenUrl;
    _pendingOpenUrl = '';
    return pending;
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
    if (action.isEmpty) {
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
    final result = await _invokeAction(action, payload);
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
    final delegate = await _ensureDelegateForAction(
      action: action,
      payload: payload,
    );
    if (delegate == null) {
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
      late Map<String, dynamic> state;
      switch (action) {
        case 'get_state':
          state = await delegate.getState();
          break;
        case 'open':
          state = await delegate.open(_string(payload['url']));
          break;
        case 'back':
          state = await delegate.back();
          break;
        case 'forward':
          state = await delegate.forward();
          break;
        case 'reload':
          state = await delegate.reload();
          break;
        case 'click':
          state = await delegate.click(
            selector: _string(payload['selector']),
          );
          break;
        case 'type':
          state = await delegate.type(
            selector: _string(payload['selector']),
            text: _string(payload['text']),
            submit: payload['submit'] == true,
          );
          break;
        case 'wait_for_text':
          state = await delegate.waitForText(
            text: _string(payload['text']),
            timeoutMs: _int(payload['timeoutMs'], fallback: 10000),
          );
          break;
        case 'extract':
          state = await delegate.extract(
            selector: _nullableString(payload['selector']),
            prompt: _nullableString(payload['prompt']),
            maxLength: _int(payload['maxLength'], fallback: 4000),
          );
          break;
        case 'list_links':
          state = await delegate.listLinks(
            filter: _nullableString(payload['filter']),
            maxItems: _int(payload['maxItems'], fallback: 12),
          );
          break;
        case 'list_interactables':
          state = await delegate.listInteractables(
            filter: _nullableString(payload['filter']),
            maxItems: _int(payload['maxItems'], fallback: 16),
          );
          break;
        case 'highlight':
          state = await delegate.highlight(
            selector: _string(payload['selector']),
          );
          break;
        case 'capture_snapshot':
          state = await delegate.captureSnapshot(
            selector: _nullableString(payload['selector']),
            maxLength: _int(payload['maxLength'], fallback: 8000),
          );
          break;
        case 'eval':
          state = await delegate.eval(
            script: _string(payload['script']),
          );
          break;
        default:
          return {
            'ok': false,
            'message': 'Unsupported browser action: $action',
            'state': _snapshot(),
          };
      }

      _mergeState(state);
      _recordAction(
        action: action,
        ok: state['ok'] != false,
        message: _stringOrFallback(
          state['message'],
          fallback: 'Browser action "$action" completed.',
        ),
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

  Future<BrowserAutomationDelegate?> _ensureDelegateForAction({
    required String action,
    required Map<String, dynamic> payload,
  }) async {
    final existing = _delegate;
    if (existing != null) {
      return existing;
    }

    final preferredUrl = action == 'open' ? _string(payload['url']) : '';
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
    final normalizedUrl = initialUrl.trim();
    if (normalizedUrl.isNotEmpty) {
      _pendingOpenUrl = normalizedUrl;
    }
    _panelRequestNonce += 1;
    notifyListeners();
  }

  void _mergeState(Map<String, dynamic> state) {
    final normalizedUrl = _nullableString(state['url']);
    final normalizedTitle = _nullableString(state['title']);
    final normalizedLoading = state['loading'] == true;
    final normalizedError = _nullableString(state['error']);
    if (normalizedUrl != null) {
      _currentUrl = normalizedUrl;
    }
    if (normalizedTitle != null) {
      _currentTitle = normalizedTitle;
    }
    _loading = normalizedLoading;
    if (normalizedError != null) {
      _lastError = normalizedError;
    }
  }

  Map<String, dynamic> _snapshot() {
    return {
      'bridgeUrl': bridgeUrl,
      'browserAttached': isBrowserAttached,
      'sessionLabel': sessionLabel,
      'url': _currentUrl,
      'title': _currentTitle,
      'loading': _loading,
      'lastError': _lastError,
      'activeToolCalls': _activeToolCalls,
      'lastToolName': _lastToolName,
      'lastToolCallAt': _lastToolCallAt?.toIso8601String(),
      'recentActions': [
        for (final entry in _recentActions)
          {
            'action': entry.action,
            'ok': entry.ok,
            'message': entry.message,
            'at': entry.at.toIso8601String(),
          },
      ],
    };
  }

  void _recordAction({
    required String action,
    required bool ok,
    required String message,
  }) {
    _recentActions.insert(
      0,
      BrowserActionLogEntry(
        action: action,
        ok: ok,
        message: message,
        at: DateTime.now().toUtc(),
      ),
    );
    if (_recentActions.length > 20) {
      _recentActions.removeRange(20, _recentActions.length);
    }
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
