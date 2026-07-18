# Current App State

Last updated: 2026-07-18 UTC

## Current Truth
- App: `次元虾` / package `com.agent.cyx`. Flutter Android shell + Kotlin native services + PRoot Ubuntu RootFS + legacy Node CLI.
- Stack: Flutter/Dart Android shell, Kotlin native Android services, PRoot Ubuntu RootFS runtime, legacy Node.js CLI package.
- Cloud build: `.github/workflows/flutter-build.yml` builds arm64-v8a APK, runs `flutter analyze --no-fatal-infos`, uploads GitHub artifact + Gitee split parts, and can publish a GitHub Release; it does not run `flutter test`.
- App version: published display `5.4`; latest cloud-packaged candidate display `6.6`; source semantic anchor remains `2.5.0`.
- Build number: published logical build `173`; latest successful cloud-packaged candidate build `185`; next fresh cloud build must be greater than `185`.
- Repository root: `/storage/emulated/0/ZeroTermux/开发/openclaw-termux-zh-5.5`.
- Source version anchor: root `package.json` `2.5.0`; Flutter `pubspec.yaml` `2.5.0+143`.
- Active local branch: `codex-terminal-ime-lag-fix` at `f6c94bab2ac003f59b4d6e7317dd9044383c0356`, with local uncommitted native Codex pager session/script-library UI fixes.
- Remotes: `origin` Gitee, `shwiki` GitHub.
- Latest published GitHub Release: `v5.4.0 / 5.4 / 173` from Actions `29538124523`.
- Latest cloud-packaged unreleased candidate: `6.6 / 185` from Actions `29640675284` on branch `codex-gitee-transfer-timeout-186` at `b08f9931e715f839dc1e63401219a7faeb48699a`; APK `CiYuanXia-v6.6-185-arm64-v8a.apk`, artifact `ciyuanxia-apks` ID `8428690154`, artifact digest `sha256:c4344f874ef2a64958c570eda23690b693444361e0d8c55aedc07d8f0889517c`. User reported this version is already downloaded and installed locally; no local redownload was performed in this session.
- Fixed APK delivery path: GitHub Actions runner -> Gitee temp branch `apk-transfer-<run-id>` -> local reassembly under `dist/gitee-run-<run-id>/`.
- Terminal architecture: ordinary CLI tools open `NativeTerminalActivity`; Codex opens `NativeTerminalPagerActivity` with native browser page.
- Current local unreleased code change: Codex pager now has multi-session controls, removes the terminal/page outer card frame, keeps Codex terminal shortcut keys as rounded press-feedback buttons, removes the browser WebView border, compresses browser controls into a compact top band, replaces the browser more menu with a custom dense list, and uses Lucide-style icon-only rounded controls with haptic feedback for terminal/browser/script-library actions. No build submitted.

## Active Task
- Local-only native browser script-library UI/function parity pass: beautify the native script assistant dialog and continue filling old Flutter script assistant methods in `NativeCodexBrowserView`. Work only in the main project directory; do not create branches/worktrees or cloud-build unless the user asks.

## Recently Changed
- 2026-07-18 native script-library UI/function parity: `NativeCodexBrowserView` script assistant dialog now has a denser dark workbench header, clearer workspace counts, pending-draft card, improved empty states, and native handling for `browser_script_stage/save/run/rename/delete/clear_pending` plus `browser_user_script_list/save/delete` aliases. This keeps the native path closer to the old Flutter script assistant without creating a new branch/worktree.
- 2026-07-18 memory sync: cloud run `29640675284` succeeded after the Gitee timeout work, producing `6.6 / 185`; branch name `codex-gitee-transfer-timeout-186` is a topic name, not the APK build number. Project memory previously lagged at `6.5 / 184` and has been corrected.
- 2026-07-18 native Codex pager/browser rounded icon-button fix: `NativeTerminalPagerActivity` top actions are Lucide-style icon-only rounded buttons with selected/pressed states and `KEYBOARD_TAP` haptics. `NativeTerminalSessionView` keeps Codex shortcut keys rounded with press feedback. `NativeCodexBrowserView` browser nav/open/UA/more/inspector/script-library actions are icon-first rounded controls with haptics, while script-library tabs use selected rounded states.
- 2026-07-18 native Codex pager session + script-library/browser density fix: `NativeTerminalPagerActivity` supports multi-session tabs and removes the rounded outer terminal frame/action-row frame. `NativeCodexBrowserView` script library is dual-workspace, the browser WebView is unframed, controls are compressed into a compact top band, and the more menu is a custom dense list.
- 2026-07-18 earlier governance refresh recorded the verified `6.5 / 184` Gitee transfer path.

