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
- Follow-up cleanup commit `a1f6608` changed RootFS doc cleanup to delete non-copyright files and symlinks under `/usr/share/doc`, after APK inspection of `8.7 / 206` showed Debian doc symlinks such as `changelog.gz` remained.

## Checks Run
- `bash -n scripts/build-prebuilt-rootfs.sh` passed.
- `npm test` passed 39/39.
- `npm run lint -- --no-warn-ignored` passed.
- `python3 /data/data/com.termux/files/home/.codex/skills/app-development-governor/scripts/check_dependency_licenses.py --project .` found 0 unknown npm direct licenses.
- `python3 /data/data/com.termux/files/home/.codex/skills/app-development-governor/scripts/validate_app_memory.py --project .` passed with no warnings.
- `git diff --check` passed.
- Follow-up after `a1f6608`: `bash -n scripts/build-prebuilt-rootfs.sh`, `npm test`, `npm run lint -- --no-warn-ignored`, `check_dependency_licenses.py --project .`, and `git diff --check` passed locally.

## Cloud Build
- Run `29886700435` at commit `d9e15bbd56332d89f0758821d3707f370e9a6fbd` succeeded with `rebuild_rootfs=true`; selected `8.7 / 206`, artifact `ciyuanxia-apks` ID `8517188063`, digest `sha256:3dd6b735a6f750de32f290a3b978a8d0373b790e4f5b01b80292443070b488c2`, final artifact size `291017477` bytes.
- Local `8.7 / 206` verification passed: ZIP SHA-256 matched GitHub, `unzip -t` passed, APK SHA-256 `472494957527e682ec3dabb1dcd03118b2ea5e682f729f2fafbded36755461df`, APK contains `assets/flutter_assets/assets/open_source/OPEN_SOURCE_NOTICES.md`, `OPEN_SOURCE_SOURCES.md`, `THIRD_PARTY_NOTICES.md`, and RootFS archive. RootFS entry size `259105940` bytes, RootFS stream SHA-256 `d5d8da25718dbd9afc2060b26d6e4f1b16a73f07bb2a65eb3ef2f7c77c43f772`, and tar listing confirmed 152 `./usr/share/doc/<package>/copyright` files.
- Run `29888947739` at commit `a1f66089954275ae15307300f3f42b1d7c46d7bf` succeeded with `rebuild_rootfs=true`; selected `8.8 / 207`, artifact `ciyuanxia-apks` ID `8517950770`, digest `sha256:9dffac7c0520aefb6793abfd2e348c2c248d1928e18a38c76e9276675afff685`, final artifact size `291010637` bytes. This is the latest cloud candidate and includes the doc-symlink cleanup follow-up. Local download was stopped at about 50 MiB due to around 100 KiB/s artifact API throughput; resume under `dist/github-run-29888947739/` if APK-level verification is needed.

## Version And Artifacts
- Latest cloud candidate is `8.8 / 207` from run `29888947739`.
- Latest fully locally APK-verified candidate is `8.7 / 206` from run `29886700435`.
- Next fresh cloud build must use logical build `> 207`.

## Known Risks
- Local Flutter/Dart/adb tooling remains unavailable, so Flutter analyze, APK compile, and device smoke require GitHub Actions/device validation.
- Dialog content may be long because it includes package license text; verify scrollability on device.

## Next Actions
- Resume/download `8.8 / 207` locally if APK-level verification of the latest artifact is required.
- Device-smoke Settings -> Open Source Licenses dialog and first-run RootFS extraction/runtime behavior on Android arm64.
