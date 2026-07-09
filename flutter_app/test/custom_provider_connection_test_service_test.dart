import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openclaw/models/custom_provider_preset.dart';
import 'package:openclaw/services/custom_provider_connection_test_service.dart';

void main() {
  group('CustomProviderConnectionTestService', () {
    test('uses chat completions endpoint for OpenAI-compatible checks',
        () async {
      final adapter = _FakeHttpClientAdapter((options) async {
        expect(
          options.uri.toString(),
          'https://api.example.com/v1/models',
        );
        expect(options.headers['Authorization'], 'Bearer sk-test');
        return _jsonResponse({
          'data': [
            {'id': 'demo-model'},
          ],
        }, 200);
      });

      final dio = Dio()..httpClientAdapter = adapter;
      final service = CustomProviderConnectionTestService(dio: dio);

      final result = await service.testConnection(
        compatibility: CustomProviderCompatibility.openaiChatCompletions,
        apiKey: 'sk-test',
        baseUrl: 'https://api.example.com/v1',
      );

      expect(result.success, isTrue);
      expect(
        result.compatibility,
        CustomProviderCompatibility.openaiChatCompletions,
      );
      expect(result.modelCount, 1);
    });

    test('auto-detect prefers Google endpoint when base URL matches', () async {
      final adapter = _FakeHttpClientAdapter((options) async {
        expect(
          options.uri.toString(),
          'https://generativelanguage.googleapis.com/v1beta/models?key=AIza-test',
        );
        return _jsonResponse({
          'models': [
            {
              'name': 'models/gemini-2.0-flash',
              'supportedGenerationMethods': ['generateContent'],
            },
          ],
        }, 200);
      });

      final dio = Dio()..httpClientAdapter = adapter;
      final service = CustomProviderConnectionTestService(dio: dio);

      final result = await service.testConnection(
        compatibility: CustomProviderCompatibility.autoDetect,
        apiKey: 'AIza-test',
        baseUrl: 'https://generativelanguage.googleapis.com/v1beta',
      );

      expect(result.success, isTrue);
      expect(
        result.compatibility,
        CustomProviderCompatibility.googleGenerativeAi,
      );
      expect(result.autoDetected, isTrue);
      expect(result.modelCount, 1);
    });

    test('auto-detect prefers Zhipu endpoint when host is bigmodel.cn',
        () async {
      final adapter = _FakeHttpClientAdapter((options) async {
        expect(
          options.uri.toString(),
          'https://open.bigmodel.cn/api/paas/v4/models',
        );
        expect(options.headers['Authorization'], 'Bearer zhipu-test');
        return _jsonResponse({
          'data': [
            {'id': 'glm-5'},
          ],
        }, 200);
      });

      final dio = Dio()..httpClientAdapter = adapter;
      final service = CustomProviderConnectionTestService(dio: dio);

      final result = await service.testConnection(
        compatibility: CustomProviderCompatibility.autoDetect,
        apiKey: 'zhipu-test',
        baseUrl: 'https://open.bigmodel.cn/api/paas/v4',
      );

      expect(result.success, isTrue);
      expect(
        result.compatibility,
        CustomProviderCompatibility.zhipuChatCompletions,
      );
      expect(result.autoDetected, isTrue);
      expect(result.modelCount, 1);
    });

    test('returns HTTP error details when probe fails', () async {
      final adapter = _FakeHttpClientAdapter((options) async {
        return _jsonResponse(
          {
            'error': {
              'message': 'invalid api key',
            },
          },
          401,
        );
      });

      final dio = Dio()..httpClientAdapter = adapter;
      final service = CustomProviderConnectionTestService(dio: dio);

      final result = await service.testConnection(
        compatibility: CustomProviderCompatibility.openaiResponses,
        apiKey: 'bad-key',
        baseUrl: 'https://api.example.com/v1',
      );

      expect(result.success, isFalse);
      expect(result.statusCode, 401);
      expect(result.detail, 'invalid api key');
    });
  });
}

ResponseBody _jsonResponse(Map<String, dynamic> body, int statusCode) {
  return ResponseBody.fromString(
    jsonEncode(body),
    statusCode,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

class _FakeHttpClientAdapter implements HttpClientAdapter {
  _FakeHttpClientAdapter(this._handler);

  final Future<ResponseBody> Function(RequestOptions options) _handler;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return _handler(options);
  }

  @override
  void close({bool force = false}) {}
}
