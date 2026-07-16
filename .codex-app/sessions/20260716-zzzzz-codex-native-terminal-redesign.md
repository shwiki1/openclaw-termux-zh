# 2026-07-16 14:02 UTC - Codex Native Terminal Redesign

## Goal

Replace the Codex terminal's Flutter shortcut overlay with a native terminal-plus-shortcuts structure inspired by ZeroTermux, and confirm the separate Codex tool-call issue is already fixed in the proxy layer.

## Repo Facts Read

- `.codex-app/state.md`
- `.codex-app/architecture.md`
- `.codex-app/ui-system.md`
- `flutter_app/lib/screens/terminal_screen.dart`
- `flutter_app/lib/widgets/terminal_toolbar.dart`
- `flutter_app/lib/widgets/native_terminal_view.dart`
- `flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/NativeTerminalView.kt`
- ZeroTermux upstream `LICENSE.md`, `activity_termux.xml`, and `TerminalExtraKeys.java`

## Changes Made

- Moved Codex terminal sessions back onto the native shortcut bar by setting `useNativeToolbar: true` in `TerminalScreen`.
- Removed the now-unused Flutter-side `TerminalInputController` wiring from `TerminalScreen`.
- Simplified `NativeTerminalView.kt` to keep the terminal surface and shortcut bar in one Android container without the old global-layout IME compensation chain.
- Kept the lightweight keyboard-open path and bottom input-strip `requestRectangleOnScreen(...)` helper.
- Updated `lib/test.js` to guard the new native-toolbar-only Codex path and the absence of the removed IME compensation code.
- Synced `.codex-app` memory to reflect the new architecture and the GPL-only ZeroTermux reference constraint.

## Checks Run

- `npm test`
- `npm run lint -- --no-warn-ignored`
- `git diff --check`

## Cloud Build

- Not run in this session.

## Version And Artifacts

- Source anchor unchanged: `2.5.0+143`
- Next expected cloud build remains logical build `164` / display `4.5`

## Known Risks

- Local `flutter`, `dart`, and `kotlinc` are still unavailable, so no Flutter analyze/test or Android compile check ran locally.
- Real Android IME smoke is still required for repeated close/reopen, shortcut taps immediately after dismiss, and Codex browser-sidecar coexistence.

## Next Actions

- Push this redesign and trigger the next arm64 GitHub Actions release build.
- Install the resulting APK on-device and verify Codex terminal IME behavior plus tool-calling through the proxy.
