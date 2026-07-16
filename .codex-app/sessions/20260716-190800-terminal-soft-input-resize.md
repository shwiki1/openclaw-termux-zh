# 2026-07-16 19:08 UTC - Terminal Soft Input Resize

## Goal

Fix the remaining Android terminal IME regression after the previous native-toolbar rect split still failed to lift the shortcut bar on-device.

## Repo Facts Read

- `.codex-app/state.md`
- `.codex-app/architecture.md`
- `flutter_app/lib/services/native_bridge.dart`
- `flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/MainActivity.kt`
- `flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/NativeTerminalView.kt`
- `flutter_app/lib/screens/terminal_screen.dart`
- `tool-termux-app/app/src/main/java/com/termux/app/terminal/TermuxActivityRootView.java`
- `lib/test.js`

## Changes Made

- Changed terminal soft-input ownership in `NativeBridge` from `adjustPan` to `adjustResize`.
- Kept browser-focused inputs on `adjustNothing`.
- Removed the extra native-toolbar parent visibility request from `NativeTerminalView.kt`; native-toolbar sessions now rely on Android window resizing plus the terminal prompt-strip helper instead of trying to manually push the toolbar lane.
- Updated source guards in `lib/test.js` for the new terminal soft-input policy.

## Checks Run

- `npm test`
- `npm run lint -- --no-warn-ignored`
- `git diff --check`

## Cloud Build

- Not run in this session yet.

## Version And Artifacts

- No new artifact generated in this session yet.

## Known Risks

- Local Flutter/Dart/Kotlin compilation is still unavailable in this Termux environment.
- Real Android device smoke is still required to confirm the shortcut bar now rises with `adjustResize` without regressing browser-side IME handling.

## Next Actions

- Push the resize-based terminal IME follow-up to GitHub Actions and download the new release APK.
- Verify on-device that the shortcut bar now sits above the IME and the command area no longer over-pans.
