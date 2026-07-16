# 2026-07-16 18:39 UTC - Native Toolbar Rect Split

## Goal

Fix the remaining Android terminal IME regression where the native shortcut bar still failed to rise fully and the command area was pushed too high.

## Repo Facts Read

- `.codex-app/state.md`
- `.codex-app/manifest.md`
- `.codex-app/architecture.md`
- `.codex-app/ui-system.md`
- `.codex-app/backlog.md`
- `.codex-app/sessions/20260716-zzzzzz-native-toolbar-ime-post-layout-refresh.md`
- `flutter_app/lib/screens/terminal_screen.dart`
- `flutter_app/lib/widgets/native_terminal_view.dart`
- `flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/NativeTerminalView.kt`
- `lib/test.js`
- `tool-termux-app/app/src/main/res/layout/activity_termux.xml`
- `tool-termux-app/app/src/main/java/com/termux/app/terminal/TermuxActivityRootView.java`

## Changes Made

- Kept the native-toolbar design inside `NativeTerminalView` and did not restore the older bottom-padding compensation chain.
- Reworked `requestInputStripVisible()` so native-toolbar sessions no longer request one tall rectangle spanning terminal input strip through the toolbar.
- Split the IME visibility requests into two minimal targets:
  - terminal prompt strip stays on `terminalView.requestRectangleOnScreen(...)`
  - native shortcut lane now uses its own `requestToolbarStripVisible(...)` path on the parent container
- Left the non-toolbar fallback path using the parent input-strip rectangle unchanged.
- Updated `lib/test.js` source guards to require the split toolbar-request path.

## Checks Run

- `npm test`
- `npm run lint -- --no-warn-ignored`
- `git diff --check`

## Cloud Build

- Not run in this session.

## Version And Artifacts

- No new artifact generated in this session.

## Known Risks

- Local Flutter/Dart/Kotlin compilation is still unavailable in this Termux environment.
- Android device smoke is still required to confirm the toolbar now rises above the IME without over-panning the command area.

## Next Actions

- Device-smoke repeated IME open/close cycles in the terminal and verify the toolbar sits above the keyboard while the command line stays near the bottom.
- If the device result is correct, bump the next build number and push a new arm64 release build.
