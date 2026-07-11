import 'dart:async';

import 'package:flutter/material.dart';

import '../models/cli_tool.dart';
import '../services/terminal_input_controller.dart';
import '../widgets/native_proot_terminal.dart';
import '../widgets/terminal_toolbar.dart';

class CliToolInstallResult {
  final CliToolDefinition tool;
  final int exitCode;
  final String output;

  const CliToolInstallResult({
    required this.tool,
    required this.exitCode,
    required this.output,
  });

  bool get success => exitCode == 0;

  String get outputTail {
    final lines = output
        .split('\n')
        .map((line) => line.trimRight())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.length <= 12) {
      return lines.join('\n');
    }
    return lines.sublist(lines.length - 12).join('\n');
  }
}

class CliToolInstallScreen extends StatefulWidget {
  final CliToolDefinition tool;

  const CliToolInstallScreen({
    super.key,
    required this.tool,
  });

  @override
  State<CliToolInstallScreen> createState() => _CliToolInstallScreenState();
}

class _CliToolInstallScreenState extends State<CliToolInstallScreen> {
  var _terminalKey = GlobalKey<NativeProotTerminalState>();
  final _outputLines = <String>[];
  late final TerminalInputController _terminalInput;
  var _generation = 0;
  var _completed = false;

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

  void _restart() {
    setState(() {
      _terminalKey = GlobalKey<NativeProotTerminalState>();
      _generation++;
      _completed = false;
      _outputLines.clear();
    });
  }

  void _captureOutput(String chunk) {
    final lines = chunk.replaceAll('\r\n', '\n').split('\n');
    for (final line in lines) {
      if (line.isEmpty) continue;
      _outputLines.add(line);
    }
    if (_outputLines.length > 240) {
      _outputLines.removeRange(0, _outputLines.length - 240);
    }
  }

  Future<void> _finish(int exitCode) async {
    if (_completed || !mounted) return;
    _completed = true;
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (!mounted) return;
    Navigator.of(context).pop(
      CliToolInstallResult(
        tool: widget.tool,
        exitCode: exitCode,
        output: _outputLines.join('\n'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Close',
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: Text('安装 ${widget.tool.name}'),
        actions: [
          IconButton(
            icon: const Icon(Icons.paste),
            tooltip: 'Paste',
            onPressed: () => _terminalKey.currentState?.paste(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Restart',
            onPressed: _restart,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: NativeProotTerminal(
              key: _terminalKey,
              sessionId: 'cli-install-${widget.tool.id}-$_generation',
              command: widget.tool.installCommand,
              keepAlive: true,
              restart: true,
              emitOutput: true,
              onOutput: _captureOutput,
              onSessionFinished: _finish,
            ),
          ),
          TerminalToolbar(
            onWrite: _terminalInput.writeBytes,
            ctrlNotifier: _terminalInput.ctrlNotifier,
            altNotifier: _terminalInput.altNotifier,
          ),
        ],
      ),
    );
  }
}
