# 2026-07-14 14:32 UTC - Terminal IME Lag Fix

## Goal

Reduce the visible lag when opening the Android input method while Codex browser automation and the native terminal are active on the same terminal screen.

## Repo Facts Read

- Read the app governor skill, `.codex-app/state.md`, `.codex-app/manifest.md`, `.codex-app/architecture.md`, `.codex-app/ui-system.md`, `.codex-app/backlog.md`, and the latest browser-header session log.
- Verified the relevant terminal/browser implementation in `flutter_app/lib/screens/terminal_screen.dart`, `flutter_app/lib/widgets/native_terminal_view.dart`, `flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/NativeTerminalView.kt`, `flutter_app/lib/widgets/terminal_browser_panel.dart`, and `lib/test.js`.
- Confirmed local Flutter/Dart/Kotlin SDKs are still unavailable in this Termux environment, so only Node/lint/text checks are reliable locally.

## Changes Made

- Disabled `Scaffold` IME resizing on `TerminalScreen` with `resizeToAvoidBottomInset: false` so Android no longer shrinks the combined terminal/browser platform-view layout when the keyboard opens.
- Added a short code comment explaining that terminal `AndroidView` plus browser `WebView` relayout is the source of the keyboard jank risk.
- Added a root Node self-test assertion in `lib/test.js` to keep the terminal-screen IME layout policy from regressing silently.
- Updated app memory with the new terminal-screen IME policy and Android smoke expectations.

## Checks Run

- `npm test`: passed with 21 checks.
- `npm run lint -- --no-warn-ignored`: passed.
- `git diff --check`: passed.
- `python3 /data/data/com.termux/files/home/.codex/skills/app-development-governor/scripts/validate_app_memory.py --project /storage/emulated/0/ZeroTermux/开发/openclaw-termux-zh-5.5`: passed with no errors and no warnings.
- Local `flutter`, `dart`, and `kotlinc` remain unavailable, so Flutter analyze/test and native compile checks were not run locally.

## Cloud Build

- No new cloud build was started in this session.

## Version And Artifacts

- No version/build metadata changed in this session.
- No new APK artifact was produced in this session.

## Known Risks

- The IME lag fix still needs Android device verification on both compact and wide Codex terminal layouts.
- Leaving `resizeToAvoidBottomInset` disabled must be confirmed against real keyboard overlap behavior for the terminal toolbar and browser sidecar controls.

## Next Actions

- On Android, open a Codex terminal with the browser sidecar visible, repeatedly show/hide the keyboard, and verify the page no longer stutters or jumps.
- If device smoke still shows lag, inspect whether the native `showSoftInput` path in `NativeTerminalView.kt` needs additional debouncing.
