# 2026-07-14 13:44 UTC - Version Display Format

## Goal

Fix the build/app version display so installer and in-app UI use a short `0.0` format, starting from `2.5`, while Android keeps a separate integer build number.

## Repo Facts Read

- Read the app governor skill plus the versioning reference.
- Read `.codex-app/state.md`, `manifest.md`, `architecture.md`, `ui-system.md`, `build.md`, `backlog.md`, and the install-visible version decision record.
- Verified current version/display/build logic from `flutter_app/pubspec.yaml`, `package.json`, `flutter_app/lib/constants.dart`, `flutter_app/android/app/build.gradle`, `scripts/build-apk.sh`, `scripts/build_release.py`, `.github/workflows/flutter-build.yml`, `flutter_app/lib/screens/settings_screen.dart`, and the root Node CLI/test files.

## Changes Made

- Changed source semantic version metadata to `2.5.0+142` in Flutter and `2.5.0` in the root compatibility package.
- Reworked app/install display version handling so semantic `x.y.0` renders as user-visible `x.y`.
- Added `APP_VERSION_DISPLAY` handling in Flutter constants, local build scripts, and GitHub Actions so installer/app UI stay synchronized.
- Changed the Gradle fallback so `versionName` derives from short display version instead of `base+build`.
- Updated release helper artifact naming/examples to the short form `CiYuanXia-v2.5-<build>-arm64-v8a.apk`.
- Updated the root compatibility CLI version, Node self-test guards, and current-version docs.
- Updated project memory and the install-visible version decision to preserve the new rule.

## Checks Run

- `git diff --check`: passed.
- `npm test`: passed with 16 checks.
- `npm run lint -- --no-warn-ignored`: passed.
- `python3 -B -m py_compile scripts/build_release.py`: passed.
- `bash -n scripts/build-apk.sh`: passed.
- Local `flutter`, `dart`, and `kotlinc` remain unavailable, so Flutter analyze/test were not run locally.

## Cloud Build

- No new cloud build was started in this session.
- Latest verified cloud build remains GitHub Actions run `29323908852`, which still produced the pre-fix `2.0.50+143` artifact.

## Version And Artifacts

- Current source semantic version: `2.5.0+142`.
- Current intended install-visible/app display version: `2.5`.
- No new APK artifact was produced in this session.
- Next expected artifact naming form: `CiYuanXia-v2.5-<build>-arm64-v8a.apk`.

## Known Risks

- The new version-display scheme is not artifact-verified yet on an actual APK or Android device.
- Local Flutter/Dart/Kotlin checks remain unavailable in this Termux environment.
- The current GitHub Actions workflow still does not run `flutter test`.

## Next Actions

- Build the first APK under the new display-version scheme and verify installer/settings/dashboard all show `2.5`.
- Before the next later user-facing build, advance the semantic source version to `2.6.0` and continue the one-decimal progression from there.
