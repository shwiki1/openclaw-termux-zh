import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../services/local_api_proxy_service.dart';

class LocalApiProxyBrowserScreen extends StatefulWidget {
  const LocalApiProxyBrowserScreen({super.key});

  @override
  State<LocalApiProxyBrowserScreen> createState() =>
      _LocalApiProxyBrowserScreenState();
}

class _LocalApiProxyBrowserScreenState
    extends State<LocalApiProxyBrowserScreen> {
  late final WebViewController _controller;
  late final TextEditingController _addressController;
  bool _loading = true;
  bool _canGoBack = false;
  bool _canGoForward = false;
  String _serviceMessage = '正在连接本地中转代理...';

  @override
  void initState() {
    super.initState();
    _addressController = TextEditingController(text: LocalApiProxyService.url);
    _controller = _createController();
    unawaited(_openManagerWhenReady());
  }

  @override
  void dispose() {
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _openManagerWhenReady() async {
    setState(() {
      _loading = true;
      _serviceMessage = '正在检查本地中转代理...';
    });
    var status = await LocalApiProxyService.status();
    if (!status.manageable) {
      setState(() => _serviceMessage = '正在启动本地中转代理...');
      try {
        await LocalApiProxyService.start();
      } catch (error) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _serviceMessage = '启动失败：$error';
        });
        return;
      }
      status = await LocalApiProxyService.status();
    }
    if (!mounted) return;
    if (!status.manageable) {
      setState(() {
        _loading = false;
        _serviceMessage = status.message;
      });
      return;
    }
    setState(() => _serviceMessage = status.message);
    await _controller.loadRequest(Uri.parse(LocalApiProxyService.url));
  }

  WebViewController _createController() {
    const params = PlatformWebViewControllerCreationParams();
    final controller = WebViewController.fromPlatformCreationParams(params)
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(Colors.transparent)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (url) {
            if (!mounted) return;
            setState(() {
              _loading = true;
              _addressController.text = url;
            });
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

  Future<void> _openAddress() async {
    final raw = _addressController.text.trim();
    if (raw.isEmpty) return;
    final url = raw.contains('://') ? raw : 'http://$raw';
    await _controller.loadRequest(Uri.parse(url));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('中转代理管理')),
      body: Column(
        children: [
          Material(
            color: theme.colorScheme.surface,
            elevation: 1,
            child: SafeArea(
              top: false,
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
                child: Row(
                  children: [
                    IconButton.filledTonal(
                      tooltip: '后退',
                      onPressed: _canGoBack ? () => _controller.goBack() : null,
                      icon: const Icon(Icons.arrow_back),
                    ),
                    const SizedBox(width: 4),
                    IconButton.filledTonal(
                      tooltip: '前进',
                      onPressed:
                          _canGoForward ? () => _controller.goForward() : null,
                      icon: const Icon(Icons.arrow_forward),
                    ),
                    const SizedBox(width: 4),
                    IconButton.filledTonal(
                      tooltip: '刷新',
                      onPressed: () => _controller.reload(),
                      icon: _loading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.refresh),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _addressController,
                        keyboardType: TextInputType.url,
                        textInputAction: TextInputAction.go,
                        minLines: 1,
                        maxLines: 1,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          hintText: 'http://127.0.0.1:9999/',
                        ),
                        onSubmitted: (_) => _openAddress(),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_serviceMessage.isNotEmpty)
            Material(
              color: theme.colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    Icon(
                      _serviceMessage.contains('正常')
                          ? Icons.check_circle_outline
                          : Icons.info_outline,
                      size: 16,
                      color: _serviceMessage.contains('正常')
                          ? Colors.green
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _serviceMessage,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
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
                      ),
                    ),
                  )
                : WebViewWidget(controller: _controller),
          ),
        ],
      ),
    );
  }
}
