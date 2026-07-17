# 2026-07-17 12:05 UTC - CLI Proxy And Terminal Top UI Fix

## Goal

Fix configuration saves not restarting the local Codex proxy and repair the broken top UI on all non-Codex native CLI terminals, then push an arm64 cloud build.

## Repo Facts Read

- CLI API persistence and generated proxy launchers in `CliApiConfigService`.
- Ordinary CLI launch path through `NativeTerminalActivity`; Codex remains on `NativeTerminalPagerActivity`.
- The Codex pager already owned system-bar and IME insets, while the ordinary activity did not.

## Changes Made

- Configuration persistence now stops stale Codex Python/Node proxies after runtime files are written and immediately starts the implementation supported by the RootFS when a managed upstream is configured.
- `NativeTerminalActivity` now applies system-bar and IME insets, colors system bars consistently, and renders compact card-based title/action rows without applying Codex styling to the ordinary terminal shortcut strip.
- Added Flutter service coverage and Node source guards for both regressions.

## Checks Run

- `npm test`: 32 passed, 0 failed.
- `npm run lint -- --no-warn-ignored`: passed.
- `git diff --check`: passed.
- App memory validation: passed with no errors or warnings.
- Local Flutter/Dart/Kotlin compilers are unavailable; cloud analysis/compile is required.

## Cloud Build

- Target branch: GitHub `codex-terminal-ime-lag-fix`.
- Expected fresh build: logical `176`, semantic `5.7.0`, display `5.7`, `arm64-v8a` only.

## Version And Artifacts

- Source anchor remains `2.5.0+143`.
- No artifact recorded yet; update this handoff after Actions completes.

## Known Risks

- Android device smoke is still required for status-bar spacing, IME behavior, and live proxy replacement.

## Next Actions

- Push through the GitHub Data API, watch Actions, download and verify the APK, then device-smoke both fixes.
