# 2026-07-13 20:18 UTC - Terminal Sidecar Performance

## Goal

Remove unused-looking browser sidecar header button boxes and reduce jank when opening/closing the compact browser sidecar or running long Codex CLI conversations.

## Repo Facts Read

- Read `.codex-app/state.md`, `manifest.md`, `architecture.md`, `ui-system.md`, `build.md`, `backlog.md`, and latest session.
- Read app-development-governor references for continuity, UI quality, testing matrix, and quality gates.
- Inspected `TerminalBrowserPanel`, `TerminalScreen`, `NativeTerminalView` Dart wrapper, and native Android `NativeTerminalView.kt`.

## Changes Made

- Removed the compact browser sidecar header back/forward icon buttons that appeared as disabled boxes beside refresh. Browser automation `back`/`forward` actions remain available.
- Changed compact browser sidecar animation from `AnimatedPositioned` layout animation to `AnimatedSlide` plus `RepaintBoundary`.
- Added `NativeTerminalView.renderingPaused` and `transcriptRows` parameters.
- Codex terminal display now uses a 1200-row visible transcript buffer while other terminal uses keep the previous 3000-row buffer.
- Native Android `TerminalView` repainting is throttled to roughly one screen update per 32 ms.
- When the compact browser sidecar is open, Flutter asks the native terminal view to pause screen repainting; the CLI process/session still runs and receives input/output normally.

## Checks Run

- `git diff --check`: passed.
- `npm test`: passed, 11 checks passed and 0 failed.
- `npm run lint -- --no-warn-ignored`: passed.
- `command -v dart`, `command -v flutter`, `command -v kotlinc`: no local SDK/compiler paths returned.
- `flutter_app/android/gradlew`: no executable wrapper available locally.

## Cloud Build

- Not run. No installable artifact was requested in this turn.

## Version And Artifacts

- Source metadata remains `2.0.50+137`.
- Latest cloud artifact remains GitHub Actions run `29278136954`, APK `CiYuanXia-v2.0.50-138-arm64-v8a.apk`.

## Known Risks

- Needs Android device smoke because local visual testing, Flutter analyzer, Kotlin compile, and APK build are not available in this Termux environment.
- The shorter terminal transcript affects only visible terminal scrollback, not CLI-managed conversation context, files, or auto-compression behavior.

## Next Actions

- Device-smoke a long Codex CLI conversation while opening/closing the compact browser sidecar.
- Verify terminal input/output continues during sidecar open and the latest terminal screen catches up after closing it.
- Run Flutter analyze/test or GitHub Actions build before release.
