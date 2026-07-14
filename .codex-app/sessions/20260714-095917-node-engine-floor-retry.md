# 2026-07-14 09:59 UTC - Node Engine Floor Retry

## Goal

Resume after the Codex browser tabs/UA build submission, diagnose the failed GitHub Actions run, patch the rootfs Node.js engine floor, and complete a new arm64-v8a cloud build.

## Repo Facts Read

- Read app governor, GitHub API cloud build, and open-source license compliance skills plus build/version/testing/release/license references.
- Read `.codex-app/state.md`, `manifest.md`, `architecture.md`, `build.md`, `backlog.md`, and the latest browser-tabs/UA session.
- Verified `AGENTS.md`: build/release only Android `arm64-v8a` APK unless explicitly requested.

## Changes Made

- Confirmed GitHub Actions run `29321533131` failed in `Build bundled OpenClaw rootfs` because `openclaw@latest` rejected Node.js `v24.14.1`.
- Bumped Flutter source metadata from `2.0.50+141` to `2.0.50+142` for the retry.
- Updated runtime defaults to Node.js `24.15.0` for arm64/x86_64 and `22.22.3` for armv7 across app constants, prebuilt rootfs scripts, setup l10n copy, docs, bootstrap resource docs, legacy installer URLs, notices, and the runtime drift self-test.
- Preserved historical changelog facts for old releases and corrected `STRUCTURE.md` to record the actual local Node.js `v24.14.1`.
- Committed the fix locally as `bc8b808` and pushed through the GitHub API as remote commit `97c7861608daca62c22a9ae1c1259d7abe7e02c3`.

## Checks Run

- `git diff --check`: passed.
- `npm test`: passed with 14 checks.
- `npm run lint -- --no-warn-ignored`: passed.
- `bash -n scripts/build-apk.sh`, `bash -n scripts/build-prebuilt-rootfs.sh`, `bash -n scripts/prebuilt-rootfs-metadata.sh`, and `bash -n scripts/fetch-prebuilt-rootfs-asset.sh`: passed.
- `python3 -B -m py_compile scripts/build_release.py`: passed.
- `command -v dart`, `command -v flutter`, and `command -v kotlinc`: no local paths available.
- GitHub Actions run `29323908852`: completed successfully.
- Artifact ZIP `unzip -t`: passed.
- APK `unzip -t`: passed.
- APK `aapt dump badging`: `package='com.agent.cyx'`, `versionCode='2143'`, `versionName='2.0.50+143'`.
- APK `apksigner verify --print-certs`: passed; signer SHA-256 `0618eafd1855855749abb7c04d6f44edf9a4b7cb09e26fd882e856d5c994dde6`.
- APK `zipalign -c -p 4`: passed.
- Bundled rootfs gzip test: passed.
- Bundled rootfs Node.js header: `24.15.0`.
- Bundled rootfs OpenClaw package version: `2026.6.11`.

## Cloud Build

- Previous run `29321533131`: failed before artifact upload, no APK produced.
- Retry run `29323908852`: succeeded.
- Workflow URL: `https://github.com/shwiki1/openclaw-termux-zh/actions/runs/29323908852`.

## Version And Artifacts

- Source version prepared: `2.0.50+142`.
- Produced CI install-visible version: `2.0.50+143`.
- Artifact ID: `8307231575`.
- Artifact ZIP digest/SHA256: `sha256:c64c3f6a539b77b506a799f8dc224ae96f51851b577bc58c7688b531c62b17b0`.
- Downloaded ZIP: `artifacts/github-run-29323908852/ciyuanxia-apks.zip`.
- Downloaded APK: `artifacts/github-run-29323908852/CiYuanXia-v2.0.50-143-arm64-v8a.apk`.
- APK SHA256: `dedeed3176251da991d9e55435b633a6034d8e9cb80a2549054d12f75df48010`.

## Known Risks

- Local Flutter/Dart/Kotlin checks remain unavailable in Termux.
- Android device smoke is still needed for browser multi-tab, UA switching, desktop-page layout behavior, runtime setup, and in-place install/update behavior.

## Next Actions

- Device-smoke the new arm64 APK on Android, focusing on Codex browser multi-tab/UA behavior and runtime bootstrap.
