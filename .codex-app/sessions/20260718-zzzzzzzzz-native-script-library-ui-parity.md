# 2026-07-18 14:05 UTC - Native Script Library UI Parity

## Goal
- Beautify the native browser script-library dialog.
- Continue filling old Flutter script assistant behavior in the native Codex browser path.
- Work only in `/storage/emulated/0/ZeroTermux/开发/openclaw-termux-zh-5.5`; no branch/worktree creation and no cloud build.

## Repo Facts Read
- `.codex-app/state.md`, `.codex-app/ui-system.md`, `.codex-app/backlog.md`.
- Old Flutter script assistant: `flutter_app/lib/widgets/terminal_browser_panel.dart`.
- Script services: `browser_automation_service.dart`, `browser_script_library_service.dart`, `browser_user_script_library_service.dart`.
- Native browser implementation: `NativeCodexBrowserView.kt`.
- Source guards: `lib/test.js`.

## Changes Made
- `NativeCodexBrowserView.kt`: added native pending-draft model and UI card for `browser_script_stage` workflows.
- `NativeCodexBrowserView.kt`: added native handling for script-library actions: `script_list`, `script_stage`, `script_save`, `script_run`, `script_rename`, `script_delete`, `script_clear_pending`, `user_script_list`, `user_script_save`, and `user_script_delete`, including `browser_script_*` / `browser_user_script_*` aliases.
- `NativeCodexBrowserView.kt`: script assistant dialog now uses a denser dark workbench header with icon, workspace counts, clearer copy, selected tabs, improved empty states, and pending-draft save/copy/discard actions.
- `lib/test.js`: extended source guards so pending-draft UI, native script action aliases, native script run/stage handling, and snapshot pending state are covered.
- `.codex-app/`: updated state, UI system, backlog, and this session handoff.

## Checks Run
- `npm test`: 32 passed, 0 failed.
- `npm run lint -- --no-warn-ignored`: passed.
- `git diff --check -- flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/NativeCodexBrowserView.kt lib/test.js`: passed.
- Local Flutter/Dart/Kotlin compile checks were not run because this Termux environment lacks those toolchains.

## Cloud Build
- Not requested; none launched.

## Version And Artifacts
- Latest installed/user-reported cloud candidate remains `6.6 / 185` from Actions `29640675284`.
- No new APK artifact produced.
- Next fresh cloud build must use logical build greater than `185`.

## Known Risks
- Kotlin compilation still needs GitHub Actions or a full SDK environment.
- Native pager pending drafts are now handled by the native controller. Old Flutter fallback-panel in-memory drafts remain separate unless a future explicit bridge is designed.
- Device smoke is required for actual dialog sizing, IME behavior in edit/import dialogs, haptics, and script run flows.

## Next Actions
1. Device-smoke native script assistant: stage pending draft, save/edit pending draft, copy prompt, discard, save recent flow, run/rename/copy/delete saved automation, add/import/edit/run/delete traditional scripts.
2. If packaging is requested, cloud build the main project only, with build number greater than `185`.
