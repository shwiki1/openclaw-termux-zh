class RuntimeInstallOptions {
  final String? prebuiltRootfsUrl;
  final String? prebuiltRootfsArchivePath;
  final String? ubuntuRootfsUrl;
  final String? ubuntuRootfsArchivePath;
  final String? nodeArchiveUrl;
  final String? nodeArchivePath;

  const RuntimeInstallOptions({
    this.prebuiltRootfsUrl,
    this.prebuiltRootfsArchivePath,
    this.ubuntuRootfsUrl,
    this.ubuntuRootfsArchivePath,
    this.nodeArchiveUrl,
    this.nodeArchivePath,
  });

  String? get normalizedPrebuiltRootfsUrl {
    final value = prebuiltRootfsUrl?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  String? get normalizedPrebuiltRootfsArchivePath {
    final value = prebuiltRootfsArchivePath?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  String? get normalizedUbuntuRootfsUrl {
    final value = ubuntuRootfsUrl?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  String? get normalizedUbuntuRootfsArchivePath {
    final value = ubuntuRootfsArchivePath?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  String? get normalizedNodeArchiveUrl {
    final value = nodeArchiveUrl?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  String? get normalizedNodeArchivePath {
    final value = nodeArchivePath?.trim() ?? '';
    return value.isEmpty ? null : value;
  }

  bool get hasPrebuiltRootfsOverride =>
      normalizedPrebuiltRootfsUrl != null ||
      normalizedPrebuiltRootfsArchivePath != null;

  bool get hasBootstrapResourceOverrides =>
      hasPrebuiltRootfsOverride ||
      normalizedUbuntuRootfsUrl != null ||
      normalizedUbuntuRootfsArchivePath != null ||
      normalizedNodeArchiveUrl != null ||
      normalizedNodeArchivePath != null;

  RuntimeInstallOptions copyWith({
    String? prebuiltRootfsUrl,
    String? prebuiltRootfsArchivePath,
    String? ubuntuRootfsUrl,
    String? ubuntuRootfsArchivePath,
    String? nodeArchiveUrl,
    String? nodeArchivePath,
    bool clearPrebuiltRootfsUrl = false,
    bool clearPrebuiltRootfsArchivePath = false,
    bool clearUbuntuRootfsUrl = false,
    bool clearUbuntuRootfsArchivePath = false,
    bool clearNodeArchiveUrl = false,
    bool clearNodeArchivePath = false,
  }) {
    return RuntimeInstallOptions(
      prebuiltRootfsUrl: clearPrebuiltRootfsUrl
          ? null
          : (prebuiltRootfsUrl ?? this.prebuiltRootfsUrl),
      prebuiltRootfsArchivePath: clearPrebuiltRootfsArchivePath
          ? null
          : (prebuiltRootfsArchivePath ?? this.prebuiltRootfsArchivePath),
      ubuntuRootfsUrl: clearUbuntuRootfsUrl
          ? null
          : (ubuntuRootfsUrl ?? this.ubuntuRootfsUrl),
      ubuntuRootfsArchivePath: clearUbuntuRootfsArchivePath
          ? null
          : (ubuntuRootfsArchivePath ?? this.ubuntuRootfsArchivePath),
      nodeArchiveUrl:
          clearNodeArchiveUrl ? null : (nodeArchiveUrl ?? this.nodeArchiveUrl),
      nodeArchivePath: clearNodeArchivePath
          ? null
          : (nodeArchivePath ?? this.nodeArchivePath),
    );
  }
}
