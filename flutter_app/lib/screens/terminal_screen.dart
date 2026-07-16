import 'dart:async';

import 'package:flutter/material.dart';

import '../services/browser_automation_service.dart';
import '../services/native_bridge.dart';
import '../services/terminal_service.dart';
import '../widgets/native_terminal_view.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/terminal_browser_panel.dart';

class TerminalScreen extends StatefulWidget {
  final String sessionId;
  final String title;
  final String? initialCommand;
  final bool restartOnOpen;

  const TerminalScreen({
    super.key,
    this.sessionId = 'shell',
    this.title = 'Terminal',
    this.initialCommand,
    this.restartOnOpen = false,
  });

  @override
  State<TerminalScreen> createState() => _TerminalScreenState();
}

class _TerminalScreenState extends State<TerminalScreen> {
  static const _defaultTerminalTranscriptRows = 3000;
  static const _codexTerminalTranscriptRows = 1200;
  static final Map<String, List<_TerminalSessionTab>> _savedSessions = {};
  static final Map<String, int> _savedActiveIndexes = {};

  var _terminalKey = GlobalKey<NativeTerminalViewState>();
  final _browserService = BrowserAutomationService.instance;
  late Future<_NativeTerminalConfig> _configFuture;
  late final List<_TerminalSessionTab> _sessions;
  var _activeIndex = 0;
  var _restartOnCreate = false;
  var _closedAllSessions = false;
  var _browserPanelOpen = false;
  var _lastBrowserPanelRequestNonce = 0;

  _TerminalSessionTab get _activeSession => _sessions[_activeIndex];

  bool get _isCodexSession {
    final command = widget.initialCommand?.toLowerCase() ?? '';
    return widget.sessionId.toLowerCase().contains('codex') ||
        widget.title.toLowerCase().contains('codex') ||
        command.contains('codex');
  }

  @override
  void initState() {
    super.initState();
    NativeBridge.startTerminalService().catchError((_) => false);
    NativeBridge.acquireTerminalSoftInputMode().catchError((_) => false);
    if (_isCodexSession) {
      _browserService.ensureStarted().catchError((_) => false);
      _browserService.addListener(_handleBrowserAutomationUpdate);
    }
    if (widget.restartOnOpen) {
      _savedSessions.remove(widget.sessionId);
      _savedActiveIndexes.remove(widget.sessionId);
    }
    final saved = _savedSessions[widget.sessionId];
    _sessions = saved != null && saved.isNotEmpty
        ? List<_TerminalSessionTab>.of(saved)
        : [_TerminalSessionTab(id: widget.sessionId, title: widget.title)];
    final savedIndex = _savedActiveIndexes[widget.sessionId] ?? 0;
    _activeIndex = savedIndex.clamp(0, _sessions.length - 1).toInt();
    _restartOnCreate = widget.restartOnOpen;
    _configFuture = _loadConfig();
  }

  Future<_NativeTerminalConfig> _loadConfig() async {
    final config = await TerminalService.getProotShellConfig();
    var args = TerminalService.buildProotArgs(config);
    final command = widget.initialCommand;
    if (command != null && command.trim().isNotEmpty) {
      args = TerminalService.replaceLoginShell(args, command);
    }
    return _NativeTerminalConfig(
      executable: config['executable']!,
      arguments: args,
      environment: TerminalService.buildHostEnv(config),
    );
  }

  @override
  void dispose() {
    if (!_closedAllSessions) {
      _persistSessionTabs();
    }
    unawaited(NativeBridge.releaseTerminalSoftInputMode().catchError((_) => false));
    if (_isCodexSession) {
      _browserService.removeListener(_handleBrowserAutomationUpdate);
    }
    super.dispose();
  }

