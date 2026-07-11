import 'dart:async';

import 'package:flutter/material.dart';

import '../app.dart';
import '../models/cli_api_config.dart';
import '../models/cli_tool.dart';
import '../services/cli_api_config_service.dart';
import '../services/cli_tool_service.dart';
import '../widgets/cli_api_config_dialog.dart';
import '../widgets/cli_api_profiles_dialog.dart';
import 'cli_tool_install_screen.dart';
import 'terminal_screen.dart';

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
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TerminalScreen(
          sessionId: tool.id,
          title: tool.name,
          initialCommand: tool.launchCommand.trim().isEmpty
              ? null
              : tool.launchCommand,
        ),
      ),
    );
    if (mounted) {
      unawaited(
        _refresh(
          showLoader: false,
          forceStatusRefresh: true,
        ),
      );
    }
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
    final saved = await CliApiProfilesDialog.show(context);
    if (saved && mounted) {
      await _refresh(showLoader: false, forceStatusRefresh: true);
    }
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
        ? '还没有共享 API。先在这里添加 API 地址与 Key，再到各 CLI 工具里选择并配置模型。'
        : '已维护 ${_sharedProfiles.length} 个共享 API，其中 ${configuredCount} 个已填写连接信息。';

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
                    '统一 API 配置',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _loading ? null : _manageSharedApis,
                  icon: const Icon(Icons.settings_input_component),
                  label: const Text('管理 API'),
                ),
              ],
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
