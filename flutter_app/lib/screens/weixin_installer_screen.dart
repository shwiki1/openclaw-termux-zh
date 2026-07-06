import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_pty/flutter_pty.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:xterm/xterm.dart';

import '../l10n/app_localizations.dart';
import '../services/message_platform_config_service.dart';
import '../services/native_bridge.dart';
import '../services/screenshot_service.dart';
import '../services/terminal_output_buffer.dart';
import '../services/terminal_service.dart';
import '../widgets/terminal_toolbar.dart';
import '../widgets/native_terminal_view.dart';

/// Runs the Weixin installer command in an interactive terminal so the user
/// can scan the QR code or open the login link shown by the installer.
class WeixinInstallerScreen extends StatefulWidget {
  const WeixinInstallerScreen({super.key});

  @override
  State<WeixinInstallerScreen> createState() => _WeixinInstallerScreenState();
}

class _WeixinInstallerScreenState extends State<WeixinInstallerScreen> {
  late final Terminal _terminal;
  late final TerminalController _controller;
  late final TerminalOutputBuffer _outputBuffer;
  Pty? _pty;
  bool _loading = true;
  bool _finished = false;
  String? _error;
  final _ctrlNotifier = ValueNotifier<bool>(false);
  final _altNotifier = ValueNotifier<bool>(false);
  final _nativeTerminalKey = GlobalKey<NativeTerminalViewState>();
  final _screenshotKey = GlobalKey();

