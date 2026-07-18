# 2026-07-18 13:30 UTC - Cloud 6.6 Memory Sync

## Goal
- Correct project memory after the user pointed out that cloud build `6.6` had already been built and installed.

## Repo Facts Read
- `gh run list --repo shwiki1/openclaw-termux-zh --limit 20`
- `gh run view 29640675284 --repo shwiki1/openclaw-termux-zh --json ...`
- `gh run view 29640675284 --repo shwiki1/openclaw-termux-zh --log`
- `openclaw-gitee-timeout-work` linked worktree status and commit history.
- `.codex-app/state.md`, `.codex-app/build.md`, `.codex-app/backlog.md`.

## Changes Made
- Updated `.codex-app/state.md` from latest candidate `6.5 / 184` to latest cloud-packaged candidate `6.6 / 185`.
- Updated `.codex-app/build.md` with run `29640675284`, branch `codex-gitee-transfer-timeout-186`, SHA `b08f9931e715f839dc1e63401219a7faeb48699a`, artifact ID `8428690154`, and artifact digest `sha256:c4344f874ef2a64958c570eda23690b693444361e0d8c55aedc07d8f0889517c`.
- Updated `.codex-app/backlog.md` so device smoke and next-build guidance target `6.6 / 185`, with `6.5 / 184` kept only as previous fallback comparison.

## Checks Run
- `gh run view 29640675284 --log` confirmed `Selected next Android build: 185`, `APP_VERSION_NAME: 6.6.0`, `APP_VERSION_DISPLAY: 6.6`, `APP_VERSION_CODE: 185`, APK `CiYuanXia-v6.6-185-arm64-v8a.apk`, artifact ID `8428690154`, and artifact digest `sha256:c4344f874ef2a64958c570eda23690b693444361e0d8c55aedc07d8f0889517c`.
- Artifact download was started but cancelled at user request because the user had already downloaded and installed `6.6 / 185`.

## Cloud Build
- Latest successful cloud run: `29640675284`, branch `codex-gitee-transfer-timeout-186`, commit `b08f9931e715f839dc1e63401219a7faeb48699a`.
- Jobs passed: Flutter analyze, arm64 APK build, PRoot native-library verification, GitHub artifact upload, Gitee split-parts transfer to `apk-transfer-29640675284`.
- GitHub Release job was skipped.

## Version And Artifacts
- Latest cloud-packaged candidate: `6.6 / 185`, APK `CiYuanXia-v6.6-185-arm64-v8a.apk`.
- Artifact: `ciyuanxia-apks`, ID `8428690154`, digest `sha256:c4344f874ef2a64958c570eda23690b693444361e0d8c55aedc07d8f0889517c`.
- User reported the APK has already been downloaded and installed locally; no local SHA verification was performed in this sync.
- Next fresh cloud build must use logical build greater than `185`.

## Known Risks
- Main project memory lagged because the `6.6 / 185` work happened on the separate `openclaw-gitee-timeout-work` linked worktree / `codex-gitee-transfer-timeout-186` cloud branch and was not written back to `.codex-app` in the main development worktree at the time.
- Branch name `codex-gitee-transfer-timeout-186` is a topic name; the actual APK build number from logs is `185`.
- Device smoke status depends on the user's installed APK feedback and has not been independently verified in this session.

## Next Actions
1. Device-smoke the installed `6.6 / 185` candidate: API config binding, Codex 8787 proxy health/reuse, pager controls, browser controls, script-library actions, and haptics.
2. Preserve exact run/SHA/artifact references before any promotion.
3. Any next cloud build must use build number greater than `185`.
