import 'package:flutter/material.dart';

import '../models/cli_api_config.dart';
import '../services/cli_api_config_service.dart';

class CliApiProfilesDialog extends StatefulWidget {
  const CliApiProfilesDialog({super.key});

  static Future<String?> show(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => const CliApiProfilesDialog(),
    );
    return result;
  }

  @override
  State<CliApiProfilesDialog> createState() => _CliApiProfilesDialogState();
}

class _CliApiProfilesDialogState extends State<CliApiProfilesDialog> {
  final _profileNameController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();

  List<CliApiConfig> _profiles = const [];
  int _activeIndex = 0;
  String _apiProtocol = 'openai';
  bool _loading = true;
  bool _saving = false;
  String? _error;

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
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final profiles = await CliApiConfigService.loadSharedProfiles();
      final initialProfiles = profiles.isEmpty
          ? [
              CliApiConfig(
                toolId: 'shared',
                sharedProfileId: 'shared-${DateTime.now().microsecondsSinceEpoch}',
                profileName: 'API 1',
              ),
            ]
          : profiles;
      if (!mounted) return;
      _applyProfile(initialProfiles.first);
      setState(() {
        _profiles = initialProfiles;
        _activeIndex = 0;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      final fallback = CliApiConfig(
        toolId: 'shared',
        sharedProfileId: 'shared-${DateTime.now().microsecondsSinceEpoch}',
        profileName: 'API 1',
      );
      _applyProfile(fallback);
      setState(() {
        _profiles = [fallback];
        _activeIndex = 0;
        _loading = false;
        _error = error.toString();
      });
    }
  }

  void _applyProfile(CliApiConfig profile) {
    _profileNameController.text =
        profile.profileName.trim().isEmpty ? 'API ${_activeIndex + 1}' : profile.profileName;
    _baseUrlController.text = profile.baseUrl;
    _apiKeyController.text = profile.apiKey;
    _apiProtocol = profile.effectiveApiProtocol;
  }

  CliApiConfig _profileFromControllers() {
    final current = _profiles[_activeIndex];
    return CliApiConfig(
      toolId: 'shared',
      sharedProfileId: current.sharedProfileId,
      profileName: _profileNameController.text.trim(),
      apiProtocol: _apiProtocol,
      baseUrl: _baseUrlController.text,
      apiKey: _apiKeyController.text,
    );
  }

  void _persistCurrentProfileInMemory() {
    if (_profiles.isEmpty) {
      return;
    }
    final nextProfiles = List<CliApiConfig>.from(_profiles);
    nextProfiles[_activeIndex] = _profileFromControllers().copyWith(
      profileName: _profileNameController.text.trim().isEmpty
          ? 'API ${_activeIndex + 1}'
          : _profileNameController.text.trim(),
    );
    _profiles = nextProfiles;
  }

  void _selectProfile(int index) {
    _persistCurrentProfileInMemory();
    final safeIndex = index.clamp(0, _profiles.length - 1).toInt();
    setState(() {
      _activeIndex = safeIndex;
      _applyProfile(_profiles[safeIndex]);
    });
  }

  void _addProfile() {
    _persistCurrentProfileInMemory();
    final nextIndex = _profiles.length;
    final profile = CliApiConfig(
      toolId: 'shared',
      sharedProfileId: 'shared-${DateTime.now().microsecondsSinceEpoch}',
      profileName: 'API ${nextIndex + 1}',
      apiProtocol: _apiProtocol,
    );
    setState(() {
      _profiles = [..._profiles, profile];
      _activeIndex = nextIndex;
      _applyProfile(profile);
    });
  }

  void _deleteProfile() {
    if (_profiles.length <= 1) {
      final reset = CliApiConfig(
        toolId: 'shared',
        sharedProfileId: _profiles.first.sharedProfileId,
        profileName: 'API 1',
      );
      setState(() {
        _profiles = [reset];
        _activeIndex = 0;
        _applyProfile(reset);
      });
      return;
    }

    final nextProfiles = List<CliApiConfig>.from(_profiles)..removeAt(_activeIndex);
    final nextIndex = _activeIndex.clamp(0, nextProfiles.length - 1).toInt();
    setState(() {
      _profiles = nextProfiles;
      _activeIndex = nextIndex;
      _applyProfile(nextProfiles[nextIndex]);
    });
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      _persistCurrentProfileInMemory();
      final selectedProfileId = _profiles[_activeIndex].sharedProfileId;
      await CliApiConfigService.saveSharedProfiles(
        _profiles,
        codexSharedProfileId: selectedProfileId,
      );
      if (!mounted) return;
      Navigator.of(context).pop(selectedProfileId);
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

    return AlertDialog(
      title: const Text('统一 API 管理'),
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
                      '这里统一维护 API 地址与 Key。各 CLI 工具只需要选择这里的某个共享 API，再设置自己的模型、模型映射和推理强度。',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<int>(
                            key: ValueKey('shared-profile-$_activeIndex-${_profiles.length}'),
                            initialValue: _activeIndex,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: '共享 API 档案',
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
                          onPressed: _saving ? null : _addProfile,
                          icon: const Icon(Icons.add),
                        ),
                        const SizedBox(width: 4),
                        IconButton.outlined(
                          tooltip: '删除当前 API',
                          onPressed: _saving ? null : _deleteProfile,
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
                    DropdownButtonFormField<String>(
                      initialValue: _apiProtocol,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: '接口协议',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'openai',
                          child: Text('OpenAI 兼容协议'),
                        ),
                        DropdownMenuItem(
                          value: 'anthropic',
                          child: Text('Anthropic 协议'),
                        ),
                        DropdownMenuItem(
                          value: 'gemini',
                          child: Text('Gemini 协议'),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() => _apiProtocol = value ?? 'openai');
                      },
                    ),
                    const SizedBox(height: 12),
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
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _loading || _saving ? null : _save,
          child: Text(_saving ? '保存中...' : '保存'),
        ),
      ],
    );
  }
}
