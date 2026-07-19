import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../services/local_api_proxy_service.dart';
import '../services/native_bridge.dart';

class LocalApiProxyBrowserScreen extends StatefulWidget {
  const LocalApiProxyBrowserScreen({super.key});

  @override
  State<LocalApiProxyBrowserScreen> createState() =>
      _LocalApiProxyBrowserScreenState();
}

class _LocalApiProxyBrowserScreenState
    extends State<LocalApiProxyBrowserScreen>
    with AutomaticKeepAliveClientMixin<LocalApiProxyBrowserScreen> {
  late final WebViewController _controller;
  late final TextEditingController _addressController;
  bool _loading = true;
  bool _canGoBack = false;
  bool _canGoForward = false;
  String _serviceMessage = '正在连接本地中转代理...';
  static const _background = Color(0xFF0A0E17);
  static const _surface2 = Color(0xFF1A2235);
  static const _border = Color(0xFF1E293B);
  static const _ink = Color(0xFFE2E8F0);
  static const _ink2 = Color(0xFF94A3B8);
  static const _accent = Color(0xFF60A5FA);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _addressController = TextEditingController(text: LocalApiProxyService.url);
    _controller = _createController();
    unawaited(NativeBridge.acquireBrowserSoftInputMode());
    unawaited(_openManagerWhenReady());
  }

  @override
  void dispose() {
    unawaited(NativeBridge.releaseBrowserSoftInputMode());
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _openManagerWhenReady() async {
    _updateServiceState(loading: true, message: '正在检查本地中转代理...');
    var status = await LocalApiProxyService.status();
    if (!status.manageable) {
      _updateServiceState(message: '正在启动本地中转代理...');
      try {
        await LocalApiProxyService.start();
      } catch (error) {
        if (!mounted) return;
        _updateServiceState(loading: false, message: '启动失败：$error');
        return;
      }
      status = await LocalApiProxyService.status();
    }
    if (!mounted) return;
    if (!status.manageable) {
      _updateServiceState(loading: false, message: status.message);
      return;
    }
    _updateServiceState(message: status.message);
    await _controller.loadRequest(Uri.parse(LocalApiProxyService.url));
  }

  WebViewController _createController() {
    const params = PlatformWebViewControllerCreationParams();
    final controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(_background)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted) return;
            _updateNavigationState(loading: true, url: url);
          },
          onPageFinished: (url) async {
            await _syncNavigationState(url);
          },
          onWebResourceError: (_) async {
            await _syncNavigationState(_addressController.text);
          },
        ),
      );
    final platformController = controller.platform;
    if (platformController is AndroidWebViewController) {
      unawaited(platformController.setMediaPlaybackRequiresUserGesture(false));
      AndroidWebViewController.enableDebugging(false);
    }
    return controller;
  }

  Future<void> _syncNavigationState(String url) async {
    if (!mounted) return;
    final canGoBack = await _controller.canGoBack();
    final canGoForward = await _controller.canGoForward();
    if (!mounted) return;
    setState(() {
      _loading = false;
      _canGoBack = canGoBack;
      _canGoForward = canGoForward;
      _addressController.text = url;
    });
  }

  void _updateServiceState({bool? loading, String? message}) {
    if (!mounted) return;
    final nextLoading = loading ?? _loading;
    final nextMessage = message ?? _serviceMessage;
    if (nextLoading == _loading && nextMessage == _serviceMessage) {
      return;
    }
    setState(() {
      _loading = nextLoading;
      _serviceMessage = nextMessage;
    });
  }

  void _updateNavigationState({bool? loading, String? url}) {
    if (!mounted) return;
    final nextLoading = loading ?? _loading;
    final nextUrl = url ?? _addressController.text;
    if (nextLoading == _loading && nextUrl == _addressController.text) {
      return;
    }
    setState(() {
      _loading = nextLoading;
      _addressController.text = nextUrl;
    });
  }

  Future<void> _openAddress() async {
    final raw = _addressController.text.trim();
    if (raw.isEmpty) return;
    final url = raw.contains('://') ? raw : 'http://$raw';
    await _controller.loadRequest(Uri.parse(url));
  }

  Widget _buildWebView() {
    final platformController = _controller.platform;
    if (platformController is AndroidWebViewController) {
      final params = AndroidWebViewWidgetCreationParams(
        controller: platformController,
        displayWithHybridComposition: false,
      );
      return WebViewWidget.fromPlatformCreationParams(params: params);
    }
    return WebViewWidget(controller: _controller);
  }

  bool get _serviceOk =>
      _serviceMessage.contains('正常') || _serviceMessage.contains('响应');

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: _background,
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text(
          '中转代理管理',
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: _background,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: Column(
        children: [
          Material(
            color: _background,
            child: SafeArea(
              top: false,
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _addressController,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.go,
                        minLines: 1,
                        maxLines: 1,
                        style: const TextStyle(
                          fontFamily: 'monospace',
                          color: _ink,
                          fontSize: 13,
                        ),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: _background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _border),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _border),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(color: _accent),
                          ),
                          hintText: 'http://127.0.0.1:9999/',
                          hintStyle: const TextStyle(color: _ink2),
                        ),
                        onSubmitted: (_) => _openAddress(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      constraints: const BoxConstraints(maxWidth: 128),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 7,
                      ),
                      decoration: BoxDecoration(
                        color: _serviceOk
                            ? Colors.green.withAlpha(28)
                            : _surface2,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _serviceOk
                              ? Colors.green.withAlpha(120)
                              : _border,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _serviceOk
                                ? Icons.check_circle_outline
                                : Icons.info_outline,
                            size: 14,
                            color: _serviceOk ? Colors.greenAccent : _ink2,
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: Text(
                              _serviceOk ? '正常' : _serviceMessage,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: _ink2,
                                fontSize: 11,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: _serviceMessage.startsWith('启动失败') ||
                    _serviceMessage.contains('未响应') ||
                    _serviceMessage.contains('异常') ||
                    _serviceMessage.contains('缺失')
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: SelectableText(
                        _serviceMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: _ink),
                      ),
                    ),
                  )
                : _buildWebView(),
          ),
          SafeArea(
            top: false,
            child: Material(
              color: _background,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Center(
                        child: _bottomButton(
                          tooltip: '后退',
                          onPressed: _canGoBack
                              ? () => _controller.goBack()
                              : null,
                          icon: Icons.arrow_back,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: _bottomButton(
                          tooltip: '前进',
                          onPressed: _canGoForward
                              ? () => _controller.goForward()
                              : null,
                          icon: Icons.arrow_forward,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Center(
                        child: _bottomButton(
                          tooltip: '刷新',
                          onPressed: () => _controller.reload(),
                          icon: Icons.refresh,
                          loading: _loading,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _bottomButton({
    required String tooltip,
    required VoidCallback? onPressed,
    required IconData icon,
    bool loading = false,
  }) {
    return Tooltip(
      message: tooltip,
      child: SizedBox(
        width: 48,
        height: 40,
        child: FilledButton.tonal(
          style: FilledButton.styleFrom(
            padding: EdgeInsets.zero,
            backgroundColor: _surface2,
            foregroundColor: _ink,
            disabledBackgroundColor: _surface2.withAlpha(120),
            disabledForegroundColor: _ink2.withAlpha(120),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: const BorderSide(color: _border),
            ),
          ),
          onPressed: onPressed,
          child: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icon, size: 20),
        ),
      ),
    );
  }
}
