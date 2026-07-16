# 2026-07-16 19:32 UTC - Terminal IME Window Resize

## Goal

Fix the remaining Android terminal IME regression after device feedback confirmed the shortcut bar still was not moving above the keyboard.

## Repo Facts Read

- `.codex-app/state.md`
- `.codex-app/manifest.md`
- `.codex-app/architecture.md`
- `.codex-app/ui-system.md`
- `.codex-app/build.md`
- `.codex-app/backlog.md`
- `flutter_app/lib/screens/terminal_screen.dart`
- `flutter_app/lib/services/native_bridge.dart`
- `flutter_app/android/app/src/main/AndroidManifest.xml`
- `flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/MainActivity.kt`
- `flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/NativeTerminalView.kt`
- `flutter_app/lib/widgets/native_terminal_view.dart`
- `lib/test.js`
- ZeroTermux reference files:
  - `app/src/main/AndroidManifest.xml`
  - `app/src/main/res/layout/activity_termux.xml`
  - `app/src/main/java/com/termux/app/terminal/TermuxActivityRootView.java`
  - `app/src/main/java/com/termux/app/terminal/io/TerminalToolbarViewPager.java`

## Changes Made

- Switched the terminal route back to real window-inset consumption by setting `TerminalScreen.resizeToAvoidBottomInset` to `true`.
- Removed the native terminal post-layout IME refresh/global-layout chain so the resized terminal surface is no longer re-pushed after the keyboard opens.
- Kept the lightweight terminal input-strip visibility request and the route-scoped browser `adjustNothing` handoff unchanged.
- Updated `lib/test.js` to guard the new resize-based terminal policy and the absence of the removed IME compensation chain.

## Checks Run

- `npm test`
- `npm run lint -- --no-warn-ignored`
- `git diff --check`

## Cloud Build

- An earlier run for the previous commit is still in progress separately; this session has not pushed the new terminal window-resize follow-up yet.

## Version And Artifacts

- No new artifact generated in this session yet.

## Known Risks

- Local Flutter/Dart/Kotlin compilation is still unavailable in this Termux environment.
- The new behavior still requires Android device smoke because the failure mode is IME/layout interaction on a real keyboard.
- The prior in-progress GitHub Actions run is based on the older pre-feedback commit and should not be treated as the final terminal IME fix if it succeeds.

## Next Actions

- Commit the terminal window-resize handoff, push it to GitHub `main`, watch the next arm64 build, and download the APK.
- Smoke the resulting APK on-device: open terminal, show/hide IME repeatedly, confirm the shortcut bar rises above the IME, and confirm the prompt is no longer pushed too high.
