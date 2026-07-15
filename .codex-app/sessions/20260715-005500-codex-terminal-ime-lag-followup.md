# 2026-07-15 00:55 UTC - Codex Terminal IME Lag Follow-up

## Goal

Recheck why only the Codex terminal felt laggy on IME reopen, while other CLI terminal screens were smooth.

## Repo Facts Read

- Re-read the current app memory, `TerminalScreen`, `NativeTerminalView.kt`, `BrowserAutomationService`, and `TerminalBrowserPanel`.
- Confirmed other CLI screens use `NativeProotTerminal` directly, while the Codex terminal page adds browser automation and a compact sidecar.

## Changes Made

- Stopped keeping the compact Codex browser sidecar mounted after close on narrow screens; the hidden WebView now gets disposed instead of staying in the tree.
- Tightened native terminal focus handling so reopening IME skips redundant `requestFocus()` when the terminal already has focus.
- Updated project memory to reflect the new compact-sidecar lifecycle and the lighter terminal focus path.

## Checks Run

- `git diff --check`: passed
- `npm test`: passed with 28 checks
- `npm run lint -- --no-warn-ignored`: passed
- Local `flutter`, `dart`, and `kotlinc` remain unavailable, so Flutter analyze/test and native compile checks were not run locally.

## Cloud Build

- Not run.

## Known Risks

- Browser panel reopen now pays a fresh WebView mount cost after close on compact screens, but terminal IME reopen should be lighter.

## Risk

- Browser panel reopen now pays a fresh WebView mount cost after close on compact screens, but terminal IME reopen should be lighter.

## Next Actions

- Device-smoke terminal IME open/close/reopen on Android.
- Device-smoke compact browser sidecar close/reopen after the disposal change.
