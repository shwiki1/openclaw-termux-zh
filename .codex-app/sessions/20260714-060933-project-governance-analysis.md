# 2026-07-14 06:09 UTC - Project Governance Analysis

## Goal

Analyze the current app project end to end using `app-development-governor` and refresh project-management memory.

## Repo Facts Read

- Read `.codex-app/state.md`, `.codex-app/manifest.md`, `.codex-app/architecture.md`, `.codex-app/ui-system.md`, `.codex-app/build.md`, `.codex-app/backlog.md`, latest session handoff, and the install-visible version decision record.
- Ran `validate_app_memory.py --project .`; it passed with no errors or warnings before work.
- Ran `inspect_app_project.py --project .`; it scanned 439 files but only auto-detected the root Node shell, so Flutter/Kotlin facts were verified manually.
- Inspected project instructions, version sources, workflow, Android Gradle, Android manifest, Flutter entry/theme/constants, native bridge, Kotlin `MainActivity`, bootstrap/runtime setup, terminal, browser automation, Node compatibility CLI, build scripts, and tests.
- Current branch is `codex-termux-runtime-fix`, ahead of `shwiki/main` by 14 commits, with existing uncommitted work in version-display and memory files.

## Changes Made

- Updated `.codex-app/state.md` with this analysis, current local checks, and unresolved risks.
- Updated `.codex-app/build.md` with latest local verification results, auto-inspection caveat, and runtime version drift.
- Updated `.codex-app/backlog.md` with ready tasks for Node runtime version reconciliation and terminal documentation correction.
- No app/business source files were edited in this session.

## Checks Run

- `git diff --check`: passed.
- `npm test`: passed with 13 checks.
- `npm run lint -- --no-warn-ignored`: passed.
- `python3 -m py_compile scripts/build_release.py`: passed.
- `bash -n scripts/build-apk.sh`: passed.
- `bash -n scripts/build-prebuilt-rootfs.sh`: passed.
- `command -v flutter`, `command -v dart`, `command -v kotlinc`: unavailable locally.
- `command -v gradle`: `/data/data/com.termux/files/usr/bin/gradle`.

## Cloud Build

- No GitHub cloud build was dispatched.
- Follow the documented policy: bump `flutter_app/pubspec.yaml` build metadata before any new installable cloud artifact.

## Version And Artifacts

- Source version remains root `package.json` `2.0.50` and Flutter `flutter_app/pubspec.yaml` `2.0.50+140`.
- Latest recorded artifact remains GitHub Actions run `29283260131`, APK `CiYuanXia-v2.0.50-140-arm64-v8a.apk`, SHA256 `db236bd4a96d30f59340df9d060ae9b4ae9fbdd80f075ac82d5bf43840348ada`.
- No new artifact was produced.

## Known Risks

- Local Termux lacks Flutter/Dart/Kotlin SDK commands, so Flutter analyze/test/build remain blocked locally.
- Runtime Node version references drift: Flutter constants and prebuilt RootFS scripts use `24.15.0`; README/STRUCTURE/CHANGELOG/basic-resource docs/local fallback asset/legacy Node CLI still reference `24.14.1`.
- `STRUCTURE.md` still says terminal emulation is `xterm + flutter_pty`, while current source uses native Android Termux `TerminalView` through `NativeTerminalView`.
- The latest install-visible versionName policy needs Android APK/device verification on the next cloud build.

## Next Actions

- Reconcile Node.js runtime version references across code, scripts, docs, local fallback resource docs, and legacy Node CLI before the next release note/build prep.
- Correct `STRUCTURE.md` terminal implementation notes.
- Run Android device smoke for the latest APK and browser/terminal workflows listed in `.codex-app/backlog.md`.
- In a Flutter SDK or GitHub Actions environment, run `cd flutter_app && flutter analyze && flutter test`.
