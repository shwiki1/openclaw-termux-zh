# 2026-07-17 Codex Proxy Occupied Port Release

## Goal
- Fix repeated Codex launch failure where the embedded proxy still failed to bind `127.0.0.1:8787` with `OSError: [Errno 98] Address already in use`.
- Build a new APK, upload it through Gitee for local download, verify the Gitee download, then remove the Gitee-hosted temporary artifact.

## Repo Facts Read
- Save-time proxy sync still had an unconditional `pkill` before the health reuse check, which weakened the previous reuse fix.
- The generated Python proxy used plain `http.server.ThreadingHTTPServer` without `allow_reuse_address`.
- `pkill` by command line was insufficient when a stale process still owned `8787` but did not match the expected command pattern.
- Gitee rejects direct APK upload as a single file above 100MB, both for Release attachments and normal git pushes.

## Changes Made
- Removed the unconditional save-time proxy kill before the reuse check.
- Added `openclaw_kill_codex_proxy_port()` to save-time sync, the generated `/root/.openclaw/bin/codex` wrapper, and the installer-generated `/usr/local/bin/codex` wrapper.
- The helper scans `/proc/net/tcp` and `/proc/net/tcp6` for local port `8787`, maps socket inodes back to `/proc/<pid>/fd`, and sends `SIGTERM` to the owning process before starting a fresh embedded proxy.
- Added `ReusableThreadingHTTPServer` with `allow_reuse_address = True` to the generated Python proxy.
- Updated Flutter and Node source guards for the new port-release and address-reuse behavior.

## Checks Run
- `npm test` passed 32/32.
- `npm run lint -- --no-warn-ignored` passed.
- Focused `git diff --check` passed.
- Focused source search confirmed no old local relay port text in code/test/memory targets.

## Cloud Build
- Local commit: `c1ce407` (`fix: release occupied codex proxy port`).
- GitHub API push advanced `shwiki1/openclaw-termux-zh` branch `codex-terminal-ime-lag-fix` to remote commit `5a86a63f7735a8508f058f1fe5fc16c3ef1b6c96`.
- GitHub Actions run `29616280314` succeeded.
- Artifact `ciyuanxia-apks` ID `8420693125`, digest `sha256:d6d331615dff8e928d77fa611ea881cc32328a1fc4503b9e05d8d899a524380f`.
- Downloaded ZIP to `dist/github-run-29616280314/ciyuanxia-apks.zip`; SHA-256 matched artifact digest and `unzip -t` passed.
- Extracted APK: `dist/github-run-29616280314/CiYuanXia-v6.4-183-arm64-v8a.apk`, SHA-256 `5e5141757560784a0f4dcfd963ab850eab5e309d5c3c2861f8c7301bf7d921d9`.
- Required arm64 PRoot libraries are present.

## Gitee Transfer
- Direct single-file push of the APK to Gitee was rejected by the 100MB limit.
- Split the APK into four parts under 100MB and pushed them to temporary Gitee branch `apk-transfer-29616280314`.
- Gitee raw URL returned 403 for the temporary branch, and Gitee Contents API returned truncated 10MB content for large blobs.
- Verified Gitee download by `git clone --depth 1 --branch apk-transfer-29616280314`, reassembling the parts into `dist/gitee-run-29616280314/CiYuanXia-v6.4-183-arm64-v8a.apk`.
- Reassembled Gitee APK SHA-256 matched the GitHub APK: `5e5141757560784a0f4dcfd963ab850eab5e309d5c3c2861f8c7301bf7d921d9`.
- Deleted Gitee temporary branch `apk-transfer-29616280314` after verification.

## Known Risks
- Android device smoke is still required to confirm the installed app regenerates RootFS proxy files and that the port-release helper works under the app's runtime permissions.
- Gitee may retain unreachable large git objects server-side after branch deletion until its own garbage collection; do not use this transfer path as permanent artifact hosting.

## Next Actions
- Install `dist/gitee-run-29616280314/CiYuanXia-v6.4-183-arm64-v8a.apk` or the identical GitHub-downloaded APK.
- Save API config and open Codex repeatedly, including after a previous failed proxy start, to confirm no address-in-use failure remains.
