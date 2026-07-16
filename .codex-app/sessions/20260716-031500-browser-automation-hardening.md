# 2026-07-16 03:15 UTC - Browser Automation Hardening

## Goal

Improve in-app browser automation reliability and make mobile pages the default.

## Repo Facts Read

- `BrowserAutomationService` owns loopback bridge routing; `TerminalBrowserPanel` implements the WebView delegate and per-tab UA behavior.
- The generated MCP and shell bridge definitions live in `CliApiConfigService`.
- Existing worktree changes to release-memory files were preserved.

## Changes Made

- Defaulted newly created browser tabs and service state to the mobile Android UA.
- Added `browser_health_check`, `browser_reset_tab`, `browser_paste`, `browser_wait_for_resource`, `browser_list_overlays`, and `browser_click_at` to the bridge, MCP tool list, stable aliases, and shell fallback aliases.
- Changed automatic pending script drafts to opt-in; explicit script staging remains unchanged.
- Added static compatibility coverage and recorded the native file-upload/screenshot boundary.

## Checks Run

- `npm run lint` passed.
- `npm test` passed: 29 passed, 0 failed.
- `git diff --check` passed.
- Flutter/Dart analysis was not run because the local Termux environment has no `flutter` executable.

## Cloud Build

No push, cloud build, or release was requested or performed.

## Version And Artifacts

Source version remains `2.5.0+143`. No artifact was created.

## Known Risks

- New Flutter/Dart code needs `flutter analyze`, `flutter test`, and Android device smoke in a Flutter SDK environment.
- Native file upload and bitmap screenshot/OCR are intentionally not claimed; they need a reviewed Android bridge and storage/consent design.

## Next Actions

1. Run Flutter analysis/tests and device-smoke browser health/reset/paste/resource/overlay flows.
2. Design native file selector and bitmap capture only if the product requires automated upload or OCR.
