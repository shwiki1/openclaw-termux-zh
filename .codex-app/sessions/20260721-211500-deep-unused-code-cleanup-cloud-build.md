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
- Cleanup commit `c8a87a3384edf27350e7f4125f679363ec0d87b0` was pushed to GitHub branch `codex-terminal-ime-lag-fix`.
- GitHub Actions run `29867482912` completed successfully in about 8 minutes. It selected semantic `8.5.0`, display `8.5`, Android build `204`, restored and verified the prebuilt `basic-resource` RootFS, skipped RootFS build/publish, passed Flutter analyze, built the arm64 APK, verified APK native PRoot binaries, collected artifacts, and uploaded GitHub artifact `ciyuanxia-apks`. No Gitee upload step ran.

## Version And Artifacts
- Latest published GitHub Release remains `5.4 / 173`.
- Latest GitHub artifact candidate after this cleanup is `8.5 / 204` from Actions run `29867482912`, head SHA `c8a87a3384edf27350e7f4125f679363ec0d87b0`.
- GitHub artifact `ciyuanxia-apks` ID `8509966202`, digest `sha256:0efb1d1438808a284c6591a2a1835cf809426006cbd72db13671c9f7764074b3`, artifact size `311437095` bytes.
- Local artifact path: `dist/github-run-29867482912/ciyuanxia-apks.zip`; ZIP SHA-256 `0efb1d1438808a284c6591a2a1835cf809426006cbd72db13671c9f7764074b3`; `unzip -t` passed.
- Local APK path: `dist/github-run-29867482912/CiYuanXia-v8.5-204-arm64-v8a.apk`; size `325175770` bytes; APK SHA-256 `42d29e264f4a92b4829121b4ac9c79f5465596fd22240e6826e9f7810f336675`.
- APK inspection confirmed api2py frontend/backend assets, `data/config.example.json`, offline Tailwind/Lucide assets, and `openclaw-rootfs-noble-arm64.tar.gz` are present.

## Known Risks
- Local Flutter/Dart/adb tooling remains unavailable; Android compile validation depends on GitHub Actions.
- The workflow still does not run `flutter test`; it runs Flutter analyze and APK packaging in cloud.
- Device smoke for `8.5 / 204` remains required.

## Next Actions
- Device-smoke `8.5 / 204` on Android, especially CodeBuddy through the local api2py relay and the prior proxy/API-management regression list.
- Future APK builds must use logical build `> 204` and continue to reuse the prebuilt `basic-resource` RootFS unless the user explicitly requests a RootFS rebuild.
