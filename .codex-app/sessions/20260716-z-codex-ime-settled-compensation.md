# 2026-07-16 06:20 UTC - Codex IME Close Jank Follow-Up

## Goal

Find and fix the remaining multi-second stall when closing the Android input method in a Codex terminal with a long transcript.

## Repo Facts Read

- `TerminalScreen` switches terminal pages to Android `adjustPan` through `NativeBridge` and keeps Flutter's scaffold from resizing for the IME.
- `NativeTerminalPlatformView` owns the native `TerminalView`, its toolbar, IME overlap compensation, and terminal repaint scheduling.
- Codex uses the same native terminal host as other CLI sessions, but dense long output makes repeated terminal re-layouts especially visible.

## Changes Made

- Found that every `OnGlobalLayout` callback during the IME animation immediately changed `contentContainer` bottom padding. Each change relaid out the native terminal and its toolbar while output refresh was deferred.
- Added `pendingImeCompensationBottomPx`; IME callbacks now only record the latest overlap and reset a 140 ms settle timer.
- Added `applyPendingImeCompensation()` so the padding changes once after the animation is stable, then the deferred terminal refresh resumes.
- Updated source-level regression checks in `lib/test.js` for the pending compensation and single settled-apply path.

## Checks Run

- `npm test` passed: 30 passed, 0 failed.
- `npm run lint` passed.
- `git diff --check` passed.
- Local Flutter/Dart and Android device execution remain unavailable in this Termux environment.

## Cloud Build

- Build requested for this local follow-up: GitHub `shwiki/main`, arm64-v8a only, logical build `163`, semantic version `4.4.0`, and install-visible version `4.4`.
- The current published release remains `v4.3.0 / 4.3 / 162`, arm64-v8a only.

## Known Risks

- Android device smoke is required because the behavior depends on real IME animation timing and a native platform view.

## Next Actions

1. Open a Codex terminal with a full transcript, close the keyboard repeatedly, and verify the terminal stays responsive without the previous roughly two-second stall.
2. Verify opening the keyboard still keeps the current prompt and native shortcut strip visible.
3. If device smoke passes, increment the build beyond `162`, push the focused fix, and run the arm64-v8a GitHub Actions release build.
