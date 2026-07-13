# 2026-07-13 10:53 UTC - Codex Browser Automation

## Goal
Update and strengthen Codex CLI browser automation inside the OpenClaw Android app.

## Repo Facts Read
- `.codex-app/state.md`, `architecture.md`, `build.md`, latest session, and `app-development-governor` references for UI, privacy, and testing.
- Browser automation files: `BrowserAutomationService`, `TerminalBrowserPanel`, `CliApiConfigService`, `cli_api_config_service_test.dart`, `TerminalScreen`.
- Existing generated MCP flow writes `/root/.openclaw/browser-mcp.mjs` and `browser-operator` skill files when CLI runtime files are regenerated.

## Changes Made
- Added browser bridge delegate actions:
  - `waitForSelector`
  - `scroll`
  - `pressKey`
  - `selectOption`
- Implemented WebView JavaScript actions for visible selector waits, page/element scrolling, keyboard events, and native select dropdown changes.
- Extended generated Codex MCP tools:
  - `browser_wait_for_selector`
  - `browser_scroll`
  - `browser_press_key`
  - `browser_select_option`
- Bumped generated MCP server info from `1.0.0` to `1.1.0`.
- Updated generated `browser-operator` skill guidance and typical flow.
- Added test assertions ensuring the generated MCP script and skill include the new tools.
- Added an Unreleased changelog entry.

## Checks Run
- `rg` consistency checks across bridge, WebView implementation, MCP generator, skill text, and tests.
- `git diff --check`: passed.
- `npm test`: passed, 11 passed and 0 failed.
- `npm run lint -- --no-warn-ignored`: passed.
- Local `dart` and `flutter` commands are unavailable in this Termux environment, so Flutter analyze/test/build were not run.

## Cloud Build
- Not run.

## Version And Artifacts
- Source version remains `2.0.50+133`.
- No artifact produced.

## Known Risks
- The Dart changes need `flutter analyze` and `flutter test` in a Flutter SDK environment.
- WebView automation should be device-smoked because JavaScript event behavior can differ by Android System WebView version.
- Browser tools can extract page content and interact with forms; `browser-operator` guidance still requires confirmation before sensitive actions.

## Next Actions
- Run Flutter checks in CI or a Flutter SDK environment.
- Device-smoke the new browser tools from Codex CLI through the terminal browser panel.
