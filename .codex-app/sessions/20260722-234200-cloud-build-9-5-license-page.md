# 2026-07-22 Cloud Build 9.5 License Page

## Goal
- Restore the second-version open-source license page because the packaged `9.4 / 213` still used the slow runtime license enumeration path.

## Repo Facts Read
- Settings already navigated to `OpenSourceLicensesScreen`, but `OpenSourceLicenseService` still appended Flutter `LicenseRegistry.licenses` output at runtime.
- The bundled notice assets are already packaged in `pubspec.yaml`: repository index, open-source notices, third-party notices, and source-offer notes.

## Changes Made
- Removed runtime `LicenseRegistry.licenses` enumeration from `OpenSourceLicenseService`.
- Added small in-memory caching for the repository index and complete bundled notices.
- Reworked `OpenSourceLicensesScreen` into a lightweight document page: repository addresses first, complete bundled notices below.
- Added `settingsOpenSourceLicensesNotices` localization in zh-Hans, zh-Hant, en, and ja.
- Updated Node drift guards to fail if `LicenseRegistry.licenses` returns.

## Checks Run
- `npm test` passed 41/41.
- `npm run lint -- --no-warn-ignored` passed.
- `git diff --check` passed.
- Focused search confirmed no `LicenseRegistry.licenses`, `showLicensePage`, `_noticesFuture`, or `_DocumentSection` remains in the license-page implementation.
- GitHub Actions run `29966397507` passed RootFS restore/verify, Flutter analyze, arm64 APK build, APK PRoot native-library verification, artifact collection, and artifact upload.
- ZIP `unzip -t` passed for `dist/github-run-29966397507/ciyuanxia-apks.zip`.
- APK `unzip -t` passed for `dist/github-run-29966397507/CiYuanXia-v9.5-214-arm64-v8a.apk`.
- APK inspection confirmed bundled RootFS, open-source notice assets, and arm64 PRoot libraries are present.

## Cloud Build
- Successful run: `29966397507`.
- Remote commit: `a2381979fbe873c3021087bbac3e5f8d8b69fb25`.
- Workflow name shown by GitHub: `Build OpenClaw Apps`.

## Version And Artifacts
- Version: `9.5.0`, display `9.5`, Android build `214`.
- Artifact: `ciyuanxia-apks`, ID `8548110539`, size `216214498` bytes, digest `sha256:2ab9dd32021304f22c0dfd3c4bae4a8403f7c13fc1a8b389fa6131b1915bf9f3`.
- Local ZIP: `dist/github-run-29966397507/ciyuanxia-apks.zip`, SHA-256 `2ab9dd32021304f22c0dfd3c4bae4a8403f7c13fc1a8b389fa6131b1915bf9f3`.
- Local APK: `dist/github-run-29966397507/CiYuanXia-v9.5-214-arm64-v8a.apk`, size `226885954` bytes, SHA-256 `cb7078e1228cf8f0e5f5e73254f4fc95629184d7fc25ef67751771f9e69bc59a`.

## Known Risks
- Local Flutter/Dart/adb are unavailable; actual screen latency/device UI smoke still requires installing the APK on device.

## Next Actions
- Install/smoke `9.5 / 214`; open Settings -> Open Source Licenses and verify immediate page navigation, repository addresses at top, full notice text below, and no long stall.
- Next fresh cloud build must use Android build greater than `214`.
