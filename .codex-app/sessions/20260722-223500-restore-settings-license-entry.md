# 2026-07-22 Restore Settings License Entry

## Goal
- Fix the regression reported by the user: the top-right Settings entry disappeared after reducing the app to CLI tools and terminal.

## Repo Facts Read
- `flutter_app/lib/screens/dashboard_screen.dart` only had CLI tools and terminal cards and no AppBar settings action.
- `settings_screen.dart`, `open_source_licenses_screen.dart`, and `open_source_license_service.dart` had been deleted during the CLI/terminal-only cleanup.
- Open-source license assets were still declared in `flutter_app/pubspec.yaml`.

## Changes Made
- Restored a top-right `Icons.settings_outlined` action in `DashboardScreen`.
- Added a minimal `SettingsScreen` that only exposes `OpenSourceLicensesScreen`.
- Restored open-source license loading and a dedicated license page using `SelectableText` instead of `flutter_markdown_plus`, avoiding a dependency re-add.
- Added missing settings/license localization keys for English, Simplified Chinese, Traditional Chinese, and Japanese.
- Updated `lib/test.js` guards so Settings may exist only as the license entry and must not restore gateway, Node, packages, update, native permission, local model, or backup settings.

## Checks Run
- `npm test` passed 41/41.
- `npm run lint -- --no-warn-ignored` passed.
- `git diff --check` passed.
- Focused source scan found no removed settings tokens in `settings_screen.dart`, `open_source_licenses_screen.dart`, or `open_source_license_service.dart`.

## Version And Artifacts
- No new APK was built in this fix turn.
- Latest built APK remains `9.2 / 211` from run `29961825999`, which does not include this settings-entry fix.

## Cloud Build
- Not run for this fix yet.

## Known Risks
- Local Flutter/Dart/adb are unavailable, so Flutter analyze/APK compile/device visual smoke still require GitHub Actions/device testing.

## Next Actions
- Push and run a fresh cloud build if the user wants an installable APK with the restored Settings entry.
- Next fresh cloud build must use Android build greater than `211`.
