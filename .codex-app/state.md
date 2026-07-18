# Current App State

Last updated: 2026-07-18 UTC

## Current Truth
- App: `次元虾` / package `com.agent.cyx`. Flutter Android shell + Kotlin native services + PRoot Ubuntu RootFS + legacy Node CLI.
- Stack: Flutter/Dart Android shell, Kotlin native Android services, PRoot Ubuntu RootFS runtime, legacy Node.js CLI package.
- Cloud build: `.github/workflows/flutter-build.yml` builds arm64-v8a APK, runs `flutter analyze --no-fatal-infos`, uploads GitHub artifact + Gitee split parts, and can publish a GitHub Release; it does not run `flutter test`.
- App version: published display `5.4`; latest packaged candidate display `6.5`; source semantic anchor remains `2.5.0`.
- Build number: published logical build `173`; latest successful packaged candidate build `184`; next fresh cloud build must be greater than `184`.
- Repository root: `/storage/emulated/0/ZeroTermux/开发/openclaw-termux-zh-5.5`.
- Source version anchor: root `package.json` `2.5.0`; Flutter `pubspec.yaml` `2.5.0+143`.
- Active local branch: `codex-terminal-ime-lag-fix` at `f6c94bab2ac003f59b4d6e7317dd9044383c0356`, with local uncommitted native Codex pager session/script-library UI fixes.
- Remotes: `origin` Gitee, `shwiki` GitHub.
- Latest published GitHub Release: `v5.4.0 / 5.4 / 173` from Actions `29538124523`.
- Latest packaged unreleased candidate: `6.5 / 184` from Actions `29623644999`, local install path `dist/gitee-run-29623644999/CiYuanXia-v6.5-184-arm64-v8a.apk`, SHA-256 `82ba2aa3d3ed64eaa9a4e7a3b3087f489e5e3f06318419219725e6c3d4ddf447`.
- Fixed APK delivery path: GitHub Actions runner -> Gitee temp branch `apk-transfer-<run-id>` -> local reassembly under `dist/gitee-run-<run-id>/`.
- Terminal architecture: ordinary CLI tools open `NativeTerminalActivity`; Codex opens `NativeTerminalPagerActivity` with native browser page.
- Current local unreleased code change: Codex pager now has multi-session controls, removes the terminal/page outer card frame, flattens Codex shortcut-key/button chrome, removes the browser WebView border, compresses browser controls into a compact top band, and replaces the browser more menu with a custom dense list. No build submitted.

## Active Task
- Local-only Codex pager UX fix: restore new/switch/close session controls and redesign native script-library UI from the old Flutter implementation. Do not commit or cloud-build unless the user asks.

## Recently Changed
- 2026-07-18 native Codex pager session + script-library/browser density fix: `NativeTerminalPagerActivity` now supports multi-session tabs and removes the rounded outer terminal frame/action-row frame. `NativeTerminalSessionView` removes Codex shortcut-key outer/button rounded frames. `NativeCodexBrowserView` script library is dual-workspace, the browser WebView is unframed, controls are compressed into a compact top band, and the more menu is a custom dense list.
- 2026-07-18 earlier governance refresh recorded the verified `6.5 / 184` Gitee transfer path.

## Checks Run
- 2026-07-18 local UI fix checks: `npm test` 32/32; `npm run lint -- --no-warn-ignored` passed; app memory validation passed. Source guards cover pager new-session, dual-workspace script assistant, flattened Codex chrome, unframed browser, compact controls, and custom more menu.
- Local Flutter/Dart/Kotlin compilers remain unavailable.
- No cloud build launched.

## Cloud Build Status
- Pending cloud build: expected logical build `185` for the Codex pager/browser density UI commit; no release publication requested.
- Latest published release: `5.4 / 173`.
- Latest packaged candidate: `6.5 / 184`.
- Current local UI fixes are not yet packaged.

## Memory Validation
- Restored concise state after a failed regex rewrite emptied the working copy; validation should pass with required Stack/Cloud build/App version/Build number fields.

## Risks And Blockers
- Pending-save draft from Flutter-side `browser_script_stage` is still not shown in the native script assistant.
- Device smoke still required for multi-session and script-library interactions.
- Branch topology remains divergent; promotion must name exact remote SHA.
- Local Termux cannot compile Flutter/Kotlin.

## Next Actions
1. Device-smoke the local Codex pager multi-session controls after the next installable build the user requests.
2. Device-smoke the dual-workspace native script assistant: save recent flow, automation ops, traditional script add/import/edit/run/delete.
3. Optionally bridge Flutter pending-save drafts into the native script assistant.
4. Only on explicit request, package a cloud build with logical build `> 184`.
