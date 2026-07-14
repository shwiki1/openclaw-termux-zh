import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

class BrowserAutomationScriptStep {
  final String action;
  final Map<String, dynamic> payload;
  final String note;

  const BrowserAutomationScriptStep({
    required this.action,
    this.payload = const <String, dynamic>{},
    this.note = '',
  });

  factory BrowserAutomationScriptStep.fromJson(Map<String, dynamic> json) {
    return BrowserAutomationScriptStep(
      action: json['action']?.toString().trim() ?? '',
      payload: _jsonMap(json['payload']),
      note: json['note']?.toString().trim() ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'action': action,
      'payload': _jsonSafe(payload),
      'note': note,
    };
  }

  static Map<String, dynamic> _jsonMap(Object? value) {
    if (value is Map<String, dynamic>) {
      return Map<String, dynamic>.from(_jsonSafe(value) as Map);
    }
    if (value is Map) {
      return Map<String, dynamic>.from(_jsonSafe(value) as Map);
    }
    return <String, dynamic>{};
  }

  static Object? _jsonSafe(Object? value) {
    if (value == null || value is String || value is num || value is bool) {
      return value;
    }
    if (value is Map) {
      return <String, dynamic>{
        for (final entry in value.entries)
          entry.key.toString(): _jsonSafe(entry.value),
      };
    }
    if (value is Iterable) {
      return [for (final item in value) _jsonSafe(item)];
    }
    return value.toString();
  }
}

class BrowserAutomationScript {
  final String id;
  final String fileName;
  final String description;
  final List<BrowserAutomationScriptStep> steps;
  final List<String> variables;
  final String sourceUrl;
  final String sourceTitle;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? lastRunAt;
  final int runCount;

  const BrowserAutomationScript({
    required this.id,
    required this.fileName,
    required this.description,
    required this.steps,
    this.variables = const <String>[],
    this.sourceUrl = '',
    this.sourceTitle = '',
    required this.createdAt,
    required this.updatedAt,
    this.lastRunAt,
    this.runCount = 0,
  });

  factory BrowserAutomationScript.fromJson(Map<String, dynamic> json) {
    final rawSteps = json['steps'];
    final rawVariables = json['variables'];
    final createdAt = _parseDate(json['createdAt']) ?? DateTime.now().toUtc();
    return BrowserAutomationScript(
      id: json['id']?.toString().trim() ?? '',
      fileName: normalizeFileName(json['fileName']?.toString() ?? ''),
      description: json['description']?.toString().trim() ?? '',
      steps: rawSteps is List
          ? rawSteps
              .whereType<Map>()
              .map((item) => BrowserAutomationScriptStep.fromJson(
                    item.map((key, value) => MapEntry(key.toString(), value)),
                  ))
              .where((step) => step.action.isNotEmpty)
              .toList()
          : const <BrowserAutomationScriptStep>[],
      variables: rawVariables is List
          ? rawVariables
              .map((item) => item.toString().trim())
              .where((item) => item.isNotEmpty)
              .toSet()
              .toList()
          : const <String>[],
      sourceUrl: json['sourceUrl']?.toString().trim() ?? '',
      sourceTitle: json['sourceTitle']?.toString().trim() ?? '',
      createdAt: createdAt,
      updatedAt: _parseDate(json['updatedAt']) ?? createdAt,
      lastRunAt: _parseDate(json['lastRunAt']),
      runCount: _intFromJson(json['runCount']),
    );
  }

  String get quickCommand =>
      '/root/.openclaw/bin/browser-script run ${shellQuote(id)}';

  String get codexPrompt =>
      '复用浏览器脚本 $fileName（id: $id）：优先调用 '
      'browser_script_run {"id":"$id"}；如果 MCP 工具不可用，'
      '在终端执行 $quickCommand。用途：$description';

  BrowserAutomationScript copyWith({
    String? id,
    String? fileName,
    String? description,
    List<BrowserAutomationScriptStep>? steps,
    List<String>? variables,
    String? sourceUrl,
    String? sourceTitle,
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? lastRunAt,
    int? runCount,
  }) {
    return BrowserAutomationScript(
      id: id ?? this.id,
      fileName: fileName ?? this.fileName,
      description: description ?? this.description,
      steps: steps ?? this.steps,
      variables: variables ?? this.variables,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      sourceTitle: sourceTitle ?? this.sourceTitle,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      lastRunAt: lastRunAt ?? this.lastRunAt,
      runCount: runCount ?? this.runCount,
    );
  }

