# 2026-07-17 Codex Proxy Port Reuse

## Goal
- Fix user-reported Codex launch failure where `/root/.openclaw/codex-proxy.py` could not bind `127.0.0.1:8787` because the port was already in use.

## Repo Facts Read
- Generated Codex launchers in `CliApiConfigService` and `CliToolService` start the embedded proxy before executing Codex.
- The previous hardening always attempted to start a fresh proxy during Codex launch, which can fail when a healthy embedded proxy is already serving the saved upstream on `127.0.0.1:8787`.

## Changes Made
- Updated save-time proxy sync to first query `http://127.0.0.1:8787/health` and reuse the existing proxy when it reports the saved upstream.
- Updated the app-generated `/root/.openclaw/bin/codex` wrapper to reuse a healthy existing `8787` proxy before killing/restarting embedded proxy processes.
- Updated the installer-generated `/usr/local/bin/codex` wrapper with the same reuse-before-restart behavior.
- Kept default local proxy port as `8787` only and kept old local relay port text out of code/test/memory targets.

## Checks Run
- `npm test` passed 32/32.
- `npm run lint -- --no-warn-ignored` passed.
- Focused `git diff --check` passed.
- Focused source search confirmed no old local relay port text in code/test/memory targets.

## Cloud Build
- Local commit: `ba6978490ec1f5d2f155c7691d55b76cd1f0138b` (`fix: reuse healthy codex proxy`).
- GitHub API push advanced `shwiki1/openclaw-termux-zh` branch `codex-terminal-ime-lag-fix` to remote commit `bcd71cc537fa3116fe3ca308a7c372dbee9989f0`.
- GitHub Actions run `29614695636` succeeded.
- Artifact `ciyuanxia-apks` ID `8420171963`, digest `sha256:1f5833629c287d4a2b5fe0d9456c82f83c600696fa99f68fabe101d41b395359`.
- Downloaded ZIP to `dist/github-run-29614695636/ciyuanxia-apks.zip`; SHA-256 matched artifact digest and `unzip -t` passed.
- Extracted APK: `dist/github-run-29614695636/CiYuanXia-v6.3-182-arm64-v8a.apk`, SHA-256 `ca687ab5a040179913fddd6a829329e3ac4d6d87e1b30a877667bfe66b6bfaa8`.
- Required arm64 PRoot libraries are present.

## Known Risks
- Android device smoke is still required to confirm the running app updates RootFS wrapper files and no stale wrapper remains after update install.

## Next Actions
- Install `dist/github-run-29614695636/CiYuanXia-v6.3-182-arm64-v8a.apk`.
- Save a Codex/shared API profile, open Codex, close it, then reopen Codex while `8787` remains occupied by the embedded proxy.
- Confirm Codex opens instead of failing with address-in-use.
