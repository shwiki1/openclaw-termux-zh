# 2026-07-16 03:45 UTC - Dual Script Assistant

## Goal

Separate Codex automation workflows from traditional website scripts and let Codex generate scripts without silently executing them.

## Repo Facts Read

- `BrowserScriptLibraryService` stores replayable browser-action workflows.
- `TerminalBrowserPanel` owns the existing script-assistant sheet.
- The current Flutter toolchain is unavailable locally, so UI validation is static-only in this session.

## Changes Made

- Added `BrowserUserScriptLibraryService` with independent SharedPreferences storage for traditional JavaScript scripts.
- Converted the script assistant into two workspaces: Codex automation workflows and traditional website scripts.
- Added create, paste-import, edit, delete, copy-source, copy-Codex-prompt, and confirmed current-page run actions for traditional scripts.
- Added `browser_user_script_list` and `browser_user_script_save`; saving generated code does not execute it.

## Checks Run

- `npm run lint` passed.
- `npm test` passed: 30 passed, 0 failed.
- `git diff --check` passed.
- Flutter/Dart analysis and device visual review are blocked because `flutter` is unavailable locally.

## Cloud Build

No cloud build, push, or release was requested or performed.

## Version And Artifacts

Source version remains `2.5.0+143`; no artifact was created.

## Known Risks

- Traditional scripts run in the current WebView only and do not provide Tampermonkey `GM_*` APIs.
- Paste import is text-based; a native file-picker import requires a separate reviewed Android storage/URI design.

## Next Actions

1. Run `flutter analyze`, `flutter test`, and Android visual/device smoke when a Flutter SDK is available.
2. Verify Codex-generated scripts save correctly and require user confirmation before execution.