  void _handleBrowserAutomationUpdate() {
    if (!mounted) {
      return;
    }
    final requestNonce = _browserService.panelRequestNonce;
    if (requestNonce == 0 || requestNonce == _lastBrowserPanelRequestNonce) {
      return;
    }
    _lastBrowserPanelRequestNonce = requestNonce;
    final screenWidth = MediaQuery.sizeOf(context).width;
    if (screenWidth >= 960 || _browserPanelOpen) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _browserPanelOpen) {
        return;
      }
      _openBrowserPanel(autoRequested: true);
    });
  }

  void _persistSessionTabs() {
    _savedSessions[widget.sessionId] = List<_TerminalSessionTab>.of(_sessions);
    _savedActiveIndexes[widget.sessionId] = _activeIndex;
  }

  void _restart() {
    setState(() {
      _restartOnCreate = true;
      _terminalKey = GlobalKey<NativeTerminalViewState>();
      _configFuture = _loadConfig();
    });
  }

  void _newSession() {
    final nextNumber = _sessions.length + 1;
    final nextSession = _TerminalSessionTab(
      id: '${widget.sessionId}-${DateTime.now().millisecondsSinceEpoch}',
      title: '${widget.title} $nextNumber',
    );
    setState(() {
      _sessions.add(nextSession);
      _activeIndex = _sessions.length - 1;
      _restartOnCreate = false;
      _terminalKey = GlobalKey<NativeTerminalViewState>();
      _configFuture = _loadConfig();
    });
    _persistSessionTabs();
  }

  void _switchSession(int index) {
    if (index == _activeIndex || index < 0 || index >= _sessions.length) {
      return;
    }
    setState(() {
      _activeIndex = index;
      _restartOnCreate = false;
      _terminalKey = GlobalKey<NativeTerminalViewState>();
      _configFuture = _loadConfig();
    });
    _persistSessionTabs();
  }

  Future<void> _paste() async {
    await _terminalKey.currentState?.paste();
  }

  Future<void> _closeSession() async {
    if (_browserPanelOpen) {
      setState(() {
        _browserPanelOpen = false;
      });
    }
    await _terminalKey.currentState?.close();
    if (!context.mounted) {
      return;
    }
    if (_sessions.length <= 1) {
      _savedSessions.remove(widget.sessionId);
      _savedActiveIndexes.remove(widget.sessionId);
      _closedAllSessions = true;
      Navigator.of(context).pop(true);
      return;
    }
    setState(() {
      _sessions.removeAt(_activeIndex);
      if (_activeIndex >= _sessions.length) {
        _activeIndex = _sessions.length - 1;
      }
      _restartOnCreate = false;
      _terminalKey = GlobalKey<NativeTerminalViewState>();
      _configFuture = _loadConfig();
    });
    _persistSessionTabs();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final compactActions = screenWidth < 420;
    final usesCompactBrowserPanel = _isCodexSession && screenWidth < 960;
    return PopScope<bool>(
      canPop: !usesCompactBrowserPanel || !_browserPanelOpen,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && usesCompactBrowserPanel && _browserPanelOpen) {
          _closeBrowserPanel();
        }
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        // Let the terminal route consume the real IME inset so the platform view
        // actually shrinks with the keyboard and keeps the native shortcut bar above it.
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          surfaceTintColor: Colors.black,
          toolbarHeight: compactActions ? 54 : 60,
          titleSpacing: compactActions ? 8 : 16,
          title: _buildTitle(),
          actions:
              compactActions ? [_buildOverflowMenu()] : _buildToolbarActions(),
        ),
        body: FutureBuilder<_NativeTerminalConfig>(
          future: _configFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return ColoredBox(
                color: Colors.black,
                child: ResponsiveLayout.scrollableCenter(
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text(
                        'Starting native terminal...',
                        style: TextStyle(color: Colors.white),
                      ),
                    ],
                  ),
                ),
              );
            }

            final error = snapshot.error;
            if (error != null || !snapshot.hasData) {
              return ColoredBox(
                color: Colors.black,
                child: ResponsiveLayout.scrollableCenter(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Colors.redAccent,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        error?.toString() ?? 'Failed to start terminal',
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.white),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _restart,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
              );
            }

            return _buildTerminal(snapshot.data!);
          },
        ),
      ),
    );
  }

  List<Widget> _buildToolbarActions() {
    return [
      if (_isCodexSession)
        IconButton(
          icon: const Icon(Icons.language),
          tooltip: 'Browser panel',
          onPressed: _openBrowserPanel,
        ),
      IconButton(
        icon: const Icon(Icons.add),
        tooltip: 'New session',
        onPressed: _newSession,
      ),
      _buildSessionMenu(),
      IconButton(
        icon: const Icon(Icons.paste),
        tooltip: 'Paste',
        onPressed: _paste,
      ),
      IconButton(
        icon: const Icon(Icons.refresh),
        tooltip: 'Restart',
        onPressed: _restart,
      ),
      IconButton(
        icon: const Icon(Icons.close),
        tooltip: 'Close session',
        onPressed: _closeSession,
      ),
    ];
  }

  Widget _buildOverflowMenu() {
    return PopupMenuButton<String>(
      tooltip: 'Actions',
      onSelected: (value) {
        if (value.startsWith('session:')) {
          _switchSession(int.parse(value.substring('session:'.length)));
          return;
        }
        switch (value) {
          case 'browser':
            _openBrowserPanel();
            break;
          case 'new':
            _newSession();
            break;
          case 'paste':
            _paste();
            break;
          case 'restart':
            _restart();
            break;
          case 'close':
            _closeSession();
            break;
        }
      },
      itemBuilder: (context) => [
        if (_isCodexSession) ...[
          const PopupMenuItem(value: 'browser', child: Text('Browser panel')),
          const PopupMenuDivider(),
        ],
        const PopupMenuItem(value: 'new', child: Text('New session')),
        const PopupMenuDivider(),
        for (var i = 0; i < _sessions.length; i++)
          PopupMenuItem(
            value: 'session:$i',
            child: Row(
              children: [
                Icon(
                  i == _activeIndex
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(_sessions[i].title)),
              ],
            ),
          ),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'paste', child: Text('Paste')),
        const PopupMenuItem(value: 'restart', child: Text('Restart')),
        const PopupMenuItem(value: 'close', child: Text('Close session')),
      ],
    );
  }

  Widget _buildSessionMenu() {
    return PopupMenuButton<int>(
      tooltip: 'Sessions',
      icon: const Icon(Icons.tab),
      onSelected: _switchSession,
      itemBuilder: (context) => [
        for (var i = 0; i < _sessions.length; i++)
          PopupMenuItem(
            value: i,
            child: Row(
              children: [
                Icon(
                  i == _activeIndex
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(_sessions[i].title)),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTitle() {
    final hasMultipleSessions = _sessions.length > 1;
    return Row(
      children: [
        Expanded(
          child: Text(
            _activeSession.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (hasMultipleSessions) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: Colors.white.withAlpha(22),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white24),
            ),
            child: Text(
              '${_activeIndex + 1}/${_sessions.length}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTerminal(_NativeTerminalConfig config) {
    final screenWidth = MediaQuery.of(context).size.width;
    final compactCodexBrowser = _isCodexSession && screenWidth < 960;
    final pauseTerminalRendering = compactCodexBrowser && _browserPanelOpen;

    final terminal = Column(
      children: [
        if (_isCodexSession) _buildBrowserStatusBanner(screenWidth),
        Expanded(
          child: NativeTerminalView(
            key: _terminalKey,
            sessionId: _activeSession.id,
            executable: config.executable,
            arguments: config.arguments,
            environment: config.environment,
            restart: _restartOnCreate,
            keepAlive: true,
            renderingPaused: pauseTerminalRendering,
            useNativeToolbar: true,
            transcriptRows: _isCodexSession
                ? _codexTerminalTranscriptRows
                : _defaultTerminalTranscriptRows,
            fontSize: 18,
          ),
        ),
      ],
    );

    if (!_isCodexSession) {
      return terminal;
    }

    if (screenWidth < 960) {
      return _buildCompactBrowserLayout(
        terminal: terminal,
        screenWidth: screenWidth,
      );
    }

    final browserWidth = screenWidth >= 1320 ? 520.0 : 420.0;
    return Row(
      children: [
        Expanded(child: terminal),
        SizedBox(
          width: browserWidth,
          child: const TerminalBrowserPanel(),
        ),
      ],
    );
  }

  void _openBrowserPanel({bool autoRequested = false}) {
    if (!_isCodexSession) {
      return;
    }
    final screenWidth = MediaQuery.sizeOf(context).width;
    if (screenWidth >= 960) {
      if (!autoRequested) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Browser panel is already visible on the right side.'),
          ),
        );
      }
      return;
    }

    if (_browserPanelOpen) {
      return;
    }
    setState(() {
      _browserPanelOpen = true;
    });
  }

  void _closeBrowserPanel() {
    if (!_browserPanelOpen) {
      return;
    }
    setState(() {
      _browserPanelOpen = false;
    });
  }

  Widget _buildCompactBrowserLayout({
    required Widget terminal,
    required double screenWidth,
  }) {
    final panelWidth = _browserPanelWidth(screenWidth);
    const shouldKeepBrowserMounted = true;

    return Stack(
      children: [
        Positioned.fill(child: terminal),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_browserPanelOpen,
            child: AnimatedOpacity(
              opacity: _browserPanelOpen ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeBrowserPanel,
                child: Container(color: Colors.black54),
              ),
            ),
          ),
        ),
        if (shouldKeepBrowserMounted)
          Positioned(
            top: 0,
            bottom: 0,
            right: 0,
            width: panelWidth,
            child: IgnorePointer(
              ignoring: !_browserPanelOpen,
              child: AnimatedSlide(
                offset: _browserPanelOpen ? Offset.zero : const Offset(1, 0),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: RepaintBoundary(
                  child: _buildPersistentBrowserPanel(),
                ),
              ),
            ),
          ),
        if (!_browserPanelOpen)
          Positioned(
            top: 0,
            right: 0,
            bottom: 0,
            width: 24,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity < -180) {
                  _openBrowserPanel();
                }
              },
            ),
          ),
      ],
    );
  }

  double _browserPanelWidth(double screenWidth) {
    final width = screenWidth < 600 ? screenWidth * 0.94 : 560.0;
    return width > screenWidth ? screenWidth : width;
  }

  Widget _buildPersistentBrowserPanel() {
    return Material(
      color: Colors.black,
      elevation: 12,
      child: Stack(
        children: [
          TerminalBrowserPanel(
            onClose: _closeBrowserPanel,
            visible: _browserPanelOpen,
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 18,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragEnd: (details) {
                final velocity = details.primaryVelocity ?? 0;
                if (velocity > 180) {
                  _closeBrowserPanel();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBrowserStatusBanner(double screenWidth) {
    final service = BrowserAutomationService.instance;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final attached = service.isBrowserAttached;
        final active = service.isToolCallActive;
        final compact = screenWidth < 560;
        final canOpenPanel = screenWidth < 960;

        late final IconData icon;
        late final Color color;
        late final String title;
        late final String subtitle;

        if (active) {
          icon = Icons.auto_awesome;
          color = const Color(0xFFDC2626);
          title = 'Codex 正在操作浏览器';
          subtitle = service.lastToolName.isEmpty
              ? '等待浏览器动作完成'
              : '当前动作: ${service.lastToolName}';
        } else if (attached) {
          icon = Icons.language;
          color = const Color(0xFF22C55E);
          title = '浏览器已连接';
          subtitle = service.currentUrl.isNotEmpty
              ? service.currentUrl
              : 'Codex 可以直接使用浏览器工具';
        } else {
          icon = Icons.link_off;
          color = const Color(0xFFF59E0B);
          title = '浏览器未连接';
          subtitle = screenWidth >= 960
              ? '右侧面板打开网页后，Codex 才能控制浏览器'
              : '点右上角浏览器按钮，先打开浏览器面板';
        }

        return Container(
          width: double.infinity,
          padding: EdgeInsets.fromLTRB(
            compact ? 10 : 12,
            10,
            compact ? 10 : 12,
            10,
          ),
          decoration: BoxDecoration(
            color: Colors.black,
            border: Border(
              bottom: BorderSide(color: Colors.white.withAlpha(18)),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: compact ? 32 : 36,
                height: compact ? 32 : 36,
                decoration: BoxDecoration(
                  color: color.withAlpha(30),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: color.withAlpha(120)),
                ),
                child: Icon(icon, color: color, size: compact ? 16 : 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: compact ? 12 : 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white60,
                        fontSize: compact ? 11 : 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                onPressed: canOpenPanel ? _openBrowserPanel : null,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.white,
                  side: BorderSide(color: color.withAlpha(150)),
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 10 : 12,
                    vertical: 8,
                  ),
                ),
                child: Text(
                  canOpenPanel ? (attached ? '查看' : '打开') : '右侧已显示',
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _NativeTerminalConfig {
  final String executable;
  final List<String> arguments;
  final Map<String, String> environment;

  const _NativeTerminalConfig({
    required this.executable,
    required this.arguments,
    required this.environment,
  });
}

class _TerminalSessionTab {
  final String id;
  final String title;

  const _TerminalSessionTab({
    required this.id,
    required this.title,
  });
}
