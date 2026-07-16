import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class BrowserUserScript {
  final String id;
  final String name;
  final String description;
  final String code;
  final List<String> matches;
  final DateTime createdAt;
  final DateTime updatedAt;

  const BrowserUserScript({
    required this.id,
    required this.name,
    required this.description,
    required this.code,
    this.matches = const <String>[],
    required this.createdAt,
    required this.updatedAt,
  });

  factory BrowserUserScript.fromJson(Map<String, dynamic> json) {
    final createdAt = _parseDate(json['createdAt']) ?? DateTime.now().toUtc();
    return BrowserUserScript(
      id: json['id']?.toString().trim() ?? '',
      name: json['name']?.toString().trim() ?? '',
      description: json['description']?.toString().trim() ?? '',
      code: json['code']?.toString() ?? '',
      matches: (json['matches'] is List ? json['matches'] as List : const [])
          .map((item) => item.toString().trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(),
      createdAt: createdAt,
      updatedAt: _parseDate(json['updatedAt']) ?? createdAt,
    );
  }

  BrowserUserScript copyWith({
    String? name,
    String? description,
    String? code,
    List<String>? matches,
    DateTime? updatedAt,
  }) {
    return BrowserUserScript(
      id: id,
      name: name ?? this.name,
      description: description ?? this.description,
      code: code ?? this.code,
      matches: matches ?? this.matches,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'description': description,
        'code': code,
        'matches': matches,
        'createdAt': createdAt.toUtc().toIso8601String(),
        'updatedAt': updatedAt.toUtc().toIso8601String(),
      };

  String get codexPrompt =>
      '请为传统网站用户脚本生成或修改脚本。脚本名：$name。'
      '用途：$description。匹配规则：${matches.isEmpty ? '*://*/*' : matches.join(', ')}。'
      '返回完整 JavaScript（可含 Tampermonkey 元数据），不要包含账号、令牌或个人数据。'
      '生成后可通过传统脚本库的“新增/导入”保存。';

  static DateTime? _parseDate(Object? value) {
    final text = value?.toString().trim() ?? '';
    return text.isEmpty ? null : DateTime.tryParse(text)?.toUtc();
  }
}

class BrowserUserScriptLibraryService {
  BrowserUserScriptLibraryService._();

  static const _storageKey = 'browser_user_scripts_v1';
  static final _uuid = Uuid();

  static Future<List<BrowserUserScript>> loadScripts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey)?.trim() ?? '';
    if (raw.isEmpty) return const <BrowserUserScript>[];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return const <BrowserUserScript>[];
      final scripts = decoded
          .whereType<Map>()
          .map((item) => BrowserUserScript.fromJson(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ))
          .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
          .toList();
      scripts.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
      return scripts;
    } catch (_) {
      return const <BrowserUserScript>[];
    }
  }

  static Future<BrowserUserScript> saveScript({
    String? id,
    required String name,
    required String description,
    required String code,
    required List<String> matches,
  }) async {
    final normalizedName = name.trim();
    final normalizedCode = code.trim();
    if (normalizedName.isEmpty || normalizedCode.isEmpty) {
      throw ArgumentError('Script name and source code are required.');
    }
    final scripts = (await loadScripts()).toList();
    final index = id == null ? -1 : scripts.indexWhere((item) => item.id == id);
    final now = DateTime.now().toUtc();
    final script = BrowserUserScript(
      id: index >= 0 ? scripts[index].id : _uuid.v4(),
      name: normalizedName,
      description: description.trim(),
      code: normalizedCode,
      matches: matches
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(),
      createdAt: index >= 0 ? scripts[index].createdAt : now,
      updatedAt: now,
    );
    if (index >= 0) {
      scripts[index] = script;
    } else {
      scripts.add(script);
    }
    await _write(scripts);
    return script;
  }

  static Future<void> deleteScript(String id) async {
    final scripts = (await loadScripts()).where((item) => item.id != id).toList();
    await _write(scripts);
  }

  static Future<void> _write(List<BrowserUserScript> scripts) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode([for (final script in scripts) script.toJson()]),
    );
  }
}