  static final _anyUrlRegex = RegExp(r'https?://[^\s<>\[\]"' "'" r'\)]+');
  static final _boxDrawing = RegExp(r'[\u2500-\u257F\u25C6\u25C7]+');
  @override
  void initState() {
    super.initState();
    _terminal = Terminal(maxLines: terminalScrollbackLines);
    _outputBuffer = TerminalOutputBuffer(_terminal);
    _controller = TerminalController();
    NativeBridge.startTerminalService();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startInstaller();
    });
  }

  Future<void> _startInstaller() async {
    _outputBuffer.flush();
    _pty?.kill();
    _pty = null;
    try {
      final config = await TerminalService.getProotShellConfig();
      final args = TerminalService.buildProotArgs(
        config,
        columns: _terminal.viewWidth,
        rows: _terminal.viewHeight,
      );

      final installerArgs = List<String>.from(args);
      installerArgs.removeLast();
      installerArgs.removeLast();
      installerArgs.addAll([
        '/bin/bash',
        '-lc',
        'echo "=== OpenClaw Weixin Installer ===" && '
            'echo "The installer may show a QR code or a login link." && '
            'echo "You can take a screenshot, tap a link, or copy it from the terminal." && '
            'echo "" && '
            '${MessagePlatformConfigService.weixinInstallerCommand}; '
            'echo "" && echo "Weixin installer finished. You can return now."',
      ]);

      _pty = Pty.start(
        config['executable']!,
        arguments: installerArgs,
        environment: TerminalService.buildHostEnv(config),
        columns: _terminal.viewWidth,
        rows: _terminal.viewHeight,
      );

      _pty!.output.cast<List<int>>().listen((data) {
        final text = utf8.decode(data, allowMalformed: true);
        _outputBuffer.write(text);
      });

      _pty!.exitCode.then((code) {
        _outputBuffer.write('\r\n[Process exited with code $code]\r\n');
        _outputBuffer.flush();
        if (mounted) {
          setState(() => _finished = true);
        }
      });

      _terminal.onOutput = (data) {
        if (_ctrlNotifier.value && data.length == 1) {
          final code = data.toLowerCase().codeUnitAt(0);
          if (code >= 97 && code <= 122) {
            _pty?.write(Uint8List.fromList([code - 96]));
            _ctrlNotifier.value = false;
            return;
          }
        }
        if (_altNotifier.value && data.isNotEmpty) {
          _pty?.write(utf8.encode('\x1b$data'));
          _altNotifier.value = false;
          return;
        }
        _pty?.write(utf8.encode(data));
      };

      _terminal.onResize = (w, h, pw, ph) {
        _pty?.resize(h, w);
      };

      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.l10n.t(
          'messagePlatformDetailWeixinTerminalFailed',
          {'error': '$e'},
        );
      });
    }
  }

  @override
  void dispose() {
    _ctrlNotifier.dispose();
    _altNotifier.dispose();
    _controller.dispose();
    _outputBuffer.dispose();
    _pty?.kill();
    NativeBridge.stopTerminalService();
    super.dispose();
  }

  String? _getSelectedText() {
    final selection = _controller.selection;
    if (selection == null || selection.isCollapsed) return null;

    final range = selection.normalized;
    final sb = StringBuffer();
    for (int y = range.begin.y; y <= range.end.y; y++) {
      if (y >= _terminal.buffer.lines.length) break;
      final line = _terminal.buffer.lines[y];
      final from = y == range.begin.y ? range.begin.x : 0;
      final to = y == range.end.y ? range.end.x : null;
      sb.write(line.getText(from, to));
      if (y < range.end.y) sb.writeln();
    }
    final text = sb.toString().trim();
    return text.isEmpty ? null : text;
  }

  String? _extractUrl(String text) {
    final clean =
        text.replaceAll(_boxDrawing, '').replaceAll(RegExp(r'\s+'), '');
    final parts = clean.split(RegExp(r'(?=https?://)'));
    String? best;
    for (final part in parts) {
      final match = _anyUrlRegex.firstMatch(part);
      if (match != null) {
        final url = match.group(0)!;
        if (best == null || url.length > best.length) {
          best = url;
        }
      }
    }
    return best;
  }

  Future<String?> _getPreferredSelectedText() async {
    return await _nativeTerminalKey.currentState?.getSelectedText() ??
        _getSelectedText();
  }

  Future<void> _copySelection() async {
    final text = await _getPreferredSelectedText();
    if (!mounted) return;
    if (text == null) return;

    Clipboard.setData(ClipboardData(text: text));
    final url = _extractUrl(text);
    if (url != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.t('commonCopiedToClipboard')),
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: context.l10n.t('commonOpen'),
            onPressed: () {
              final uri = Uri.tryParse(url);
              if (uri != null) {
                launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.t('commonCopiedToClipboard')),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _openSelection() async {
    final text = await _getPreferredSelectedText();
    if (!mounted) return;
    if (text == null) return;

    final url = _extractUrl(text);
    if (url != null) {
      final uri = Uri.tryParse(url);
      if (uri != null) {
        launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.t('commonNoUrlFound')),
        duration: const Duration(seconds: 1),
      ),
    );
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      _pty?.write(utf8.encode(data.text!));
    }
  }

  Future<void> _takeScreenshot() async {
    final path =
        await ScreenshotService.capture(_screenshotKey, prefix: 'weixin');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          path != null
              ? context.l10n.t('commonScreenshotSaved', {
                  'fileName': path.split('/').last,
                })
              : context.l10n.t('commonSaveFailed'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.t('messagePlatformDetailWeixinTerminalTitle')),
        actions: [
          IconButton(
            icon: const Icon(Icons.camera_alt_outlined),
            tooltip: l10n.t('commonScreenshot'),
            onPressed: _takeScreenshot,
          ),
          IconButton(
            icon: const Icon(Icons.copy),
            tooltip: l10n.t('commonCopy'),
            onPressed: () => unawaited(_copySelection()),
          ),
          IconButton(
            icon: const Icon(Icons.open_in_browser),
            tooltip: l10n.t('commonOpen'),
            onPressed: () => unawaited(_openSelection()),
          ),
          IconButton(
            icon: const Icon(Icons.paste),
            tooltip: l10n.t('commonPaste'),
            onPressed: _paste,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loading)
            Expanded(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(l10n.t('messagePlatformDetailWeixinTerminalStarting')),
                  ],
                ),
              ),
            )
          else if (_error != null)
            Expanded(
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.error_outline,
                        size: 48,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: () {
                          setState(() {
                            _loading = true;
                            _error = null;
                            _finished = false;
                          });
                          _startInstaller();
                        },
                        icon: const Icon(Icons.refresh),
                        label: Text(l10n.t('commonRetry')),
                      ),
                    ],
                  ),
                ),
              ),
            )
          else ...[
            Expanded(
              child: RepaintBoundary(
                key: _screenshotKey,
                child: NativeTerminalView(
                  key: _nativeTerminalKey,
                  terminal: _terminal,
                ),
              ),
            ),
            TerminalToolbar(
              pty: _pty,
              ctrlNotifier: _ctrlNotifier,
              altNotifier: _altNotifier,
            ),
          ],
          if (_finished)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.check),
                  label: Text(l10n.t('commonDone')),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
