# 2026-07-17 14:30 UTC - Codex Upstream Binding Follow-up

## Goal

Fix device feedback that a saved API address was not becoming the upstream behind the local Codex proxy on port 8787.

## Repo Facts Read

- Shared API profiles and per-tool settings are persisted separately.
- The UI implicitly selects the only shared profile, but that selection was not necessarily persisted for Codex.
- Runtime generation only enables the Codex proxy when the resolved Codex config has a non-empty base URL.

## Changes Made

- Resolve the sole shared API as the default when a tool has no explicit shared-profile selection.
- Persist the config dialog's implicit first-profile selection immediately after returning from shared API management.
- Load the generated proxy env before restart, then poll 8787 `/health` and verify it reports the newly saved upstream URL.
- Report proxy startup/health failures through the save operation instead of silently accepting stale routing.

## Checks Run

- `npm test`: 32 passed, 0 failed.
- `npm run lint -- --no-warn-ignored`: passed.
- `git diff --check`: passed.
- Local Flutter/Dart/Kotlin compilers remain unavailable.

## Cloud Build

- Target branch: GitHub `codex-terminal-ime-lag-fix`.
- Run `29587775641` for logical `177`, semantic `5.8.0`, display `5.8` failed during release Flutter compilation because shell variables in the proxy health-check command were parsed as Dart interpolations.
- Follow-up commit `34fe5f5` converted the proxy health-check command to a raw multi-line Dart string with explicit path placeholders.
- API push advanced the GitHub feature branch to `cde66bb40980f685e49c78c748aee1f26e509ad2`.
- Retry run `29588452989` succeeded and produced logical `177`, semantic `5.8.0`, display `5.8`, arm64 only. The failed predecessor did not upload an APK artifact, so no `178 / 5.9` artifact was needed.

## Version And Artifacts

- Source anchor remains `2.5.0+143`.
- Artifact ZIP: `dist/github-run-29588452989/ciyuanxia-apks.zip`, SHA-256 `29dfc1e1320d8485abf2994ca6b53345b0f2d80125e313c1e24be4803eff9ed9`.
- APK: `dist/github-run-29588452989/CiYuanXia-v5.8-177-arm64-v8a.apk`, size 316,573,547 bytes, SHA-256 `fe45bafe16761fe3f7151a11f47d7dbeea015430b22f7d49d4e8a23254543e17`.
- Manifest verification: package `com.agent.cyx`, split `versionCode=2177`, `versionName=5.8`, min SDK 29, target SDK 36.
- Integrity/signing verification passed: `unzip -t`, `zipalign -c -p -v 4`, `apksigner verify --verbose --print-certs`; signer SHA-256 `0618eafd1855855749abb7c04d6f44edf9a4b7cb09e26fd882e856d5c994dde6` matches the published `5.4` signer.

## Known Risks

- Android device verification is still required for the exact save/restart/request path.
- The Actions log still contains misleading debug-signing fallback script text even though the APK certificate matches the release signer.

## Next Actions

- Install `5.8 / 177` over `5.7 / 176` or published `5.4 / 173`, create or edit the sole shared API, save it, and verify `curl -fsS http://127.0.0.1:8787/health` inside RootFS reports the user-entered upstream before sending a Codex request.
