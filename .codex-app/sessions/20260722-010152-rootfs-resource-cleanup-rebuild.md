# 2026-07-22 01:01 UTC - RootFS Resource Cleanup Rebuild

## Goal
- User asked why APK remained large and requested checking the reused prebuilt `basic-resource` package for unused files/code, then rebuilding it if useful.

## Repo Facts Read
- `8.5 / 204` APK was dominated by `assets/flutter_assets/assets/bootstrap/openclaw-rootfs-noble-arm64.tar.gz` at `279574832` bytes.
- The old local APK was `dist/github-run-29867482912/CiYuanXia-v8.5-204-arm64-v8a.apk`, APK SHA-256 `42d29e264f4a92b4829121b4ac9c79f5465596fd22240e6826e9f7810f336675`.
- Current workflow supports intentional RootFS resource rebuild via `workflow_dispatch` input `rebuild_rootfs=true`; ordinary builds should reuse `basic-resource`.

## Changes Made
- Updated `scripts/build-prebuilt-rootfs.sh` cleanup to prune apt/npm logs/caches, temp files, docs/man/info, Python bytecode, sourcemaps, and node_modules tests/examples/docs/spec files before packaging the prebuilt RootFS.
- Updated `.codex-app/state.md`, `.codex-app/build.md`, and `.codex-app/backlog.md` with the audit, rebuild, and artifact results.

## Checks Run
- `bash -n scripts/build-prebuilt-rootfs.sh` passed.
- `npm test` passed 37/37.
- `npm run lint -- --no-warn-ignored` passed.
- `python3 /data/data/com.termux/files/home/.codex/skills/app-development-governor/scripts/audit_github_actions.py --project .` passed with no warnings.
- `python3 /data/data/com.termux/files/home/.codex/skills/app-development-governor/scripts/validate_app_memory.py --project .` passed before cloud build.
- `git diff --check` passed.
- `scan_app_secrets.py` reported high-risk paths only inside local `.tmp/rootfs-audit` extracted RootFS certificates plus expected secret-like field names; `.tmp/rootfs-audit` is local scratch and not committed.

## Cloud Build
- Commit `e9e9408ce6f576339aa31ee21395581ad7313615` was pushed to GitHub branch `codex-terminal-ime-lag-fix`.
- Push-triggered ordinary run `29869796961` was cancelled by workflow concurrency when the manual resource rebuild started.
- Manual GitHub Actions run `29869803348` completed successfully with `rebuild_rootfs=true`. It rebuilt and published `basic-resource`, verified RootFS, selected build `205`, passed Flutter analyze, built the arm64 APK, verified PRoot native libraries, collected artifacts, and uploaded GitHub artifact `ciyuanxia-apks`.

## Version And Artifacts
- New candidate: `8.6 / 205` from run `29869803348`, commit `e9e9408ce6f576339aa31ee21395581ad7313615`.
- GitHub artifact `ciyuanxia-apks` ID `8511387448`, digest `sha256:f8e14094a8fd786728326e25a162e85aed2220e3d9bf8ea458723d9158b5359f`, size `290516190` bytes.
- Local ZIP: `dist/github-run-29869803348/ciyuanxia-apks.zip`, SHA-256 `f8e14094a8fd786728326e25a162e85aed2220e3d9bf8ea458723d9158b5359f`; `unzip -t` passed.
- Local APK: `dist/github-run-29869803348/CiYuanXia-v8.6-205-arm64-v8a.apk`, size `332745122` bytes, APK SHA-256 `8251bf305a1a2f1eb30ba86fbcf854bb0f2cd19e4893b842dda9de06da4046a5`.
- APK RootFS entry is now `258613524` bytes, down from `279574832` bytes in `8.5 / 204`, saving `20961308` bytes compressed.
- Updated `basic-resource` asset: `openclaw-rootfs-noble-arm64.tar.gz` size `258613524`, digest `sha256:51127314ee170eb728de70287c6242774d9ccf52e5f558cb07bd623d6cfffc50`; manifest digest `sha256:07bf5f7993c9170279d9f3abd14741120caf5a147b972f42a689a6e474a942b6`.

## Known Risks
- Local Flutter/Dart/adb tooling remains unavailable; Android compile validation was via GitHub Actions, not local SDK.
- Device smoke for `8.6 / 205` remains required, especially first-run RootFS extraction and CLI relay behavior after docs/cache pruning.
- Removing docs/man/info and source maps affects in-RootFS help/debug material, not expected runtime behavior.

## Next Actions
- Device-smoke `8.6 / 205` on Android.
- Future ordinary APK builds should reuse the updated `basic-resource`; do not rebuild RootFS again unless explicitly requested.
- Next fresh cloud build must use logical build `> 205`.
