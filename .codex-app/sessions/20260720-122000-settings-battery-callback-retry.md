# Session: Settings battery callback retry fix

## Goal
- Fix Settings battery optimization status so returning from Android battery settings updates the row without requiring a second tap.

## Repo Facts Read
- Repo root: `/storage/emulated/0/ZeroTermux/开发/openclaw-termux-zh-5.5`.
- Branch: `codex-terminal-ime-lag-fix`.
- Settings screen: `flutter_app/lib/screens/settings_screen.dart`.
- Native bridge: `NativeBridge.requestBatteryOptimization()` calls Android `startActivity()` through `MainActivity.kt`, so the Dart Future can complete before the user returns from Android settings.

## Changes Made
- Added `_waitingBatteryOptimizationReturn` to mark that the Settings row expects a battery settings return.
- On `AppLifecycleState.resumed`, Settings now restarts a dedicated battery optimization refresh loop if that marker is set.
- `_refreshBatteryOptimizationAfterSettings()` now uses a tokened delayed retry schedule up to 4 seconds, avoiding stale overlapping refreshes and covering late `PowerManager.isIgnoringBatteryOptimizations()` updates.
- The row still starts a short delayed refresh after the tap for devices that show an in-app confirmation prompt instead of leaving the app.
- Added Node test guards for the resumed marker, refresh token, and longer delayed retry.

## Checks Run
- `npm test` passed 37/37.
- `npm run lint -- --no-warn-ignored` passed.
- `git diff --check` passed.
- App memory validation passed with no errors or warnings.

## Cloud Build
- No cloud build was run for this fix yet.
- Latest built APK remains `8.1 / 200` from run `29708374513`; this battery callback fix is local source only until the next build.

## Known Risks
- Local Flutter/Dart/Kotlin compilers are unavailable, so Flutter analyze and Android compile still require GitHub Actions.
- Device smoke is required on the affected Android device because this bug depends on system Settings timing and OEM PowerManager behavior.

## Next Actions
- When the user requests it, submit a new cloud build with logical build greater than `200`.
- Device-smoke Settings -> battery optimization: choose unrestricted/ignore optimization in Android settings, return to the app, and confirm the row changes without tapping it again.
