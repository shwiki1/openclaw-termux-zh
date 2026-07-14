# 2026-07-14 04:15 UTC - Version Display Fix

## Goal

Make every new build show an obvious version increase at APK install time and remove the misleading split-APK version display in settings.

## Repo Facts Read

- Read `.codex-app/state.md`, `.codex-app/build.md`, `.codex-app/architecture.md`, and `.codex-app/manifest.md`.
- Inspected `flutter_app/android/app/build.gradle`, `.github/workflows/flutter-build.yml`, `scripts/build-apk.sh`, `scripts/build_release.py`, `flutter_app/lib/constants.dart`, `flutter_app/lib/screens/settings_screen.dart`, `flutter_app/lib/services/update_service.dart`, and `flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/MainActivity.kt`.
- Verified the next build from `flutter_app/pubspec.yaml` `2.0.50+140` resolves to install-visible `2.0.50+141` in the current workflow logic.

## Changes Made

- Added `flutter.androidVersionName` support to the Android Gradle build so the manifest `versionName` is `base+build`.
- Updated the GitHub Actions build prep step to write `flutter.androidVersionName` into `android/local.properties`.
- Adjusted the settings screen to show the manifest `versionName` directly instead of appending the split `versionCode`.
- Changed `AppConstants.displayVersion` to always use `fullVersion`.
- Added install-visible version logging to the shell and Python release builders.
- Added Node test assertions that guard the Gradle install-visible versionName policy and the settings-screen split `versionCode` regression.

## Checks Run

- `git diff --check`: passed.
- `python3 -m py_compile scripts/build_release.py`: passed.
- `bash -n scripts/build-apk.sh`: passed.
- `npm test`: passed with 13 checks.
- `npm run lint -- --no-warn-ignored`: passed.
- `command -v flutter` and `command -v dart`: unavailable locally.
- `gradle -q tasks --dry-run`: crashed in the Termux Android Gradle runtime before any useful project verification.

## Cloud Build

- No new GitHub Actions build was dispatched in this session.
- Next cloud build should use the next build number after `2.0.50+140`; the install screen should then show `2.0.50+141` or higher.

## Known Risks

- The local environment still cannot run Flutter analyze/test/build.
- The Gradle command-line runtime is unstable in this Termux environment, so the final APK validation still depends on GitHub Actions or an Android device.

## Next Actions

- Bump `flutter_app/pubspec.yaml` to the next build number only when preparing the next cloud build.
- Verify the next APK on an Android device and confirm the installer shows `base+build` rather than raw split `versionCode`.
