# 2026-07-16 18:10 UTC - Native Toolbar IME Post-Layout Refresh

## Goal

Make the native terminal shortcut bar follow the IME above the keyboard like ZeroTermux, without restoring the older bottom-padding compensation chain.

## Repo Facts Read

- `flutter_app/lib/screens/terminal_screen.dart`
- `flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/NativeTerminalView.kt`
- `lib/test.js`
- ZeroTermux `activity_termux.xml`
- ZeroTermux `TermuxActivityRootView.java`

## Changes Made

- Reintroduced a lightweight native global-layout observer only to detect IME-visible layout changes.
- Added a one-shot post-layout `requestInputStripVisible()` refresh when the keyboard overlaps the native toolbar lane.
- Kept the direct layout-compensation code removed: no bottom padding, no delayed settle chain, no Codex-only Flutter shortcut overlay.
- Updated Node source guards to require the global-layout refresh path and still forbid the older compensation code.

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
- Android device smoke is still required to confirm the shortcut lane now sits fully above the IME with real keyboards.

## Next Actions

- Device-smoke Codex/native terminal IME open-close cycles and verify the shortcut lane stays above the keyboard.
- If the user wants, push and trigger the next arm64 build after this follow-up.
