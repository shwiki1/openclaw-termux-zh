import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

class NativeTerminalView extends StatefulWidget {
  final Terminal terminal;

  const NativeTerminalView({
    super.key,
    required this.terminal,
  });

  @override
  State<NativeTerminalView> createState() => _NativeTerminalViewState();
}

class _NativeTerminalViewState extends State<NativeTerminalView> {
  late final String _viewId;
  MethodChannel? _channel;
  Timer? _timer;
  String _lastText = '';

  @override
  void initState() {
    super.initState();
    _viewId = 'terminal_${identityHashCode(this)}';
    _timer = Timer.periodic(
      const Duration(milliseconds: 180),
      (_) => _syncText(),
    );
  }

  @override
  void didUpdateWidget(covariant NativeTerminalView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.terminal != widget.terminal) {
      _lastText = '';
      _syncText();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _channel = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (defaultTargetPlatform != TargetPlatform.android) {
      return _FallbackSelectableTerminal(text: _snapshotText());
    }
    return AndroidView(
      viewType: 'com.openclaw.cyx/native_terminal',
      creationParams: {'viewId': _viewId},
      creationParamsCodec: const StandardMessageCodec(),
      onPlatformViewCreated: (_) {
        _channel = MethodChannel('com.openclaw.cyx/native_terminal/$_viewId');
        _syncText(force: true);
      },
    );
  }

  Future<void> _syncText({bool force = false}) async {
    final channel = _channel;
    if (channel == null) return;
    final text = _snapshotText();
    if (!force && text == _lastText) return;
    _lastText = text;
    try {
      await channel.invokeMethod('setText', {'text': text});
    } catch (_) {
      // The Android view can be disposed while an async sync is in flight.
    }
  }

  String _snapshotText() {
    final sb = StringBuffer();
    for (int i = 0; i < widget.terminal.buffer.lines.length; i++) {
      final line = widget.terminal.buffer.lines[i];
      sb.writeln(line.getText().trimRight());
    }
    return sb.toString().trimRight();
  }
}

class _FallbackSelectableTerminal extends StatelessWidget {
  final String text;

  const _FallbackSelectableTerminal({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF060A12),
      width: double.infinity,
      height: double.infinity,
      padding: const EdgeInsets.all(10),
      child: SingleChildScrollView(
        child: SelectableText(
          text,
          style: const TextStyle(
            color: Color(0xFFE6EDF3),
            fontFamily: 'monospace',
            fontSize: 11,
            height: 1.0,
          ),
        ),
      ),
    );
  }
}
