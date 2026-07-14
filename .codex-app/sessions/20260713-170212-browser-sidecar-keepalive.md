# 2026-07-13 17:02 UTC - Browser Sidecar Keepalive

## Goal

Fix compact Codex terminal browser behavior so closing the right slide-in browser panel does not disconnect Codex browser automation.

## Repo Facts Read

- Used `app-development-governor` and read continuity, ecosystem patterns, UI quality, testing matrix, and quality gate references.
- Read `.codex-app/state.md`, `manifest.md`, `architecture.md`, `ui-system.md`, `build.md`, `backlog.md`, and latest prior session.
- Source owners inspected: `flutter_app/lib/screens/terminal_screen.dart`, `flutter_app/lib/widgets/terminal_browser_panel.dart`, and `flutter_app/lib/services/browser_automation_service.dart`.
- Root cause: compact `TerminalScreen` used `Scaffold.endDrawer` to host `TerminalBrowserPanel`; closing the drawer could dispose the panel, calling `BrowserAutomationService.unbindDelegate()` and dropping browser attachment.

## Changes Made

- Replaced compact `Scaffold.endDrawer` browser hosting with an in-page persistent `Stack`/`AnimatedPositioned` sidecar in `flutter_app/lib/screens/terminal_screen.dart`.
- Added `_browserPanelCreated` so the browser panel is created on first open/automation request and then remains mounted while hidden.
- Added right-edge left-swipe open, scrim tap close, back-button close, and a left-edge right-swipe close strip for the compact sidecar.
- Preserved the existing wide-screen side-by-side browser layout.
- Updated `CHANGELOG.md` with the Codex browser sidecar keep-alive fix.
- Updated `.codex-app/state.md`, `architecture.md`, and `backlog.md`.

## Checks Run

- `command -v dart` and `command -v flutter`: no local SDK paths, so Flutter analyze/test were not run locally.
- `git diff --check`: passed.
- `npm test`: passed, 11 checks passed and 0 failed.
- `npm run lint -- --no-warn-ignored`: passed.
- Final app memory validation after this handoff update: passed with no errors and no warnings.

## Cloud Build

- No cloud build was started in this turn.

## Version And Artifacts

- Source metadata remains `2.0.50+134`.
- No new artifact was produced. Bump build metadata before any next installable artifact.

## Known Risks

- The change has not been verified by `flutter analyze`, `flutter test`, or on-device UI smoke because local Flutter/Android tooling is unavailable.
- Platform-view behavior while hidden offscreen should be device-smoked on Android WebView, especially close/reopen sidecar and browser MCP actions after close.

## Next Actions

- Run Flutter analyze/test in CI or a Flutter SDK environment.
- Build a fresh arm64 APK only after bumping build metadata.
- Device-smoke compact Codex terminal: open browser sidecar, confirm `浏览器已连接`, close it, verify the banner remains connected, run browser MCP actions while hidden, reopen and confirm page state persists.
