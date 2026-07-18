# 2026-07-16 UTC - Codex IME Shortcut Post-Layout Refresh

## Goal

Fix the remaining Codex native terminal shortcut-bar stall after dismissing the Android IME.

## Repo Facts Read

- `NativeTerminalPlatformView` owns the native `TerminalView`, terminal shortcut strip, IME overlap compensation, and repaint scheduling.
- The previous `v4.4.0 / 4.4 / 163` fix coalesces global-layout overlap events for 140 ms, then applies one bottom-padding update.
- The locally installed `v4.4.0` APK was device-tested: IME open/close is normal, while shortcut input can stall after IME dismissal with a long Codex transcript.

## Changes Made

- Added a separate 32 ms post-layout finish callback after the settled IME compensation is applied.
- Cancel the pending finish callback when a new IME-layout update arrives and when the platform view is disposed.
- Resume deferred terminal rendering through the normal refresh throttle instead of forcing an immediate `onScreenUpdated()` call in the same layout cycle.
- Updated Node source-level regression assertions for the two-phase IME completion path and corrected the stale workflow release-floor assertion from `162` to the current `163`.

## Checks Run

- `npm run lint -- --no-warn-ignored` passed.
- `git diff --check` passed.
- The first `npm test` run reached the IME assertions successfully but failed only because its existing workflow assertion expected `MINIMUM_RELEASE_BUILD=162` while the checked-in workflow uses `163`; the assertion was corrected and must be re-run.
- Local `flutter`, `dart`, and Android device execution remain unavailable in this Termux environment.

## Cloud Build

- No cloud build or push was run.

## Version And Artifacts

- Latest installed/tested release remains `v4.4.0 / 4.4 / 163`, `arm64-v8a` only.
- Do not reuse build `163`; a release of this fix needs a new unique Android build number and its provenance recorded.

## Known Risks

- The timing change must be tested on a real Android device with a long Codex transcript and repeated IME dismiss/reopen cycles.
- Flutter unit tests are still not executed by the current GitHub Actions APK workflow.

## Next Actions

1. Re-run `npm test` after the release-floor assertion correction and validate project memory.
2. Build a new arm64-v8a APK with a build number above `163`.
3. On-device, rapidly dismiss/reopen the IME in a long Codex transcript and immediately tap multiple shortcut keys; confirm shortcut feedback and input stay responsive.
