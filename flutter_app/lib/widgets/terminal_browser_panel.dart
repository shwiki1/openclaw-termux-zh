import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../app.dart';
import '../services/browser_automation_service.dart';
import '../services/browser_script_library_service.dart';
import '../services/browser_user_script_library_service.dart';
import '../services/native_bridge.dart';

class TerminalBrowserPanel extends StatefulWidget {
  final bool standalone;
  final bool visible;
  final VoidCallback? onClose;

  const TerminalBrowserPanel({
    super.key,
    this.standalone = false,
    this.visible = true,
    this.onClose,
  });

  @override
  State<TerminalBrowserPanel> createState() => _TerminalBrowserPanelState();
}

enum _BrowserUserAgentMode {
  desktop,
  mobile,
}

ThemeData _browserButtonTheme(ThemeData baseTheme) {
  return baseTheme.copyWith(
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white38,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white38,
        side: const BorderSide(color: Color(0x66FFFFFF)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: const Color(0xFFFFD0CC),
        disabledForegroundColor: Colors.white38,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: Colors.white,
        disabledForegroundColor: Colors.white38,
      ),
    ),
  );
}

extension _BrowserUserAgentModeInfo on _BrowserUserAgentMode {
  String get label {
    switch (this) {
      case _BrowserUserAgentMode.desktop:
        return '电脑';
      case _BrowserUserAgentMode.mobile:
        return '手机';
    }
  }

  String get value {
    switch (this) {
      case _BrowserUserAgentMode.desktop:
        return 'desktop';
      case _BrowserUserAgentMode.mobile:
        return 'mobile';
    }
  }

  IconData get icon {
    switch (this) {
      case _BrowserUserAgentMode.desktop:
        return Icons.desktop_windows_outlined;
      case _BrowserUserAgentMode.mobile:
        return Icons.phone_android;
    }
  }

  String get userAgent {
    switch (this) {
      case _BrowserUserAgentMode.desktop:
        return _TerminalBrowserPanelState._desktopUserAgent;
      case _BrowserUserAgentMode.mobile:
        return _TerminalBrowserPanelState._mobileUserAgent;
    }
  }
}

enum _BrowserMenuAction {
  scripts,
  snapshot,
  inspector,
  recentActions,
}

class _BrowserTab {
  final int id;
  late final WebViewController controller;
  _BrowserUserAgentMode userAgentMode;
  String title;
  String currentUrl;
  String error;
  bool loading;
  bool canGoBack;
  bool canGoForward;
  bool pageInputFocused;
  Completer<void>? navigationCompleter;

  _BrowserTab({
    required this.id,
    this.userAgentMode = _BrowserUserAgentMode.mobile,
    this.title = 'Browser',
    this.currentUrl = '',
    this.error = '',
    this.loading = true,
    this.canGoBack = false,
    this.canGoForward = false,
    this.pageInputFocused = false,
  });

  Map<String, dynamic> toJson({required bool active}) {
    return {
      'id': id,
      'active': active,
      'title': title,
      'url': currentUrl,
      'loading': loading,
      'error': error,
      'canGoBack': canGoBack,
      'canGoForward': canGoForward,
      'userAgentMode': userAgentMode.value,
      'userAgentLabel': userAgentMode.label,
    };
  }
}

