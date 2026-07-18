# 2026-07-17 20:18 UTC - Gitee Mirror And RootFS Build

## Goal

Continue from the 5.9 config-save EACCES fix, push cloud builds, and test whether mirroring the APK from GitHub to Gitee improves local download speed.

## Repo Facts Read

- Workflow path: `.github/workflows/flutter-build.yml`.
- Gitee mirror script path: `scripts/mirror-apk-to-gitee.py`.
- GitHub feature branch: `codex-terminal-ime-lag-fix`.
- Gitee repo target used for mirror tests: `cds-y-code/openclaw-termux-zh`.

## Changes Made

- Added `scripts/mirror-apk-to-gitee.py` to create or reuse a Gitee Release and upload APK artifacts without exposing `GITEE_TOKEN` in command lines.
- Wired `.github/workflows/flutter-build.yml` to call the Gitee mirror script after GitHub artifact upload.
- Fixed Gitee Release creation by supplying `target_commitish`.
- Confirmed Gitee rejects this APK as a Release attachment because the file is over 100MB, then changed the script to detect oversized APKs and skip Gitee mirroring without failing the cloud build.

## Cloud Builds

- Run `29606442841`: success at `0210c0f385cf7235af22fe7403a488cc5fe09d7c`, packaged the RootFS EACCES write fix. Artifact ID `8417168720`, digest `sha256:2bda157ec4b30137dc7f7804df4c373f73dccef46ee02c6395e805f1b8d38979`.
- Run `29608651730`: success at the same SHA after manual dispatch. Artifact ID `8417977066`, digest `sha256:2a6af3580c5ea253075026358570a518245d5c3e8daac9d1896ee931bbbf6514`.
- Run `29609131224`: failed only in Gitee Release creation because Gitee required `target_commitish`.
- Run `29609648953`: failed only in Gitee attachment upload because Gitee rejects files over `104857600` bytes.
- Run `29610280469`: success at `56f0062b6642dfc16c0d5b1efd671bd4c75e18fa`. Produced `CiYuanXia-v6.2-181-arm64-v8a.apk`, artifact ID `8418581492`, digest `sha256:5594eff849aeee2e5be35c6dcaf94d6c1ab30fb043e3b552731d698191ec816d`. Gitee step logged the oversized APK and skipped cleanly.

## Checks Run

- `python3 -B -m py_compile scripts/mirror-apk-to-gitee.py`: passed.
- `git diff --check -- .github/workflows/flutter-build.yml scripts/mirror-apk-to-gitee.py`: passed.
- GitHub Actions run `29610280469`: passed Flutter analyze, Android arm64 APK build, PRoot native-library verification, artifact upload, and Gitee mirror skip handling.
- Local Flutter/Dart/Kotlin compilers remain unavailable.

## Outcome

- The RootFS EACCES fix is built successfully in installable APK artifacts.
- Direct Gitee Release mirroring is not viable for the current APK because the APK is about 316MB and Gitee Release attachments are capped at 100MB.
- Use GitHub Actions artifact `8418581492` from run `29610280469` for the latest APK unless a future distribution host supports files over 316MB.

## Known Risks

- The latest APK still needs Android device smoke for the RootFS config-save path.
- Gitee Release may contain a created tag/release without the APK from the failed oversize upload attempt; do not treat it as a valid installer source.
- GitHub artifact download speed may still be slow from the user's device/network.

## Next Actions

- Download artifact `8418581492` into `dist/github-run-29610280469/`, verify ZIP/APK integrity, then install-smoke on Android.
- If China-side distribution is still required, use a host that accepts >316MB files instead of Gitee Release attachments, or split/repackage the installer.
