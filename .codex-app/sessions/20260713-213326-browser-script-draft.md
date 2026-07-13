# 2026-07-13 21:33 UTC - Browser Script Drafts

## Goal

Update Codex browser automation so the in-app browser requests desktop pages, supports zoom, and gives Codex a reliable pending-save script workflow after completed browser tasks.

## Repo Facts Read

- Read `.codex-app/state.md`, `manifest.md`, `architecture.md`, `ui-system.md`, `build.md`, `backlog.md`, and the latest browser/terminal session.
- Read app-development-governor references for continuity, UI quality, testing matrix, quality gates, and privacy/observability.
- Verified the relevant owners: `TerminalBrowserPanel`, `BrowserAutomationService`, `BrowserScriptLibraryService`, `CliApiConfigService`, and `cli_api_config_service_test.dart`.

## Changes Made

- `TerminalBrowserPanel` now sets a desktop Chrome/Linux user agent, keeps `enableZoom(true)`, and sets Android text zoom to 100 with wide viewport.
- The default browser instructions page now notes desktop-page loading, zoom support, and script assistant pending drafts.
- Added `BrowserAutomationScriptDraft` and pending-save draft state in `BrowserAutomationService`.
- Added bridge actions and generated MCP tools for `browser_script_stage` and `browser_script_clear_pending`.
- `browser_script_list` now returns the pending draft, and `browser_script_save` can fall back to a pending draft when recent repeatable actions are absent.
- The script assistant bottom sheet now shows a pending-save card with save/edit, copy prompt, and discard actions.
- Updated generated `browser-operator` guidance so Codex stages a reusable script after a successful repeatable browser workflow with auto-filled filename and description.
- Updated generated `/root/.openclaw/bin/browser-script` with `stage` and `clear-pending` shortcuts.
- Added test assertions for new generated browser script staging tools and bumped the generated browser MCP server version string to `1.4.0`.

## Checks Run

- `git diff --check`: passed.
- `npm test`: passed, 11 checks.
- `npm run lint -- --no-warn-ignored`: passed.
- `command -v dart`, `command -v flutter`, and `command -v kotlinc`: missing locally, so Flutter analyze/test and Kotlin compile checks were not run in this Termux environment.

## Cloud Build

- Not run in this session. The user did not request a new build after these source changes.

## Version And Artifacts

- Source metadata remains `2.0.50+139`.
- Last downloaded APK remains `artifacts/github-run-29283260131/CiYuanXia-v2.0.50-140-arm64-v8a.apk` from GitHub Actions run `29283260131`.
- No new artifact was produced.

## Known Risks

- Desktop UA/zoom behavior and the pending-save script assistant UI need Android device smoke.
- Generated MCP/browser-script staging needs a live WebView-attached Codex browser session smoke.
- Local Flutter analyzer and widget tests remain blocked by the missing Flutter SDK.

## Next Actions

- Device-smoke: open the browser, confirm desktop page behavior and pinch/page zoom, run a short browser task, stage with `browser_script_stage`, save the pending draft, run the saved script, and clear/delete it.
- In a Flutter SDK environment, run `cd flutter_app && flutter analyze && flutter test`.
- Before any new cloud build, bump `flutter_app/pubspec.yaml` to at least `2.0.50+140`.
