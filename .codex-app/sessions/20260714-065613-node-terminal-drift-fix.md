# 2026-07-14 06:56 UTC - Node And Terminal Drift Fix

## Goal

Fix the already discovered project-management issues without submitting a build: Node.js runtime version drift and stale terminal technology documentation.

## Repo Facts Read

- Read app governor instructions plus continuity, testing matrix, and quality-gates references.
- Read `.codex-app/state.md`, `.codex-app/manifest.md`, `.codex-app/architecture.md`, `.codex-app/build.md`, `.codex-app/backlog.md`, the latest session handoff, and the install-visible version decision.
- Verified current source/docs with `rg` before and after edits.

## Changes Made

- Reconciled Node.js runtime defaults to `24.14.1` in `flutter_app/lib/constants.dart`, `scripts/build-prebuilt-rootfs.sh`, `scripts/prebuilt-rootfs-metadata.sh`, and setup l10n copy.
- Corrected `STRUCTURE.md` so the terminal stack is native Android Termux `TerminalView` through Flutter `PlatformView`.
- Added a runtime-version drift guard to `lib/test.js` covering constants, RootFS scripts, setup l10n copy, docs, resource docs, bundled fallback archive name, and legacy installer URLs.
- Updated `.codex-app/state.md`, `.codex-app/build.md`, and `.codex-app/backlog.md`.

## Checks Run

- `git diff --check`: passed.
- `npm test`: passed with 14 checks.
- `npm run lint -- --no-warn-ignored`: passed.
- `bash -n scripts/build-apk.sh`: passed.
- `bash -n scripts/build-prebuilt-rootfs.sh`: passed.
- `bash -n scripts/prebuilt-rootfs-metadata.sh`: passed.
- `python3 -B -m py_compile scripts/build_release.py`: passed.
- Focused `rg` check for stale Node version and obsolete terminal stack references in current source/docs targets returned no matches.
- `command -v flutter`, `command -v dart`, and `command -v kotlinc`: unavailable locally.
- App memory validation: passed with no errors and no warnings.

## Cloud Build

- No GitHub cloud build was dispatched.
- No APK was packaged.
- No commit or push was made.

## Version And Artifacts

- Source version remains root `package.json` `2.0.50` and Flutter `flutter_app/pubspec.yaml` `2.0.50+140`.
- Latest recorded artifact remains GitHub Actions run `29283260131`, APK `CiYuanXia-v2.0.50-140-arm64-v8a.apk`, SHA256 `db236bd4a96d30f59340df9d060ae9b4ae9fbdd80f075ac82d5bf43840348ada`.
- No new artifact was produced.

## Known Risks

- Local Termux lacks Flutter/Dart/Kotlin SDK commands, so Flutter analyze/test/build remain blocked locally.
- Runtime bootstrap and terminal documentation fixes still need normal Android device smoke in the next APK verification pass.

## Next Actions

- Before the next cloud build, bump `flutter_app/pubspec.yaml` build metadata and record the expected install-visible `versionName`.
- Run Android device smoke for setup/runtime bootstrap, terminal, gateway start/stop, and Codex browser workflows.
- In a Flutter SDK or GitHub Actions environment, run `cd flutter_app && flutter analyze && flutter test`.
