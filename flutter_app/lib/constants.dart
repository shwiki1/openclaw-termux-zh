class AppConstants {
  static const String appName = '次元虾';
  static const String version =
      String.fromEnvironment('APP_VERSION_NAME', defaultValue: '2.0.49');
  static const String buildNumber =
      String.fromEnvironment('APP_VERSION_CODE', defaultValue: '1');
  static const String fullVersion = '$version+$buildNumber';
  static const String displayVersion =
      buildNumber == '1' ? version : '$version ($buildNumber)';
  static const String packageName = 'com.agent.cyx';

  /// Matches ANSI escape sequences (e.g. color codes in terminal output).
  static final ansiEscape = RegExp(r'\x1b\[[0-9;]*[a-zA-Z]');

  static const String authorName = 'JunWan';
  static const String authorEmail = 'susuya0712@gmail.com';
  static const String githubUrl =
      'https://github.com/JunWan666/openclaw-termux-zh';
  static const String license = 'MIT';

  static const String appUpdateBaseUrl = 'http://api.lziyu.cn/openclaw';
  static const String appUpdateManifestUrl = '$appUpdateBaseUrl/latest.json';

  // NextGenX
  static const String orgName = 'NextGenX';
  static const String orgEmail = 'susuya0712@gmail.com';
  static const String instagramUrl =
      'https://www.instagram.com/nexgenxplorer_nxg';
  static const String youtubeUrl =
      'https://youtube.com/@nexgenxplorer?si=UG-wBC8UIyeT4bbw';
  static const String playStoreUrl =
      'https://play.google.com/store/apps/dev?id=8262374975871504599';

  static const String gatewayHost = '127.0.0.1';
  static const int gatewayPort = 18789;
  static const String gatewayUrl = 'http://$gatewayHost:$gatewayPort';

  static const String ubuntuBaseMirrorUrl =
      'https://mirrors.ustc.edu.cn/ubuntu-cdimage/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.3-base-';
  static const String ubuntuBaseMirrorFallbackUstcUrl =
      'https://mirrors.tuna.tsinghua.edu.cn/ubuntu-cdimage/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.3-base-';
  static const String ubuntuBaseMirrorFallbackAliyunUrl =
      'https://mirrors.aliyun.com/ubuntu-cdimage/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.3-base-';
  static const String ubuntuBaseOfficialUrl =
      'https://cdimage.ubuntu.com/ubuntu-base/releases/24.04/release/ubuntu-base-24.04.3-base-';
  static const String ubuntuRootfsUrl = ubuntuBaseMirrorUrl;
  static const String ubuntuCodename = 'noble';
  static const String bundledBootstrapAssetDir = 'assets/bootstrap';
  static const String rootfsArm64 = '${ubuntuRootfsUrl}arm64.tar.gz';
  static const String rootfsArmhf = '${ubuntuRootfsUrl}armhf.tar.gz';
  static const String rootfsAmd64 = '${ubuntuRootfsUrl}amd64.tar.gz';
  static const String prebuiltRootfsPrefix = 'openclaw-rootfs-$ubuntuCodename';

  // Node.js binary tarball is downloaded by Flutter and extracted by Java.
  // Bypasses curl/gpg/NodeSource which fail inside proot.
  static const String nodeVersion = '24.15.0';
  static const String nodeArmv7Version = '22.22.2';
  static const String openClawEstimatedSize = '~95 MB';
  static const String nodePrimaryMirrorBaseUrl =
      'https://npmmirror.com/mirrors/node';
  static const List<String> nodeMirrorBaseUrls = <String>[
    nodePrimaryMirrorBaseUrl,
    'https://mirrors.ustc.edu.cn/node',
    'https://mirrors.aliyun.com/nodejs-release',
    'https://nodejs.org/dist',
  ];
  static const String npmRegistryUrl = 'https://registry.npmmirror.com';
  static const String npmRegistryFallbackUrl = 'https://registry.npmjs.org';
  static const String npmNodeDistUrl = nodePrimaryMirrorBaseUrl;
  static const String nodeBaseUrl =
      '$nodePrimaryMirrorBaseUrl/v$nodeVersion/node-v$nodeVersion-linux-';
  static const String basicResourceReleaseBaseUrl =
      'https://github.com/JunWan666/openclaw-termux-zh/releases/download/basic-resource';
  static const String basicResourcePrebuiltRootfsArm64 =
      '$basicResourceReleaseBaseUrl/openclaw-rootfs-$ubuntuCodename-arm64.tar.gz';
  static const String basicResourceUbuntuRootfsArm64 =
      '$basicResourceReleaseBaseUrl/ubuntu-base-24.04.3-base-arm64.tar.gz';
  static const String basicResourceNodeArm64 =
      '${nodeBaseUrl}arm64.tar.xz';

  static bool isArmv7Arch(String arch) {
    final normalized = arch.trim().toLowerCase();
    return normalized == 'arm' ||
        normalized == 'armv7l' ||
        normalized == 'armeabi-v7a' ||
        normalized == 'armhf';
  }

  static String getNodeVersionForArch(String arch) {
    if (isArmv7Arch(arch)) {
      return nodeArmv7Version;
    }
    return nodeVersion;
  }

  static String getNodeTarballUrl(String arch) {
    return getNodeTarballUrlForVersion(arch, getNodeVersionForArch(arch));
  }

  static String getNodeTarballUrlForVersion(String arch, String version) {
    return getNodeTarballUrlsForVersion(arch, version).first;
  }

  static List<String> getNodeTarballUrlsForVersion(
    String arch,
    String version,
  ) {
    final nodeArch = switch (arch) {
      'aarch64' => 'arm64',
      'arm' => 'armv7l',
      'x86_64' => 'x64',
      _ => 'arm64',
    };

    return nodeMirrorBaseUrls.map((baseUrl) {
      return '$baseUrl/v$version/node-v$version-linux-$nodeArch.tar.xz';
    }).toList();
  }

  static String bundledBootstrapAssetPathForUrl(String url) {
    final uri = Uri.parse(url);
    final fileName = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    return '$bundledBootstrapAssetDir/$fileName';
  }

  static String ubuntuRootfsArchiveArch(String arch) {
    final normalized = arch.trim().toLowerCase();
    if (normalized == 'aarch64' ||
        normalized == 'arm64' ||
        normalized == 'arm64-v8a') {
      return 'arm64';
    }
    if (isArmv7Arch(normalized)) {
      return 'armhf';
    }
    if (normalized == 'x86_64' || normalized == 'amd64') {
      return 'amd64';
    }
    return 'arm64';
  }

  static String prebuiltRootfsAssetPathForArch(String arch) {
    final rootfsArch = ubuntuRootfsArchiveArch(arch);
    return '$bundledBootstrapAssetDir/$prebuiltRootfsPrefix-$rootfsArch.tar.gz';
  }

  static bool isUbuntuPortsArch(String arch) {
    switch (arch) {
      case 'aarch64':
      case 'arm':
        return true;
      default:
        return false;
    }
  }

  static List<String> ubuntuMirrorCandidates(String arch) {
    final isPorts = isUbuntuPortsArch(arch);
    final paths = isPorts
        ? <String>[
            'https://mirrors.ustc.edu.cn/ubuntu-ports',
            'https://mirrors.aliyun.com/ubuntu-ports',
            'https://mirrors.tuna.tsinghua.edu.cn/ubuntu-ports',
            'https://ports.ubuntu.com/ubuntu-ports',
          ]
        : <String>[
            'https://mirrors.ustc.edu.cn/ubuntu',
            'https://mirrors.aliyun.com/ubuntu',
            'https://mirrors.tuna.tsinghua.edu.cn/ubuntu',
            'https://archive.ubuntu.com/ubuntu',
          ];
    return paths;
  }

  static String buildUbuntuSourcesList(String baseUrl) {
    final suites = <String>[
      ubuntuCodename,
      '$ubuntuCodename-updates',
      '$ubuntuCodename-backports',
      '$ubuntuCodename-security',
    ];
    final buffer = StringBuffer();
    for (final suite in suites) {
      buffer.writeln(
        'deb $baseUrl $suite main restricted universe multiverse',
      );
    }
    return buffer.toString();
  }

  static const int healthCheckIntervalMs = 5000;
  static const int maxAutoRestarts = 5;

  // Node constants
  static const int wsReconnectBaseMs = 350;
  static const double wsReconnectMultiplier = 1.7;
  static const int wsReconnectCapMs = 8000;
  static const String nodeRole = 'node';
  static const int pairingTimeoutMs = 300000;

  static const String channelName = 'com.agent.cyx/native';
  static const String eventChannelName =
      'com.agent.cyx/gateway_logs';
  static const String setupLogEventChannelName =
      'com.agent.cyx/setup_logs';

  static String getRootfsUrl(String arch) {
    return getRootfsUrlCandidates(arch).first;
  }

  static List<String> getRootfsUrlCandidates(String arch) {
    String suffix;
    switch (arch) {
      case 'aarch64':
        suffix = 'arm64.tar.gz';
        break;
      case 'arm':
        suffix = 'armhf.tar.gz';
        break;
      case 'x86_64':
        suffix = 'amd64.tar.gz';
        break;
      default:
        suffix = 'arm64.tar.gz';
    }

    return [
      '$ubuntuBaseMirrorUrl$suffix',
      '$ubuntuBaseMirrorFallbackUstcUrl$suffix',
      '$ubuntuBaseMirrorFallbackAliyunUrl$suffix',
      '$ubuntuBaseOfficialUrl$suffix',
    ];
  }
}