  Map<String, dynamic> toJson({bool includeCommand = false}) {
    return <String, dynamic>{
      'id': id,
      'fileName': fileName,
      'description': description,
      'steps': [for (final step in steps) step.toJson()],
      'variables': variables,
      'sourceUrl': sourceUrl,
      'sourceTitle': sourceTitle,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'lastRunAt': lastRunAt?.toIso8601String(),
      'runCount': runCount,
      'stepCount': steps.length,
      if (includeCommand) ...{
        'quickCommand': quickCommand,
        'codexPrompt': codexPrompt,
      },
    };
  }

  static String normalizeFileName(String value) {
    var normalized = value.trim();
    if (normalized.isEmpty) {
      normalized = 'browser-script';
    }
    normalized = normalized
        .replaceAll(RegExp(r'[\\/:*?"<>|\r\n]+'), '_')
        .replaceAll(RegExp(r'\s+'), '-');
    if (normalized.length > 80) {
      normalized = normalized.substring(0, 80);
    }
    if (!normalized.endsWith('.json')) {
      normalized = '$normalized.browser.json';
    }
    return normalized;
  }

  static String shellQuote(String value) {
    return "'${value.replaceAll("'", "'\"'\"'")}'";
  }

  static DateTime? _parseDate(Object? value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) {
      return null;
    }
    return DateTime.tryParse(text)?.toUtc();
  }

  static int _intFromJson(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}

class BrowserAutomationScriptDraft {
  final String fileName;
  final String description;
  final List<BrowserAutomationScriptStep> steps;
  final List<String> variables;
  final String sourceUrl;
  final String sourceTitle;
  final DateTime updatedAt;
  final bool autoGenerated;

  const BrowserAutomationScriptDraft({
    required this.fileName,
    required this.description,
    required this.steps,
    this.variables = const <String>[],
    this.sourceUrl = '',
    this.sourceTitle = '',
    required this.updatedAt,
    this.autoGenerated = false,
  });

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'fileName': fileName,
      'description': description,
      'steps': [for (final step in steps) step.toJson()],
      'variables': variables,
      'sourceUrl': sourceUrl,
      'sourceTitle': sourceTitle,
      'updatedAt': updatedAt.toIso8601String(),
      'stepCount': steps.length,
      'autoGenerated': autoGenerated,
      'codexPrompt': codexPrompt,
    };
  }

  String get codexPrompt =>
      '浏览器脚本助手里有待保存脚本 $fileName。用途：$description。'
      '请先保存它；之后可通过 browser_script_list 查找并用 '
      'browser_script_run 复用。';
}

class BrowserScriptLibraryService {
  BrowserScriptLibraryService._();

  static const _prefsKey = 'browser_automation_scripts_json';

