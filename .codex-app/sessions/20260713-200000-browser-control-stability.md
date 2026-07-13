# 2026-07-13 20:00 UTC - Browser Control Stability

## Goal

Fix Codex browser automation instability where fine-grained tools such as `browser_list_interactables`, `browser_type`, `browser_click`, and `browser_capture_snapshot` may be discovered but not reliably exposed as callable tools.

## Repo Facts Read

- Read `.codex-app/state.md`, `manifest.md`, `architecture.md`, `build.md`, `backlog.md`, latest browser script assistant session, and app-development-governor references for continuity, testing matrix, and quality gates.
- Inspected `BrowserAutomationService`, `CliApiConfigService`, `cli_api_config_service_test.dart`, `CHANGELOG.md`, and `AGENTS.md`.
- Verified project policy remains Android `arm64-v8a` only for builds and that local Termux still lacks Dart/Flutter SDK commands.

## Changes Made

- Added generated MCP tool `browser_control` in `/root/.openclaw/browser-mcp.mjs` as a stable single-entry browser automation fallback.
- `browser_control` accepts `action` or `tool`, accepts `payload` or `arguments`, and tolerates direct top-level action payload fields.
- Extended generated `/root/.openclaw/bin/browser-script` with `state`, `self-test`, `call/control`, `open`, `interactables`, `snapshot`, `click`, `type`, `wait-selector`, `wait-text`, `scroll`, and `press-key` commands.
- Updated `BrowserAutomationService` so HTTP bridge paths also accept `browser_*` tool names such as `/browser_type`, `/browser_click`, `/browser_capture_snapshot`, and `/browser_list_interactables`.
- Updated generated `browser-operator` guidance, `cli_api_config_service_test.dart`, `CHANGELOG.md`, and `.codex-app/` memory.

## Checks Run

- `git diff --check`: passed.
- `npm test`: passed, 11 checks passed and 0 failed.
- `npm run lint -- --no-warn-ignored`: passed.
- `command -v dart` and `command -v flutter`: no local SDK paths returned, so Flutter analyze/test were not run locally.

## Cloud Build

- Not run. The user asked to continue fixing; no installable artifact was requested in this turn.

## Version And Artifacts

- Source metadata remains `2.0.50+137`.
- Latest cloud artifact remains GitHub Actions run `29278136954`, APK `CiYuanXia-v2.0.50-138-arm64-v8a.apk`.

## Known Risks

- `browser_control` and `browser-script` fallback commands need Android device smoke against an attached WebView session.
- Flutter analyzer/test coverage is still pending in a Flutter SDK or GitHub Actions environment.

## Next Actions

- Device-smoke `browser_control` for `capture_snapshot`, `list_interactables`, `type`, and `click`.
- Device-smoke shell fallbacks: `browser-script state`, `browser-script interactables`, `browser-script snapshot`, `browser-script type`, and `browser-script click`.
- Run Flutter analyze/test where Flutter SDK is available.
