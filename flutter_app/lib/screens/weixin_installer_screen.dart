import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../services/message_platform_config_service.dart';
import '../services/terminal_input_controller.dart';
import '../widgets/native_proot_terminal.dart';
import '../widgets/terminal_toolbar.dart';

class WeixinInstallerScreen extends StatefulWidget {
  const WeixinInstallerScreen({
    super.key,
    this.loginOnly = false,
  });

  final bool loginOnly;

  @override
  State<WeixinInstallerScreen> createState() => _WeixinInstallerScreenState();
}

class _WeixinInstallerScreenState extends State<WeixinInstallerScreen> {
  final _terminalKey = GlobalKey<NativeProotTerminalState>();
  late final TerminalInputController _terminalInput;
  bool _finished = false;
  int? _exitCode;
  var _generation = 0;
  String? _detectedUrl;
  StringBuffer _outputBuffer = StringBuffer();

  @override
  void initState() {
    super.initState();
    _terminalInput = TerminalInputController(
      onWrite: (bytes) {
        _terminalKey.currentState?.writeBytes(bytes);
      },
    );
  }

  @override
  void dispose() {
    _terminalInput.dispose();
    super.dispose();
  }

  String get _command => 'echo "=== OpenClaw Weixin Installer ===" && '
      'echo "The installer may show a QR code or a login link." && '
      'echo "Use the native terminal selection handles to copy links." && '
      'echo "The login flow will open directly in this terminal after plugin checks finish." && '
      'echo "" && '
      '${MessagePlatformConfigService.buildWeixinInstallerTerminalCommand(loginOnly: widget.loginOnly)}; '
      'echo "" && echo "Weixin installer finished. You can return now."';

  void _consumeOutput(String chunk) {
    if (chunk.isEmpty) {
      return;
    }
    _outputBuffer.write(chunk);
    final matches = RegExp(
      r'''https?://[^\s"'<>]+''',
    ).allMatches(_outputBuffer.toString()).toList();
    final match = matches.isEmpty ? null : matches.last;
    final url = match?.group(0);
    if (url == null || url == _detectedUrl) {
      return;
    }
    setState(() {
      _detectedUrl = url;
    });
  }

  Future<void> _openDetectedUrl() async {
    final url = _detectedUrl;
    if (url == null || url.isEmpty) {
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri == null) {
      return;
    }
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  void _restart() {
    setState(() {
      _finished = false;
      _exitCode = null;
      _generation++;
      _detectedUrl = null;
      _outputBuffer = StringBuffer();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.black,
        title: Text(l10n.t('messagePlatformDetailWeixinTerminalTitle')),
        actions: [
          IconButton(
            icon: const Icon(Icons.paste),
            tooltip: l10n.t('commonPaste'),
            onPressed: () => _terminalKey.currentState?.paste(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.t('commonRetry'),
            onPressed: _restart,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_detectedUrl != null)
            Container(
              width: double.infinity,
              color: const Color(0xFF111111),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Detected login link',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 6),
                  SelectableText(
                    _detectedUrl!,
                    style: const TextStyle(color: Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      FilledButton.tonal(
                        onPressed: _openDetectedUrl,
                        child: const Text('打开链接'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          Expanded(
            child: NativeProotTerminal(
              key: ValueKey('weixin-installer-$_generation'),
              sessionId: 'weixin-installer-$_generation',
              command: _command,
              keepAlive: true,
              emitOutput: true,
              onOutput: _consumeOutput,
              onSessionFinished: (exitCode) {
                if (mounted) {
                  setState(() {
                    _finished = true;
                    _exitCode = exitCode;
                  });
                }
              },
            ),
          ),
          TerminalToolbar(
            onWrite: _terminalInput.writeBytes,
            ctrlNotifier: _terminalInput.ctrlNotifier,
            altNotifier: _terminalInput.altNotifier,
          ),
          if (_finished)
            Padding(
              padding: const EdgeInsets.all(16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => Navigator.of(
                    context,
                  ).pop((_exitCode ?? 1) == 0),
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