  static Future<List<BrowserAutomationScript>> loadScripts() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw == null || raw.trim().isEmpty) {
      return const <BrowserAutomationScript>[];
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        return const <BrowserAutomationScript>[];
      }
      final scripts = decoded
          .whereType<Map>()
          .map((item) => BrowserAutomationScript.fromJson(
                item.map((key, value) => MapEntry(key.toString(), value)),
              ))
          .where((script) => script.id.isNotEmpty && script.steps.isNotEmpty)
          .toList();
      scripts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return scripts;
    } catch (_) {
      return const <BrowserAutomationScript>[];
    }
  }

  static Future<BrowserAutomationScript?> findScript({
    String id = '',
    String fileName = '',
  }) async {
    final normalizedId = id.trim();
    final normalizedFileName = fileName.trim().isEmpty
        ? ''
        : BrowserAutomationScript.normalizeFileName(fileName);
    final scripts = await loadScripts();
    for (final script in scripts) {
      if (normalizedId.isNotEmpty && script.id == normalizedId) {
        return script;
      }
      if (normalizedFileName.isNotEmpty && script.fileName == normalizedFileName) {
        return script;
      }
    }
    return null;
  }

  static Future<BrowserAutomationScript> saveScript({
    String id = '',
    required String fileName,
    required String description,
    required List<BrowserAutomationScriptStep> steps,
    List<String> variables = const <String>[],
    String sourceUrl = '',
    String sourceTitle = '',
    bool overwrite = false,
  }) async {
    final scripts = await loadScripts();
    final now = DateTime.now().toUtc();
    final normalizedId = id.trim();
    var normalizedFileName = BrowserAutomationScript.normalizeFileName(fileName);
    final existingIndex = scripts.indexWhere((script) {
      if (normalizedId.isNotEmpty && script.id == normalizedId) {
        return true;
      }
      return overwrite && script.fileName == normalizedFileName;
    });
    if (existingIndex < 0) {
      normalizedFileName = _uniqueFileName(scripts, normalizedFileName);
    }
    final existing = existingIndex >= 0 ? scripts[existingIndex] : null;
    final script = BrowserAutomationScript(
      id: existing?.id ?? _newId(),
      fileName: normalizedFileName,
      description: description.trim().isEmpty
          ? 'Reusable browser automation script'
          : description.trim(),
      steps: steps,
      variables: variables
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toSet()
          .toList(),
      sourceUrl: sourceUrl.trim(),
      sourceTitle: sourceTitle.trim(),
      createdAt: existing?.createdAt ?? now,
      updatedAt: now,
      lastRunAt: existing?.lastRunAt,
      runCount: existing?.runCount ?? 0,
    );
    if (existingIndex >= 0) {
      scripts[existingIndex] = script;
    } else {
      scripts.insert(0, script);
    }
    await _persistScripts(scripts);
    return script;
  }

  static Future<BrowserAutomationScript?> renameScript({
    required String id,
    required String fileName,
    String? description,
  }) async {
    final scripts = await loadScripts();
    final index = scripts.indexWhere((script) => script.id == id.trim());
    if (index < 0) {
      return null;
    }
    final normalizedFileName = _uniqueFileName(
      scripts.where((script) => script.id != id.trim()).toList(),
      BrowserAutomationScript.normalizeFileName(fileName),
    );
    final previous = scripts[index];
    final updated = previous.copyWith(
      fileName: normalizedFileName,
      description: description == null ? previous.description : description.trim(),
      updatedAt: DateTime.now().toUtc(),
    );
    scripts[index] = updated;
    await _persistScripts(scripts);
    return updated;
  }

  static Future<bool> deleteScript(String id) async {
    final scripts = await loadScripts();
    final before = scripts.length;
    scripts.removeWhere((script) => script.id == id.trim());
    if (scripts.length == before) {
      return false;
    }
    await _persistScripts(scripts);
    return true;
  }

  static Future<BrowserAutomationScript?> markRun(String id) async {
    final scripts = await loadScripts();
    final index = scripts.indexWhere((script) => script.id == id.trim());
    if (index < 0) {
      return null;
    }
    final previous = scripts[index];
    final updated = previous.copyWith(
      lastRunAt: DateTime.now().toUtc(),
      runCount: previous.runCount + 1,
      updatedAt: DateTime.now().toUtc(),
    );
    scripts[index] = updated;
    await _persistScripts(scripts);
    return updated;
  }

  static Future<void> _persistScripts(
    List<BrowserAutomationScript> scripts,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    scripts.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    await prefs.setString(
      _prefsKey,
      const JsonEncoder.withIndent('  ').convert(
        [for (final script in scripts) script.toJson()],
      ),
    );
  }

  static String _newId() {
    return 'script-${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}';
  }

  static String _uniqueFileName(
    List<BrowserAutomationScript> scripts,
    String fileName,
  ) {
    final existing = scripts.map((script) => script.fileName).toSet();
    if (!existing.contains(fileName)) {
      return fileName;
    }
    final suffix = fileName.endsWith('.browser.json')
        ? '.browser.json'
        : fileName.endsWith('.json')
            ? '.json'
            : '';
    final base = suffix.isEmpty
        ? fileName
        : fileName.substring(0, fileName.length - suffix.length);
    var index = 2;
    while (existing.contains('$base-$index$suffix')) {
      index += 1;
    }
    return '$base-$index$suffix';
  }
}