## Checks Run
- 2026-07-18 native script-library parity checks: `npm test` 32/32 passed; `npm run lint -- --no-warn-ignored` passed; `git diff --check -- NativeCodexBrowserView.kt lib/test.js` passed. Local Flutter/Dart/Kotlin compilers remain unavailable, so Android compile verification still requires GitHub Actions or a full SDK environment.
- 2026-07-18 cloud-build memory sync: `gh run list` and `gh run view 29640675284 --log` confirmed successful cloud build `6.6 / 185`, artifact ID `8428690154`, artifact digest `sha256:c4344f874ef2a64958c570eda23690b693444361e0d8c55aedc07d8f0889517c`; artifact download was started then cancelled at user request because the user had already downloaded/installed it.
- 2026-07-18 project-management governance pass: `validate_app_memory.py --project .` passed with no errors or warnings; `inspect_app_project.py --project .` ran but only auto-detected the root Node shell, so Flutter/Kotlin facts were manually verified from `flutter_app/pubspec.yaml`, `flutter_app/test/`, and `.github/workflows/flutter-build.yml`. No business-code checks were rerun in this governance-only pass.
- 2026-07-18 rounded icon-button UI checks: `npm test` 32/32; `npm run lint -- --no-warn-ignored` passed; `git diff --check` passed. Source guards cover pager new-session icon controls, rounded state drawables, haptic feedback, dual-workspace script assistant, browser icon actions, inspector icons, script-library icon mappings, unframed browser, compact controls, and custom more menu.
- Local Flutter/Dart/Kotlin compilers remain unavailable.
- No cloud build launched.

## Cloud Build Status
- Pending cloud build requested 2026-07-18: push current main-directory local changes to GitHub branch `codex-terminal-ime-lag-fix`; workflow is expected to select logical build `186` and display `6.7` because latest successful cloud candidate is `6.6 / 185`. No release publication requested.
- Latest published release: `5.4 / 173`.
- Latest cloud-packaged candidate: `6.6 / 185`.
- Current local UI fixes are not yet packaged.

## Memory Validation
- Restored concise state after a failed regex rewrite emptied the working copy; validation should pass with required Stack/Cloud build/App version/Build number fields.

## Risks And Blockers
- Native script assistant now handles native `browser_script_stage` pending drafts, but existing Flutter-side in-memory drafts from the old `TerminalBrowserPanel` are still separate if that fallback panel is used in the same session.
- Device smoke still required for multi-session and script-library interactions.
- Branch topology remains divergent; promotion must name exact remote SHA.
- Local Termux cannot compile Flutter/Kotlin.

## Next Actions
1. Device-smoke the local Codex pager multi-session controls after the next installable build the user requests.
2. Device-smoke the dual-workspace native script assistant: stage pending draft, save/edit pending draft, save recent flow, automation run/rename/copy/delete, traditional script add/import/edit/run/delete/copy.
3. If old Flutter fallback panel and native pager must share drafts live, design an explicit cross-controller draft bridge; do not assume their in-memory pending drafts are shared.
4. Only on explicit request, package a cloud build with logical build `> 185`.
