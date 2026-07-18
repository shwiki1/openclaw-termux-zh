# 2026-07-17 Codex Proxy 8787 Hardening

## Goal
- User reported saved API configuration still did not affect Codex and required the built-in local proxy default to be `127.0.0.1:8787` only.

## Repo Facts Read
- Confirmed current app already embeds the Codex relay through generated RootFS files: `/root/.openclaw/codex-proxy.py`, `/root/.openclaw/codex-proxy.js`, `/root/.openclaw/codex-proxy.env`, `/root/.codex/config.toml`, and `/root/.openclaw/bin/codex`.

## Changes Made
- Hardened both generated Codex wrappers so they source `codex-proxy.env`, reject an empty upstream, run `configure_codex_termux_runtime`, start the embedded proxy, poll `http://127.0.0.1:8787/health`, verify the saved upstream appears in health output, and exit visibly if proxy startup fails.
- Removed all old local relay port text from the touched code/test/memory targets per user instruction; default local proxy port is represented as `8787` only.

## Code Changed
- `flutter_app/lib/services/cli_api_config_service.dart`
- `flutter_app/lib/services/cli_tool_service.dart`
- `flutter_app/test/cli_api_config_service_test.dart`
- `lib/test.js`

## Checks Run
- `npm test` passed 32/32.
- `npm run lint -- --no-warn-ignored` passed.
- Focused `git diff --check` passed.
- Focused source search confirmed no old local relay port text in the touched code/test/memory targets.

## Cloud Build
- Local commit: `cc3152b96dd9d94915950ea05ea22ca7ab1cf23f` (`fix: force codex proxy to saved upstream`).
- GitHub API push advanced `shwiki1/openclaw-termux-zh` branch `codex-terminal-ime-lag-fix` from `56f0062` to remote commit `5366470dba8d6ee5bf6e5a1340f16335461afea3`.
- GitHub Actions run `29612968011` succeeded.
- Artifact `ciyuanxia-apks` ID `8419562088`, digest `sha256:bf41f88ce62e13ce5d6061286bb44cd7cb457c200869c7fc63d71099d09e08e7`.
- Downloaded ZIP to `dist/github-run-29612968011/ciyuanxia-apks.zip`; SHA-256 matched artifact digest and `unzip -t` passed.
- Extracted APK: `dist/github-run-29612968011/CiYuanXia-v6.2-181-arm64-v8a.apk`, SHA-256 `cd913c58f147167e5ddc32760fbcef99997c3de7925b6229f4deeb57bad122a6`.
- Required arm64 PRoot libraries are present.

## Known Risks
- Android device smoke is still required to prove the saved upstream is applied on an installed device after RootFS sync and proxy restart.

## Next Actions
- Install `dist/github-run-29612968011/CiYuanXia-v6.2-181-arm64-v8a.apk`.
- Save a shared/Codex API profile.
- Verify Codex generated config uses `http://127.0.0.1:8787/v1`.
- Verify `http://127.0.0.1:8787/health` reports the saved upstream.
- Verify Codex does not proceed if the embedded proxy is not healthy.
