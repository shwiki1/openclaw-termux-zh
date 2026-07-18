import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/cli_api_config.dart';
import '../models/cli_tool.dart';
import '../services/browser_automation_service.dart';
import '../services/cli_api_config_service.dart';
import '../services/cli_tool_service.dart';
import '../services/local_api_proxy_service.dart';
import '../services/native_bridge.dart';
import '../services/native_browser_automation_delegate.dart';
import '../services/terminal_service.dart';
import '../widgets/cli_api_config_dialog.dart';
import '../widgets/cli_api_profiles_dialog.dart';
import 'cli_tool_install_screen.dart';
import 'local_api_proxy_browser_screen.dart';

class CliToolsScreen extends StatefulWidget {
  const CliToolsScreen({super.key});

  @override
  State<CliToolsScreen> createState() => _CliToolsScreenState();
}

class _CliToolsScreenState extends State<CliToolsScreen> {
  List<CliToolStatus> _statuses = const [];
  List<CliApiConfig> _sharedProfiles = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    final cachedStatuses = CliToolService.cachedStatuses;
    if (cachedStatuses.isNotEmpty) {
      _statuses = cachedStatuses;
      _loading = false;
      unawaited(
        _refresh(
          showLoader: false,
          forceStatusRefresh: true,
        ),
      );
      return;
    }
    unawaited(_refresh());
  }

  Future<void> _refresh({
    bool showLoader = true,
    bool forceStatusRefresh = true,
  }) async {
    if (mounted && showLoader) {
      setState(() => _loading = true);
    }
    try {
      await CliApiConfigService.regenerateRuntimeFiles();
    } catch (_) {
      // Status probing should still proceed when the rootfs is not ready yet.
    }
    final results = await Future.wait<dynamic>([
      CliToolService.checkAllStatuses(forceRefresh: forceStatusRefresh),
      CliApiConfigService.loadSharedProfiles(),
    ]);
    final statuses = results[0] as List<CliToolStatus>;
    final sharedProfiles = results[1] as List<CliApiConfig>;
    if (!mounted) return;
    setState(() {
      _statuses = statuses;
      _sharedProfiles = sharedProfiles;
      _loading = false;
    });
  }

  Future<void> _openTool(CliToolDefinition tool) async {
    if (tool.id != CliToolService.shellTool.id) {
      try {
        await CliApiConfigService.regenerateRuntimeFiles();
      } catch (_) {
        // The terminal launch script will surface missing runtime files.
      }
    }
    final config = await TerminalService.getProotShellConfig();
    var arguments = TerminalService.buildProotArgs(config);
    final initialCommand = tool.launchCommand.trim().isEmpty
        ? null
        : tool.launchCommand;
    if (initialCommand != null) {
      arguments = TerminalService.replaceLoginShell(arguments, initialCommand);
    }
    final environment = TerminalService.buildHostEnv(config);
    final browserService = BrowserAutomationService.instance;
    final browserDelegate = NativeBrowserAutomationDelegate.instance;
    final isCodexTool = _isCodexTool(tool, initialCommand);
    if (isCodexTool) {
      await browserService.ensureStarted();
      browserService.bindDelegate(browserDelegate);
    }
    try {
      if (isCodexTool) {
        await NativeBridge.openNativeTerminalPagerActivity(
          sessionId: tool.id,
          title: tool.name,
          executable: config['executable']!,
          arguments: arguments,
          environment: environment,
          useNativeToolbar: true,
          keepAlive: true,
          transcriptRows: 1200,
        );
      } else {
        await NativeBridge.openNativeTerminalActivity(
          sessionId: tool.id,
          title: tool.name,
          executable: config['executable']!,
          arguments: arguments,
          environment: environment,
          useNativeToolbar: true,
          keepAlive: true,
        );
      }
    } finally {
      if (isCodexTool) {
        browserService.unbindDelegate(browserDelegate);
      }
    }
    if (mounted) {
      unawaited(
        _refresh(
          showLoader: false,
          forceStatusRefresh: true,
        ),
      );
    }
  }

  bool _isCodexTool(CliToolDefinition tool, String? initialCommand) {
    final id = tool.id.toLowerCase();
    final name = tool.name.toLowerCase();
    final command = initialCommand?.toLowerCase() ?? '';
    return id.contains('codex') ||
        name.contains('codex') ||
        command.contains('codex');
  }

  Future<void> _installTool(CliToolDefinition tool) async {
    try {
      await CliToolService.prepareInstallAssets(tool);
    } catch (_) {
      // Optional installer assets are best-effort; npm/runtime installers
      // surface any real failures in the terminal.
    }

    final result = await Navigator.of(context).push<CliToolInstallResult>(
      MaterialPageRoute(
        builder: (_) => CliToolInstallScreen(tool: tool),
      ),
    );
    if (mounted) {
      await _refresh(forceStatusRefresh: true);
      if (result != null) {
        await _showInstallResultDialog(result);
      }
    }
  }

  Future<void> _configureTool(CliToolDefinition tool) async {
    final saved = await CliApiConfigDialog.show(context, tool: tool);
    if (saved && mounted) {
      await _refresh(showLoader: false, forceStatusRefresh: true);
    }
  }

  Future<void> _manageSharedApis() async {
    final savedProfileId = await CliApiProfilesDialog.show(context);
    if (savedProfileId != null && mounted) {
      await _refresh(showLoader: false, forceStatusRefresh: true);
    }
  }

  Future<void> _showLocalApiProxyDialog() async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _LocalApiProxyDialog(
        onOpenManager: () {
          Navigator.of(dialogContext).pop();
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const LocalApiProxyBrowserScreen(),
            ),
          );
        },
      ),
    );
  }

  CliToolStatus? _statusForTool(String toolId) {
    for (final status in _statuses) {
      if (status.tool.id == toolId) {
        return status;
      }
    }
    return null;
  }

  Future<void> _showInstallResultDialog(CliToolInstallResult result) async {
    if (!mounted) return;
    final status = _statusForTool(result.tool.id);
    final effectiveSuccess = result.success && (status?.installed ?? false);
    final version = status?.version?.trim() ?? '';
    final detail = status?.error?.trim().isNotEmpty == true
        ? status!.error!.trim()
        : result.outputTail.trim();
    final message = effectiveSuccess
        ? (version.isEmpty ? '安装完成。' : '安装完成，当前版本：$version')
        : (detail.isEmpty ? '安装失败，请重新安装并检查日志。' : detail);
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(effectiveSuccess ? '${result.tool.name} 已安装' : '${result.tool.name} 安装失败'),
        content: SingleChildScrollView(
          child: SelectableText(message),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('CLI Tools'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: _loading ? null : () => _refresh(forceStatusRefresh: true),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => _refresh(showLoader: false, forceStatusRefresh: true),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    '管理 Ubuntu 环境中的命令行工具。返回列表不会关闭已打开的终端，会话页右上角的关闭按钮才会终止进程。',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildSharedApiCard(theme),
                  const SizedBox(height: 12),
                  for (final status in _statuses) _buildToolCard(theme, status),
                ],
              ),
            ),
    );
  }

  Widget _buildSharedApiCard(ThemeData theme) {
    final configuredCount =
        _sharedProfiles.where((profile) => profile.isConfigured).length;
    final summary = _sharedProfiles.isEmpty
        ? '推荐先启动本地中转代理，在代理管理页维护上游 API、模型映射和访问 Token。旧共享 API 入口仍保留用于兼容已配置工具。'
        : '本地中转代理可统一接管 API 转发；旧共享 API 中还有 ${_sharedProfiles.length} 个配置，其中 ${configuredCount} 个已填写连接信息。';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'API 接入',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: _loading ? null : _manageSharedApis,
                  icon: const Icon(Icons.settings_input_component),
                  label: const Text('管理 API'),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _loading ? null : _showLocalApiProxyDialog,
                icon: const Icon(Icons.hub_outlined),
                label: const Text('中转代理'),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              summary,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToolCard(ThemeData theme, CliToolStatus status) {
    final tool = status.tool;
    final isShell = tool.id == CliToolService.shellTool.id;
    final configurable =
        CliApiConfigService.configurableToolIds.contains(tool.id);
    final installed = isShell || status.installed;
    final statusColor =
        installed ? AppColors.statusGreen : theme.colorScheme.error;
    final statusLabel = installed ? '已安装' : '未安装';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: tool.color.withAlpha(28),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(tool.icon, color: tool.color),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        tool.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        tool.packageName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                _buildStatusPill(theme, statusLabel, statusColor),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              tool.description,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 10),
            _buildVersionLine(theme, status),
            if (status.error != null) ...[
              const SizedBox(height: 8),
              Text(
                status.error!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (configurable) ...[
                  OutlinedButton.icon(
                    onPressed: () => _configureTool(tool),
                    icon: const Icon(Icons.tune),
                    label: const Text('配置'),
                  ),
                  const SizedBox(width: 8),
                ],
                if (!isShell) ...[
                  FilledButton.icon(
                    onPressed: () => _installTool(tool),
                    icon: const Icon(Icons.download),
                    label: Text(status.installed ? '更新' : '安装'),
                  ),
                  const SizedBox(width: 8),
                ],
                OutlinedButton.icon(
                  onPressed: installed ? () => _openTool(tool) : null,
                  icon: const Icon(Icons.open_in_new),
                  label: const Text('打开'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusPill(ThemeData theme, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _buildVersionLine(ThemeData theme, CliToolStatus status) {
    final version = status.version?.trim();
    final value = version == null || version.isEmpty ? '未知版本' : version;
    return Row(
      children: [
        Icon(
          Icons.info_outline,
          size: 15,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _LocalApiProxyDialog extends StatefulWidget {
  const _LocalApiProxyDialog({required this.onOpenManager});

  final VoidCallback onOpenManager;

  @override
  State<_LocalApiProxyDialog> createState() => _LocalApiProxyDialogState();
}

class _LocalApiProxyDialogState extends State<_LocalApiProxyDialog> {
  bool _starting = false;
  String _status = '';

  Future<void> _startService() async {
    setState(() {
      _starting = true;
      _status = '正在同步内置服务并重启代理...';
    });
    try {
      final output = await LocalApiProxyService.restart();
      if (!mounted) return;
      setState(() {
        _status = output.trim().isEmpty
            ? '代理已重启：${LocalApiProxyService.url}'
            : output.trim();
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _status = '启动失败：$error';
      });
    } finally {
      if (mounted) {
        setState(() => _starting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('本地中转代理'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _starting ? null : _startService,
                      icon: _starting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow),
                      label: Text(_starting ? '重启中' : '重启代理'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: widget.onOpenManager,
                      icon: const Icon(Icons.open_in_browser_outlined),
                      label: const Text('API 管理'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                '内置 api2py 会在 Ubuntu RootFS 中运行一个本地 OpenAI/Responses/Anthropic 兼容中转服务。',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 10),
              SelectableText(
                '代理地址：${LocalApiProxyService.url}\n'
                '健康检查：${LocalApiProxyService.healthUrl}\n'
                'RootFS 路径：${LocalApiProxyService.guestDir}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFamily: 'monospace',
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '软件打开后会自动启动代理。需要刷新进程时点“重启代理”，再点“API 管理”直接进入管理页。原有“管理 API”里保存的提供商和模型会同步写入这个中转代理，各 CLI 工具统一使用 http://127.0.0.1:9999/v1。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              if (_status.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                  ),
                  child: SelectableText(
                    _status,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _starting ? null : () => Navigator.of(context).pop(),
          child: const Text('关闭'),
        ),
      ],
    );
  }
}
