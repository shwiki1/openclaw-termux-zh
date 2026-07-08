import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';

import '../models/custom_provider_preset.dart';

class CustomProviderConnectionTestResult {
  const CustomProviderConnectionTestResult({
    required this.success,
    required this.compatibility,
    required this.endpoint,
    this.statusCode,
    this.detail,
    this.modelCount,
    this.autoDetected = false,
  });

  final bool success;
  final CustomProviderCompatibility compatibility;
  final Uri endpoint;
  final int? statusCode;
  final String? detail;
  final int? modelCount;
  final bool autoDetected;
}

class CustomProviderModelFetchResult {
  const CustomProviderModelFetchResult({
    required this.compatibility,
    required this.endpoint,
    required this.models,
    this.autoDetected = false,
  });

  final CustomProviderCompatibility compatibility;
  final Uri endpoint;
  final List<String> models;
  final bool autoDetected;
}

class CustomProviderConnectionTestService {
  CustomProviderConnectionTestService({Dio? dio})
      : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                sendTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 12),
                responseType: ResponseType.json,
                validateStatus: (_) => true,
                headers: const {
                  'Accept': 'application/json',
                  'Content-Type': 'application/json',
                },
              ),
            );

  final Dio _dio;

  Future<CustomProviderConnectionTestResult> testConnection({
    required CustomProviderCompatibility compatibility,
    required String baseUrl,
    required String apiKey,
  }) async {
    try {
      final result = await fetchModels(
        compatibility: compatibility,
        baseUrl: baseUrl,
        apiKey: apiKey,
      );
      return CustomProviderConnectionTestResult(
        success: true,
        compatibility: result.compatibility,
        endpoint: result.endpoint,
        modelCount: result.models.length,
        autoDetected: result.autoDetected,
      );
    } on _ModelFetchFailure catch (failure) {
      return failure.result;
    }
  }

  Future<CustomProviderModelFetchResult> fetchModels({
    required CustomProviderCompatibility compatibility,
    required String baseUrl,
    required String apiKey,
  }) async {
    final normalizedBaseUrl = baseUrl.trim();
    final normalizedApiKey = apiKey.trim();

    if (compatibility != CustomProviderCompatibility.autoDetect) {
      return _runModelListProbe(
        compatibility,
        baseUrl: normalizedBaseUrl,
        apiKey: normalizedApiKey,
      );
    }

    final attempts = _autoDetectCompatibilities(
      normalizedBaseUrl,
      normalizedApiKey,
    );
    final failures = <CustomProviderConnectionTestResult>[];

    for (final candidate in attempts) {
      try {
        return await _runModelListProbe(
          candidate,
          baseUrl: normalizedBaseUrl,
          apiKey: normalizedApiKey,
          autoDetected: true,
        );
      } on _ModelFetchFailure catch (failure) {
        failures.add(failure.result);
      }
    }

    throw _ModelFetchFailure(_pickBestFailure(failures));
  }

  Future<CustomProviderModelFetchResult> _runModelListProbe(
    CustomProviderCompatibility compatibility, {
    required String baseUrl,
    required String apiKey,
    bool autoDetected = false,
  }) async {
    final request = _buildModelListRequest(
      compatibility,
      baseUrl: baseUrl,
      apiKey: apiKey,
    );

    try {
      final response = await _dio.getUri(
        request.endpoint,
        options: Options(headers: request.headers),
      );
      final success = response.statusCode != null &&
          response.statusCode! >= 200 &&
          response.statusCode! < 300;
      final detail = _extractErrorDetail(response.data);

      if (!success) {
        throw _ModelFetchFailure(
          CustomProviderConnectionTestResult(
            success: false,
            compatibility: compatibility,
            endpoint: request.endpoint,
            statusCode: response.statusCode,
            detail: detail,
            autoDetected: autoDetected,
          ),
        );
      }

      final models = _extractModelIds(response.data).toSet().toList()..sort();
      if (models.isEmpty) {
        throw _ModelFetchFailure(
          CustomProviderConnectionTestResult(
            success: false,
            compatibility: compatibility,
            endpoint: request.endpoint,
            statusCode: response.statusCode,
            detail: 'Model list is empty or unsupported',
            autoDetected: autoDetected,
          ),
        );
      }

      return CustomProviderModelFetchResult(
        compatibility: compatibility,
        endpoint: request.endpoint,
        models: models,
        autoDetected: autoDetected,
      );
    } on DioException catch (error) {
      throw _ModelFetchFailure(
        CustomProviderConnectionTestResult(
          success: false,
          compatibility: compatibility,
          endpoint: request.endpoint,
          statusCode: error.response?.statusCode,
          detail: _extractDioErrorDetail(error),
          autoDetected: autoDetected,
        ),
      );
    } on TimeoutException {
      throw _ModelFetchFailure(
        CustomProviderConnectionTestResult(
          success: false,
          compatibility: compatibility,
          endpoint: request.endpoint,
          detail: 'Request timed out',
          autoDetected: autoDetected,
        ),
      );
    } catch (error) {
      if (error is _ModelFetchFailure) {
        rethrow;
      }
      throw _ModelFetchFailure(
        CustomProviderConnectionTestResult(
          success: false,
          compatibility: compatibility,
          endpoint: request.endpoint,
          detail: '$error',
          autoDetected: autoDetected,
        ),
      );
    }
  }

  _ProbeRequest _buildModelListRequest(
    CustomProviderCompatibility compatibility, {
    required String baseUrl,
    required String apiKey,
  }) {
    switch (compatibility) {
      case CustomProviderCompatibility.autoDetect:
        throw StateError('autoDetect is resolved before building a request');
      case CustomProviderCompatibility.openaiChatCompletions:
      case CustomProviderCompatibility.zhipuChatCompletions:
      case CustomProviderCompatibility.openaiResponses:
        return _ProbeRequest(
          endpoint: _appendPath(baseUrl, 'models'),
          headers: _bearerHeaders(apiKey),
        );
      case CustomProviderCompatibility.anthropicMessages:
        return _ProbeRequest(
          endpoint: _appendPath(baseUrl, 'models'),
          headers: {
            if (apiKey.isNotEmpty) 'x-api-key': apiKey,
            if (apiKey.isNotEmpty) 'Authorization': 'Bearer $apiKey',
            'anthropic-version': '2023-06-01',
          },
        );
      case CustomProviderCompatibility.googleGenerativeAi:
        return _ProbeRequest(
          endpoint: _appendPath(
            baseUrl,
            'models',
            queryParameters: {
              if (apiKey.isNotEmpty) 'key': apiKey,
            },
          ),
          headers: const <String, String>{},
        );
    }
  }

  List<CustomProviderCompatibility> _autoDetectCompatibilities(
    String baseUrl,
    String apiKey,
  ) {
    final parsed = Uri.tryParse(baseUrl);
    final host = parsed?.host.toLowerCase() ?? '';
    final path = parsed?.path.toLowerCase() ?? '';

    final prioritized = <CustomProviderCompatibility>[];

    void add(CustomProviderCompatibility compatibility) {
      if (!prioritized.contains(compatibility)) {
        prioritized.add(compatibility);
      }
    }

    if (apiKey.startsWith('AIza') ||
        host.contains('googleapis.com') ||
        host.contains('generativelanguage')) {
      add(CustomProviderCompatibility.googleGenerativeAi);
    }
    if (host.contains('bigmodel.cn')) {
      add(CustomProviderCompatibility.zhipuChatCompletions);
    }
    if (apiKey.startsWith('sk-ant') || host.contains('anthropic')) {
      add(CustomProviderCompatibility.anthropicMessages);
    }
    if (path.contains('/responses')) {
      add(CustomProviderCompatibility.openaiResponses);
    }
    add(CustomProviderCompatibility.openaiChatCompletions);
    add(CustomProviderCompatibility.zhipuChatCompletions);
    add(CustomProviderCompatibility.openaiResponses);
    add(CustomProviderCompatibility.anthropicMessages);
    add(CustomProviderCompatibility.googleGenerativeAi);
    return prioritized;
  }

  CustomProviderConnectionTestResult _pickBestFailure(
    List<CustomProviderConnectionTestResult> failures,
  ) {
    if (failures.isEmpty) {
      throw StateError('Expected at least one failure result');
    }

    for (final result in failures) {
      if (result.statusCode != null &&
          result.statusCode != 404 &&
          result.statusCode != 405) {
        return result;
      }
    }

    for (final result in failures) {
      if (result.detail != null && result.detail!.trim().isNotEmpty) {
        return result;
      }
    }

    return failures.first;
  }

  Map<String, String> _bearerHeaders(String apiKey) {
    if (apiKey.isEmpty) {
      return const <String, String>{};
    }
    return {'Authorization': 'Bearer $apiKey'};
  }

  List<String> _extractModelIds(dynamic data) {
    if (data is Map) {
      if (data['models'] is List) {
        final models = <String>[];
        for (final item in data['models'] as List) {
          final supportedMethods = _stringList(item is Map ? item['supportedGenerationMethods'] : null);
          if (supportedMethods.isNotEmpty &&
              !supportedMethods.contains('generateContent')) {
            continue;
          }
          final name = _extractModelName(item);
          if (name != null) {
            models.add(name);
          }
        }
        return models;
      }

      if (data['data'] is List) {
        final models = <String>[];
        for (final item in data['data'] as List) {
          final name = _extractModelName(item);
          if (name != null) {
            models.add(name);
          }
        }
        return models;
      }
    }

    if (data is List) {
      final models = <String>[];
      for (final item in data) {
        final name = _extractModelName(item);
        if (name != null) {
          models.add(name);
        }
      }
      return models;
    }

    return const <String>[];
  }

  String? _extractModelName(dynamic item) {
    if (item is String) {
      final normalized = item.trim();
      if (normalized.isEmpty) {
        return null;
      }
      return normalized.replaceFirst(RegExp(r'^models/'), '');
    }

    if (item is! Map) {
      return null;
    }

    for (final key in const ['id', 'name', 'model', 'model_id']) {
      final value = item[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim().replaceFirst(RegExp(r'^models/'), '');
      }
    }
    return null;
  }

  List<String> _stringList(dynamic value) {
    if (value is! List) {
      return const <String>[];
    }
    return value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList();
  }

  Uri _appendPath(
    String baseUrl,
    String suffix, {
    Map<String, String>? queryParameters,
  }) {
    final baseUri = Uri.parse(baseUrl);
    final basePath = baseUri.path.replaceAll(RegExp(r'/+$'), '');
    final suffixPath = suffix.replaceFirst(RegExp(r'^/+'), '');
    final nextPath =
        basePath.isEmpty ? '/$suffixPath' : '$basePath/$suffixPath';
    final mergedQuery = <String, String>{
      ...baseUri.queryParameters,
      ...?queryParameters,
    };
    return baseUri.replace(
      path: nextPath,
      queryParameters: mergedQuery.isEmpty ? null : mergedQuery,
    );
  }

  String? _extractDioErrorDetail(DioException error) {
    final response = error.response;
    final responseDetail = _extractErrorDetail(response?.data);
    if (responseDetail != null) {
      return responseDetail;
    }

    if (error.message != null && error.message!.trim().isNotEmpty) {
      return error.message!.trim();
    }
    return error.type.name;
  }

  String? _extractErrorDetail(dynamic data) {
    if (data == null) {
      return null;
    }

    if (data is String) {
      final trimmed = data.trim();
      if (trimmed.isEmpty) {
        return null;
      }

      try {
        return _extractErrorDetail(jsonDecode(trimmed));
      } catch (_) {
        return trimmed;
      }
    }

    if (data is Map) {
      final error = data['error'];
      if (error is Map) {
        final nestedMessage = _extractErrorDetail(error);
        if (nestedMessage != null) {
          return nestedMessage;
        }
      }

      final detailKeys = ['message', 'detail', 'error_description', 'type'];
      for (final key in detailKeys) {
        final value = data[key];
        if (value is String && value.trim().isNotEmpty) {
          return value.trim();
        }
      }
    }

    if (data is List) {
      for (final item in data) {
        final nestedMessage = _extractErrorDetail(item);
        if (nestedMessage != null) {
          return nestedMessage;
        }
      }
    }

    return '$data';
  }
}

class _ProbeRequest {
  const _ProbeRequest({
    required this.endpoint,
    required this.headers,
  });

  final Uri endpoint;
  final Map<String, String> headers;
}

class _ModelFetchFailure implements Exception {
  const _ModelFetchFailure(this.result);

  final CustomProviderConnectionTestResult result;

  @override
  String toString() {
    final detail = result.detail?.trim();
    if (detail != null && detail.isNotEmpty) {
      return detail;
    }
    if (result.statusCode != null) {
      return 'HTTP ${result.statusCode}';
    }
    return 'Model fetch failed';
  }
}
