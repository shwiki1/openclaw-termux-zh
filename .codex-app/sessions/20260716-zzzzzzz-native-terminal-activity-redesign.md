# 2026-07-16 20:35 UTC - Native Terminal Activity Redesign

## Goal

Stop chasing Flutter `AndroidView` IME compensation for Codex/CLI terminal lag and move the active CLI terminal path onto a native Android terminal activity similar in architecture to ZeroTermux/Termux.

## Repo Facts Read

- `flutter_app/lib/screens/cli_tools_screen.dart`
- `flutter_app/lib/screens/terminal_screen.dart`
- `flutter_app/lib/services/native_bridge.dart`
- `flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/MainActivity.kt`
- `flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/NativeTerminalView.kt`
- `flutter_app/android/app/src/main/AndroidManifest.xml`
- Upstream `termux-app` `activity_termux.xml` and `TermuxActivityRootView.java`

## Changes Made

- Added `NativeTerminalSessionView.kt` as the shared native terminal core for both the Flutter platform-view wrapper and the new native terminal activity.
- Added `NativeTerminalActivity.kt` as a dedicated full-screen Android terminal screen with native session switching, restart, paste, close, and the same native shortcut bar.
- Refactored `NativeTerminalView.kt` into a thin Flutter `PlatformView` wrapper around `NativeTerminalSessionView`.
- Extended `MainActivity.kt` and `NativeBridge` with `openNativeTerminalActivity(...)` so Flutter can launch the native terminal activity and wait for it to close.
- Updated `CliToolsScreen` to resolve the PRoot shell config in Dart and open CLI/Codex sessions through the new native activity instead of pushing `TerminalScreen`.
- Updated `AndroidManifest.xml` to register `NativeTerminalActivity` on `adjustResize`.
- Updated `lib/test.js` source guards for the new native launch path and shared terminal core.

## Checks Run

- `npm test`
- `npm run lint -- --no-warn-ignored`
- `git diff --check`

## Cloud Build

- Not run in this session.

## Version And Artifacts

- No new artifact generated in this session.
- Current published baseline remains `v5.3.0 / 5.3 / 172`.

## Known Risks

- Local `flutter`, `dart`, and `kotlinc` are unavailable, so no local Flutter analyze/test or Kotlin compile verification was possible.
- The new native activity path bypasses the Flutter browser-sidecar terminal route; Android device smoke is required to confirm the desired IME smoothness and to evaluate any Codex browser-sidecar workflow impact.

## Next Actions

- Push the native terminal activity follow-up to GitHub and run the next arm64 cloud build with a logical build number above `172`.
- Install and smoke the resulting APK on Android, focusing on full-scrollback IME open/close smoothness and native session persistence.
