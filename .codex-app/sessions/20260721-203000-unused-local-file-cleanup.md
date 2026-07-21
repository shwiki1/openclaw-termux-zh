# 2026-07-21 20:30 UTC - Unused Local File Cleanup

## Goal
- User requested removal of files/code that are not actually used in the project.

## Repo Facts Read
- Existing app memory validated cleanly before cleanup.
- Working tree already had prior `.codex-app` state-sync edits; they were preserved.
- `flutter_app/assets/bootstrap/claude-code-2.1.148-bundle.tar.gz` was 70 MB, untracked, ignored by `.gitignore`, not declared in `flutter_app/pubspec.yaml`, and had no source references.
- Python bytecode caches under `flutter_app/assets/api2py/` and `scripts/` were generated local artifacts and ignored by `.gitignore` via `__pycache__/`.
- `NativeUiStyle.kt` was not removed: although the filename itself has no external class-name references, its `NativeUiPalette`, `nativeCardDrawable`, `nativeRoundedStateDrawable`, and `nativeDp` helpers are referenced throughout native terminal/browser Kotlin files.
- `flutter_app/assets/sample_configs/openclaw/*.json` were not removed: `BundledSampleConfigService` loads `assets/sample_configs/openclaw` dynamically by version.

## Changes Made
- Removed ignored Python cache directories/files under `flutter_app/assets/api2py/` and `scripts/`.
- Removed ignored local bootstrap cache `flutter_app/assets/bootstrap/claude-code-2.1.148-bundle.tar.gz`.
- Updated `.codex-app/state.md` with the cleanup scope, retained-file rationale, and checks.
- No tracked business source files were deleted.

## Checks Run
- `rg`/`find` reference scans for bootstrap archives, sample configs, scripts, Kotlin helpers, ignored temp files, `.pyc`, and large local files.
- `git check-ignore -v flutter_app/assets/bootstrap/claude-code-2.1.148-bundle.tar.gz ...`: confirmed the removed large archive and Python cache files were ignored.
- `python3 -m py_compile flutter_app/assets/api2py/app/*.py flutter_app/assets/api2py/server.py flutter_app/assets/api2py/scripts/migrate_from_php.py` passed; generated caches were removed afterward.
- `bash -n flutter_app/assets/api2py/start.sh flutter_app/assets/api2py/stop.sh scripts/build-prebuilt-rootfs.sh scripts/fetch-prebuilt-rootfs-asset.sh scripts/publish-prebuilt-rootfs-asset.sh scripts/build-apk.sh` passed.
- `npm test` passed 37/37.
- `npm run lint -- --no-warn-ignored` passed.
- `git diff --check` passed.
- Final scan found no remaining `__pycache__`, `.pyc`, or non-`node_modules`/non-`dist` files over 50 MB.

## Cloud Build
- No cloud build was requested or launched.

## Version And Artifacts
- Latest published GitHub Release remains `5.4 / 173`.
- Latest GitHub artifact candidate remains `8.4 / 203` from Actions run `29740833706`.
- Latest local APK remains `dist/github-run-29740833706/CiYuanXia-v8.4-203-arm64-v8a.apk`, SHA-256 `138036ffcfe0a740d8f2dc0785c592ded3fdec39cbeb2e8c7191cbdf6f7dbf36`.
- Next fresh cloud build must use logical build greater than `203`.

## Known Risks
- This cleanup intentionally avoided deleting files that can be loaded dynamically, used by manual release/resource workflows, or needed as fallback runtime resources.
- Local Flutter/Dart/adb tooling remains unavailable; Flutter analyze/test, Android compile, and device smoke still require cloud/device environments.

## Next Actions
- Device-smoke `8.4 / 203` remains the top release-readiness task.
- If deeper code pruning is desired, run it as a separate tracked-source refactor with Flutter SDK analysis/build available, because many Dart/Kotlin assets are referenced dynamically or through platform channels.
