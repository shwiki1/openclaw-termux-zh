# Session: api2py Asset And RootFS Dependency Hotfix

Date: 2026-07-18 UTC

## Goal
- User reported `7.3 / 192` still failed to start the local relay. The visible error showed pip dependencies installed successfully, then `ModuleNotFoundError: No module named 'app'` from `/root/.openclaw/api2py/server.py`.
- User asked whether api2py dependencies can be prebuilt into RootFS so first launch is easier.

## Repo Facts Read
- Repo root: `/storage/emulated/0/ZeroTermux/开发/openclaw-termux-zh-5.5`.
- api2py source assets exist locally under `flutter_app/assets/api2py/`, including `app/config.py`, `app/main.py`, `data/config.example.json`, and `public/static/index.html`.
- `7.3 / 192` APK inspection with `unzip -l dist/github-run-29659937270/CiYuanXia-v7.3-192-arm64-v8a.apk | rg api2py` showed only top-level `assets/api2py/*` files and no nested `app/`, `data/`, `public/static/`, or `scripts/` entries.
- Ordinary APK builds reuse the published `basic-resource` RootFS. RootFS rebuild/publish happens only when `BUILD_BUNDLED_ROOTFS=true` is explicitly set.

## Changes Made
- `flutter_app/pubspec.yaml`: explicitly declares `assets/api2py/app/`, `assets/api2py/data/`, `assets/api2py/public/static/`, and `assets/api2py/scripts/` so Flutter packages nested api2py resources.
- `flutter_app/lib/services/local_api_proxy_service.dart`: after syncing assets into RootFS, verifies required files including `app/__init__.py`, `app/config.py`, `app/main.py`, and `public/static/index.html`; throws a clear incomplete-resource error if missing.
- `flutter_app/assets/api2py/start.sh`: checks for the `app/` Python package before starting and reports incomplete bundled files directly.
- `scripts/build-prebuilt-rootfs.sh`: adds `python3-pip` to base packages and preinstalls api2py requirements from `flutter_app/assets/api2py/requirements.txt` during intentional RootFS builds.
- `lib/test.js`: added guards for nested api2py asset declarations, required package files, incomplete-resource diagnostics, and RootFS preinstalled api2py dependencies.

## Checks Run
- `npm test` passed 36/36.
- `npm run lint -- --no-warn-ignored` passed.
- `bash -n flutter_app/assets/api2py/start.sh flutter_app/assets/api2py/stop.sh scripts/build-prebuilt-rootfs.sh` passed.
- `git diff --check` passed.
- Existing `7.3 / 192` APK was inspected and confirmed to be missing nested api2py assets.

## Cloud Build
- No cloud build was started in this session.
- Next APK build must use a new logical build greater than `192` and then verify nested api2py files are present in the APK before delivery.

## Known Risks
- Installed `7.3 / 192` remains bad for api2py relay startup because it lacks nested api2py assets.
- RootFS dependency preinstall is only a script change until a dedicated `basic-resource` RootFS rebuild/publish is approved and completed.
- Local Flutter/Dart/Kotlin compilers remain unavailable.

## Next Actions
- Build a new APK for the api2py asset-packaging fix and inspect the APK for nested api2py assets before reporting it as usable.
- If user wants first-run startup without pip installs, explicitly rebuild and publish `basic-resource`, then build a follow-up APK that reuses the new RootFS.
