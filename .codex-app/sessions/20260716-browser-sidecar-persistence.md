# 2026-07-16 UTC - Browser Sidecar Persistence And Script Workspaces

## Goal

Keep the Codex browser automation connection alive after a compact sidecar is closed, and change the script assistant from stacked columns to horizontal workspaces.

## Repo Facts Read

- `TerminalScreen` owns the compact browser sidecar and controls whether its `TerminalBrowserPanel` remains mounted.
- `TerminalBrowserPanel` registers itself as the browser automation delegate; disposing it disconnects active browser automation.
- `_BrowserScriptLibrarySheet` stores Codex workflows and traditional website scripts separately.

## Changes Made

- Made compact sidecar browser mounting unconditional so closing only hides/slides out the panel instead of disposing the WebView and automation bridge.
- Replaced the responsive stacked/row script layout with a `PageView` that exposes two labeled workspaces: `Codex 自动化` and `传统脚本`.
- Added workspace selector controls and disposal for the sheet `PageController`.
- Added a browser-panel-local button theme that makes filled, outlined, text, and icon button foregrounds readable on black surfaces, including the address-bar `打开` button.
- Reduced Codex terminal IME-close jank by coalescing `adjustPan` bottom-compensation changes and deferring terminal redraws while the IME layout is transitioning; a pending redraw runs once after a 90 ms settle period.
- Added source-level regression guards in `lib/test.js`.

## Checks Run

- `npm test` passed: 30 passed, 0 failed.
- `npm run lint` passed.
- `git diff --check` passed before this handoff update; it is rerun after this update.
- The button contrast update uses the same checks and still needs Flutter/device visual verification because local Flutter/Dart tooling is unavailable.
- The terminal IME performance fix also needs Android device verification with a long Codex transcript; local Flutter/Dart tooling remains unavailable.
- Local `flutter` and `dart` availability is checked during final validation; native Flutter/device verification is not assumed.

## Cloud Build

No new cloud build was requested or started. The last published APK remains `v4.0.0 / 4.0 / 159`.

## Version And Artifacts

- No version or artifact change.
- Existing local APK: `dist/github-release-v4.0.0/CiYuanXia-v4.0-159-arm64-v8a.apk`.

## Known Risks

- Keeping the hidden WebView mounted intentionally trades some compact-screen memory for reliable browser automation continuity.
- The changed sidecar lifecycle and horizontal swipe behavior require Android device smoke because Flutter/Dart tooling is unavailable locally.

## Next Actions

1. On an Android device, open a Codex browser page, close the sidecar, invoke browser tools from the terminal, and reopen it to confirm the same tab/session remains attached.
2. Verify the script assistant can tap and swipe between `Codex 自动化` and `传统脚本`, including keyboard and scroll behavior.
3. If approved, submit this focused change to GitHub Actions as the next incremented arm64-only release.
