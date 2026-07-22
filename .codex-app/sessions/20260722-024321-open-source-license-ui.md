# 2026-07-22 02:43 UTC - Open Source License UI And RootFS Copyright Retention

## Goal
- User requested preserving license files and adding a Settings entry that opens a dialog showing all open-source license/source-offer requirements.

## Repo Facts Read
- Settings screen is `flutter_app/lib/screens/settings_screen.dart`.
- App assets are declared in `flutter_app/pubspec.yaml`.
- Existing compliance docs are `THIRD_PARTY_NOTICES.md` and `OPEN_SOURCE_SOURCES.md`.
- Previous RootFS cleanup removed all of `/usr/share/doc`; this is acceptable for runtime but removes package copyright files that are useful for compliance.

## Changes Made
- Changed `scripts/build-prebuilt-rootfs.sh` to preserve `/usr/share/doc/**/copyright` while deleting other non-license docs and empty doc directories.
- Added bundled license assets under `flutter_app/assets/open_source/`.
- Added `OpenSourceLicenseService` to load bundled notices/source-offer records and append Flutter `LicenseRegistry` package licenses.
- Replaced the Settings license row with a clickable `Open Source Licenses` row that opens a scrollable selectable-text dialog.
- Added localized strings for English, Simplified Chinese, Traditional Chinese, and Japanese.
- Updated third-party notices for DejaVu Sans Mono fonts, RootFS copyright retention, and corrected `flutter_blue_plus` version to 1.32.0.
- Added Node drift guards for RootFS copyright preservation and Settings license asset registration.

## Checks Run
- `bash -n scripts/build-prebuilt-rootfs.sh` passed.
- `npm test` passed 39/39.
- `npm run lint -- --no-warn-ignored` passed.
- `python3 /data/data/com.termux/files/home/.codex/skills/app-development-governor/scripts/check_dependency_licenses.py --project .` found 0 unknown npm direct licenses.
- `python3 /data/data/com.termux/files/home/.codex/skills/app-development-governor/scripts/validate_app_memory.py --project .` passed with no warnings.
- `git diff --check` passed.

## Cloud Build
- Pending. A new `rebuild_rootfs=true` cloud build is required because the reusable RootFS must be regenerated to retain package copyright files.

## Version And Artifacts
- Latest packaged candidate before this change remains `8.6 / 205` from run `29869803348`.
- Next fresh cloud build must use logical build `> 205`.

## Known Risks
- Local Flutter/Dart/adb tooling remains unavailable, so Flutter analyze, APK compile, and device smoke require GitHub Actions/device validation.
- Dialog content may be long because it includes package license text; verify scrollability on device.

## Next Actions
- Commit/push this change.
- Dispatch GitHub Actions `Build OpenClaw Apps` with `rebuild_rootfs=true`.
- Verify APK includes `assets/open_source/*` and rebuilt RootFS retains `/usr/share/doc/**/copyright`.