class _TerminalBrowserPanelState extends State<TerminalBrowserPanel>
    implements BrowserAutomationDelegate {
  static const _desktopUserAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36';
  static const _mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
  static const _panelHeaderBg = Color(0xFF090909);
  static const _panelSurface = Color(0xFF121212);
  static const _panelSurfaceAlt = Color(0xFF171717);
  static const _panelBorder = Color(0x30FFFFFF);
  static const _panelText = Color(0xFFF5F5F5);
  static const _panelMutedText = Color(0xFFCACACA);
  static const _panelDisabledText = Color(0xFF8A8A8A);
  static const _keyboardFocusChannelName = 'OpenClawImeFocus';

  static const _welcomeHtml = '''
<!doctype html>
<html lang="zh-CN">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0, viewport-fit=cover">
    <title>Codex 浏览器自动化控制</title>
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
        box-sizing: border-box;
        padding: 18px;
      }
      main {
        width: min(92vw, 520px);
        margin: 0 auto;
      }
      .panel {
        border: 1px solid rgba(255,255,255,0.08);
        border-radius: 8px;
        background: linear-gradient(180deg, #101010 0%, #070707 100%);
        padding: 18px;
        box-sizing: border-box;
      }
      h1 { margin: 0 0 8px; font-size: 21px; line-height: 1.25; }
      h2 { margin: 20px 0 8px; font-size: 14px; color: #ffffff; }
      p, li { line-height: 1.6; color: #d4d4d4; font-size: 14px; }
      p { margin: 0 0 12px; }
      ul { margin: 0; padding-left: 18px; }
      code {
        display: inline-block;
        max-width: 100%;
        padding: 2px 7px;
        border-radius: 999px;
        background: rgba(255,255,255,0.08);
        color: #ffffff;
        overflow-wrap: anywhere;
      }
      .status {
        display: inline-flex;
        align-items: center;
        gap: 6px;
        margin: 0 0 14px;
        padding: 5px 9px;
        border: 1px solid rgba(34,197,94,0.42);
        border-radius: 999px;
        color: #bbf7d0;
        background: rgba(34,197,94,0.1);
        font-size: 12px;
        font-weight: 700;
      }
      .dot {
        width: 7px;
        height: 7px;
        border-radius: 999px;
        background: #22c55e;
      }
      .examples {
        display: grid;
        gap: 8px;
      }
      .example {
        border: 1px solid rgba(255,255,255,0.08);
        border-radius: 8px;
        padding: 10px;
        background: rgba(255,255,255,0.035);
      }
      .note {
        margin-top: 16px;
        padding-top: 14px;
        border-top: 1px solid rgba(255,255,255,0.08);
        color: #a3a3a3;
        font-size: 13px;
      }
    </style>
  </head>
  <body>
    <main>
      <section class="panel">
        <div class="status"><span class="dot"></span>浏览器自动化已就绪</div>
        <h1>Codex 浏览器自动化控制</h1>
        <p>这个浏览器用于打开你指定的网页，让 Codex 通过浏览器工具执行访问、点击、输入、滚动、选择、等待元素、提取页面内容和截图快照等操作。</p>

        <h2>使用方式</h2>
        <ul>
          <li>在终端里告诉 Codex 目标网址和要完成的任务。</li>
          <li>需要登录、搜索、填写表单或读取页面内容时，让 Codex 使用 <code>browser-operator</code>。</li>
          <li>你也可以在上方地址栏手动输入网址，当前页面会被 Codex 接管。</li>
          <li>浏览器默认请求手机页面；需要桌面页面时，让 Codex 使用 <code>browser_set_ua</code> 切换。</li>
          <li>只有明确开启自动草稿或要求保存脚本时，操作流程才会进入脚本助手的待保存区。</li>
        </ul>

        <h2>提示示例</h2>
        <div class="examples">
          <div class="example">打开 https://example.com，提取首页主要标题。</div>
          <div class="example">打开我给你的后台地址，点击登录并等待表单出现。</div>
          <div class="example">在当前页面查找下载按钮，滚动到它的位置并截图。</div>
        </div>

        <p class="note">默认不会自动打开 OpenClaw Gateway 控制台。只有你输入网址，或 Codex 工具发起打开请求时，浏览器才会访问目标网页。</p>
      </section>
    </main>
  </body>
</html>
''';

  static const _selfTestHtml = '''
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>OpenClaw Browser Self Test</title>
    <style>
      :root { color-scheme: dark; }
      html, body {
        margin: 0;
        min-height: 100%;
        background: #0a0a0a;
        color: #f7f7f7;
        font-family: sans-serif;
      }
      body {
        display: grid;
        place-items: center;
      }
      main {
        width: min(88vw, 420px);
        border: 1px solid rgba(255,255,255,0.12);
        border-radius: 8px;
        padding: 20px;
      }
      h1 { margin: 0 0 8px; font-size: 20px; }
      p { margin: 0; color: #d6d6d6; line-height: 1.5; }
    </style>
    <script>
      window.__openclawBrowserSelfTest = 'ready';
    </script>
  </head>
  <body>
    <main data-openclaw-self-test="ready">
      <h1>Browser self-test ready</h1>
      <p>The embedded browser loaded local HTML and JavaScript is available.</p>
    </main>
  </body>
</html>
''';

  final _service = BrowserAutomationService.instance;
  final _urlController = TextEditingController();
  final _urlFocusNode = FocusNode();
  final List<_BrowserTab> _tabs = <_BrowserTab>[];
  int _nextTabId = 1;
  int _activeTabIndex = 0;

  String _title = 'Browser';
  String _currentUrl = '';
  String _error = '';
  bool _loading = true;
  bool _canGoBack = false;
  bool _canGoForward = false;
  bool _showRecentActions = false;
  bool _showInspector = false;
  bool _inspectorLoading = false;
  String _inspectorError = '';
  String _inspectorMode = 'interactables';
  List<Map<String, dynamic>> _inspectorItems = const [];
  bool _browserSoftInputModeActive = false;

  _BrowserTab get _activeTab => _tabs[_activeTabIndex];

  WebViewController get _controller => _activeTab.controller;

  @override
  String get sessionLabel => widget.standalone ? 'terminal-browser-page' : 'terminal-browser-sidecar';

  @override
  void initState() {
    super.initState();
    _urlFocusNode.addListener(_handleAddressBarFocusChange);
    final initialTab = _createTab();
    _tabs.add(initialTab);
    _syncStateFromTab(initialTab, updateAddress: true);
    _service.bindDelegate(this);
    unawaited(_service.ensureStarted());
    unawaited(_initializeBrowser());
  }

  @override
  void didUpdateWidget(covariant TerminalBrowserPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible == widget.visible) {
      return;
    }
    if (!widget.visible) {
      _clearActivePageInputFocus(blurWebView: true);
      return;
    }
    _syncBrowserSoftInputMode();
  }

  @override
  void dispose() {
    _service.unbindDelegate(this);
    _urlFocusNode.removeListener(_handleAddressBarFocusChange);
    if (_browserSoftInputModeActive) {
      unawaited(
        NativeBridge.releaseBrowserSoftInputMode().catchError((_) => false),
      );
      _browserSoftInputModeActive = false;
    }
    _urlFocusNode.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _initializeBrowser() async {
    final pendingUrl = _service.takePendingOpenUrl().trim();
    if (pendingUrl.isNotEmpty) {
      if (pendingUrl == 'about:blank') {
        await _loadWelcomePage();
        return;
      }
      await _loadUrl(pendingUrl);
      return;
    }
    await _loadWelcomePage();
  }

  _BrowserTab _createTab({
    String? initialUrl,
    _BrowserUserAgentMode userAgentMode = _BrowserUserAgentMode.mobile,
  }) {
    final tab = _BrowserTab(
      id: _nextTabId++,
      userAgentMode: userAgentMode,
    );
    tab.controller = _createController(tab);
    if (initialUrl != null && initialUrl.trim().isNotEmpty) {
      tab.currentUrl = initialUrl.trim();
    }
    return tab;
  }

  bool _isActiveTab(_BrowserTab tab) {
    return _tabs.isNotEmpty && identical(_activeTab, tab);
  }

  void _syncStateFromTab(_BrowserTab tab, {required bool updateAddress}) {
    _title = tab.title;
    _currentUrl = tab.currentUrl;
    _error = tab.error;
    _loading = tab.loading;
    _canGoBack = tab.canGoBack;
    _canGoForward = tab.canGoForward;
    if (updateAddress) {
      _urlController.text = tab.currentUrl;
    }
  }

  void _handleAddressBarFocusChange() {
    _syncBrowserSoftInputMode();
  }

  bool _shouldUseBrowserSoftInputMode() {
    if (!widget.visible) {
      return false;
    }
    if (_urlFocusNode.hasFocus) {
      return true;
    }
    if (_tabs.isEmpty) {
      return false;
    }
    return _activeTab.pageInputFocused;
  }

  void _syncBrowserSoftInputMode() {
    final shouldUseBrowserMode = _shouldUseBrowserSoftInputMode();
    if (shouldUseBrowserMode == _browserSoftInputModeActive) {
      return;
    }
    _browserSoftInputModeActive = shouldUseBrowserMode;
    final future = shouldUseBrowserMode
        ? NativeBridge.acquireBrowserSoftInputMode()
        : NativeBridge.releaseBrowserSoftInputMode();
    unawaited(future.catchError((_) => false));
  }

  void _clearActivePageInputFocus({bool blurWebView = false}) {
    if (_tabs.isNotEmpty) {
      _activeTab.pageInputFocused = false;
    }
    if (_urlFocusNode.hasFocus) {
      _urlFocusNode.unfocus();
    }
    _syncBrowserSoftInputMode();
    if (blurWebView && _tabs.isNotEmpty) {
      unawaited(_blurFocusedElement(_activeTab));
    }
  }

  Future<void> _blurFocusedElement(_BrowserTab tab) async {
    try {
      await tab.controller.runJavaScript(r'''
(() => {
  const active = document.activeElement;
  if (active && typeof active.blur === 'function') {
    active.blur();
  }
})();
''');
    } catch (_) {}
  }

  void _setTabLoadingState(
    _BrowserTab tab, {
    String? title,
    String? url,
    String? error,
    bool? loading,
    bool syncUrlText = false,
  }) {
    if (title != null) {
      tab.title = title;
    }
    if (url != null) {
      tab.currentUrl = url;
    }
    if (error != null) {
      tab.error = error;
    }
    if (loading != null) {
      tab.loading = loading;
    }
    if (!mounted) {
      return;
    }
    if (_isActiveTab(tab)) {
      setState(() {
        _syncStateFromTab(tab, updateAddress: syncUrlText);
      });
    }
    _publishStateToService();
  }

  void _setTabBrowserState(
    _BrowserTab tab, {
    String? title,
    bool? canGoBack,
    bool? canGoForward,
  }) {
    if (title != null) {
      tab.title = title;
    }
    if (canGoBack != null) {
      tab.canGoBack = canGoBack;
    }
    if (canGoForward != null) {
      tab.canGoForward = canGoForward;
    }
    if (!mounted) {
      return;
    }
    if (_isActiveTab(tab)) {
      setState(() {
        _syncStateFromTab(tab, updateAddress: false);
      });
    }
    _publishStateToService();
  }

  void _publishStateToService() {
    final active = _activeTab;
    _service.updateObservedState(
      url: active.currentUrl,
      title: active.title,
      loading: active.loading,
      error: active.error,
      tabs: _tabs
          .map((item) => item.toJson(active: identical(item, _activeTab)))
          .toList(),
      activeTabId: active.id,
      userAgentMode: active.userAgentMode.value,
      userAgentLabel: active.userAgentMode.label,
    );
  }

  void _handlePageInputFocusMessage(_BrowserTab tab, String rawMessage) {
    bool focused = false;
    try {
      final decoded = jsonDecode(rawMessage);
      if (decoded is Map<String, dynamic>) {
        focused = decoded['focused'] == true;
      } else if (decoded is Map) {
        focused = decoded['focused'] == true;
      }
    } catch (_) {
      final normalized = rawMessage.trim().toLowerCase();
      focused = normalized == 'true' || normalized == 'focused';
    }
    if (tab.pageInputFocused == focused) {
      return;
    }
    tab.pageInputFocused = focused;
    if (_isActiveTab(tab)) {
      _syncBrowserSoftInputMode();
    }
  }

  Future<void> _installPageInputFocusBridge(_BrowserTab tab) async {
    try {
      await tab.controller.runJavaScript('''
(() => {
  const channel = window.$_keyboardFocusChannelName;
  if (!channel || typeof channel.postMessage !== 'function') {
    return;
  }
  const isEditable = (element) => {
    if (!element) {
      return false;
    }
    const tag = (element.tagName || '').toLowerCase();
    if (tag === 'input' || tag === 'textarea' || tag === 'select') {
      return true;
    }
    if (element.isContentEditable) {
      return true;
    }
    if (typeof element.getAttribute !== 'function') {
      return false;
    }
    const contentEditable = element.getAttribute('contenteditable');
    return contentEditable === '' || contentEditable === 'true';
  };
  const postState = () => {
    try {
      channel.postMessage(JSON.stringify({
        focused: isEditable(document.activeElement),
      }));
    } catch (_) {}
  };
  if (!window.__openclawImeFocusBridgeInstalled) {
    window.__openclawImeFocusBridgeInstalled = true;
    document.addEventListener('focusin', postState, true);
    document.addEventListener('focusout', () => {
      window.setTimeout(postState, 0);
    }, true);
    window.addEventListener('pageshow', postState, true);
  }
  postState();
})();
''');
    } catch (_) {}
  }

  Map<String, String> _userAgentHeadersForTab(_BrowserTab tab) {
    return {'User-Agent': tab.userAgentMode.userAgent};
  }

  Future<void> _configureWebViewForUserAgent(
    WebViewController controller,
    _BrowserUserAgentMode mode,
  ) async {
    await controller.setUserAgent(mode.userAgent);
    final platformController = controller.platform;
    if (platformController is AndroidWebViewController) {
      await platformController.setUseWideViewPort(
        mode == _BrowserUserAgentMode.desktop,
      );
      await platformController.setTextZoom(100);
    }
  }

  Future<void> _applyDesktopViewportHint(_BrowserTab tab) async {
    if (tab.userAgentMode != _BrowserUserAgentMode.desktop) {
      return;
    }
    try {
      await tab.controller.runJavaScript(r'''
(() => {
  const desiredWidth = '1280';
  let viewport = document.querySelector('meta[name="viewport"]');
  if (!viewport) {
    viewport = document.createElement('meta');
    viewport.setAttribute('name', 'viewport');
    document.head.appendChild(viewport);
  }
  viewport.setAttribute('content', `width=${desiredWidth}, initial-scale=1.0`);
  try {
    Object.defineProperty(navigator, 'maxTouchPoints', {
      get: () => 0,
      configurable: true
    });
  } catch (_) {}
})();
''');
    } catch (_) {}
  }

  Future<void> _loadWelcomePage({_BrowserTab? tab}) async {
    final targetTab = tab ?? _activeTab;
    targetTab.pageInputFocused = false;
    if (_isActiveTab(targetTab)) {
      _syncBrowserSoftInputMode();
    }
    _setTabLoadingState(
      targetTab,
      title: 'Codex 浏览器自动化控制',
      url: 'about:blank',
      error: '',
      loading: true,
      syncUrlText: true,
    );
    await targetTab.controller.loadHtmlString(_welcomeHtml);
    if (!mounted) {
      return;
    }
    _setTabLoadingState(
      targetTab,
      title: 'Codex 浏览器自动化控制',
      url: 'about:blank',
      error: '',
      loading: false,
      syncUrlText: true,
    );
    _publishStateToService();
  }

  WebViewController _createController(_BrowserTab tab) {
    const params = PlatformWebViewControllerCreationParams();
    final controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..enableZoom(true)
      ..setBackgroundColor(Colors.black)
      ..addJavaScriptChannel(
        _keyboardFocusChannelName,
        onMessageReceived: (message) {
          _handlePageInputFocusMessage(tab, message.message);
        },
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            tab.pageInputFocused = false;
            if (_isActiveTab(tab)) {
              _syncBrowserSoftInputMode();
            }
            if (tab.navigationCompleter == null ||
                tab.navigationCompleter!.isCompleted) {
              tab.navigationCompleter = Completer<void>();
            }
            _setTabLoadingState(
              tab,
              url: url,
              error: '',
              loading: true,
              syncUrlText: _isActiveTab(tab),
            );
          },
          onPageFinished: (url) {
            _completePendingNavigation(tab);
            unawaited(_applyDesktopViewportHint(tab));
            unawaited(_installPageInputFocusBridge(tab));
            unawaited(_refreshNavigationState(tab));
            if (_isActiveTab(tab) && _showInspector) {
              unawaited(_refreshInspectorCurrentMode());
            }
            _setTabLoadingState(
              tab,
              url: url,
              loading: false,
              syncUrlText: _isActiveTab(tab),
            );
          },
          onWebResourceError: (error) {
            if (error.isForMainFrame == false) {
              return;
            }
            _completePendingNavigation(tab);
            tab.pageInputFocused = false;
            if (_isActiveTab(tab)) {
              _syncBrowserSoftInputMode();
            }
            _setTabLoadingState(
              tab,
              error: error.description.trim(),
              loading: false,
              syncUrlText: _isActiveTab(tab),
            );
          },
        ),
      );

    unawaited(_configureWebViewForUserAgent(controller, tab.userAgentMode));
    final platformController = controller.platform;
    if (platformController is AndroidWebViewController) {
      unawaited(
        platformController.setMixedContentMode(MixedContentMode.alwaysAllow),
      );
      unawaited(platformController.setVerticalScrollBarEnabled(true));
      unawaited(platformController.setHorizontalScrollBarEnabled(true));
    }

    return controller;
  }

  Future<void> _refreshNavigationState([_BrowserTab? tab]) async {
    final targetTab = tab ?? _activeTab;
    try {
      final title = await targetTab.controller.getTitle() ?? 'Browser';
      final canGoBack = await targetTab.controller.canGoBack();
      final canGoForward = await targetTab.controller.canGoForward();
      if (!mounted) {
        return;
      }
      _setTabBrowserState(
        targetTab,
        title: title.trim().isEmpty ? 'Browser' : title.trim(),
        canGoBack: canGoBack,
        canGoForward: canGoForward,
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

  Future<void> _loadUrl(String rawUrl, {_BrowserTab? tab}) async {
    final targetTab = tab ?? _activeTab;
    final url = _normalizeUrl(rawUrl);
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      if (_isActiveTab(targetTab)) {
        setState(() {
          _error = 'Invalid URL';
        });
      }
      targetTab.error = 'Invalid URL';
      _publishStateToService();
      return;
    }

    _setTabLoadingState(
      targetTab,
      url: uri.toString(),
      error: '',
      loading: true,
      syncUrlText: true,
    );
    await targetTab.controller.loadRequest(
      uri,
      headers: _userAgentHeadersForTab(targetTab),
    );
    await _awaitNavigationCompletion(targetTab);
    await _refreshNavigationState(targetTab);
  }

  void _clearInspectorItems() {
    _inspectorItems = const [];
    _inspectorError = '';
    _inspectorLoading = false;
  }

  _BrowserUserAgentMode? _parseUserAgentMode(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) {
      return null;
    }
    if (normalized == 'desktop' ||
        normalized == 'pc' ||
        normalized == 'computer' ||
        normalized == '电脑' ||
        normalized == '桌面') {
      return _BrowserUserAgentMode.desktop;
    }
    if (normalized == 'mobile' ||
        normalized == 'phone' ||
        normalized == 'android' ||
        normalized == '手机' ||
        normalized == '移动') {
      return _BrowserUserAgentMode.mobile;
    }
    return null;
  }

  Future<void> _setUserAgentMode(
    _BrowserUserAgentMode mode, {
    bool reloadCurrentPage = false,
  }) async {
    final tab = _activeTab;
    if (tab.userAgentMode == mode && !reloadCurrentPage) {
      return;
    }
    tab.userAgentMode = mode;
    await _configureWebViewForUserAgent(tab.controller, mode);
    _publishStateToService();
    if (!mounted) {
      return;
    }
    setState(() {
      _syncStateFromTab(tab, updateAddress: false);
    });
    final currentUrl = tab.currentUrl.trim();
    final uri = Uri.tryParse(currentUrl);
    final shouldReload = reloadCurrentPage &&
        currentUrl.isNotEmpty &&
        currentUrl != 'about:blank' &&
        uri != null &&
        uri.hasScheme;
    if (shouldReload) {
      await _loadUrl(currentUrl, tab: tab);
    }
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

  Future<void> _awaitNavigationCompletion([_BrowserTab? tab]) async {
    final completer = (tab ?? _activeTab).navigationCompleter;
    if (completer == null) {
      return;
    }
    await completer.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () {},
    );
  }

  void _completePendingNavigation([_BrowserTab? tab]) {
    final completer = (tab ?? _activeTab).navigationCompleter;
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
    final active = _activeTab;
    return {
      'ok': ok,
      'message': message,
      'url': active.currentUrl,
      'title': active.title,
      'loading': active.loading,
      'error': active.error,
      'canGoBack': active.canGoBack,
      'canGoForward': active.canGoForward,
      'tabs': _tabs
          .map((tab) => tab.toJson(active: identical(tab, active)))
          .toList(),
      'activeTabId': active.id,
      'userAgentMode': active.userAgentMode.value,
      'userAgentLabel': active.userAgentMode.label,
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
  Future<Map<String, dynamic>> selfTest() async {
    final tab = _activeTab;
    _setTabLoadingState(
      tab,
      title: 'OpenClaw Browser Self Test',
      url: 'about:blank',
      error: '',
      loading: true,
      syncUrlText: true,
    );

    try {
      tab.navigationCompleter = Completer<void>();
      await tab.controller.loadHtmlString(_selfTestHtml);
      await Future<void>.delayed(const Duration(milliseconds: 250));
    } catch (error) {
      _setTabLoadingState(
        tab,
        error: error.toString(),
        loading: false,
        syncUrlText: true,
      );
      return _pageSnapshot(
        ok: false,
        message: 'Failed to load the browser self-test page.',
      );
    }

    final raw = await _runStringJs('''
(() => {
  const marker = document.querySelector('[data-openclaw-self-test="ready"]');
  return JSON.stringify({
    ok: Boolean(marker) && window.__openclawBrowserSelfTest === 'ready',
    title: document.title || '',
    markerText: marker ? (marker.textContent || '').trim().slice(0, 160) : '',
    href: location.href || ''
  });
})();
''');
    if (raw == null) {
      _setTabLoadingState(tab, loading: false, syncUrlText: true);
      return _pageSnapshot(
        ok: false,
        message: 'Self-test page loaded, but JavaScript evaluation failed.',
      );
    }

    Map<String, dynamic> decoded;
    try {
      decoded = jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      _setTabLoadingState(tab, loading: false, syncUrlText: true);
      return _pageSnapshot(
        ok: false,
        message: 'Self-test JavaScript returned an unreadable result.',
      );
    }
    final passed = decoded['ok'] == true;
    _setTabLoadingState(
      tab,
      error: '',
      loading: false,
      syncUrlText: true,
    );
    return _pageSnapshot(
      ok: passed,
      message: passed
          ? 'Browser self-test passed.'
          : 'Self-test page loaded, but the readiness marker was not found.',
      extra: {'actionResult': decoded},
    );
  }

  @override
  Future<Map<String, dynamic>> healthCheck({
    int quietWindowMs = 500,
    int timeoutMs = 10000,
  }) async {
    final safeQuietWindowMs = quietWindowMs.clamp(100, 5000);
    final safeTimeoutMs = timeoutMs.clamp(safeQuietWindowMs, 30000);
    final deadline = DateTime.now().millisecondsSinceEpoch + safeTimeoutMs;
    while (DateTime.now().millisecondsSinceEpoch < deadline) {
      final raw = await _runStringJs('''
(() => {
  const quietWindowMs = $safeQuietWindowMs;
  const now = Date.now();
  const state = document.readyState || 'unknown';
  const body = document.body;
  const root = document.documentElement;
  const lastMutation = window.__openclawLastDomMutationAt || 0;
  if (!window.__openclawHealthObserver && document.documentElement) {
    window.__openclawLastDomMutationAt = now;
    window.__openclawHealthObserver = new MutationObserver(() => {
      window.__openclawLastDomMutationAt = Date.now();
    });
    window.__openclawHealthObserver.observe(document.documentElement, {
      childList: true, subtree: true, attributes: true, characterData: true
    });
  }
  const resources = performance.getEntriesByType('resource');
  const recentResources = resources.filter((entry) => now - entry.responseEnd < quietWindowMs);
  const domQuiet = now - lastMutation >= quietWindowMs;
  const ready = state === 'complete' && Boolean(body) && Boolean(root) && domQuiet && recentResources.length === 0;
  return JSON.stringify({
    ok: ready,
    javascript: true,
    dom: Boolean(body) && Boolean(root),
    readyState: state,
    domQuiet,
    recentResourceCount: recentResources.length,
    url: location.href || '',
    title: document.title || ''
  });
})();
''');
      if (raw != null) {
        try {
          final decoded = jsonDecode(raw) as Map<String, dynamic>;
          if (decoded['ok'] == true) {
            return _pageSnapshot(
              message: 'Browser health check passed: DOM, JavaScript, and network idle are ready.',
              extra: {'actionResult': decoded},
            );
          }
        } catch (_) {}
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return _pageSnapshot(
      ok: false,
      message: 'Timed out waiting for DOM and network idle; the page may still be hydrating.',
    );
  }

  @override
  Future<Map<String, dynamic>> resetTab({String? url}) async {
    final previous = _activeTab;
    final replacement = _createTab(userAgentMode: previous.userAgentMode);
    final index = _activeTabIndex;
    if (!mounted) {
      return _pageSnapshot(ok: false, message: 'Browser panel is no longer mounted.');
    }
    setState(() {
      _tabs[index] = replacement;
      _syncStateFromTab(replacement, updateAddress: true);
      _clearInspectorItems();
    });
    _publishStateToService();
    final target = url?.trim().isNotEmpty == true ? url!.trim() : previous.currentUrl;
    if (target.isEmpty || target == 'about:blank') {
      await _loadWelcomePage(tab: replacement);
    } else {
      await _loadUrl(target, tab: replacement);
    }
    return _pageSnapshot(message: 'Browser tab was reset with a fresh WebView session.');
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
    _activeTab.navigationCompleter = Completer<void>();
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
    _activeTab.navigationCompleter = Completer<void>();
    await _controller.goForward();
    await _awaitNavigationCompletion();
    return _pageSnapshot(message: 'Navigated forward.');
  }

  @override
  Future<Map<String, dynamic>> reload() async {
    _activeTab.navigationCompleter = Completer<void>();
    await _controller.reload();
    await _awaitNavigationCompletion();
    return _pageSnapshot(message: 'Page reloaded.');
  }

  @override
  Future<Map<String, dynamic>> listTabs() {
    return _pageSnapshot(message: 'Browser tabs loaded.');
  }

  @override
  Future<Map<String, dynamic>> newTab({
    String? url,
  }) async {
    final tab = _createTab(userAgentMode: _activeTab.userAgentMode);
    if (!mounted) {
      return _pageSnapshot(
        ok: false,
        message: 'Browser panel is no longer mounted.',
      );
    }
    setState(() {
      _tabs.add(tab);
      _activeTabIndex = _tabs.length - 1;
      _syncStateFromTab(tab, updateAddress: true);
      _clearInspectorItems();
    });
    _syncBrowserSoftInputMode();
    _publishStateToService();
    final targetUrl = url?.trim() ?? '';
    if (targetUrl.isEmpty) {
      await _loadWelcomePage(tab: tab);
    } else {
      await _loadUrl(targetUrl, tab: tab);
    }
    return _pageSnapshot(message: 'New browser tab opened.');
  }

  @override
  Future<Map<String, dynamic>> switchTab({
    required int id,
  }) async {
    final index = _tabs.indexWhere((tab) => tab.id == id);
    if (index < 0) {
      return _pageSnapshot(
        ok: false,
        message: 'Browser tab was not found: $id',
      );
    }
    setState(() {
      _activeTabIndex = index;
      _syncStateFromTab(_activeTab, updateAddress: true);
      _clearInspectorItems();
    });
    _syncBrowserSoftInputMode();
    _publishStateToService();
    return _pageSnapshot(message: 'Switched to browser tab $id.');
  }

  @override
  Future<Map<String, dynamic>> closeTab({
    int? id,
  }) async {
    final targetId = id == null || id <= 0 ? _activeTab.id : id;
    final index = _tabs.indexWhere((tab) => tab.id == targetId);
    if (index < 0) {
      return _pageSnapshot(
        ok: false,
        message: 'Browser tab was not found: $targetId',
      );
    }
    setState(() {
      _tabs.removeAt(index);
      if (_tabs.isEmpty) {
        _tabs.add(_createTab());
        _activeTabIndex = 0;
      } else if (_activeTabIndex >= _tabs.length) {
        _activeTabIndex = _tabs.length - 1;
      } else if (index < _activeTabIndex) {
        _activeTabIndex -= 1;
      }
      _syncStateFromTab(_activeTab, updateAddress: true);
      _clearInspectorItems();
    });
    _syncBrowserSoftInputMode();
    _publishStateToService();
    if (_activeTab.currentUrl.isEmpty) {
      await _loadWelcomePage();
    }
    return _pageSnapshot(message: 'Browser tab closed.');
  }

  @override
  Future<Map<String, dynamic>> setUserAgent({
    required String mode,
  }) async {
    final nextMode = _parseUserAgentMode(mode);
    if (nextMode == null) {
      return _pageSnapshot(
        ok: false,
        message: 'Unsupported browser user-agent mode: $mode',
      );
    }
    await _setUserAgentMode(nextMode, reloadCurrentPage: true);
    return _pageSnapshot(
      message: 'Browser user-agent switched to ${nextMode.label}.',
    );
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
    final script = """
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
""";
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
    final script = """
(() => {
  const selector = ${jsonEncode(selector)};
  const value = ${jsonEncode(text)};
  const shouldSubmit = ${submit ? 'true' : 'false'};
  const element = document.querySelector(selector);
  if (!element) return JSON.stringify({ ok: false, message: `Selector not found: \${selector}` });
  element.scrollIntoView({ behavior: 'instant', block: 'center', inline: 'center' });
  if (typeof element.focus === 'function') element.focus();
  if ('value' in element) element.value = value;
  else if (element.isContentEditable) element.textContent = value;
  else return JSON.stringify({ ok: false, message: 'Target element is not editable.' });
  element.dispatchEvent(new Event('input', { bubbles: true }));
  element.dispatchEvent(new Event('change', { bubbles: true }));
  if (shouldSubmit) {
    const form = element.form || element.closest('form');
    if (form?.requestSubmit) form.requestSubmit();
    else element.dispatchEvent(new KeyboardEvent('keydown', { key: 'Enter', code: 'Enter', bubbles: true }));
  }
  return JSON.stringify({ ok: true, message: shouldSubmit ? 'Text entered and submitted.' : 'Text entered.', tag: element.tagName || '' });
})();
""";
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
  Future<Map<String, dynamic>> paste({
    required String selector,
    required String text,
    bool submit = false,
  }) async {
    if (selector.trim().isEmpty) return _pageSnapshot(ok: false, message: 'The selector argument cannot be empty.');
    final raw = await _runStringJs("""
(() => {
  const selector = ${jsonEncode(selector)};
  const value = ${jsonEncode(text)};
  const shouldSubmit = ${submit ? 'true' : 'false'};
  const element = document.querySelector(selector);
  if (!element) return JSON.stringify({ ok: false, message: `Selector not found: \${selector}` });
  const tag = (element.tagName || '').toLowerCase();
  if (!(tag === 'input' || tag === 'textarea' || element.isContentEditable)) return JSON.stringify({ ok: false, message: 'Target element is not editable.' });
  element.focus();
  element.dispatchEvent(new InputEvent('beforeinput', { bubbles: true, cancelable: true, inputType: 'insertFromPaste', data: value }));
  if (tag === 'input' || tag === 'textarea') {
    const prototype = tag === 'textarea' ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
    const setter = Object.getOwnPropertyDescriptor(prototype, 'value')?.set;
    if (setter) setter.call(element, value); else element.value = value;
  } else element.textContent = value;
  element.dispatchEvent(new InputEvent('input', { bubbles: true, inputType: 'insertFromPaste', data: value }));
  element.dispatchEvent(new Event('change', { bubbles: true }));
  if (shouldSubmit) (element.form || element.closest?.('form'))?.requestSubmit?.();
  return JSON.stringify({ ok: true, message: 'Text pasted with input events.' });
})();
""");
    if (raw == null) return _pageSnapshot(ok: false, message: 'Failed to run the paste action in WebView.');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return _pageSnapshot(ok: decoded['ok'] != false, message: decoded['message']?.toString() ?? 'Text pasted.', extra: {'actionResult': decoded});
  }

  @override
  Future<Map<String, dynamic>> waitForResource({
    required String pattern,
    int timeoutMs = 10000,
  }) async {
    if (pattern.trim().isEmpty) return _pageSnapshot(ok: false, message: 'The resource pattern cannot be empty.');
    final deadline = DateTime.now().millisecondsSinceEpoch + timeoutMs.clamp(100, 30000);
    while (DateTime.now().millisecondsSinceEpoch < deadline) {
      final raw = await _runStringJs("""
(() => {
  const pattern = ${jsonEncode(pattern)}.toLowerCase();
  const resources = performance.getEntriesByType('resource').filter((entry) => entry.name.toLowerCase().includes(pattern));
  const item = resources[resources.length - 1];
  return JSON.stringify({ ok: Boolean(item), resource: item ? { url: item.name, initiatorType: item.initiatorType } : null });
})();
""");
      if (raw != null) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded['ok'] == true) return _pageSnapshot(message: 'Matched a loaded page resource.', extra: {'actionResult': decoded});
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return _pageSnapshot(ok: false, message: 'Timed out waiting for a matching page resource.');
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
  Future<Map<String, dynamic>> waitForSelector({
    required String selector,
    int timeoutMs = 10000,
    bool visible = true,
  }) async {
    if (selector.trim().isEmpty) {
      return _pageSnapshot(
        ok: false,
        message: 'The selector argument cannot be empty.',
      );
    }
    final deadline = DateTime.now().millisecondsSinceEpoch + timeoutMs;
    while (DateTime.now().millisecondsSinceEpoch < deadline) {
      final script = '''
(() => {
  const selector = ${jsonEncode(selector)};
  const requireVisible = ${visible ? 'true' : 'false'};
  const element = document.querySelector(selector);
  if (!element) {
    return JSON.stringify({ ok: false, found: false, visible: false });
  }
  const rect = element.getBoundingClientRect();
  const style = window.getComputedStyle(element);
  const isVisible = rect.width > 0 &&
    rect.height > 0 &&
    style.visibility !== 'hidden' &&
    style.display !== 'none' &&
    Number(style.opacity || '1') > 0;
  return JSON.stringify({
    ok: requireVisible ? isVisible : true,
    found: true,
    visible: isVisible,
    tag: element.tagName || '',
    text: (element.innerText || element.textContent || element.value || '')
      .trim()
      .slice(0, 240),
    rect: {
      x: Math.round(rect.x),
      y: Math.round(rect.y),
      width: Math.round(rect.width),
      height: Math.round(rect.height)
    }
  });
})();
''';
      final raw = await _runStringJs(script);
      if (raw != null) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        if (decoded['ok'] == true) {
          return _pageSnapshot(
            message: visible
                ? 'Found the visible selector on the page.'
                : 'Found the requested selector on the page.',
            extra: {'actionResult': decoded},
          );
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
    return _pageSnapshot(
      ok: false,
      message: visible
          ? 'Timed out while waiting for the visible selector.'
          : 'Timed out while waiting for the requested selector.',
    );
  }

  @override
  Future<Map<String, dynamic>> scroll({
    String? selector,
    String direction = 'down',
    int pixels = 700,
  }) async {
    final safePixels = pixels.clamp(50, 5000);
    final safeDirection = direction.trim().toLowerCase().isEmpty
        ? 'down'
        : direction.trim().toLowerCase();
    final script = '''
(() => {
  const selector = ${jsonEncode(selector?.trim() ?? '')};
  const direction = ${jsonEncode(safeDirection)};
  const pixels = $safePixels;
  const root = document.scrollingElement || document.documentElement || document.body;
  const target = selector ? document.querySelector(selector) : root;
  if (!target) {
    return JSON.stringify({ ok: false, message: `Selector not found: \${selector}` });
  }

  const isPage = target === root || target === document.body || target === document.documentElement;
  const before = {
    x: isPage ? window.scrollX : target.scrollLeft,
    y: isPage ? window.scrollY : target.scrollTop
  };
  let dx = 0;
  let dy = 0;
  let absolute = false;
  let top = 0;
  let left = 0;
  switch (direction) {
    case 'up':
      dy = -pixels;
      break;
    case 'left':
      dx = -pixels;
      break;
    case 'right':
      dx = pixels;
      break;
    case 'top':
      absolute = true;
      top = 0;
      left = before.x;
      break;
    case 'bottom':
      absolute = true;
      top = isPage ? root.scrollHeight : target.scrollHeight;
      left = before.x;
      break;
    case 'down':
    default:
      dy = pixels;
      break;
  }

  if (isPage) {
    if (absolute) {
      window.scrollTo({ left, top, behavior: 'instant' });
    } else {
      window.scrollBy({ left: dx, top: dy, behavior: 'instant' });
    }
  } else if (absolute) {
    target.scrollTo({ left, top, behavior: 'instant' });
  } else {
    target.scrollBy({ left: dx, top: dy, behavior: 'instant' });
  }

  const after = {
    x: isPage ? window.scrollX : target.scrollLeft,
    y: isPage ? window.scrollY : target.scrollTop
  };
  return JSON.stringify({
    ok: true,
    message: `Scrolled \${direction}.`,
    selector: selector || null,
    before,
    after,
    max: {
      width: isPage ? root.scrollWidth : target.scrollWidth,
      height: isPage ? root.scrollHeight : target.scrollHeight
    }
  });
})();
''';
    final raw = await _runStringJs(script);
    if (raw == null) {
      return _pageSnapshot(
        ok: false,
        message: 'Failed to run the scroll action in WebView.',
      );
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return _pageSnapshot(
      ok: decoded['ok'] != false,
      message: decoded['message']?.toString() ?? 'Scrolled page.',
      extra: {'actionResult': decoded},
    );
  }

  @override
  Future<Map<String, dynamic>> pressKey({
    String? selector,
    required String key,
  }) async {
    if (key.trim().isEmpty) {
      return _pageSnapshot(
        ok: false,
        message: 'The key argument cannot be empty.',
      );
    }
    final script = '''
(() => {
  const selector = ${jsonEncode(selector?.trim() ?? '')};
  const key = ${jsonEncode(key.trim())};
  let target = selector ? document.querySelector(selector) : document.activeElement;
  if (selector && !target) {
    return JSON.stringify({ ok: false, message: `Selector not found: \${selector}` });
  }
  if (!target || target === document.body || target === document.documentElement) {
    target = document.querySelector('input, textarea, select, button, a[href], [tabindex], [contenteditable="true"]') || document.body;
  }
  if (typeof target.focus === 'function') {
    target.focus();
  }

  const code = key.length === 1 ? `Key\${key.toUpperCase()}` : key;
  const eventInit = { key, code, bubbles: true, cancelable: true };
  const down = target.dispatchEvent(new KeyboardEvent('keydown', eventInit));
  target.dispatchEvent(new KeyboardEvent('keypress', eventInit));
  const up = target.dispatchEvent(new KeyboardEvent('keyup', eventInit));

  if (key === 'Enter' && down !== false) {
    const form = target.form || target.closest?.('form');
    if (form && typeof form.requestSubmit === 'function') {
      form.requestSubmit();
    }
  }

  return JSON.stringify({
    ok: true,
    message: `Pressed \${key}.`,
    selector: selector || null,
    canceled: down === false || up === false,
    activeTag: document.activeElement?.tagName || '',
    activeText: (
      document.activeElement?.innerText ||
      document.activeElement?.textContent ||
      document.activeElement?.value ||
      ''
    ).trim().slice(0, 160)
  });
})();
''';
    final raw = await _runStringJs(script);
    if (raw == null) {
      return _pageSnapshot(
        ok: false,
        message: 'Failed to run the key press action in WebView.',
      );
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return _pageSnapshot(
      ok: decoded['ok'] != false,
      message: decoded['message']?.toString() ?? 'Key pressed.',
      extra: {'actionResult': decoded},
    );
  }

  @override
  Future<Map<String, dynamic>> selectOption({
    required String selector,
    String? value,
    String? label,
    int? index,
  }) async {
    if (selector.trim().isEmpty) {
      return _pageSnapshot(
        ok: false,
        message: 'The selector argument cannot be empty.',
      );
    }
    final hasValue = value?.trim().isNotEmpty ?? false;
    final hasLabel = label?.trim().isNotEmpty ?? false;
    final hasIndex = index != null && index >= 0;
    if (!hasValue && !hasLabel && !hasIndex) {
      return _pageSnapshot(
        ok: false,
        message: 'Provide value, label, or index for the option to select.',
      );
    }
    final script = '''
(() => {
  const selector = ${jsonEncode(selector)};
  const value = ${jsonEncode(value?.trim() ?? '')};
  const label = ${jsonEncode(label?.trim() ?? '')};
  const index = ${index == null ? 'null' : index.toString()};
  const select = document.querySelector(selector);
  if (!select) {
    return JSON.stringify({ ok: false, message: `Selector not found: \${selector}` });
  }
  if (select.tagName !== 'SELECT') {
    return JSON.stringify({ ok: false, message: 'Target element is not a select.' });
  }

  const options = Array.from(select.options || []);
  const normalizedLabel = label.toLowerCase();
  let option = null;
  if (value) {
    option = options.find((item) => item.value === value);
  }
  if (!option && label) {
    option = options.find((item) =>
      (item.label || item.text || '').trim().toLowerCase() === normalizedLabel
    ) || options.find((item) =>
      (item.label || item.text || '').trim().toLowerCase().includes(normalizedLabel)
    );
  }
  if (!option && Number.isInteger(index) && index >= 0 && index < options.length) {
    option = options[index];
  }
  if (!option) {
    return JSON.stringify({ ok: false, message: 'Matching option was not found.' });
  }

  select.value = option.value;
  option.selected = true;
  select.dispatchEvent(new Event('input', { bubbles: true }));
  select.dispatchEvent(new Event('change', { bubbles: true }));
  return JSON.stringify({
    ok: true,
    message: 'Option selected.',
    selector,
    selectedIndex: select.selectedIndex,
    value: select.value,
    text: (option.label || option.text || '').trim()
  });
})();
''';
    final raw = await _runStringJs(script);
    if (raw == null) {
      return _pageSnapshot(
        ok: false,
        message: 'Failed to run the select action in WebView.',
      );
    }
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return _pageSnapshot(
      ok: decoded['ok'] != false,
      message: decoded['message']?.toString() ?? 'Option selected.',
      extra: {'actionResult': decoded},
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
  Future<Map<String, dynamic>> listOverlays({int maxItems = 24}) async {
    final safeMaxItems = maxItems.clamp(1, 80);
    final raw = await _runStringJs('''
(() => {
  const visible = (element) => {
    const rect = element.getBoundingClientRect();
    const style = getComputedStyle(element);
    return rect.width > 0 && rect.height > 0 && style.display !== 'none' && style.visibility !== 'hidden' && Number(style.opacity || 1) > 0;
  };
  const candidates = Array.from(document.querySelectorAll('[role="dialog"], [role="menu"], [role="listbox"], [aria-modal="true"], [data-radix-popper-content-wrapper], [data-radix-portal], body *'))
    .filter((element) => visible(element))
    .filter((element) => {
      const style = getComputedStyle(element);
      return ['fixed', 'absolute'].includes(style.position) || ['dialog', 'menu', 'listbox'].includes(element.getAttribute('role') || '') || element.getAttribute('aria-modal') === 'true';
    })
    .map((element) => {
      const rect = element.getBoundingClientRect();
      const style = getComputedStyle(element);
      return { tag: element.tagName || '', role: element.getAttribute('role') || '', ariaLabel: element.getAttribute('aria-label') || '', text: (element.innerText || element.textContent || '').trim().slice(0, 240), zIndex: style.zIndex || 'auto', rect: { x: Math.round(rect.x), y: Math.round(rect.y), width: Math.round(rect.width), height: Math.round(rect.height) } };
    })
    .sort((a, b) => (Number.parseInt(b.zIndex, 10) || 0) - (Number.parseInt(a.zIndex, 10) || 0))
    .slice(0, $safeMaxItems);
  return JSON.stringify({ ok: true, overlays: candidates });
})();
''');
    if (raw == null) return _pageSnapshot(ok: false, message: 'Failed to inspect visible overlays.');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return _pageSnapshot(message: 'Visible overlays listed.', extra: {'actionResult': decoded});
  }

  @override
  Future<Map<String, dynamic>> clickAt({required double x, required double y}) async {
    if (!x.isFinite || !y.isFinite || x < 0 || y < 0) {
      return _pageSnapshot(ok: false, message: 'Coordinates must be finite non-negative viewport values.');
    }
    final raw = await _runStringJs('''
(() => {
  const x = ${x.toStringAsFixed(2)};
  const y = ${y.toStringAsFixed(2)};
  const element = document.elementFromPoint(x, y);
  if (!element) return JSON.stringify({ ok: false, message: 'No element exists at the requested viewport coordinates.' });
  element.scrollIntoView({ behavior: 'instant', block: 'center', inline: 'center' });
  if (typeof element.focus === 'function') element.focus();
  for (const type of ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click']) {
    element.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, clientX: x, clientY: y, view: window }));
  }
  const rect = element.getBoundingClientRect();
  return JSON.stringify({ ok: true, message: 'Clicked element at viewport coordinates.', tag: element.tagName || '', text: (element.innerText || element.textContent || element.getAttribute('aria-label') || '').trim().slice(0, 160), rect: { x: Math.round(rect.x), y: Math.round(rect.y), width: Math.round(rect.width), height: Math.round(rect.height) } });
})();
''');
    if (raw == null) return _pageSnapshot(ok: false, message: 'Failed to run the coordinate click action in WebView.');
    final decoded = jsonDecode(raw) as Map<String, dynamic>;
    return _pageSnapshot(ok: decoded['ok'] != false, message: decoded['message']?.toString() ?? 'Coordinate click completed.', extra: {'actionResult': decoded});
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
    return Theme(
      data: _browserButtonTheme(theme),
      child: AnimatedBuilder(
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
                if (_showRecentActions) _buildRecentActionsStrip(theme),
                if (_showInspector || _inspectorLoading || _inspectorItems.isNotEmpty)
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
          ),
          );
        },
      ),
    );
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

  Future<void> _showScriptLibrary() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: const Color(0xFF090909),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
      ),
      builder: (context) {
        return Theme(
          data: _browserButtonTheme(Theme.of(context)),
          child: _BrowserScriptLibrarySheet(service: _service),
        );
      },
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

  Widget _buildTabStrip(ThemeData theme, {required bool compact}) {
    return SizedBox(
      height: 38,
      child: Row(
        children: [
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _tabs.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                return _buildTabChip(
                  theme,
                  _tabs[index],
                  compact: compact,
                );
              },
            ),
          ),
          const SizedBox(width: 6),
          _buildActionIcon(
            icon: Icons.add,
            tooltip: '新建标签页',
            onTap: () => unawaited(newTab()),
          ),
        ],
      ),
    );
  }

  Widget _buildTabChip(
    ThemeData theme,
    _BrowserTab tab, {
    required bool compact,
  }) {
    final active = _isActiveTab(tab);
    final title = tab.title.trim().isNotEmpty
        ? tab.title.trim()
        : tab.currentUrl.trim().isNotEmpty
            ? tab.currentUrl.trim()
            : '新标签页';
    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: compact ? 102 : 128,
        maxWidth: compact ? 142 : 190,
      ),
      child: Material(
        color: active ? AppColors.accent.withAlpha(28) : Colors.white.withAlpha(8),
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: active ? null : () => unawaited(switchTab(id: tab.id)),
          child: Container(
            padding: const EdgeInsets.only(left: 9, right: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: active
                    ? AppColors.accent.withAlpha(150)
                    : Colors.white.withAlpha(14),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  tab.userAgentMode.icon,
                  size: 14,
                  color: active ? AppColors.accent : Colors.white54,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: active ? Colors.white : Colors.white70,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
                if (_tabs.length > 1)
                  IconButton(
                    tooltip: '关闭标签页',
                    onPressed: () => unawaited(closeTab(id: tab.id)),
                    icon: const Icon(Icons.close, size: 14),
                    color: Colors.white54,
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAddressBar(ThemeData theme, {required bool compact}) {
    final label = _title.trim().isEmpty ? '地址' : _title.trim();
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: _urlController,
            focusNode: _urlFocusNode,
            style: const TextStyle(
              color: _panelText,
              fontSize: 13,
            ),
            cursorColor: _panelText,
            textInputAction: TextInputAction.go,
            onSubmitted: (_) => unawaited(_submitAddress()),
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: _panelSurfaceAlt,
              label: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: _panelMutedText),
              ),
              floatingLabelStyle: const TextStyle(color: AppColors.accent),
              hintText: '输入网址',
              hintStyle: const TextStyle(color: _panelMutedText),
              prefixIcon: Icon(
                _activeTab.userAgentMode.icon,
                size: 18,
                color: AppColors.accent,
              ),
              prefixIconConstraints: const BoxConstraints(
                minWidth: 38,
                minHeight: 38,
              ),
              contentPadding: EdgeInsets.symmetric(
                horizontal: compact ? 9 : 11,
                vertical: compact ? 10 : 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _panelBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: const BorderSide(color: _panelBorder),
              ),
              focusedBorder: const OutlineInputBorder(
                borderRadius: BorderRadius.all(
                  Radius.circular(8),
                ),
                borderSide: BorderSide(color: AppColors.accent),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _buildAddressSubmitButton(compact: compact),
      ],
    );
  }

  Widget _buildUaModeButton({required bool compact}) {
    return PopupMenuButton<_BrowserUserAgentMode>(
      tooltip: '切换 UA',
      onSelected: (mode) => unawaited(
        _setUserAgentMode(mode, reloadCurrentPage: true),
      ),
      color: _panelSurfaceAlt,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: _panelBorder),
      ),
      itemBuilder: (context) {
        return [
          for (final mode in _BrowserUserAgentMode.values)
            PopupMenuItem(
              value: mode,
              child: _buildMenuEntry(
                icon: mode.icon,
                label: '${mode.label} UA',
                iconColor: mode == _activeTab.userAgentMode
                    ? AppColors.accent
                    : _panelText,
                textColor: mode == _activeTab.userAgentMode
                    ? AppColors.accent
                    : _panelText,
              ),
            )
        ];
      },
      child: Container(
        width: compact ? 38 : 42,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _panelSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _panelBorder),
        ),
        child: Icon(
          _activeTab.userAgentMode.icon,
          size: 18,
          color: _panelText,
        ),
      ),
    );
  }

  Widget _buildMoreMenu({required bool compact}) {
    return PopupMenuButton<_BrowserMenuAction>(
      tooltip: '更多浏览器工具',
      color: _panelSurfaceAlt,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: const BorderSide(color: _panelBorder),
      ),
      onSelected: _handleBrowserMenuAction,
      itemBuilder: (context) {
        return [
          PopupMenuItem(
            value: _BrowserMenuAction.scripts,
            child: _buildMenuEntry(
              icon: Icons.playlist_play,
              label: '脚本助手',
            ),
          ),
          PopupMenuItem(
            value: _BrowserMenuAction.inspector,
            child: _buildMenuEntry(
              icon: Icons.tune,
              label: _showInspector ? '隐藏检查器' : '显示检查器',
            ),
          ),
          PopupMenuItem(
            value: _BrowserMenuAction.recentActions,
            child: _buildMenuEntry(
              icon: Icons.history,
              label: _showRecentActions ? '隐藏最近操作' : '显示最近操作',
            ),
          ),
          PopupMenuItem(
            value: _BrowserMenuAction.snapshot,
            child: _buildMenuEntry(
              icon: Icons.download_rounded,
              label: '保存页面快照',
            ),
          ),
        ];
      },
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: _panelSurface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _panelBorder),
        ),
        child: const Icon(Icons.more_horiz, size: 19, color: _panelText),
      ),
    );
  }

  Widget _buildMenuEntry({
    required IconData icon,
    required String label,
    Color? iconColor,
    Color? textColor,
  }) {
    final resolvedIconColor = iconColor ?? _panelText;
    final resolvedTextColor = textColor ?? _panelText;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 18, color: resolvedIconColor),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            color: resolvedTextColor,
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  void _handleBrowserMenuAction(_BrowserMenuAction action) {
    switch (action) {
      case _BrowserMenuAction.scripts:
        unawaited(_showScriptLibrary());
        break;
      case _BrowserMenuAction.snapshot:
        unawaited(_exportSnapshot());
        break;
      case _BrowserMenuAction.inspector:
        setState(() {
          _showInspector = !_showInspector;
        });
        if (_showInspector && _inspectorItems.isEmpty) {
          unawaited(_refreshInspectorCurrentMode());
        }
        break;
      case _BrowserMenuAction.recentActions:
        setState(() {
          _showRecentActions = !_showRecentActions;
        });
        break;
    }
  }

  Widget _buildHeader(ThemeData theme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 380;
        return ColoredBox(
          color: _panelHeaderBg,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                compact ? 10 : 12,
                10,
                compact ? 10 : 12,
                10,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTabStrip(theme, compact: compact),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildActionIcon(
                        icon: Icons.arrow_back,
                        tooltip: '后退',
                        enabled: _canGoBack,
                        onTap: () => unawaited(back()),
                      ),
                      _buildActionIcon(
                        icon: Icons.arrow_forward,
                        tooltip: '前进',
                        enabled: _canGoForward,
                        onTap: () => unawaited(forward()),
                      ),
                      _buildActionIcon(
                        icon: Icons.refresh,
                        tooltip: '刷新',
                        onTap: () => unawaited(_handleReloadButton()),
                      ),
                      const Spacer(),
                      _buildUaModeButton(compact: compact),
                      const SizedBox(width: 6),
                      _buildMoreMenu(compact: compact),
                      if (widget.onClose != null) ...[
                        const SizedBox(width: 6),
                        _buildActionIcon(
                          icon: Icons.close,
                          tooltip: '关闭',
                          onTap: widget.onClose,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 10),
                  _buildAddressBar(theme, compact: compact),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAddressSubmitButton({required bool compact}) {
    if (compact) {
      return IconButton.filled(
        tooltip: 'Open URL',
        onPressed: () => unawaited(_submitAddress()),
        icon: const Icon(Icons.arrow_forward, size: 18),
        style: IconButton.styleFrom(
          backgroundColor: AppColors.accent,
          foregroundColor: Colors.white,
          fixedSize: const Size(42, 42),
          minimumSize: const Size(42, 42),
          padding: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      );
    }
    return FilledButton.icon(
      onPressed: () => unawaited(_submitAddress()),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        backgroundColor: AppColors.accent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      icon: const Icon(Icons.arrow_forward, size: 16),
      label: const Text('打开'),
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
    String? tooltip,
  }) {
    return IconButton(
      tooltip: tooltip,
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 19),
      color: enabled ? _panelText : _panelDisabledText,
      visualDensity: VisualDensity.compact,
      style: IconButton.styleFrom(
        backgroundColor: enabled ? _panelSurface : _panelSurfaceAlt,
        fixedSize: const Size(38, 38),
        minimumSize: const Size(38, 38),
        padding: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: _panelBorder),
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

class _BrowserScriptLibrarySheet extends StatefulWidget {
  final BrowserAutomationService service;

  const _BrowserScriptLibrarySheet({
    required this.service,
  });

  @override
  State<_BrowserScriptLibrarySheet> createState() =>
      _BrowserScriptLibrarySheetState();
}

class _BrowserScriptLibrarySheetState
    extends State<_BrowserScriptLibrarySheet> {
  var _loading = true;
  var _saving = false;
  var _savingPending = false;
  var _clearingPending = false;
  var _error = '';
  String _runningId = '';
  String _deletingId = '';
  List<BrowserAutomationScript> _scripts = const <BrowserAutomationScript>[];
  List<BrowserUserScript> _userScripts = const <BrowserUserScript>[];
  BrowserAutomationScriptDraft? _pendingDraft;
  late final PageController _workspacePageController;
  var _workspaceIndex = 0;

  @override
  void initState() {
    super.initState();
    _workspacePageController = PageController();
    widget.service.addListener(_handleServiceChanged);
    unawaited(_loadScripts());
  }

  @override
  void dispose() {
    _workspacePageController.dispose();
    widget.service.removeListener(_handleServiceChanged);
    super.dispose();
  }

  void _handleServiceChanged() {
    final nextDraft = widget.service.pendingScriptDraft;
    if (identical(nextDraft, _pendingDraft) || !mounted) {
      return;
    }
    setState(() {
      _pendingDraft = nextDraft;
    });
  }

  Future<void> _loadScripts() async {
    setState(() {
      _loading = true;
      _error = '';
    });
    try {
      final scripts = await widget.service.loadScripts();
      final userScripts = await BrowserUserScriptLibraryService.loadScripts();
      if (!mounted) {
        return;
      }
      setState(() {
        _scripts = scripts;
        _userScripts = userScripts;
        _pendingDraft = widget.service.pendingScriptDraft;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _savePendingScript(BrowserAutomationScriptDraft draft) async {
    final result = await _showScriptEditDialog(
      title: '保存待保存脚本',
      fileName: draft.fileName,
      description: draft.description,
      confirmLabel: '保存',
    );
    if (result == null) {
      return;
    }
    setState(() {
      _savingPending = true;
    });
    try {
      final response = await widget.service.savePendingScript(
        fileName: result.fileName,
        description: result.description,
      );
      if (!mounted) {
        return;
      }
      _showSnack(
        response['ok'] == false
            ? response['message']?.toString() ?? '待保存脚本保存失败'
            : '待保存脚本已保存',
      );
      await _loadScripts();
    } finally {
      if (mounted) {
        setState(() {
          _savingPending = false;
        });
      }
    }
  }

  Future<void> _discardPendingScript() async {
    setState(() {
      _clearingPending = true;
    });
    try {
      final response = await widget.service.clearPendingScriptDraft();
      if (!mounted) {
        return;
      }
      _showSnack(
        response['ok'] == false
            ? response['message']?.toString() ?? '待保存脚本清除失败'
            : '待保存脚本已清除',
      );
      setState(() {
        _pendingDraft = widget.service.pendingScriptDraft;
      });
    } finally {
      if (mounted) {
        setState(() {
          _clearingPending = false;
        });
      }
    }
  }

  Future<void> _saveRecentScript() async {
    final result = await _showScriptEditDialog(
      title: '保存最近流程',
      fileName: _defaultScriptFileName(),
      description: '保存最近一次可复用的浏览器操作流程',
      confirmLabel: '保存',
    );
    if (result == null) {
      return;
    }
    setState(() {
      _saving = true;
    });
    try {
      final response = await widget.service.saveRecentScript(
        fileName: result.fileName,
        description: result.description,
      );
      if (!mounted) {
        return;
      }
      _showSnack(
        response['ok'] == false
            ? response['message']?.toString() ?? '脚本保存失败'
            : '脚本已保存',
      );
      await _loadScripts();
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _runScript(BrowserAutomationScript script) async {
    setState(() {
      _runningId = script.id;
    });
    try {
      final response = await widget.service.runScript(script.id);
      if (!mounted) {
        return;
      }
      _showSnack(
        response['ok'] == false
            ? response['message']?.toString() ?? '脚本运行失败'
            : '脚本运行完成',
      );
      await _loadScripts();
    } finally {
      if (mounted) {
        setState(() {
          _runningId = '';
        });
      }
    }
  }

  Future<void> _renameScript(BrowserAutomationScript script) async {
    final result = await _showScriptEditDialog(
      title: '重命名脚本',
      fileName: script.fileName,
      description: script.description,
      confirmLabel: '保存',
    );
    if (result == null) {
      return;
    }
    final response = await widget.service.renameScript(
      id: script.id,
      fileName: result.fileName,
      description: result.description,
    );
    if (!mounted) {
      return;
    }
    _showSnack(
      response['ok'] == false
          ? response['message']?.toString() ?? '脚本重命名失败'
          : '脚本已更新',
    );
    await _loadScripts();
  }

  Future<void> _deleteScript(BrowserAutomationScript script) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('删除脚本'),
          content: Text('确定删除 ${script.fileName}？'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('删除'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) {
      return;
    }
    setState(() {
      _deletingId = script.id;
    });
    try {
      final response = await widget.service.deleteScript(script.id);
      if (!mounted) {
        return;
      }
      _showSnack(
        response['ok'] == false
            ? response['message']?.toString() ?? '脚本删除失败'
            : '脚本已删除',
      );
      await _loadScripts();
    } finally {
      if (mounted) {
        setState(() {
          _deletingId = '';
        });
      }
    }
  }

  Future<void> _copyText(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    _showSnack('$label 已复制');
  }

  Future<_ScriptEditResult?> _showScriptEditDialog({
    required String title,
    required String fileName,
    required String description,
    required String confirmLabel,
  }) async {
    final fileController = TextEditingController(text: fileName);
    final descriptionController = TextEditingController(text: description);
    try {
      return await showDialog<_ScriptEditResult>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: Text(title),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: fileController,
                  decoration: const InputDecoration(
                    labelText: '文件名',
                    hintText: 'daily-login.browser.json',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descriptionController,
                  decoration: const InputDecoration(
                    labelText: '用处简介',
                    hintText: '说明这个脚本适合什么任务',
                  ),
                  minLines: 2,
                  maxLines: 4,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () {
                  final nextFileName = fileController.text.trim();
                  if (nextFileName.isEmpty) {
                    return;
                  }
                  Navigator.of(context).pop(
                    _ScriptEditResult(
                      fileName: nextFileName,
                      description: descriptionController.text.trim(),
                    ),
                  );
                },
                child: Text(confirmLabel),
              ),
            ],
          );
        },
      );
    } finally {
      fileController.dispose();
      descriptionController.dispose();
    }
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _defaultScriptFileName() {
    final now = DateTime.now();
    String two(int value) => value.toString().padLeft(2, '0');
    return 'browser-${now.year}${two(now.month)}${two(now.day)}-'
        '${two(now.hour)}${two(now.minute)}.browser.json';
  }

  String _formatDate(DateTime value) {
    String two(int number) => number.toString().padLeft(2, '0');
    final local = value.toLocal();
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final height = MediaQuery.sizeOf(context).height * 0.86;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: height),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    color: AppColors.accent.withAlpha(26),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.accent.withAlpha(110)),
                  ),
                  child: const Icon(
                    Icons.playlist_play,
                    size: 19,
                    color: AppColors.accent,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '浏览器脚本助手',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '左右滑动切换 Codex 自动化流程与传统网站脚本',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: Colors.white60,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '刷新',
                  onPressed: _loading ? null : () => unawaited(_loadScripts()),
                  icon: const Icon(Icons.refresh),
                ),
                IconButton(
                  tooltip: '关闭',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        _saving ? null : () => unawaited(_saveRecentScript()),
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_alt, size: 18),
                    label: const Text('保存最近流程'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_editUserScript()),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('新增传统脚本'),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => unawaited(_importUserScript()),
                  icon: const Icon(Icons.content_paste_go, size: 18),
                  label: const Text('导入'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: _buildWorkspaceTab(
                    icon: Icons.playlist_play,
                    label: 'Codex 自动化',
                    index: 0,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildWorkspaceTab(
                    icon: Icons.code,
                    label: '传统脚本',
                    index: 1,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.white.withAlpha(14)),
          Expanded(child: _buildBody(theme)),
        ],
      ),
    );
  }

  Widget _buildBody(ThemeData theme) {
    return PageView(
      controller: _workspacePageController,
      onPageChanged: (index) {
        setState(() {
          _workspaceIndex = index;
        });
      },
      children: [
        _buildAutomationBody(theme),
        _buildUserScriptsColumn(theme),
      ],
    );
  }

  Widget _buildWorkspaceTab({
    required IconData icon,
    required String label,
    required int index,
  }) {
    final selected = _workspaceIndex == index;
    final color = index == 0 ? AppColors.accent : const Color(0xFFFBBF24);
    return OutlinedButton.icon(
      onPressed: () {
        _workspacePageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      },
      style: OutlinedButton.styleFrom(
        foregroundColor: selected ? color : Colors.white70,
        backgroundColor: selected ? color.withAlpha(24) : Colors.transparent,
        side: BorderSide(color: selected ? color.withAlpha(150) : Colors.white24),
        padding: const EdgeInsets.symmetric(vertical: 10),
      ),
      icon: Icon(icon, size: 17),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    );
  }

  Widget _buildAutomationBody(ThemeData theme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Text(
            _error,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: AppColors.statusRed,
            ),
          ),
        ),
      );
    }
    if (_scripts.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (_pendingDraft != null) ...[
            _buildPendingDraftCard(theme, _pendingDraft!),
            const SizedBox(height: 10),
          ],
          _buildEmptyScriptsState(theme),
        ],
      );
    }

    final children = <Widget>[
      if (_pendingDraft != null) ...[
        _buildPendingDraftCard(theme, _pendingDraft!),
        const SizedBox(height: 10),
      ],
      for (var index = 0; index < _scripts.length; index++) ...[
        _buildScriptCard(theme, _scripts[index]),
        if (index != _scripts.length - 1) const SizedBox(height: 10),
      ],
    ];
    return ListView(
      padding: const EdgeInsets.all(12),
      children: children,
    );
  }

  Widget _buildUserScriptsColumn(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    return Container(
      color: Colors.white.withAlpha(3),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Row(
              children: [
                const Icon(Icons.code, size: 18, color: Color(0xFFFBBF24)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '传统网站脚本',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Text(
                  '${_userScripts.length}',
                  style: theme.textTheme.labelMedium?.copyWith(color: Colors.white60),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              '油猴风格 JavaScript。可新增、粘贴导入、由 Codex 生成后保存；运行前请审阅源码。',
              style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _userScripts.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(22),
                      child: Text(
                        '还没有传统脚本。使用“新增传统脚本”编写，或用“导入”粘贴现有油猴脚本。',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(color: Colors.white60),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _userScripts.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 10),
                    itemBuilder: (context, index) =>
                        _buildUserScriptCard(theme, _userScripts[index]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserScriptCard(ThemeData theme, BrowserUserScript script) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFBBF24).withAlpha(55)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(script.name, style: theme.textTheme.bodyMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
          if (script.description.isNotEmpty) ...[
            const SizedBox(height: 5),
            Text(script.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: Colors.white70)),
          ],
          const SizedBox(height: 6),
          Text(
            script.matches.isEmpty ? '*://*/*' : script.matches.join(', '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: const Color(0xFFFBBF24), fontFamily: 'monospace'),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton.icon(
                onPressed: () => unawaited(_runUserScript(script)),
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('运行当前页'),
              ),
              OutlinedButton.icon(
                onPressed: () => unawaited(_editUserScript(script: script)),
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('编辑'),
              ),
              OutlinedButton.icon(
                onPressed: () => unawaited(_copyText(script.code, '脚本源码')),
                icon: const Icon(Icons.content_copy, size: 16),
                label: const Text('复制源码'),
              ),
              OutlinedButton.icon(
                onPressed: () => unawaited(_copyText(script.codexPrompt, 'Codex 生成提示')),
                icon: const Icon(Icons.auto_awesome, size: 16),
                label: const Text('让 Codex 生成'),
              ),
              TextButton.icon(
                onPressed: () => unawaited(_deleteUserScript(script)),
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('删除'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _importUserScript() async {
    final sourceController = TextEditingController();
    final source = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('导入传统脚本'),
        content: SizedBox(
          width: 560,
          child: TextField(
            controller: sourceController,
            minLines: 10,
            maxLines: 18,
            decoration: const InputDecoration(
              labelText: '粘贴 Tampermonkey / JavaScript 源码',
              alignLabelWithHint: true,
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(context).pop(sourceController.text), child: const Text('继续')),
        ],
      ),
    );
    sourceController.dispose();
    if (source == null || source.trim().isEmpty) return;
    await _editUserScript(initialCode: source.trim());
  }

  Future<void> _editUserScript({BrowserUserScript? script, String initialCode = ''}) async {
    final nameController = TextEditingController(text: script?.name ?? '新建传统脚本');
    final descriptionController = TextEditingController(text: script?.description ?? '');
    final matchesController = TextEditingController(text: script?.matches.join('\n') ?? '*://*/*');
    final codeController = TextEditingController(text: script?.code ?? initialCode);
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(script == null ? '新增传统脚本' : '编辑传统脚本'),
        content: SizedBox(
          width: 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(controller: nameController, decoration: const InputDecoration(labelText: '脚本名称')),
                const SizedBox(height: 10),
                TextField(controller: descriptionController, decoration: const InputDecoration(labelText: '用途简介')),
                const SizedBox(height: 10),
                TextField(controller: matchesController, minLines: 2, maxLines: 4, decoration: const InputDecoration(labelText: '匹配规则（每行一条）', alignLabelWithHint: true)),
                const SizedBox(height: 10),
                TextField(controller: codeController, minLines: 10, maxLines: 18, decoration: const InputDecoration(labelText: 'JavaScript 源码', alignLabelWithHint: true)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('保存')),
        ],
      ),
    );
    if (shouldSave == true) {
      try {
        await BrowserUserScriptLibraryService.saveScript(
          id: script?.id,
          name: nameController.text,
          description: descriptionController.text,
          code: codeController.text,
          matches: matchesController.text.split(RegExp(r'\r?\n')),
        );
        if (mounted) _showSnack(script == null ? '传统脚本已保存' : '传统脚本已更新');
        await _loadScripts();
      } catch (error) {
        if (mounted) _showSnack('保存传统脚本失败：$error');
      }
    }
    nameController.dispose();
    descriptionController.dispose();
    matchesController.dispose();
    codeController.dispose();
  }

  Future<void> _runUserScript(BrowserUserScript script) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('运行传统脚本'),
        content: Text('将在当前页面执行“${script.name}”。请仅运行已审阅、可信的源码。'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('运行')),
        ],
      ),
    );
    if (confirmed != true) return;
    final response = await widget.service.runPageScript(script.code);
    if (mounted) _showSnack(response['ok'] == false ? response['message']?.toString() ?? '脚本运行失败' : '传统脚本已在当前页运行');
  }

  Future<void> _deleteUserScript(BrowserUserScript script) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除传统脚本'),
        content: Text('确定删除 ${script.name}？'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('删除')),
        ],
      ),
    );
    if (confirmed != true) return;
    await BrowserUserScriptLibraryService.deleteScript(script.id);
    if (mounted) _showSnack('传统脚本已删除');
    await _loadScripts();
  }

  Widget _buildEmptyScriptsState(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.topic_outlined,
            size: 42,
            color: Colors.white.withAlpha(90),
          ),
          const SizedBox(height: 12),
          Text(
            '还没有保存的浏览器脚本',
            style: theme.textTheme.titleSmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _pendingDraft == null
                ? '让 Codex 完成一次浏览器流程后，脚本助手会显示待保存的可复用脚本。'
                : '上方待保存脚本确认后会进入这里，之后可一键运行或复制快捷命令。',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white60,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPendingDraftCard(
    ThemeData theme,
    BrowserAutomationScriptDraft draft,
  ) {
    final meta = [
      '${draft.steps.length} 步',
      draft.autoGenerated ? '自动草稿' : 'Codex 草稿',
      '更新 ${_formatDate(draft.updatedAt)}',
    ].join(' · ');
    final disabled = _savingPending || _clearingPending;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFBBF24).withAlpha(12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFBBF24).withAlpha(90)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.pending_actions,
                size: 18,
                color: Color(0xFFFBBF24),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '待保存：${draft.fileName}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            draft.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withAlpha(115),
            ),
          ),
          if (draft.sourceUrl.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              draft.sourceUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFFFBBF24),
                fontFamily: 'monospace',
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton.icon(
                onPressed:
                    disabled ? null : () => unawaited(_savePendingScript(draft)),
                icon: _savingPending
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_alt, size: 16),
                label: const Text('保存/编辑'),
              ),
              OutlinedButton.icon(
                onPressed: disabled
                    ? null
                    : () => unawaited(
                          _copyText(draft.codexPrompt, '复用提示'),
                        ),
                icon: const Icon(Icons.content_copy, size: 16),
                label: const Text('复制提示'),
              ),
              TextButton.icon(
                onPressed:
                    disabled ? null : () => unawaited(_discardPendingScript()),
                icon: _clearingPending
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.clear, size: 16),
                label: const Text('丢弃'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildScriptCard(ThemeData theme, BrowserAutomationScript script) {
    final running = _runningId == script.id;
    final deleting = _deletingId == script.id;
    final disabled = running || deleting;
    final meta = [
      '${script.steps.length} 步',
      '运行 ${script.runCount} 次',
      '更新 ${_formatDate(script.updatedAt)}',
      if (script.lastRunAt != null) '最近运行 ${_formatDate(script.lastRunAt!)}',
    ].join(' · ');
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withAlpha(7),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withAlpha(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.description_outlined,
                size: 18,
                color: AppColors.accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  script.fileName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            script.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white70,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            meta,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: Colors.white.withAlpha(115),
            ),
          ),
          if (script.sourceUrl.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              script.sourceUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFFFBBF24),
                fontFamily: 'monospace',
              ),
            ),
          ],
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              FilledButton.icon(
                onPressed: disabled ? null : () => unawaited(_runScript(script)),
                icon: running
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow, size: 16),
                label: const Text('运行'),
              ),
              OutlinedButton.icon(
                onPressed:
                    disabled ? null : () => unawaited(_renameScript(script)),
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('重命名'),
              ),
              OutlinedButton.icon(
                onPressed: disabled
                    ? null
                    : () => unawaited(
                          _copyText(script.quickCommand, '快捷命令'),
                        ),
                icon: const Icon(Icons.terminal, size: 16),
                label: const Text('复制命令'),
              ),
              OutlinedButton.icon(
                onPressed: disabled
                    ? null
                    : () => unawaited(
                          _copyText(script.codexPrompt, 'Codex 提示词'),
                        ),
                icon: const Icon(Icons.content_copy, size: 16),
                label: const Text('复制提示'),
              ),
              TextButton.icon(
                onPressed:
                    disabled ? null : () => unawaited(_deleteScript(script)),
                icon: deleting
                    ? const SizedBox(
                        width: 15,
                        height: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline, size: 16),
                label: const Text('删除'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ScriptEditResult {
  final String fileName;
  final String description;

  const _ScriptEditResult({
    required this.fileName,
    required this.description,
  });
}
