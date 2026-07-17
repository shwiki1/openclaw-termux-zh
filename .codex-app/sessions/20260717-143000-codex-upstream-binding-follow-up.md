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
- Required retry build: logical `178`, semantic `5.9.0`, display `5.9`, arm64 only.

## Version And Artifacts

- Source anchor remains `2.5.0+143`.
- No `177` artifact recorded yet.

## Known Risks

- The follow-up still requires cloud Flutter/Kotlin compilation and Android device verification.

## Next Actions

- Commit only relevant files, API-push, watch Actions, download and verify the APK, then repeat the exact device save/request flow.
