# 2026-07-14 14:03 UTC - Version Auto Progression

## Goal

Turn the new short `0.0` version display into a real build-time rule so installer, in-app UI, artifact names, and release metadata stay synchronized automatically.

## Repo Facts Read

- Read the app governor skill plus `continuity.md`, `versioning.md`, and `quality-gates.md`.
- Re-read `.codex-app/state.md`, `manifest.md`, `architecture.md`, `build.md`, `backlog.md`, and the install-visible version decision.
- Verified current build/version paths from `flutter_app/pubspec.yaml`, `flutter_app/lib/constants.dart`, `scripts/build-apk.sh`, `scripts/build_release.py`, `.github/workflows/flutter-build.yml`, `flutter_app/android/app/build.gradle`, and `lib/test.js`.

## Changes Made

- Added shared helper `scripts/versioning.py` to derive artifact semantic version, display version, and full version from a repo anchor plus target build number.
- Bumped the Flutter source anchor from `2.5.0+142` to `2.5.0+143` so the next fresh build starts the fixed display series at `144 -> 2.5`.
- Updated local build, release helper, and GitHub Actions to use the shared helper for `APP_VERSION_NAME`, `APP_VERSION_DISPLAY`, artifact names, and release tagging.
- Updated docs and project memory to record the automatic mapping `144 -> 2.5`, `145 -> 2.6`, `146 -> 2.7`, `147 -> 2.8`, `148 -> 2.9`, `149 -> 3.0`.
- Added Node self-tests covering the shared versioning helper and the fact that build automation uses it.

## Checks Run

- `git diff --check`: passed.
- `npm test`: passed with 18 checks.
- `npm run lint -- --no-warn-ignored`: passed.
- `python3 -B -m py_compile scripts/build_release.py scripts/versioning.py`: passed.
- `bash -n scripts/build-apk.sh`: passed.
- Local `flutter`, `dart`, and `kotlinc` remain unavailable, so Flutter analyze/test were not run locally.

## Cloud Build

- No new cloud build was started in this session.
- Latest verified cloud build remains GitHub Actions run `29323908852`, which still produced the pre-fix `2.0.50+143` artifact.

## Version And Artifacts

- Current source anchor: `2.5.0+143`.
- Current intended display series start: build `144` -> `2.5`.
- Next derived artifact naming form: `CiYuanXia-v2.5-144-arm64-v8a.apk`.
- No new APK artifact was produced in this session.

## Known Risks

- The automatic display-version chain is not artifact-verified yet on an actual APK or Android device.
- Local Flutter/Dart/Kotlin checks remain unavailable in this Termux environment.
- The current GitHub Actions workflow still does not run `flutter test`.

## Next Actions

- Build the next APK and verify build `144` shows `2.5` in the installer, settings page, and dashboard badge.
- If that passes, keep the helper-driven sequence in place for later builds (`145 -> 2.6`, `146 -> 2.7`, `147 -> 2.8`, `148 -> 2.9`, `149 -> 3.0`).
