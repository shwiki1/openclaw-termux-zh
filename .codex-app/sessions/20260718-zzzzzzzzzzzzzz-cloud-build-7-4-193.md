# Session: Cloud Build 7.4 / 193

Date: 2026-07-18 UTC

## Goal
- User requested `提交构建` after the api2py nested-asset packaging fix and RootFS dependency preinstall script change.

## Repo Facts Read
- Repo root: `/storage/emulated/0/ZeroTermux/开发/openclaw-termux-zh-5.5`.
- Branch: `codex-terminal-ime-lag-fix`.
- GitHub repo: `shwiki1/openclaw-termux-zh`.
- APK delivery policy: GitHub Actions artifact download to `dist/github-run-<run-id>/`; no Gitee upload.
- RootFS policy: ordinary APK builds reuse the published `basic-resource` archive; RootFS rebuild/publish requires explicit `BUILD_BUNDLED_ROOTFS=true`.

## Changes Made
- Committed local changes as `c92b7e0 fix: package api2py assets`.
- Pushed to the existing GitHub branch through GitHub API; remote commit SHA is `3bbfa196279a72c2326c84a85a02c1a335f5ec85`.
- Updated project memory with build provenance and local artifact verification.

## Checks Run
- Pre-push checks from the hotfix session: `npm test` 36/36 passed; `npm run lint -- --no-warn-ignored` passed; `bash -n flutter_app/assets/api2py/start.sh flutter_app/assets/api2py/stop.sh scripts/build-prebuilt-rootfs.sh` passed; `git diff --check` passed.
- GitHub Actions passed RootFS restore/verify, Flutter analyze, arm64 APK build, APK PRoot native-library verification, artifact collection, and artifact upload.
- Local artifact verification: ZIP SHA matched artifact digest, `unzip -t` passed, APK SHA recorded, and APK inspection confirmed nested api2py assets exist.

## Cloud Build
- Run: `29661374383`.
- Version/build: install-visible `7.4`, semantic `7.4.0`, Android build `193`.
- APK: `CiYuanXia-v7.4-193-arm64-v8a.apk`.
- Artifact: `ciyuanxia-apks`, ID `8434470729`, digest `sha256:02038c0f97e1ca38ed27dd854758fac212b7bacf0eb81103100aca9e7ab5743d`, size `302975029` bytes.
- RootFS was reused from the published `basic-resource` archive. `Build bundled OpenClaw rootfs` and `Publish bundled OpenClaw rootfs` were skipped.
- No Gitee upload step ran.
- Release publication was skipped.

## Local Artifact Verification
- ZIP: `dist/github-run-29661374383/ciyuanxia-apks.zip`.
- ZIP SHA-256: `02038c0f97e1ca38ed27dd854758fac212b7bacf0eb81103100aca9e7ab5743d`.
- Extracted APK: `dist/github-run-29661374383/CiYuanXia-v7.4-193-arm64-v8a.apk`.
- APK SHA-256: `e1d14cacdf52fd4590e668785bb5d4d174becae925ec6c30ffbcd1c632d1b1ef`.
- APK contains nested api2py assets: `assets/flutter_assets/assets/api2py/app/__init__.py`, `app/config.py`, `app/main.py`, `data/config.example.json`, `public/static/index.html`, and `scripts/migrate_from_php.py`.

## Known Risks
- This is a GitHub artifact candidate, not a published Release.
- It reuses the current published RootFS, so api2py Python dependencies are not preinstalled in first-run RootFS yet. The app still has runtime pip fallback. A dedicated `basic-resource` rebuild/publish is needed to make dependency preinstall effective.
- Android device smoke is still required for relay startup and browser UI behavior.

## Next Actions
- Device-smoke `7.4 / 193`: start/restart local relay, confirm no `No module named 'app'`, confirm frontend login/setup is gone, confirm `管理 API` writes to api2py config, and verify managed CLIs use `http://127.0.0.1:9999/v1`.
- Only on explicit request, rebuild/publish `basic-resource` with preinstalled api2py dependencies, then build another APK with logical build `> 193`.
