import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

import '../constants.dart';

class UpdateReleaseAsset {
  const UpdateReleaseAsset({
    required this.name,
    required this.downloadUrl,
  });

  final String name;
  final String downloadUrl;

  bool get isApk => name.toLowerCase().endsWith('.apk');

  bool get isUniversalApk => name.toLowerCase().contains('-universal.apk');

  bool matchesAbi(String abi) => name.toLowerCase().contains('-$abi.apk');
}

class UpdateResult {
  final String latest;
  final String latestVersion;
  final int latestBuildNumber;
  final String url;
  final bool available;
  final List<UpdateReleaseAsset> assets;

  const UpdateResult({
    required this.latest,
    required this.latestVersion,
    required this.latestBuildNumber,
    required this.url,
    required this.available,
    required this.assets,
  });

  UpdateReleaseAsset? preferredApkAssetForArch(String arch) {
    final apkAssets = assets.where((asset) => asset.isApk).toList();
    if (apkAssets.isEmpty) {
      return null;
    }

    final preferredAbi = _preferredAbiForArch(arch);
    if (preferredAbi != null) {
      for (final asset in apkAssets) {
        if (asset.matchesAbi(preferredAbi)) {
          return asset;
        }
      }
    }

    for (final asset in apkAssets) {
      if (asset.isUniversalApk) {
        return asset;
      }
    }

    return null;
  }

  static String? _preferredAbiForArch(String arch) {
    switch (arch.trim().toLowerCase()) {
      case 'aarch64':
        return 'arm64-v8a';
      case 'arm':
        return 'armeabi-v7a';
      case 'x86_64':
        return 'x86_64';
      default:
        return null;
    }
  }
}

class UpdateService {
  static final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(minutes: 10),
      sendTimeout: const Duration(seconds: 30),
      followRedirects: true,
      responseType: ResponseType.bytes,
      validateStatus: (status) =>
          status != null && status >= 200 && status < 400,
    ),
  );

  static Future<UpdateResult> check() async {
    final response = await http.get(
      Uri.parse(AppConstants.appUpdateManifestUrl),
      headers: {'Accept': 'application/json'},
    );

    if (response.statusCode != 200) {
      throw Exception('Update manifest returned ${response.statusCode}');
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final latestVersion = data['version']?.toString().trim() ?? '';
    if (latestVersion.isEmpty) {
      throw Exception('Update manifest missing version');
    }

    final latestBuildNumber = int.tryParse(
          data['buildNumber']?.toString().trim() ?? '',
        ) ??
        0;
    final apkUrl = data['url']?.toString().trim() ?? '';
    final assets = ((data['assets'] as List?) ?? const <dynamic>[])
        .whereType<Map>()
        .map(
          (rawAsset) => UpdateReleaseAsset(
            name: rawAsset['name'] as String? ?? '',
            downloadUrl: rawAsset['downloadUrl'] as String? ?? '',
          ),
        )
        .where(
          (asset) => asset.name.isNotEmpty && asset.downloadUrl.isNotEmpty,
        )
        .toList();

    if (assets.isEmpty && apkUrl.isNotEmpty) {
      assets.add(
        UpdateReleaseAsset(
          name: data['fileName']?.toString().trim().isNotEmpty == true
              ? data['fileName'].toString().trim()
              : '次元虾-${latestVersion}+${latestBuildNumber}-arm64-v8a.apk',
          downloadUrl: apkUrl,
        ),
      );
    }

    final available = _isRemoteNewer(
      remoteVersion: latestVersion,
      remoteBuildNumber: latestBuildNumber,
      localVersion: AppConstants.version,
      localBuildNumber: int.tryParse(AppConstants.buildNumber) ?? 0,
    );
    final landingUrl = data['pageUrl']?.toString().trim().isNotEmpty == true
        ? data['pageUrl'].toString().trim()
        : (apkUrl.isNotEmpty ? apkUrl : AppConstants.appUpdateBaseUrl);

    return UpdateResult(
      latest: latestVersion,
      latestVersion: latestVersion,
      latestBuildNumber: latestBuildNumber,
      url: landingUrl,
      available: available,
      assets: assets,
    );
  }

  static Future<String> downloadAsset(
    UpdateReleaseAsset asset, {
    void Function(int received, int total)? onProgress,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final updateDir = Directory('${tempDir.path}/updates');
    if (!await updateDir.exists()) {
      await updateDir.create(recursive: true);
    }

    final targetFile = File('${updateDir.path}/${asset.name}');
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    final response = await _dio.download(
      asset.downloadUrl,
      targetFile.path,
      onReceiveProgress: onProgress,
      options: Options(
        headers: const {
          'Accept': 'application/octet-stream',
        },
      ),
    );

    final statusCode = response.statusCode ?? 0;
    if (statusCode < 200 || statusCode >= 400 || !await targetFile.exists()) {
      throw Exception('Download failed with status $statusCode');
    }

    return targetFile.path;
  }

  /// Returns true if [remote] is newer than [local] by semver comparison.
  static bool _isRemoteNewer({
    required String remoteVersion,
    required int remoteBuildNumber,
    required String localVersion,
    required int localBuildNumber,
  }) {
    final r = remoteVersion.split('.').map(int.parse).toList();
    final l = localVersion.split('.').map(int.parse).toList();
    for (var i = 0; i < 3; i++) {
      final rv = i < r.length ? r[i] : 0;
      final lv = i < l.length ? l[i] : 0;
      if (rv > lv) return true;
      if (rv < lv) return false;
    }
    return remoteBuildNumber > localBuildNumber;
  }
}
