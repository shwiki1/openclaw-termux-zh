# Current App State

Last updated: 2026-07-18 UTC

## Current Truth
- App: `次元虾` / package `com.agent.cyx`. Flutter Android shell + Kotlin native services + PRoot Ubuntu RootFS + legacy Node CLI.
- Stack: Flutter/Dart Android shell, Kotlin native Android services, PRoot Ubuntu RootFS runtime, legacy Node.js CLI package.
- Cloud build: `.github/workflows/flutter-build.yml` builds arm64-v8a APK, runs `flutter analyze --no-fatal-infos`, uploads the APK as GitHub artifact `ciyuanxia-apks`, and can publish a GitHub Release; it does not run `flutter test`. The Gitee split-parts upload step was removed locally on 2026-07-18 after repeated timeout risk.
- App version: published display `5.4`; latest GitHub artifact cloud candidate display `6.8`; source semantic anchor remains `2.5.0`.
- Build number: published logical build `173`; latest GitHub artifact cloud candidate build `187`; next fresh cloud build must be greater than `187`.
- Repository root: `/storage/emulated/0/ZeroTermux/开发/openclaw-termux-zh-5.5`.
- Source version anchor: root `package.json` `2.5.0`; Flutter `pubspec.yaml` `2.5.0+143`.
- Active local branch: `codex-terminal-ime-lag-fix`; latest pushed GitHub feature-branch commit is API-created remote SHA `0b434c87cd2cefbd25cc145a597ac5601d7c8068` for the 2026-07-18 script-library build attempt. Local commit `330761a` has the same intended tree changes but a different SHA because the GitHub API push recreated the commit with remote parent metadata.
- Remotes: `origin` Gitee, `shwiki` GitHub.
- Latest published GitHub Release: `v5.4.0 / 5.4 / 173` from Actions `29538124523`.
- Latest GitHub artifact cloud candidate: `6.8 / 187` from Actions `29647690716` on branch `codex-terminal-ime-lag-fix` at remote SHA `0b434c87cd2cefbd25cc145a597ac5601d7c8068`; APK `CiYuanXia-v6.8-187-arm64-v8a.apk`, artifact `ciyuanxia-apks` ID `8430713820`, artifact digest `sha256:189c6eaaee4c0af6d48c54bacc0bfbeb13fcbfbba1af7ec644426a99f42f6abc`, final size `302906860` bytes. Flutter analyze, arm64 APK packaging, PRoot native-library verification, artifact collection, and GitHub artifact upload passed; workflow conclusion is `failure` only because Gitee split-part upload timed out on part `1/7` after 10 minutes at about 8.37 MiB uploaded.
- Local downloaded `6.8 / 187` artifact: `dist/github-run-29647690716/ciyuanxia-apks.zip` matches artifact digest `sha256:189c6eaaee4c0af6d48c54bacc0bfbeb13fcbfbba1af7ec644426a99f42f6abc`; extracted APK is `dist/github-run-29647690716/CiYuanXia-v6.8-187-arm64-v8a.apk` with APK SHA-256 `df8144fa887bc8648684a5d0105e5b2be0ded157adfd0e8551b7b5213e0105c3`.
- Latest fully Gitee-transferred cloud candidate remains `6.6 / 185` from Actions `29640675284` on branch `codex-gitee-transfer-timeout-186` at `b08f9931e715f839dc1e63401219a7faeb48699a`; APK `CiYuanXia-v6.6-185-arm64-v8a.apk`, artifact `ciyuanxia-apks` ID `8428690154`, artifact digest `sha256:c4344f874ef2a64958c570eda23690b693444361e0d8c55aedc07d8f0889517c`. User reported this version is already downloaded and installed locally; no local redownload was performed in this session.
- Current APK delivery path: GitHub Actions artifact `ciyuanxia-apks` -> local download under `dist/github-run-<run-id>/` -> ZIP/APK SHA verification. Do not run the Gitee split-parts upload in the main APK workflow unless explicitly restored later.
- Terminal architecture: ordinary CLI tools open `NativeTerminalActivity`; Codex opens `NativeTerminalPagerActivity` with native browser page.
- Current packaged feature state: native browser script-library UI/function parity changes are packaged in the GitHub artifact candidate `6.8 / 187`, but the Gitee delivery helper failed. Treat `6.8 / 187` as GitHub-artifact-only until downloaded/verified or distributed through another path.

