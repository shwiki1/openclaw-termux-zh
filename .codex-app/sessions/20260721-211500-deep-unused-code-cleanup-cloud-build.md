# 2026-07-21 21:15 UTC - Deep Unused Code Cleanup And Cloud Build

## Goal
- User requested deep unused-code cleanup combined with cloud build validation.

## Repo Facts Read
- Existing app memory validated cleanly before work.
- GitHub CLI is authenticated; no token values were written to the repository.
- Current APK delivery policy is GitHub Actions artifact-only. `.github/workflows/flutter-build.yml` no longer references the old Gitee split upload step, and `lib/test.js` already guards against restoring that workflow reference.
- `.codex-app/build.md` records Gitee Release attachments as non-viable for current APK size; split-branch upload timed out historically.
- Dart/Kotlin file scans found many low text-reference files, but they are route entries, dynamic Flutter assets, platform-channel surfaces, native UI helpers, tests, or manual/build tooling. They were not safe to delete solely by filename reference counts.

## Changes Made
- Removed obsolete tracked Gitee distribution scripts:
  - `scripts/mirror-apk-to-gitee.py`
  - `scripts/upload-apk-parts-to-gitee-branch.sh`
- Added `lib/test.js` guards that both deleted scripts must remain absent and the workflow remains GitHub-artifact-only.
- Added `.github/workflows/flutter-build.yml` concurrency with group `${{ github.workflow }}-${{ github.ref }}` and `cancel-in-progress: true`.
- Updated `.codex-app/state.md`, `.codex-app/build.md`, and `.codex-app/backlog.md` with the current cleanup and distribution policy.

## Checks Run
- `npm test` passed 37/37.
- `npm run lint -- --no-warn-ignored` passed.
- `bash -n scripts/build-apk.sh scripts/build-prebuilt-rootfs.sh scripts/fetch-prebuilt-rootfs-asset.sh scripts/fetch-proot-binaries.sh scripts/prebuilt-rootfs-metadata.sh scripts/publish-prebuilt-rootfs-asset.sh` passed.
- `python3 -m py_compile scripts/build_release.py scripts/versioning.py` passed; generated `scripts/__pycache__` was removed afterward.
- `python3 /data/data/com.termux/files/home/.codex/skills/app-development-governor/scripts/audit_github_actions.py --project .` passed with no warnings after concurrency was added.
- `python3 /data/data/com.termux/files/home/.codex/skills/app-development-governor/scripts/scan_app_secrets.py --project .` found no high-risk secrets; it reported expected secret-like field names and ignore-rule gaps for `*.p12`/`*.mobileprovision`.
- `git diff --check` passed.

## Cloud Build
- Cloud build not launched yet at the time this handoff was written; next step is to commit/push the cleanup and watch the GitHub Actions run.
- Expected next logical Android build must be greater than `203`; the workflow derives this from existing release/workflow history.

## Version And Artifacts
- Latest published GitHub Release remains `5.4 / 173`.
- Latest GitHub artifact candidate before this cleanup remains `8.4 / 203` from Actions run `29740833706`.
- Latest local APK before this cleanup remains `dist/github-run-29740833706/CiYuanXia-v8.4-203-arm64-v8a.apk`, SHA-256 `138036ffcfe0a740d8f2dc0785c592ded3fdec39cbeb2e8c7191cbdf6f7dbf36`.
- The cleanup cloud validation build must use logical build `> 203` and reuse the prebuilt `basic-resource` RootFS.

## Known Risks
- Local Flutter/Dart/adb tooling remains unavailable; Android compile validation depends on GitHub Actions.
- The workflow still does not run `flutter test`; it runs Flutter analyze and APK packaging in cloud.
- Device smoke for `8.4 / 203` and any new cleanup candidate remains required.

## Next Actions
- Commit and push the cleanup to `codex-terminal-ime-lag-fix`.
- Watch the triggered GitHub Actions APK build, record run id/version/build/artifact details, and download/verify the artifact if successful.
- If the cloud build fails, patch the minimal issue and produce a fresh build number for the retry.
