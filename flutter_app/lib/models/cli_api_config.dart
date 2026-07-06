class CliApiConfig {
  final String toolId;
  final String baseUrl;
  final String apiKey;
  final String model;
  final String reasoningEffort;
  final String modelMapping;
  final String apiProtocol;
  final String profileName;

  const CliApiConfig({
    required this.toolId,
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.reasoningEffort = '',
    this.modelMapping = '',
    this.apiProtocol = '',
    this.profileName = '',
  });

  bool get isConfigured =>
      baseUrl.trim().isNotEmpty ||
      apiKey.trim().isNotEmpty ||
      model.trim().isNotEmpty ||
      reasoningEffort.trim().isNotEmpty ||
      modelMapping.trim().isNotEmpty;

  String get effectiveApiProtocol {
    final protocol = apiProtocol.trim();
    if (protocol.isNotEmpty) return protocol;
    return toolId == 'gemini' ? 'gemini' : 'openai';
  }

  String get effectiveToolModel {
    final mapped = modelMapping.trim();
    return mapped.isNotEmpty ? mapped : model.trim();
  }

  String get codexModelMapping => modelMapping;
  String get effectiveCodexModel => effectiveToolModel;

  CliApiConfig copyWith({
    String? baseUrl,
    String? apiKey,
    String? model,
    String? reasoningEffort,
    String? modelMapping,
    String? codexModelMapping,
    String? apiProtocol,
    String? profileName,
  }) {
    return CliApiConfig(
      toolId: toolId,
      baseUrl: baseUrl ?? this.baseUrl,
      apiKey: apiKey ?? this.apiKey,
      model: model ?? this.model,
      reasoningEffort: reasoningEffort ?? this.reasoningEffort,
      modelMapping: modelMapping ?? codexModelMapping ?? this.modelMapping,
      apiProtocol: apiProtocol ?? this.apiProtocol,
      profileName: profileName ?? this.profileName,
    );
  }

  Map<String, dynamic> toJson() => {
        'profileName': profileName.trim(),
        'baseUrl': baseUrl.trim(),
        'apiKey': apiKey.trim(),
        'model': model.trim(),
        'reasoningEffort': reasoningEffort.trim(),
        'modelMapping': modelMapping.trim(),
        'codexModelMapping': modelMapping.trim(),
        'apiProtocol': effectiveApiProtocol,
      };

  static CliApiConfig fromJson(String toolId, Map<String, dynamic>? json) {
    if (json == null) {
      return CliApiConfig(toolId: toolId);
    }
    return CliApiConfig(
      toolId: toolId,
      baseUrl: _string(json['baseUrl']),
      apiKey: _string(json['apiKey']),
      model: _string(json['model']),
      reasoningEffort: _string(json['reasoningEffort']),
      modelMapping:
          _string(json['modelMapping']).isNotEmpty
              ? _string(json['modelMapping'])
              : _string(json['codexModelMapping']),
      apiProtocol: _string(json['apiProtocol']),
      profileName: _string(json['profileName']),
    );
  }

  static String _string(dynamic value) => value is String ? value : '';
}
