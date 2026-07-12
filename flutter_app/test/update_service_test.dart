import 'package:flutter_test/flutter_test.dart';

import 'package:openclaw/services/update_service.dart';

void main() {
  group('UpdateResult.preferredApkAssetForArch', () {
    const assets = [
      UpdateReleaseAsset(
        name: 'CiYuanXia-v2.0.50-universal.apk',
        downloadUrl: 'https://example.com/universal.apk',
      ),
      UpdateReleaseAsset(
        name: 'CiYuanXia-v2.0.50-arm64-v8a.apk',
        downloadUrl: 'https://example.com/arm64.apk',
      ),
      UpdateReleaseAsset(
        name: 'CiYuanXia-v2.0.50-armeabi-v7a.apk',
        downloadUrl: 'https://example.com/arm.apk',
      ),
      UpdateReleaseAsset(
        name: 'CiYuanXia-v2.0.50-x86_64.apk',
        downloadUrl: 'https://example.com/x86_64.apk',
      ),
      UpdateReleaseAsset(
        name: 'CiYuanXia-v2.0.50.aab',
        downloadUrl: 'https://example.com/app.aab',
      ),
    ];

    const result = UpdateResult(
      latest: '2.0.50',
      latestVersion: '2.0.50',
      latestBuildNumber: 126,
      url: 'https://example.com/release',
      available: true,
      assets: assets,
    );

    test('prefers exact arm64 asset for aarch64 devices', () {
      expect(
        result.preferredApkAssetForArch('aarch64')?.name,
        'CiYuanXia-v2.0.50-arm64-v8a.apk',
      );
    });

    test('prefers exact arm asset for arm devices', () {
      expect(
        result.preferredApkAssetForArch('arm')?.name,
        'CiYuanXia-v2.0.50-armeabi-v7a.apk',
      );
    });

    test('falls back to universal apk when architecture is unsupported', () {
      expect(
        result.preferredApkAssetForArch('x86')?.name,
        'CiYuanXia-v2.0.50-universal.apk',
      );
    });

    test('returns null when no apk asset exists', () {
      const noApkResult = UpdateResult(
        latest: '2.0.50',
        latestVersion: '2.0.50',
        latestBuildNumber: 126,
        url: 'https://example.com/release',
        available: true,
        assets: [
          UpdateReleaseAsset(
            name: 'CiYuanXia-v2.0.50.aab',
            downloadUrl: 'https://example.com/app.aab',
          ),
        ],
      );

      expect(noApkResult.preferredApkAssetForArch('aarch64'), isNull);
    });
  });
}
