import 'package:flutter/services.dart';

class OpenSourceLicenseService {
  static const repositoryIndexAsset =
      'assets/open_source/OPEN_SOURCE_REPOSITORIES.md';

  static const _noticeAssets = <String>[
    'assets/open_source/OPEN_SOURCE_NOTICES.md',
    'assets/open_source/THIRD_PARTY_NOTICES.md',
    'assets/open_source/OPEN_SOURCE_SOURCES.md',
  ];

  String? _repositoryIndexCache;
  String? _completeNoticesCache;

  Future<String> loadRepositoryIndex() async {
    return _repositoryIndexCache ??=
        await rootBundle.loadString(repositoryIndexAsset);
  }

  Future<String> loadOpenSourceNotices() async {
    final cached = _completeNoticesCache;
    if (cached != null) {
      return cached;
    }

    final buffer = StringBuffer();

    for (final asset in _noticeAssets) {
      final content = await rootBundle.loadString(asset);
      buffer
        ..writeln(content.trimRight())
        ..writeln()
        ..writeln('---')
        ..writeln();
    }

    return _completeNoticesCache = buffer.toString().trimRight();
  }
}
