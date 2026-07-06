import 'package:flutter/material.dart';

import '../models/cli_api_config.dart';
import '../models/cli_tool.dart';
import '../services/cli_api_config_service.dart';

class CliApiConfigDialog extends StatefulWidget {
  final CliToolDefinition tool;

  const CliApiConfigDialog({
    super.key,
    required this.tool,
  });

  @override
  State<CliApiConfigDialog> createState() => _CliApiConfigDialogState();

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
}

class _CliApiConfigDialogState extends State<CliApiConfigDialog> {
  final _profileNameController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();
  final _mappingController = TextEditingController();
  String _reasoningEffort = '';
  String _apiProtocol = 'anthropic';
  List<CliApiConfig> _profiles = const [];
  int _activeProfileIndex = 0;
  List<String> _availableModels = const [];
  bool _loading = true;
  bool _saving = false;
  bool _loadingModels = false;
  String? _error;

  bool get _isCodex => widget.tool.id == 'codex';
  bool get _isClaude => widget.tool.id == 'claude';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _profileNameController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _mappingController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profiles = await CliApiConfigService.loadProfiles(widget.tool.id);
      final activeIndex =
          await CliApiConfigService.loadActiveProfileIndex(widget.tool.id);
      if (!mounted) return;
      final safeIndex = activeIndex.clamp(0, profiles.length - 1).toInt();
      final config = profiles[safeIndex];
      _applyConfig(config);
      setState(() {
        _profiles = profiles;
        _activeProfileIndex = safeIndex;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      _persistCurrentProfileInMemory();
      await CliApiConfigService.saveProfiles(
        toolId: widget.tool.id,
        profiles: _profiles,
        activeProfileIndex: _activeProfileIndex,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _saving = false;
      });
    }
  }

  Future<void> _fetchModels() async {
    setState(() {
      _loadingModels = true;
      _error = null;
    });

    try {
      final models = await CliApiConfigService.fetchModels(
        toolId: widget.tool.id,
        baseUrl: _baseUrlController.text,
        apiKey: _apiKeyController.text,
        apiProtocol: _isClaude ? _apiProtocol : 'openai',
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

  CliApiConfig _configFromControllers() {
    return CliApiConfig(
      toolId: widget.tool.id,
      profileName: _profileNameController.text.trim(),
      baseUrl: _baseUrlController.text,
      apiKey: _apiKeyController.text,
      model: _modelController.text,
      reasoningEffort: _reasoningEffort,
      codexModelMapping: _isCodex ? _mappingController.text : '',
      apiProtocol: _isClaude ? _apiProtocol : 'openai',
    );
  }

  void _applyConfig(CliApiConfig config) {
    _profileNameController.text =
        config.profileName.trim().isEmpty ? '默认' : config.profileName;
    _baseUrlController.text = config.baseUrl;
    _apiKeyController.text = config.apiKey;
    _modelController.text = config.model;
    _mappingController.text = config.codexModelMapping;
    _reasoningEffort = config.reasoningEffort;
    _apiProtocol = config.effectiveApiProtocol;
    _availableModels = const [];
  }

  void _persistCurrentProfileInMemory() {
    final profiles = _profiles.isEmpty
        ? [CliApiConfig(toolId: widget.tool.id, profileName: '默认')]
        : List<CliApiConfig>.from(_profiles);
    final index = _activeProfileIndex.clamp(0, profiles.length - 1).toInt();
    profiles[index] = _configFromControllers().copyWith(
      profileName: _profileNameController.text.trim().isEmpty
          ? 'API ${index + 1}'
          : _profileNameController.text.trim(),
    );
    _profiles = profiles;
    _activeProfileIndex = index;
  }

  void _selectProfile(int index) {
    _persistCurrentProfileInMemory();
    final safeIndex = index.clamp(0, _profiles.length - 1).toInt();
    final config = _profiles[safeIndex];
    setState(() {
      _activeProfileIndex = safeIndex;
      _applyConfig(config);
    });
  }

  void _addProfile() {
    _persistCurrentProfileInMemory();
    final nextIndex = _profiles.length;
    final next = CliApiConfig(
      toolId: widget.tool.id,
      profileName: 'API ${nextIndex + 1}',
      apiProtocol: _isClaude ? _apiProtocol : 'openai',
    );
    setState(() {
      _profiles = [..._profiles, next];
      _activeProfileIndex = nextIndex;
      _applyConfig(next);
    });
  }

  void _deleteProfile() {
    if (_profiles.length <= 1) {
      setState(() {
        _applyConfig(CliApiConfig(
          toolId: widget.tool.id,
          profileName: '默认',
          apiProtocol: _isClaude ? _apiProtocol : 'openai',
        ));
      });
      return;
    }
    final profiles = List<CliApiConfig>.from(_profiles)
      ..removeAt(_activeProfileIndex);
    final nextIndex = _activeProfileIndex.clamp(0, profiles.length - 1).toInt();
    final next = profiles[nextIndex];
    setState(() {
      _profiles = profiles;
      _activeProfileIndex = nextIndex;
      _applyConfig(next);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text('${widget.tool.name} 配置'),
      content: SizedBox(
        width: 520,
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
                      _isCodex
                          ? 'Codex 支持自定义 OpenAI 兼容地址。若服务端模型名和 Codex 识别名不同，可填写模型映射。'
                          : 'Claude Code 会连接本地代理。可选择 Anthropic 兼容接口，或把 OpenAI 兼容接口转换为 Anthropic 协议。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            initialValue: _activeProfileIndex,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'API 配置档案',
                              border: OutlineInputBorder(),
                            ),
                            items: [
                              for (var i = 0; i < _profiles.length; i++)
                                DropdownMenuItem(
                                  value: i,
                                  child: Text(
                                    _profiles[i].profileName.trim().isEmpty
                                        ? 'API ${i + 1}'
                                        : _profiles[i].profileName.trim(),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              _selectProfile(value);
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.outlined(
                          tooltip: '新增 API',
                          onPressed: _saving || _loadingModels ? null : _addProfile,
                          icon: const Icon(Icons.add),
                        ),
                        const SizedBox(width: 4),
                        IconButton.outlined(
                          tooltip: '删除当前 API',
                          onPressed:
                              _saving || _loadingModels ? null : _deleteProfile,
                          icon: const Icon(Icons.delete_outline),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _profileNameController,
                      decoration: const InputDecoration(
                        labelText: '配置名称',
                        hintText: '例如：主线路 / 备用线路',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (_isClaude) ...[
                      DropdownButtonFormField<String>(
                        initialValue: _apiProtocol,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '接口协议',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 'anthropic',
                            child: Text('Anthropic 协议'),
                          ),
                          DropdownMenuItem(
                            value: 'openai',
                            child: Text('OpenAI 兼容转 Anthropic'),
                          ),
                        ],
                        onChanged: (value) {
                          setState(() => _apiProtocol = value ?? 'anthropic');
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: _baseUrlController,
                      decoration: const InputDecoration(
                        labelText: 'API 地址',
                        hintText: 'https://api.example.com/v1',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.url,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _apiKeyController,
                      decoration: const InputDecoration(
                        labelText: 'API Key',
                        hintText: 'sk-...',
                        border: OutlineInputBorder(),
                      ),
                      obscureText: true,
                      enableSuggestions: false,
                      autocorrect: false,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _modelController,
                      decoration: InputDecoration(
                        labelText: _isCodex ? '服务端模型名' : '模型',
                        hintText: _isCodex ? 'gpt-5-codex' : 'claude-sonnet-4',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _availableModels.isEmpty
                                ? '可从当前 API 获取模型列表后选择。'
                                : '已获取 ${_availableModels.length} 个模型。',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed:
                              _loadingModels || _saving ? null : _fetchModels,
                          icon: _loadingModels
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.cloud_download_outlined),
                          label: Text(_loadingModels ? '获取中...' : '获取模型'),
                        ),
                      ],
                    ),
                    if (_availableModels.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        initialValue:
                            _availableModels.contains(_modelController.text)
                                ? _modelController.text
                                : null,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: '选择模型',
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          for (final model in _availableModels)
                            DropdownMenuItem(
                              value: model,
                              child: Text(
                                model,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setState(() => _modelController.text = value);
                        },
                      ),
                    ],
                    if (_isCodex) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _mappingController,
                        decoration: const InputDecoration(
                          labelText: 'Codex 模型映射（可选）',
                          hintText: '留空则使用服务端模型名',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
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
                        DropdownMenuItem(
                          value: 'minimal',
                          child: Text('minimal'),
                        ),
                        DropdownMenuItem(value: 'low', child: Text('low')),
                        DropdownMenuItem(
                          value: 'medium',
                          child: Text('medium'),
                        ),
                        DropdownMenuItem(value: 'high', child: Text('high')),
                        DropdownMenuItem(
                          value: 'xhigh',
                          child: Text('xhigh'),
                        ),
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
