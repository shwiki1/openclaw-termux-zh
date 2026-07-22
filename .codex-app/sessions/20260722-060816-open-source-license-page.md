# 2026-07-22 06:08 UTC - Open Source License Page Follow-Up

## Goal
- User requested replacing the laggy open-source license dialog with a dedicated screen. Settings -> Open Source Licenses should navigate to that screen; the document should show all open-source repository/source addresses at the top, then the full license/source-offer text below.

## Repo Facts Read
- App stack is Flutter Android shell with Material 3 UI, Kotlin native services, and bundled PRoot RootFS.
- Settings screen is `flutter_app/lib/screens/settings_screen.dart` and uses `MaterialPageRoute` navigation.
- Compliance documents are bundled from `flutter_app/assets/open_source/` and loaded through `OpenSourceLicenseService`.
- Local Flutter/Dart/adb tooling is unavailable in this Termux environment; GitHub Actions is the APK compile path.

## Changes Made
- Added `flutter_app/assets/open_source/OPEN_SOURCE_REPOSITORIES.md` with upstream/source/package addresses for Flutter/Dart packages, Android libraries, bundled browser/file-manager libraries, fonts, Ubuntu/RootFS runtime packages, OpenClaw components, and optional CLI tools.
- Registered `assets/open_source/OPEN_SOURCE_REPOSITORIES.md` in `flutter_app/pubspec.yaml`.
- Added `OpenSourceLicenseService.loadRepositoryIndex()`.
- Added `flutter_app/lib/screens/open_source_licenses_screen.dart`, a full-screen responsive Markdown page with selectable text, loading/error/empty states, repository addresses first, and full notices loaded after the first frame to reduce entry jank.
- Changed Settings -> Open Source Licenses to navigate to `OpenSourceLicensesScreen` and removed the old `_loadingOpenSourceLicenses` state plus `_showOpenSourceLicenseDialog()` popup path.
- Added localized page/loading/empty/repository-index strings for English, Simplified Chinese, Traditional Chinese, and Japanese; removed the unused page subtitle key after removing the explanatory header card.
- Updated `lib/test.js` drift guard to assert the new page flow, bundled repository index, removal of the old dialog method, and deferred full-notice loading.

## Checks Run
- `npm test` passed 39/39.
- `npm run lint -- --no-warn-ignored` passed.
- `git diff --check` passed.
- `python3 /data/data/com.termux/files/home/.codex/skills/app-development-governor/scripts/inspect_app_project.py --project .` completed with the known Node-only auto-detection caveat.
- `python3 /data/data/com.termux/files/home/.codex/skills/app-development-governor/scripts/audit_ui_static.py --project .` returned existing broad static findings; none targeted the new open-source license page.
- `python3 /data/data/com.termux/files/home/.codex/skills/app-development-governor/scripts/audit_i18n_copy.py --project .` returned existing broad static findings; new page strings follow the existing l10n map pattern.
- `python3 /data/data/com.termux/files/home/.codex/skills/app-development-governor/scripts/check_dependency_licenses.py --project .` found 0 unknown npm direct licenses.

## Cloud Build
- No cloud build was triggered for this local UI follow-up.
- Latest cloud candidate remains `8.8 / 207` from run `29888947739`.
- Next fresh cloud build must use logical build `> 207`.

## Version And Artifacts
- No version bump and no cloud build were performed in this follow-up.
- Latest cloud candidate remains `8.8 / 207` from run `29888947739`.
- Next fresh cloud build must use logical build `> 207`.

## Known Risks
- Local Flutter analyze/test, APK compile, emulator/device visual smoke, and packaged-asset verification were not run because Flutter/Dart/adb are unavailable locally.
- This UI change is local source only until the next GitHub Actions build packages it.

## Next Actions
- On the next cloud build, verify the APK includes `assets/flutter_assets/assets/open_source/OPEN_SOURCE_REPOSITORIES.md` along with the existing notice/source files.
- Device-smoke Settings -> Open Source Licenses on Android: confirm it opens a page, shows repository addresses first, then renders the full licenses below without the old popup lag.
