# 2026-07-13 17:16 UTC - Browser Default Instructions

## Goal

Make the Codex browser automation sidecar default to an instructions page instead of automatically loading the OpenClaw Gateway dashboard URL/token.

## Repo Facts Read

- Used `app-development-governor` and read continuity, UI quality, and quality gate references.
- Read `.codex-app/state.md` and latest prior browser sidecar session.
- Source owner inspected: `flutter_app/lib/widgets/terminal_browser_panel.dart`.
- Existing behavior: `_initializeBrowser()` loaded `PreferencesService.dashboardUrl` when no pending tool URL existed, which opened `http://127.0.0.1:18789/#token=...` by default.

## Changes Made

- Removed the `PreferencesService` import and dashboard URL fallback from `TerminalBrowserPanel`.
- Added a richer built-in `Codex 浏览器自动化控制` HTML instructions page as the default browser content.
- Kept explicit pending URL behavior intact: Codex browser actions and manual address entry still open requested target pages.
- Changed `about:blank` bootstrap requests to show the instructions page instead of doing nothing.
- Updated `CHANGELOG.md` and `.codex-app/architecture.md`, `state.md`, and `backlog.md`.

## Checks Run

- `rg` confirmed no `PreferencesService` or `dashboardUrl` reference remains in `flutter_app/lib/widgets/terminal_browser_panel.dart`.
- `command -v dart` and `command -v flutter`: no local SDK paths, so Flutter analyze/test were not run locally.
- `git diff --check`: passed.
- `npm test`: passed, 11 checks passed and 0 failed.
- `npm run lint -- --no-warn-ignored`: passed.
- Final app memory validation after this handoff update: passed with no errors and no warnings.

## Cloud Build

- No cloud build was started in this turn.

## Version And Artifacts

- Source metadata remains `2.0.50+134`.
- No new artifact was produced. Bump build metadata before any next installable APK.

## Known Risks

- The default-page behavior has not been verified on a device/emulator because local Flutter/Android tooling is unavailable.
- Flutter analyze/test still need CI or a Flutter SDK environment.

## Next Actions

- Run Flutter analyze/test in CI or a Flutter SDK environment.
- Device-smoke a fresh APK: first open of the Codex browser sidecar should show the instructions page, not Gateway; explicit Codex `browser_open` and manual URL entry should still navigate to requested webpages.