## Active Task
- Local-only native browser script-library UI/function parity pass: beautify the native script assistant dialog and continue filling old Flutter script assistant methods in `NativeCodexBrowserView`. Work only in the main project directory; do not create branches/worktrees or cloud-build unless the user asks.

## Recently Changed
- 2026-07-18 push/build: pushed native browser script-library UI/function parity work to existing GitHub branch `codex-terminal-ime-lag-fix` without creating a new branch/worktree. Initial run `29646867533` selected `6.7 / 186` and failed in Kotlin compilation because `NativeCodexBrowserView.kt` called `nativeRoundedStateDrawable(...)` without the required `Context` receiver. Follow-up fixed those calls to `context.nativeRoundedStateDrawable(...)` and changed workflow build-number discovery to include latest completed runs, so the retry did not reuse failed build `186`.
- 2026-07-18 cloud candidate `6.8 / 187`: retry run `29647690716` selected `6.8 / 187`, passed Flutter analyze, Android arm64 build, APK PRoot verification, collection, and GitHub artifact upload. GitHub artifact is available, but the workflow failed at Gitee split-part upload due to the Gitee network being too slow for the 10-minute per-push timeout.
- 2026-07-18 GitHub-artifact-only delivery change: removed the `Upload APK parts to Gitee transfer branch` step from `.github/workflows/flutter-build.yml`, added a Node test guard that the workflow publishes APK through GitHub artifacts only, and downloaded run `29647690716` locally to `dist/github-run-29647690716/`.
- 2026-07-18 native script-library UI/function parity: `NativeCodexBrowserView` script assistant dialog now has a denser dark workbench header, clearer workspace counts, pending-draft card, improved empty states, and native handling for `browser_script_stage/save/run/rename/delete/clear_pending` plus `browser_user_script_list/save/delete` aliases. This keeps the native path closer to the old Flutter script assistant without creating a new branch/worktree.
- 2026-07-18 memory sync: cloud run `29640675284` succeeded after the Gitee timeout work, producing `6.6 / 185`; branch name `codex-gitee-transfer-timeout-186` is a topic name, not the APK build number. Project memory previously lagged at `6.5 / 184` and has been corrected.
- 2026-07-18 native Codex pager/browser rounded icon-button fix: `NativeTerminalPagerActivity` top actions are Lucide-style icon-only rounded buttons with selected/pressed states and `KEYBOARD_TAP` haptics. `NativeTerminalSessionView` keeps Codex shortcut keys rounded with press feedback. `NativeCodexBrowserView` browser nav/open/UA/more/inspector/script-library actions are icon-first rounded controls with haptics, while script-library tabs use selected rounded states.
- 2026-07-18 native Codex pager session + script-library/browser density fix: `NativeTerminalPagerActivity` supports multi-session tabs and removes the rounded outer terminal frame/action-row frame. `NativeCodexBrowserView` script library is dual-workspace, the browser WebView is unframed, controls are compressed into a compact top band, and the more menu is a custom dense list.
- 2026-07-18 earlier governance refresh recorded the verified `6.5 / 184` Gitee transfer path.

