import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../app.dart';
import '../services/browser_automation_service.dart';
import '../services/native_bridge.dart';
import '../services/preferences_service.dart';

class TerminalBrowserPanel extends StatefulWidget {
  final bool standalone;

  const TerminalBrowserPanel({
    super.key,
    this.standalone = false,
  });

  @override
  State<TerminalBrowserPanel> createState() => _TerminalBrowserPanelState();
}

class _TerminalBrowserPanelState extends State<TerminalBrowserPanel>
    implements BrowserAutomationDelegate {
  static const _welcomeHtml = '''
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
    <style>
      :root { color-scheme: dark; }
      html, body {
        margin: 0;
        padding: 0;
        background: #050505;
        color: #f5f5f5;
        font-family: sans-serif;
        min-height: 100%;
      }
      body {
        display: flex;
        align-items: center;
        justify-content: center;
      }
      .card {
        width: min(92vw, 520px);
        border: 1px solid rgba(255,255,255,0.08);
        border-radius: 18px;
        background: linear-gradient(180deg, #101010 0%, #070707 100%);
        padding: 24px;
        box-sizing: border-box;
      }
      h1 { margin: 0 0 12px; font-size: 24px; }
      p { margin: 0 0 12px; line-height: 1.6; color: #d4d4d4; }
      code {
        display: inline-block;
        padding: 2px 8px;
        border-radius: 999px;
        background: rgba(255,255,255,0.08);
      }
    </style>
  </head>
  <body>
    <div class="card">
      <h1>OpenClaw Browser Panel</h1>
      <p>在这里打开网页后，Codex 就可以通过浏览器工具执行打开、点击、输入、提取页面内容等操作。</p>
      <p>建议在终端里明确说明目标网址，并提示 Codex 使用 <code>browser-operator</code> 技能。</p>
    </div>
  </body>
</html>
''';

  final _service = BrowserAutomationService.instance;
  final _urlController = TextEditingController();
  late final WebViewController _controller;

  String _title = 'Browser';
  String _currentUrl = '';
  String _error = '';
  bool _loading = true;
  bool _canGoBack = false;
  bool _canGoForward = false;
  Completer<void>? _navigationCompleter;
  bool _showInspector = false;
  bool _inspectorLoading = false;
  String _inspectorError = '';
  String _inspectorMode = 'interactables';
  List<Map<String, dynamic>> _inspectorItems = const [];

  @override
  String get sessionLabel => widget.standalone ? 'terminal-browser-page' : 'terminal-browser-sidecar';

  @override
  void initState() {
    super.initState();
    _controller = _createController();
    _service.bindDelegate(this);
    unawaited(_service.ensureStarted());
    unawaited(_initializeBrowser());
  }

  @override
  void dispose() {
    _service.unbindDelegate(this);
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _initializeBrowser() async {
    final pendingUrl = _service.takePendingOpenUrl().trim();
    if (pendingUrl.isNotEmpty) {
      await _loadUrl(pendingUrl);
      return;
    }
    final prefs = PreferencesService();
    await prefs.init();
    final initialUrl = prefs.dashboardUrl?.trim() ?? '';
    if (initialUrl.isNotEmpty) {
      await _loadUrl(initialUrl);
      return;
    }
    await _controller.loadHtmlString(_welcomeHtml);
  }

  WebViewController _createController() {
    const params = PlatformWebViewControllerCreationParams();
    final controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(true)
      ..setBackgroundColor(Colors.black)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (_navigationCompleter == null ||
                _navigationCompleter!.isCompleted) {
              _navigationCompleter = Completer<void>();
            }
            _service.updateObservedState(
              url: url,
              loading: true,
              error: '',
            );
            if (!mounted) {
              return;
            }
            setState(() {
              _loading = true;
              _currentUrl = url;
              _urlController.text = url;
              _error = '';
            });
          },
          onPageFinished: (url) {
            _completePendingNavigation();
            unawaited(_refreshNavigationState());
            if (_showInspector) {
              unawaited(_refreshInspectorCurrentMode());
            }
            _service.updateObservedState(
              url: url,
              title: _title,
              loading: false,
              error: '',
            );
            if (!mounted) {
              return;
            }
            setState(() {
              _loading = false;
              _currentUrl = url;
              _urlController.text = url;
            });
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == false) {
              return;
            }
            _completePendingNavigation();
            _service.updateObservedState(
              loading: false,
              error: error.description.trim(),
            );
            if (!mounted) {
              return;
            }
            setState(() {
              _loading = false;
              _error = error.description.trim();
            });
          },
        ),
      );

    final platformController = controller.platform;
    if (platformController is AndroidWebViewController) {
      unawaited(platformController.setUseWideViewPort(true));
      unawaited(
        platformController.setMixedContentMode(MixedContentMode.alwaysAllow),
      );
      unawaited(platformController.setVerticalScrollBarEnabled(true));
      unawaited(platformController.setHorizontalScrollBarEnabled(true));
    }

    return controller;
  }

  Future<void> _refreshNavigationState() async {
    try {
      final title = await _controller.getTitle() ?? 'Browser';
      final canGoBack = await _controller.canGoBack();
      final canGoForward = await _controller.canGoForward();
      if (!mounted) {
        return;
      }
      setState(() {
        _title = title.trim().isEmpty ? 'Browser' : title.trim();
        _canGoBack = canGoBack;
        _canGoForward = canGoForward;
      });
      _service.updateObservedState(
        title: _title,
        url: _currentUrl,
        loading: _loading,
        error: _error,
      );
    } catch (_) {}
  }

  Future<void> _submitAddress() async {
    final text = _urlController.text.trim();
    if (text.isEmpty) {
      return;
    }
    await _loadUrl(text);
  }

  Future<void> _loadUrl(String rawUrl) async {
    final url = _normalizeUrl(rawUrl);
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      setState(() {
        _error = 'Invalid URL';
      });
      return;
    }

    _error = '';
    _navigationCompleter = Completer<void>();
    await _controller.loadRequest(uri);
    await _awaitNavigationCompletion();
    await _refreshNavigationState();
  }

  String _normalizeUrl(String value) {
    final text = value.trim();
    if (text.isEmpty) {
      return text;
    }
    final uri = Uri.tryParse(text);
    if (uri != null && uri.hasScheme) {
      return text;
    }
    if (text.startsWith('localhost') || text.startsWith('127.0.0.1')) {
      return 'http://$text';
    }
    return 'https://$text';
  }

  Future<void> _awaitNavigationCompletion() async {
    final completer = _navigationCompleter;
    if (completer == null) {
      return;
    }
    await completer.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () {},
    );
  }

  void _completePendingNavigation() {
    final completer = _navigationCompleter;
    if (completer == null || completer.isCompleted) {
      return;
    }
    completer.complete();
  }

  Future<String?> _runStringJs(String script) async {
    try {
      final raw = await _controller.runJavaScriptReturningResult(script);
      return _normalizeJavaScriptStringResult(raw);
    } catch (_) {
      return null;
    }
  }

  String? _normalizeJavaScriptStringResult(Object raw) {
    final text = raw.toString().trim();
    if (text.isEmpty || text == 'null' || text == 'undefined') {
      return null;
    }
    if ((text.startsWith('"') && text.endsWith('"')) ||
        (text.startsWith("'") && text.endsWith("'"))) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is String) {
          return decoded;
        }
      } catch (_) {}
    }
    return text;
  }

  Future<Map<String, dynamic>> _pageSnapshot({
    bool ok = true,
    String message = '',
    Map<String, dynamic>? extra,
  }) async {
    await _refreshNavigationState();
    return {
      'ok': ok,
      'message': message,
      'url': _currentUrl,
      'title': _title,
      'loading': _loading,
      'error': _error,
      'canGoBack': _canGoBack,
      'canGoForward': _canGoForward,
      if (extra != null) ...extra,
    };
  }

  @override
  Future<Map<String, dynamic>> getState() {
    return _pageSnapshot(
      message: 'Browser state loaded.',
    );
  }

  @override
  Future<Map<String, dynamic>> open(String url) async {
    if (url.trim().isEmpty) {
      return _pageSnapshot(
        ok: false,
        message: 'The url argument cannot be empty.',
      );
    }
    await _loadUrl(url);
    return _pageSnapshot(
      ok: _error.isEmpty,
      message: _error.isEmpty ? 'Opened $url' : _error,
    );
  }

  @override
  Future<Map<String, dynamic>> back() async {
    final canGoBack = await _controller.canGoBack();
    if (!canGoBack) {
      return _pageSnapshot(
        ok: false,
        message: 'The browser cannot go back from the current page.',
      );
    }
    _navigationCompleter = Completer<void>();
    await _controller.goBack();
    await _awaitNavigationCompletion();
    return _pageSnapshot(message: 'Navigated back.');
  }

  @override
  Future<Map<String, dynamic>> forward() async {
    final canGoForward = await _controller.canGoForward();
    if (!canGoForward) {
      return _pageSnapshot(
        ok: false,
        message: 'The browser cannot go forward from the current page.',
      );
    }
    _navigationCompleter = Completer<void>();
    await _controller.goForward();
    await _awaitNavigationCompletion();
    return _pageSnapshot(message: 'Navigated forward.');
  }

  @override
  Future<Map<String, dynamic>> reload() async {
    _navigationCompleter = Completer<void>();
    await _controller.reload();
    await _awaitNavigationCompletion();
    return _pageSnapshot(message: 'Page reloaded.');
  }

  @override
  Future<Map<String, dynamic>> click({
    required String selector,
  }) async {
    if (selector.trim().isEmpty) {
      return _pageSnapshot(
        ok: false,
        message: 'The selector argument cannot be empty.',
      );
    }
    final script = '''
(() => {
  const selector = ${jsonEncode(selector)};
  const element = document.querySelector(selector);
  if (!element) {
    return JSON.stringify({ ok: false, message: `Selector not found: \${selector}` });
  }
  element.scrollIntoView({ behavior: 'instant', block: 'center', inline: 'center' });
  if (typeof element.focus === 'function') {
    element.focus();
  }
  element.click();
  return JSON.stringify({
    ok: true,
    tag: element.tagName || '',
    text: (element.innerText || element.textContent || element.value || '').trim().slice(0, 240)
  });
})();
''';
    final raw = await _runStringJs(script);
    if (raw == null) {
      return _pageSnapshot(
        ok: false,
        message: 'Failed to run the click action in WebView.',
      );
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return _pageSnapshot(
      ok: decoded['ok'] != false,
      message: decoded['message']?.toString() ?? 'Click completed.',
      extra: {'actionResult': decoded},
    );
  }

  @override
  Future<Map<String, dynamic>> type({
    required String selector,
    required String text,
    bool submit = false,
  }) async {
    if (selector.trim().isEmpty) {
      return _pageSnapshot(
        ok: false,
        message: 'The selector argument cannot be empty.',
      );
    }
    final script = '''
(() => {
  const selector = ${jsonEncode(selector)};
  const value = ${jsonEncode(text)};
  const shouldSubmit = ${submit ? 'true' : 'false'};
  const element = document.querySelector(selector);
  if (!element) {
    return JSON.stringify({ ok: false, message: `Selector not found: \${selector}` });
  }

  element.scrollIntoView({ behavior: 'instant', block: 'center', inline: 'center' });
  if (typeof element.focus === 'function') {
    element.focus();
  }

  if ('value' in element) {
    element.value = value;
  } else if (element.isContentEditable) {
    element.textContent = value;
  } else {
    return JSON.stringify({ ok: false, message: 'Target element is not editable.' });
  }

  element.dispatchEvent(new Event('input', { bubbles: true }));
  element.dispatchEvent(new Event('change', { bubbles: true }));

  if (shouldSubmit) {
    const form = element.form || element.closest('form');
    if (form && typeof form.requestSubmit === 'function') {
      form.requestSubmit();
    } else {
      element.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', bubbles: true }));
      element.dispatchEvent(new KeyboardEvent('keyup', { key: 'Enter', code: 'Enter', bubbles: true }));
    }
  }

  return JSON.stringify({
    ok: true,
    message: shouldSubmit ? 'Text entered and submitted.' : 'Text entered.',
    tag: element.tagName || ''
  });
})();
''';
    final raw = await _runStringJs(script);
    if (raw == null) {
      return _pageSnapshot(
        ok: false,
        message: 'Failed to run the type action in WebView.',
      );
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return _pageSnapshot(
      ok: decoded['ok'] != false,
      message: decoded['message']?.toString() ?? 'Text entered.',
      extra: {'actionResult': decoded},
    );
  }

  @override
  Future<Map<String, dynamic>> waitForText({
    required String text,
    int timeoutMs = 10000,
  }) async {
    if (text.trim().isEmpty) {
      return _pageSnapshot(
        ok: false,
        message: 'The text argument cannot be empty.',
      );
    }
    final deadline = DateTime.now().millisecondsSinceEpoch + timeoutMs;
    while (DateTime.now().millisecondsSinceEpoch < deadline) {
      final script = '''
(() => {
  const needle = ${jsonEncode(text)};
  const bodyText = (document.body?.innerText || '').trim();
  return JSON.stringify({
    ok: bodyText.includes(needle),
    textLength: bodyText.length
  });
})();
''';
      final raw = await _runStringJs(script);
      if (raw != null) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded['ok'] == true) {
          return _pageSnapshot(
            message: 'Found the requested text on the page.',
            extra: {'actionResult': decoded},
          );
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 350));
    }
    return _pageSnapshot(
      ok: false,
      message: 'Timed out while waiting for the requested text.',
    );
  }

  @override
  Future<Map<String, dynamic>> extract({
    String? selector,
    String? prompt,
    int maxLength = 4000,
  }) async {
    final safeMaxLength = maxLength.clamp(256, 16000);
    final script = '''
(() => {
  const selector = ${jsonEncode(selector?.trim() ?? '')};
  const prompt = ${jsonEncode(prompt?.trim() ?? '')};
  const maxLength = $safeMaxLength;
  const target = selector ? document.querySelector(selector) : document.body;
  if (!target) {
    return JSON.stringify({ ok: false, message: `Selector not found: \${selector}` });
  }
  const text = (target.innerText || target.textContent || '').trim().slice(0, maxLength);
  const html = (target.innerHTML || '').trim().slice(0, maxLength);
  return JSON.stringify({
    ok: true,
    selector: selector || null,
    prompt: prompt || null,
    text,
    html,
    tag: target.tagName || 'BODY',
    links: Array.from(target.querySelectorAll('a[href]'))
      .slice(0, 12)
      .map((item) => ({
        href: item.href || '',
        text: (item.innerText || item.textContent || '').trim().slice(0, 160)
      }))
  });
})();
''';
    final raw = await _runStringJs(script);
    if (raw == null) {
      return _pageSnapshot(
        ok: false,
        message: 'Failed to extract content from the current page.',
      );
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return _pageSnapshot(
      ok: decoded['ok'] != false,
      message: decoded['message']?.toString() ?? 'Page content extracted.',
      extra: {'actionResult': decoded},
    );
  }

  @override
  Future<Map<String, dynamic>> listLinks({
    String? filter,
    int maxItems = 12,
  }) async {
    final safeMaxItems = maxItems.clamp(1, 40);
    final script = '''
(() => {
  const filter = ${jsonEncode(filter?.trim().toLowerCase() ?? '')};
  const maxItems = $safeMaxItems;
  const links = Array.from(document.querySelectorAll('a[href]'))
    .map((item, index) => {
      const text = (item.innerText || item.textContent || '').trim().slice(0, 160);
      const href = item.href || '';
      const aria = (item.getAttribute('aria-label') || '').trim();
      return { index, text, href, aria };
    })
    .filter((item) => {
      if (!filter) return true;
      const haystack = `\${item.text} \${item.href} \${item.aria}`.toLowerCase();
      return haystack.includes(filter);
    })
    .slice(0, maxItems);
  return JSON.stringify({ ok: true, count: links.length, items: links });
})();
''';
    final raw = await _runStringJs(script);
    if (raw == null) {
      return _pageSnapshot(
        ok: false,
        message: 'Failed to list links from the current page.',
      );
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return _pageSnapshot(
      ok: decoded['ok'] != false,
      message: 'Link list extracted.',
      extra: {'actionResult': decoded},
    );
  }

  @override
  Future<Map<String, dynamic>> listInteractables({
    String? filter,
    int maxItems = 16,
  }) async {
    final safeMaxItems = maxItems.clamp(1, 60);
    final script = '''
(() => {
  const filter = ${jsonEncode(filter?.trim().toLowerCase() ?? '')};
  const maxItems = $safeMaxItems;
  const cssEscape = (value) => {
    if (window.CSS && typeof window.CSS.escape === 'function') {
      return window.CSS.escape(value);
    }
    return String(value).replace(/["\\\\]/g, (match) => '\\\\' + match);
  };
  const selectorFor = (el) => {
    if (el.id) return `#\${cssEscape(el.id)}`;
    const dataTestId = el.getAttribute('data-testid');
    if (dataTestId) return `[data-testid="\${cssEscape(dataTestId)}"]`;
    const name = el.getAttribute('name');
    if (name) return `\${el.tagName.toLowerCase()}[name="\${cssEscape(name)}"]`;
    const aria = el.getAttribute('aria-label');
    if (aria) return `\${el.tagName.toLowerCase()}[aria-label="\${cssEscape(aria)}"]`;
    const classes = Array.from(el.classList || []).filter(Boolean).slice(0, 2);
    if (classes.length > 0) {
      return `\${el.tagName.toLowerCase()}.\${classes.map(cssEscape).join('.')}`;
    }
    return el.tagName.toLowerCase();
  };
  const isVisible = (el) => {
    const rect = el.getBoundingClientRect();
    const style = window.getComputedStyle(el);
    return rect.width > 0 && rect.height > 0 && style.visibility !== 'hidden' && style.display !== 'none';
  };
  const items = Array.from(document.querySelectorAll('a,button,input,textarea,select,[role="button"],[contenteditable="true"]'))
    .filter(isVisible)
    .map((el, index) => {
      const text = (el.innerText || el.textContent || el.value || '').trim().slice(0, 160);
      const aria = (el.getAttribute('aria-label') || '').trim();
      const placeholder = (el.getAttribute('placeholder') || '').trim();
      const role = (el.getAttribute('role') || '').trim();
      const type = (el.getAttribute('type') || '').trim();
      return {
        index,
        tag: el.tagName.toLowerCase(),
        role,
        type,
        text,
        aria,
        placeholder,
        selector: selectorFor(el)
      };
    })
    .filter((item) => {
      if (!filter) return true;
      const haystack = `\${item.tag} \${item.role} \${item.type} \${item.text} \${item.aria} \${item.placeholder} \${item.selector}`.toLowerCase();
      return haystack.includes(filter);
    })
    .slice(0, maxItems);
  return JSON.stringify({ ok: true, count: items.length, items });
})();
''';
    final raw = await _runStringJs(script);
    if (raw == null) {
      return _pageSnapshot(
        ok: false,
        message: 'Failed to inspect interactable elements on the current page.',
      );
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return _pageSnapshot(
      ok: decoded['ok'] != false,
      message: 'Interactable elements extracted.',
      extra: {'actionResult': decoded},
    );
  }

  @override
  Future<Map<String, dynamic>> highlight({
    required String selector,
  }) async {
    if (selector.trim().isEmpty) {
      return _pageSnapshot(
        ok: false,
        message: 'The selector argument cannot be empty.',
      );
    }
    final script = '''
(() => {
  const selector = ${jsonEncode(selector)};
  const element = document.querySelector(selector);
  if (!element) {
    return JSON.stringify({ ok: false, message: `Selector not found: \${selector}` });
  }
  const previousOutline = element.style.outline || '';
  const previousOffset = element.style.outlineOffset || '';
  const previousTransition = element.style.transition || '';
  element.scrollIntoView({ behavior: 'instant', block: 'center', inline: 'center' });
  element.style.transition = 'outline 120ms ease';
  element.style.outline = '3px solid #dc2626';
  element.style.outlineOffset = '2px';
  setTimeout(() => {
    element.style.outline = previousOutline;
    element.style.outlineOffset = previousOffset;
    element.style.transition = previousTransition;
  }, 2200);
  return JSON.stringify({
    ok: true,
    message: 'Element highlighted.',
    tag: element.tagName || '',
    text: (element.innerText || element.textContent || element.value || '').trim().slice(0, 200)
  });
})();
''';
    final raw = await _runStringJs(script);
    if (raw == null) {
      return _pageSnapshot(
        ok: false,
        message: 'Failed to highlight the selected element.',
      );
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return _pageSnapshot(
      ok: decoded['ok'] != false,
      message: decoded['message']?.toString() ?? 'Element highlighted.',
      extra: {'actionResult': decoded},
    );
  }

  @override
  Future<Map<String, dynamic>> captureSnapshot({
    String? selector,
    int maxLength = 8000,
  }) async {
    final safeMaxLength = maxLength.clamp(512, 32000);
    final script = '''
(() => {
  const selector = ${jsonEncode(selector?.trim() ?? '')};
  const maxLength = $safeMaxLength;
  const target = selector ? document.querySelector(selector) : document.body;
  if (!target) {
    return JSON.stringify({ ok: false, message: `Selector not found: \${selector}` });
  }
  const text = (target.innerText || target.textContent || '').trim().slice(0, maxLength);
  const html = (target.innerHTML || '').trim().slice(0, maxLength);
  const links = Array.from(target.querySelectorAll('a[href]'))
    .slice(0, 20)
    .map((item) => ({
      href: item.href || '',
      text: (item.innerText || item.textContent || '').trim().slice(0, 160)
    }));
  return JSON.stringify({
    ok: true,
    title: document.title || '',
    url: location.href || '',
    selector: selector || null,
    text,
    html,
    links
  });
})();
''';
    final raw = await _runStringJs(script);
    if (raw == null) {
      return _pageSnapshot(
        ok: false,
        message: 'Failed to capture a browser snapshot.',
      );
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return _pageSnapshot(
      ok: decoded['ok'] != false,
      message: decoded['message']?.toString() ?? 'Snapshot captured.',
      extra: {'actionResult': decoded},
    );
  }

  @override
  Future<Map<String, dynamic>> eval({
    required String script,
  }) async {
    if (script.trim().isEmpty) {
      return _pageSnapshot(
        ok: false,
        message: 'The script argument cannot be empty.',
      );
    }
    final raw = await _runStringJs('''
(() => {
  const result = (() => {
    $script
  })();
  return JSON.stringify({
    ok: true,
    result
  });
})();
''');
    if (raw == null) {
      return _pageSnapshot(
        ok: false,
        message: 'The provided script returned no serializable value.',
      );
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return _pageSnapshot(
      ok: decoded['ok'] != false,
      message: 'Script executed.',
      extra: {'actionResult': decoded},
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedBuilder(
      animation: _service,
      builder: (context, _) {
        return DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border(
              left: BorderSide(
                color: Colors.white.withAlpha(18),
              ),
            ),
          ),
          child: Column(
            children: [
              _buildHeader(theme),
              _buildRecentActionsStrip(theme),
              _buildInspectorStrip(theme),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(child: _buildWebView()),
                    if (_loading)
                      const Positioned(
                        top: 16,
                        right: 16,
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    if (_service.isToolCallActive)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: _buildStatusChip(
                          icon: Icons.auto_awesome,
                          text: 'Codex 正在操作浏览器: ${_service.lastToolName}',
                          color: AppColors.accent,
                        ),
                      ),
                    if (_error.isNotEmpty)
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: _service.isToolCallActive ? 60 : 12,
                        child: _buildStatusChip(
                          icon: Icons.error_outline,
                          text: _error,
                          color: AppColors.statusRed,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _handleBackButton() async {
    await back();
  }

  Future<void> _handleForwardButton() async {
    await forward();
  }

  Future<void> _handleReloadButton() async {
    await reload();
  }

  Future<void> _exportSnapshot() async {
    final result = await captureSnapshot(maxLength: 12000);
    final actionResult = result['actionResult'];
    if (actionResult is! Map<String, dynamic>) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to capture browser snapshot')),
      );
      return;
    }
    final title = (actionResult['title']?.toString().trim().isNotEmpty ?? false)
        ? actionResult['title'].toString().trim()
        : 'browser-page';
    final safeTitle = title.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
    final content = const JsonEncoder.withIndent('  ').convert({
      'title': actionResult['title'],
      'url': actionResult['url'],
      'selector': actionResult['selector'],
      'capturedAt': DateTime.now().toIso8601String(),
      'text': actionResult['text'],
      'html': actionResult['html'],
      'links': actionResult['links'],
    });
    final saved = await NativeBridge.saveSnapshotFile(
      suggestedName: 'browser-$safeTitle.json',
      content: content,
    );
    if (!mounted) {
      return;
    }
    final path = saved?['path']?.toString().trim() ?? '';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          path.isNotEmpty ? 'Snapshot saved: $path' : 'Snapshot export finished',
        ),
      ),
    );
  }

  Future<void> _copyText(String text, String label) async {
    if (text.trim().isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$label copied')),
    );
  }

  Future<void> _refreshInspectorCurrentMode() async {
    if (_inspectorMode == 'links') {
      await _loadLinksInspector();
      return;
    }
    await _loadInteractablesInspector();
  }

  Future<void> _loadInteractablesInspector() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _inspectorLoading = true;
      _inspectorError = '';
      _inspectorMode = 'interactables';
    });
    try {
      final result = await listInteractables(maxItems: 24);
      final actionResult = result['actionResult'];
      final items = actionResult is Map<String, dynamic>
          ? actionResult['items']
          : null;
      setState(() {
        _inspectorItems = items is List
            ? items
                .whereType<Map>()
                .map((item) => item.map(
                      (key, value) => MapEntry(key.toString(), value),
                    ))
                .toList()
            : const [];
      });
    } catch (error) {
      _inspectorError = error.toString();
    } finally {
      if (mounted) {
        setState(() {
          _inspectorLoading = false;
        });
      }
    }
  }

  Future<void> _loadLinksInspector() async {
    if (!mounted) {
      return;
    }
    setState(() {
      _inspectorLoading = true;
      _inspectorError = '';
      _inspectorMode = 'links';
    });
    try {
      final result = await listLinks(maxItems: 20);
      final actionResult = result['actionResult'];
      final items = actionResult is Map<String, dynamic>
          ? actionResult['items']
          : null;
      setState(() {
        _inspectorItems = items is List
            ? items
                .whereType<Map>()
                .map((item) => item.map(
                      (key, value) => MapEntry(key.toString(), value),
                    ))
                .toList()
            : const [];
      });
    } catch (error) {
      _inspectorError = error.toString();
    } finally {
      if (mounted) {
        setState(() {
          _inspectorLoading = false;
        });
      }
    }
  }

  Widget _buildRecentActionsStrip(ThemeData theme) {
    return AnimatedBuilder(
      animation: _service,
      builder: (context, _) {
        final actions = _service.recentActions.take(3).toList();
        if (actions.isEmpty) {
          return const SizedBox.shrink();
        }
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: const Color(0xFF050505),
            border: Border(
              bottom: BorderSide(color: Colors.white.withAlpha(14)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Recent browser actions',
                style: theme.textTheme.labelMedium?.copyWith(
                  color: Colors.white70,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              for (final action in actions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        action.ok ? Icons.check_circle_outline : Icons.error_outline,
                        size: 14,
                        color: action.ok
                            ? AppColors.statusGreen
                            : AppColors.statusRed,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '${action.action}: ${action.message}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.white60,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInspectorStrip(ThemeData theme) {
    final visible =
        _showInspector || _inspectorLoading || _inspectorItems.isNotEmpty;
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFF070707),
        border: Border(
          bottom: BorderSide(color: Colors.white.withAlpha(14)),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            child: Row(
              children: [
                Icon(
                  Icons.tune,
                  size: 16,
                  color: _showInspector ? AppColors.accent : Colors.white70,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Browser inspector',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    setState(() {
                      _showInspector = !_showInspector;
                    });
                    if (_showInspector && _inspectorItems.isEmpty) {
                      unawaited(_refreshInspectorCurrentMode());
                    }
                  },
                  child: Text(_showInspector ? 'Hide' : 'Show'),
                ),
              ],
            ),
          ),
          if (_showInspector)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _inspectorLoading
                              ? null
                              : () => unawaited(_loadInteractablesInspector()),
                          icon: const Icon(Icons.ads_click_outlined, size: 16),
                          label: const Text('Elements'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _inspectorLoading
                              ? null
                              : () => unawaited(_loadLinksInspector()),
                          icon: const Icon(Icons.link, size: 16),
                          label: const Text('Links'),
                        ),
                      ),
                    ],
                  ),
                  if (_inspectorLoading)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: LinearProgressIndicator(minHeight: 2),
                    ),
                  if (_inspectorError.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          _inspectorError,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: AppColors.statusRed,
                          ),
                        ),
                      ),
                    ),
                  if (visible)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 220),
                        child: _buildInspectorList(theme),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInspectorList(ThemeData theme) {
    if (_inspectorItems.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withAlpha(14)),
        ),
        child: Text(
          _inspectorMode == 'links'
              ? 'No visible links were found on the current page.'
              : 'No visible interactable elements were found on the current page.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: Colors.white60,
          ),
        ),
      );
    }

    return ListView.separated(
      shrinkWrap: true,
      itemCount: _inspectorItems.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final item = _inspectorItems[index];
        return _inspectorMode == 'links'
            ? _buildLinkInspectorCard(theme, item)
            : _buildInteractableInspectorCard(theme, item);
      },
    );
  }

  Widget _buildLinkInspectorCard(ThemeData theme, Map<String, dynamic> item) {
    final text = (item['text']?.toString().trim().isNotEmpty ?? false)
        ? item['text'].toString().trim()
        : '(no link text)';
    final href = item['href']?.toString().trim() ?? '';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            href,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white60,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: href.isEmpty
                    ? null
                    : () => unawaited(_copyText(href, 'Link URL')),
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: href.isEmpty ? null : () => unawaited(open(href)),
                icon: const Icon(Icons.open_in_browser, size: 16),
                label: const Text('Open'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInteractableInspectorCard(
    ThemeData theme,
    Map<String, dynamic> item,
  ) {
    final selector = item['selector']?.toString().trim() ?? '';
    final text = (item['text']?.toString().trim().isNotEmpty ?? false)
        ? item['text'].toString().trim()
        : (item['aria']?.toString().trim().isNotEmpty ?? false)
            ? item['aria'].toString().trim()
            : item['tag']?.toString().trim() ?? 'element';
    final metaParts = [
      item['tag']?.toString().trim() ?? '',
      item['role']?.toString().trim() ?? '',
      item['type']?.toString().trim() ?? '',
      item['placeholder']?.toString().trim() ?? '',
    ].where((part) => part.isNotEmpty).toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withAlpha(14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (metaParts.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              metaParts.join(' · '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: Colors.white60,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            selector,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFFFBBF24),
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton.icon(
                onPressed: selector.isEmpty
                    ? null
                    : () => unawaited(_copyText(selector, 'Selector')),
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Copy'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: selector.isEmpty
                    ? null
                    : () => unawaited(highlight(selector: selector)),
                icon: const Icon(Icons.highlight_alt, size: 16),
                label: const Text('Mark'),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: selector.isEmpty
                    ? null
                    : () => unawaited(click(selector: selector)),
                icon: const Icon(Icons.ads_click, size: 16),
                label: const Text('Click'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return ColoredBox(
      color: const Color(0xFF090909),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.language, color: Colors.white, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildActionIcon(
                    icon: Icons.arrow_back,
                    enabled: _canGoBack,
                    onTap: _canGoBack ? () => unawaited(_handleBackButton()) : null,
                  ),
                  _buildActionIcon(
                    icon: Icons.arrow_forward,
                    enabled: _canGoForward,
                    onTap:
                        _canGoForward ? () => unawaited(_handleForwardButton()) : null,
                  ),
                  _buildActionIcon(
                    icon: Icons.refresh,
                    onTap: () => unawaited(_handleReloadButton()),
                  ),
                  _buildActionIcon(
                    icon: Icons.download_rounded,
                    onTap: () => unawaited(_exportSnapshot()),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _urlController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      cursorColor: Colors.white,
                      textInputAction: TextInputAction.go,
                      onSubmitted: (_) => unawaited(_submitAddress()),
                      decoration: InputDecoration(
                        isDense: true,
                        filled: true,
                        fillColor: Colors.white.withAlpha(8),
                        hintText: 'Enter URL',
                        hintStyle: const TextStyle(color: Colors.white54),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.white.withAlpha(22),
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: Colors.white.withAlpha(18),
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: AppColors.accent),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => unawaited(_submitAddress()),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      backgroundColor: AppColors.accent,
                    ),
                    child: const Text('Open'),
                  ),
                ],
              ),
              if (_currentUrl.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  _currentUrl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.white60,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildWebView() {
    final platformController = _controller.platform;
    if (platformController is AndroidWebViewController) {
      final params = AndroidWebViewWidgetCreationParams(
        controller: platformController,
        displayWithHybridComposition: true,
      );
      return WebViewWidget.fromPlatformCreationParams(params: params);
    }
    return WebViewWidget(controller: _controller);
  }

  Widget _buildActionIcon({
    required IconData icon,
    required VoidCallback? onTap,
    bool enabled = true,
  }) {
    return IconButton(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 18),
      color: enabled ? Colors.white : Colors.white24,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: Colors.white.withAlpha(10),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: BorderSide(color: Colors.white.withAlpha(14)),
        ),
      ),
    );
  }

  Widget _buildStatusChip({
    required IconData icon,
    required String text,
    required Color color,
  }) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withAlpha(210),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withAlpha(160)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
