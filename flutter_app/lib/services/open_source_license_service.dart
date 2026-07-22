import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class OpenSourceLicenseService {
  static const repositoryIndexAsset =
      'assets/open_source/OPEN_SOURCE_REPOSITORIES.md';

  static const _noticeAssets = <String>[
    'assets/open_source/OPEN_SOURCE_NOTICES.md',
    'assets/open_source/THIRD_PARTY_NOTICES.md',
    'assets/open_source/OPEN_SOURCE_SOURCES.md',
  ];

  Future<String> loadRepositoryIndex() {
    return rootBundle.loadString(repositoryIndexAsset);
  }

  Future<String> loadOpenSourceNotices() async {
    final buffer = StringBuffer();

    for (final asset in _noticeAssets) {
      final content = await rootBundle.loadString(asset);
      buffer
        ..writeln(content.trimRight())
        ..writeln()
        ..writeln('---')
        ..writeln();
    }

    buffer
      ..writeln('# Flutter And Pub Package Licenses')
      ..writeln()
      ..writeln(
        'The following license texts are reported by Flutter at runtime from '
        'the packages and assets linked into this application.',
      )
      ..writeln();

    await for (final entry in LicenseRegistry.licenses) {
      final packages = entry.packages.toList()..sort();
      buffer
        ..writeln('## ${packages.join(', ')}')
        ..writeln();

      for (final paragraph in entry.paragraphs) {
        buffer.writeln(paragraph.text);
        buffer.writeln();
      }
    }

    return buffer.toString().trimRight();
  }
}
