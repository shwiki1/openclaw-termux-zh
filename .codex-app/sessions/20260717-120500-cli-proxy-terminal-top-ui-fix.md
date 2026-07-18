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

- Pushed local fix commit `b049ed9` through the GitHub Data API to branch `codex-terminal-ime-lag-fix`, producing remote commit `d15357dd7bd01b656aa90df401814433d87a3705`.
- GitHub Actions run `29584749891` succeeded: Flutter analysis, Android arm64 packaging, and required PRoot-library verification passed. The release job was intentionally skipped on the feature branch.
- Built logical `176`, semantic `5.7.0`, display `5.7`, `arm64-v8a` only.

## Version And Artifacts

- Source anchor remains `2.5.0+143`.
- Artifact: `dist/github-run-29584749891/CiYuanXia-v5.7-176-arm64-v8a.apk`, 316,571,991 bytes, SHA-256 `e56d798b98e4581aea04b388a98ec0487d6b21abdbcd608caa98029d29bc0a19`.
- GitHub artifact ID `8408672413`, ZIP digest `sha256:27319e6e5fb37bf509abe5ed008ce6c3861b5935ce8e2425bf112c12bbb450cc`.
- ZIP integrity, alignment, package/version metadata, and all required PRoot libraries passed. The APK uses the established release signer SHA-256 `0618eafd1855855749abb7c04d6f44edf9a4b7cb09e26fd882e856d5c994dde6`.

## Known Risks

- Android device smoke is still required for status-bar spacing, IME behavior, and live proxy replacement.
- Actions printed a debug-signing fallback message despite the APK carrying the established release certificate; update compatibility is confirmed by certificate equality, but the misleading log/config path should be investigated before public promotion.

## Next Actions

- Update-install the verified APK over published `5.4`, then device-smoke both fixes.
- Any fresh cloud build must use a logical build greater than `176`.
