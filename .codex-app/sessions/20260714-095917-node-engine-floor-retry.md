# 2026-07-14 09:59 UTC - Node Engine Floor Retry

## Goal

Resume after the Codex browser tabs/UA build submission, diagnose the failed GitHub Actions run, patch the rootfs Node.js engine floor, and prepare a new arm64-v8a cloud build.

## Repo Facts Read

- Read app governor, GitHub API cloud build, and open-source license compliance skills plus build/version/testing/release/license references.
- Read `.codex-app/state.md`, `manifest.md`, `architecture.md`, `build.md`, `backlog.md`, and the latest browser-tabs/UA session.
- Verified `AGENTS.md`: build/release only Android `arm64-v8a` APK unless explicitly requested.

## Changes Made

- Confirmed GitHub Actions run `29321533131` failed in `Build bundled OpenClaw rootfs` because `openclaw@latest` rejected Node.js `v24.14.1`.
- Bumped Flutter source metadata from `2.0.50+141` to `2.0.50+142` for the retry.
- Updated runtime defaults to Node.js `24.15.0` for arm64/x86_64 and `22.22.3` for armv7 across app constants, prebuilt rootfs scripts, setup l10n copy, docs, bootstrap resource docs, legacy installer URLs, notices, and the runtime drift self-test.
- Preserved historical changelog facts for old releases and corrected `STRUCTURE.md` to record the actual local Node.js `v24.14.1`.

## Checks Run

- `git diff --check`: passed.
- `npm test`: passed with 14 checks.
- `npm run lint -- --no-warn-ignored`: passed.
- `bash -n scripts/build-apk.sh`, `bash -n scripts/build-prebuilt-rootfs.sh`, `bash -n scripts/prebuilt-rootfs-metadata.sh`, and `bash -n scripts/fetch-prebuilt-rootfs-asset.sh`: passed.
- `python3 -B -m py_compile scripts/build_release.py`: passed.
- `command -v dart`, `command -v flutter`, and `command -v kotlinc`: no local paths available.

## Cloud Build

- Previous run `29321533131`: failed before artifact upload, no APK produced.
- GitHub auth is available through `gh auth status`; token env vars are not set.
- Next action: commit and push via GitHub API helper, then watch the new `Build OpenClaw Apps` run.

## Version And Artifacts

- Source version prepared: `2.0.50+142`.
- Expected next CI install-visible version: `2.0.50+143` or higher, depending on workflow run number.
- No new artifact has been produced yet in this retry session.

## Known Risks

- Local Flutter/Dart/Kotlin checks remain unavailable in Termux.
- The cloud build may still need to rebuild the bundled rootfs if the `basic-resource` restore is unavailable.

## Next Actions

- Push the retry commit to `shwiki1/openclaw-termux-zh` branch `codex-termux-runtime-fix`.
- Watch the GitHub Actions run, download `ciyuanxia-apks` on success, verify APK integrity/libraries/checksum/version, then update project memory again.