## Checks Run
- 2026-07-18 push/build retry checks: `npm test` 32/32 passed; `npm run lint -- --no-warn-ignored` passed; `git diff --check` passed; `bash -n scripts/upload-apk-parts-to-gitee-branch.sh scripts/build-apk.sh scripts/build-prebuilt-rootfs.sh scripts/prebuilt-rootfs-metadata.sh scripts/fetch-prebuilt-rootfs-asset.sh` passed. GitHub Actions run `29647690716` passed Flutter analyze, Kotlin/Gradle APK build, and APK PRoot verification, then failed only in the Gitee split upload step.
- 2026-07-18 GitHub-artifact-only delivery checks: `npm test` 33/33 passed; `npm run lint -- --no-warn-ignored` passed; `git diff --check -- .github/workflows/flutter-build.yml lib/test.js` passed; `sha256sum dist/github-run-29647690716/ciyuanxia-apks.zip` matched GitHub artifact digest; `unzip -t dist/github-run-29647690716/ciyuanxia-apks.zip` passed; extracted APK SHA-256 is `df8144fa887bc8648684a5d0105e5b2be0ded157adfd0e8551b7b5213e0105c3`.
- 2026-07-18 native script-library parity checks: `npm test` 32/32 passed; `npm run lint -- --no-warn-ignored` passed; `git diff --check -- NativeCodexBrowserView.kt lib/test.js` passed. Local Flutter/Dart/Kotlin compilers remain unavailable, so Android compile verification still requires GitHub Actions or a full SDK environment.
- 2026-07-18 cloud-build memory sync: `gh run list` and `gh run view 29640675284 --log` confirmed successful cloud build `6.6 / 185`, artifact ID `8428690154`, artifact digest `sha256:c4344f874ef2a64958c570eda23690b693444361e0d8c55aedc07d8f0889517c`; artifact download was started then cancelled at user request because the user had already downloaded/installed it.
- 2026-07-18 project-management governance pass: `validate_app_memory.py --project .` passed with no errors or warnings; `inspect_app_project.py --project .` ran but only auto-detected the root Node shell, so Flutter/Kotlin facts were manually verified from `flutter_app/pubspec.yaml`, `flutter_app/test/`, and `.github/workflows/flutter-build.yml`. No business-code checks were rerun in this governance-only pass.
- 2026-07-18 rounded icon-button UI checks: `npm test` 32/32; `npm run lint -- --no-warn-ignored` passed; `git diff --check` passed. Source guards cover pager new-session icon controls, rounded state drawables, haptic feedback, dual-workspace script assistant, browser icon actions, inspector icons, script-library icon mappings, unframed browser, compact controls, and custom more menu.
- Local Flutter/Dart/Kotlin compilers remain unavailable.
- Cloud build launched after user request; latest run `29647690716` produced GitHub artifact `6.8 / 187` but failed final Gitee split transfer.

## Cloud Build Status
- Latest requested cloud build: GitHub Actions run `29647690716` completed with workflow conclusion `failure`, but the installable APK artifact was successfully produced and uploaded to GitHub. It selected logical build `187`, semantic `6.8.0`, display `6.8`, APK `CiYuanXia-v6.8-187-arm64-v8a.apk`, artifact ID `8430713820`, digest `sha256:189c6eaaee4c0af6d48c54bacc0bfbeb13fcbfbba1af7ec644426a99f42f6abc`. Gitee branch `apk-transfer-29647690716` was created with the manifest, then part `1/7` timed out after 10 minutes at about 8.37 MiB uploaded. Do not call this a full Gitee-delivered build.
- Latest published release: `5.4 / 173`.
- Latest GitHub artifact candidate: `6.8 / 187`.
- Latest fully Gitee-delivered candidate: `6.6 / 185`.

## Memory Validation
- Restored concise state after a failed regex rewrite emptied the working copy; validation should pass with required Stack/Cloud build/App version/Build number fields.

## Risks And Blockers
- Gitee split-part upload was removed from the main APK workflow after timeout on run `29647690716`; do not restore it without a new explicit distribution strategy.
- Native script assistant now handles native `browser_script_stage` pending drafts, but existing Flutter-side in-memory drafts from the old `TerminalBrowserPanel` are still separate if that fallback panel is used in the same session.
- Device smoke still required for multi-session and script-library interactions.
- Branch topology remains divergent; promotion must name exact remote SHA.
- Local Termux cannot compile Flutter/Kotlin.

## Next Actions
1. Device-smoke the local Codex pager multi-session controls after the next installable build the user requests.
2. Device-smoke the dual-workspace native script assistant: stage pending draft, save/edit pending draft, save recent flow, automation run/rename/copy/delete, traditional script add/import/edit/run/delete/copy.
3. If old Flutter fallback panel and native pager must share drafts live, design an explicit cross-controller draft bridge; do not assume their in-memory pending drafts are shared.
4. Only on explicit request, package another cloud build with logical build `> 187`; do not reuse `186` or `187`.
5. Push the GitHub-artifact-only workflow change to the existing GitHub branch when the user wants the next cloud build; that build must use logical build `> 187` and should no longer fail in a Gitee upload step.
