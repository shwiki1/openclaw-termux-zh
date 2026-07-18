# Session Handoff: GitHub Artifact Only APK Delivery

Date: 2026-07-18 UTC

## Goal
- User requested removing the Gitee upload step and directly pulling the APK artifact to local storage.
- Keep work in `/storage/emulated/0/ZeroTermux/开发/openclaw-termux-zh-5.5` and avoid new branches/worktrees.

## Repo Facts Read
- Workflow file is `.github/workflows/flutter-build.yml`.
- APK build job uploads GitHub artifact `ciyuanxia-apks` via `actions/upload-artifact@v7.0.1`.
- Prior run `29647690716` already produced GitHub artifact ID `8430713820` for `6.8 / 187` but failed only in the Gitee split upload step.

## Changes Made
- Removed the `Upload APK parts to Gitee transfer branch` step from `.github/workflows/flutter-build.yml`.
- Kept GitHub artifact upload and release-job artifact download intact.
- Added a Node test in `lib/test.js` asserting that the workflow publishes APKs through GitHub artifacts only and no longer references `scripts/upload-apk-parts-to-gitee-branch.sh` or `GITEE_TRANSFER_BRANCH`.
- Downloaded artifact ID `8430713820` from run `29647690716` to `dist/github-run-29647690716/`.
- Updated `.codex-app/state.md`, `.codex-app/build.md`, and `.codex-app/backlog.md` to record the local artifact path and new delivery policy.

## Checks Run
- `npm test`: 33/33 passed.
- `npm run lint -- --no-warn-ignored`: passed.
- `git diff --check -- .github/workflows/flutter-build.yml lib/test.js`: passed.
- `sha256sum dist/github-run-29647690716/ciyuanxia-apks.zip`: `189c6eaaee4c0af6d48c54bacc0bfbeb13fcbfbba1af7ec644426a99f42f6abc`, matching the GitHub artifact digest.
- `unzip -t dist/github-run-29647690716/ciyuanxia-apks.zip`: passed.
- Extracted APK: `dist/github-run-29647690716/CiYuanXia-v6.8-187-arm64-v8a.apk`.
- APK SHA-256: `df8144fa887bc8648684a5d0105e5b2be0ded157adfd0e8551b7b5213e0105c3`.

## Cloud Build
- No new cloud build has completed for this workflow change yet.
- Pushing this change should trigger the next build with logical build greater than `187`.
- Expected behavior after push: build finishes after GitHub artifact upload and does not run a Gitee upload step.

## Known Risks
- The workflow change is local until pushed to GitHub. The next pushed build should use logical build `> 187` and should no longer fail in Gitee upload.
- Local Flutter/Dart/Kotlin compilers remain unavailable in Termux.
- Device smoke is still needed for the native browser script-library UI/function parity changes packaged in `6.8 / 187`.

## Next Actions
- Commit and push the workflow/test/memory changes to the existing GitHub branch when ready.
- Watch the resulting cloud build and confirm it completes after GitHub artifact upload with no Gitee upload step.
- Device-smoke local APK `dist/github-run-29647690716/CiYuanXia-v6.8-187-arm64-v8a.apk`.
