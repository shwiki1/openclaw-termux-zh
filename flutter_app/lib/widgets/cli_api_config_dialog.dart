import 'package:flutter/material.dart';

import '../models/cli_api_config.dart';
import '../models/cli_tool.dart';
import '../services/cli_api_config_service.dart';
import 'cli_api_profiles_dialog.dart';

class CliApiConfigDialog extends StatefulWidget {
  final CliToolDefinition tool;

  const CliApiConfigDialog({
    super.key,
    required this.tool,
  });

  static Future<bool> show(
    BuildContext context, {
    required CliToolDefinition tool,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => CliApiConfigDialog(tool: tool),
    );
    return result == true;
  }

  @override
  State<CliApiConfigDialog> createState() => _CliApiConfigDialogState();
}

class _CliApiConfigDialogState extends State<CliApiConfigDialog> {
  final _modelController = TextEditingController();
  final _mappingController = TextEditingController();

  List<CliApiConfig> _sharedProfiles = const [];
  List<String> _availableModels = const [];
  String _reasoningEffort = '';
  String _sharedProfileId = '';
  bool _loading = true;
  bool _saving = false;
  bool _loadingModels = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _modelController.dispose();
    _mappingController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await CliApiConfigService.loadToolSettings(widget.tool.id);
      final profiles = await CliApiConfigService.loadSharedProfiles();
      if (!mounted) return;
      _applySettings(settings);
      setState(() {
        _sharedProfiles = profiles;
        _sharedProfileId = _pickSharedProfileId(
          requested: settings.sharedProfileId,
          profiles: profiles,
        );
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _applySettings(CliApiConfig settings) {
    _modelController.text = settings.model;
    _mappingController.text = settings.modelMapping;
    _reasoningEffort = settings.reasoningEffort;
    _availableModels = const [];
  }

  String _pickSharedProfileId({
    required String requested,
    required List<CliApiConfig> profiles,
  }) {
    if (requested.trim().isNotEmpty &&
        profiles.any((item) => item.sharedProfileId == requested.trim())) {
      return requested.trim();
    }
    if (profiles.length == 1) {
      return profiles.first.sharedProfileId;
    }
    return '';
  }

  CliApiConfig? get _selectedSharedProfile {
    final id = _sharedProfileId.trim();
    if (id.isEmpty) {
      return null;
    }
    for (final profile in _sharedProfiles) {
      if (profile.sharedProfileId == id) {
        return profile;
      }
    }
    return null;
  }

  Future<void> _openSharedProfilesManager() async {
    final saved = await CliApiProfilesDialog.show(context);
    if (!saved) {
      return;
    }
    final profiles = await CliApiConfigService.loadSharedProfiles();
    if (!mounted) return;
    setState(() {
      _sharedProfiles = profiles;
      _sharedProfileId = _pickSharedProfileId(
        requested: _sharedProfileId,
        profiles: profiles,
      );
    });
  }

  Future<void> _fetchModels() async {
    final profile = _selectedSharedProfile;
    if (profile == null) {
      setState(() => _error = '请先选择共享 API，或先到“统一 API 管理”里新增。');
      return;
    }

    setState(() {
      _loadingModels = true;
      _error = null;
    });

    try {
      final models = await CliApiConfigService.fetchModels(
        toolId: widget.tool.id,
        baseUrl: profile.baseUrl,
        apiKey: profile.apiKey,
        apiProtocol: profile.effectiveApiProtocol,
      );
      if (!mounted) return;
      setState(() {
        _availableModels = models;
        _loadingModels = false;
        if (_modelController.text.trim().isEmpty && models.isNotEmpty) {
          _modelController.text = models.first;
        }
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loadingModels = false;
      });
    }
  }

  Future<void> _selectModelFromList() async {
    if (_availableModels.isEmpty) {
      setState(() {
        _error = '请先获取模型列表。';
      });
      return;
    }

    final selected = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final currentModel = _modelController.text.trim();
        return SafeArea(
          child: FractionallySizedBox(
            heightFactor: 0.82,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '选择模型',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '已获取 ${_availableModels.length} 个模型，列表可上下滑动。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: ListView.separated(
                      itemCount: _availableModels.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, index) {
                        final model = _availableModels[index];
                        final selected = model == currentModel;
                        return ListTile(
                          title: Text(
                            model,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: selected
                              ? Icon(
                                  Icons.check_circle,
                                  color: theme.colorScheme.primary,
                                )
                              : null,
                          onTap: () => Navigator.of(ctx).pop(model),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    if (!mounted || selected == null || selected.isEmpty) {
      return;
    }

    setState(() {
      _modelController.text = selected;
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await CliApiConfigService.saveToolSettings(
        CliApiConfig(
          toolId: widget.tool.id,
          sharedProfileId: _sharedProfileId,
          model: _modelController.text,
          reasoningEffort: _reasoningEffort,
          modelMapping: _mappingController.text,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final selectedProfile = _selectedSharedProfile;

    return AlertDialog(
      title: Text('${widget.tool.name} 配置'),
      content: SizedBox(
        width: 540,
        child: _loading
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 28),
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '这里仅配置 ${widget.tool.name} 自己的共享 API 选择、模型、映射和推理强度。API 地址与 Key 请在统一 API 管理里维护。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            key: ValueKey('tool-shared-api-${widget.tool.id}-$_sharedProfileId-${_sharedProfiles.length}'),
                            initialValue: _sharedProfileId.isEmpty ? null : _sharedProfileId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: '共享 API',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              const DropdownMenuItem<String>(
                                value: '',
                                child: Text('未选择'),
                              ),
                              for (final profile in _sharedProfiles)
                                DropdownMenuItem<String>(
                                  value: profile.sharedProfileId,
                                  child: Text(
                                    profile.profileName.trim().isEmpty
                                        ? '未命名 API'
                                        : profile.profileName.trim(),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: _saving || _loadingModels
                                ? null
                                : (value) {
                                    setState(() {
                                      _sharedProfileId = value ?? '';
                                      _availableModels = const [];
                                    });
                                  },
                          ),
                        ),
                        const SizedBox(width: 8),
                        OutlinedButton.icon(
                          onPressed: _saving || _loadingModels
                              ? null
                              : _openSharedProfilesManager,
                          icon: const Icon(Icons.settings_ethernet),
                          label: const Text('管理 API'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest.withAlpha(120),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant.withAlpha(140),
                        ),
                      ),
                      child: selectedProfile == null
                          ? Text(
                              '当前还没有选中共享 API。先添加并选择一个共享 API，之后“获取模型”会复用它的协议、地址和 Key。',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            )
                          : Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '协议：${selectedProfile.effectiveApiProtocol}',
                                  style: theme.textTheme.bodySmall,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '地址：${selectedProfile.baseUrl.trim().isEmpty ? '未填写' : selectedProfile.baseUrl.trim()}',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _modelController,
                      decoration: const InputDecoration(
                        labelText: '服务端模型名',
                        hintText: '例如：qwen3-coder-plus / gemini-2.5-pro',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _availableModels.isEmpty
                                ? '从选中的共享 API 获取模型列表后可直接选择。'
                                : '已获取 ${_availableModels.length} 个模型。',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: _loadingModels || _saving ? null : _fetchModels,
                          icon: _loadingModels
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.cloud_download_outlined),
                          label: Text(_loadingModels ? '获取中...' : '获取模型'),
                        ),
                      ],
                    ),
                    if (_availableModels.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        onPressed:
                            _saving || _loadingModels ? null : _selectModelFromList,
                        icon: const Icon(Icons.format_list_bulleted),
                        label: Text(
                          _modelController.text.trim().isEmpty
                              ? '打开模型列表'
                              : '已选：${_modelController.text.trim()}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    TextField(
                      controller: _mappingController,
                      decoration: const InputDecoration(
                        labelText: '工具侧模型名映射（可选）',
                        hintText: '留空则使用服务端模型名；按当前 CLI 支持的模型名填写',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: _reasoningEffort,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '推理强度（可选）',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: '', child: Text('不设置')),
                        DropdownMenuItem(value: 'minimal', child: Text('minimal')),
                        DropdownMenuItem(value: 'low', child: Text('low')),
                        DropdownMenuItem(value: 'medium', child: Text('medium')),
                        DropdownMenuItem(value: 'high', child: Text('high')),
                        DropdownMenuItem(value: 'xhigh', child: Text('xhigh')),
                        DropdownMenuItem(value: 'ultra', child: Text('ultra')),
                      ],
                      onChanged: (value) {
                        setState(() => _reasoningEffort = value ?? '');
                      },
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        _error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving || _loadingModels
              ? null
              : () => Navigator.of(context).pop(false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _loading || _saving || _loadingModels ? null : _save,
          child: Text(_saving ? '保存中...' : '保存'),
        ),
      ],
    );
  }
}
