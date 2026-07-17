# Backlog

## Priority Now
- Build and device-smoke `5.8 / 177`: create or edit the sole shared API, save it, confirm Codex automatically binds it, and verify the 8787 `/health` response reports that exact upstream before sending a Codex request.
- Device-smoke the locally verified `5.7 / 176` feature build: update-install it over published `5.4`, save a changed Codex API profile and verify the running local proxy uses it without reopening Codex; then open each non-Codex CLI and verify its title/actions sit below the status bar and remain usable through IME open/close.
- Device-smoke the locally verified `5.6 / 175` feature candidate on Android 10+ arm64, including update install from published `5.4`, native terminal IME open/close, shortcut-bar position, pager navigation, browser form/address IME, script-library actions, and `browser_*` automation.
- Resolve the signing provenance discrepancy: run `29551560421` reported missing `KEYSTORE_BASE64`, but the downloaded APK uses the established signer SHA-256 `0618eafd1855855749abb7c04d6f44edf9a4b7cb09e26fd882e856d5c994dde6`.
- Choose the authoritative release history and promotion route. Local `dab844a` and GitHub feature SHA `28a3c243` share the same tree but have different parents; GitHub `main` remains `02602bb2`.
- Device-smoke the 2026-07-17 native Codex pager UI stabilization on Android: verify top safe-area spacing, terminal shortcut-bar lift with IME, browser icon-button rendering, recent-actions toggle, and inspector cards before any new cloud build.
- Device-smoke the 2026-07-17 Codex space/script-parity follow-up on Android: confirm ordinary CLI terminals really kept the compact toolbar style, Codex pager chrome no longer steals too much viewport height, and the native script library add/import/edit/run/delete flows all work on-device.
- Device-smoke the native Codex pager on Android before any new cloud build: terminal full-scrollback IME open/close smoothness, horizontal page switching, native browser address-bar/form input, and `browser_*` tool actions against the new native `WebView`.
- Decide whether the current native browser parity is sufficient to replace the old Flutter browser sidecar for Codex, or whether the script assistant / inspector UI also needs a native port before push/build.
- Decide whether native support also needs a bridge for Flutter-side pending-save drafts (`browser_script_stage`), or whether that remaining gap is acceptable before the next build.
- Promote the native Codex pager only after device smoke and branch/signing decisions; any fresh cloud build must use a logical build greater than `176`.
- Device-smoke the new native terminal activity on Android: full-screen terminal scrollback, repeated IME open/close, bottom shortcut bar position, session reopen persistence, and close-vs-back behavior. Confirm it is materially smoother than the old Flutter `TerminalScreen` path.
- Device-smoke the current `CiYuanXia-v5.6-175-arm64-v8a.apk` candidate on Android; use published `5.4 / 173` as the update-install baseline.
- If lag somehow remains on the new native activity path, inspect the shared `NativeTerminalSessionView` render/update path first. Do not revert to more Flutter/platform-view IME compensation work unless the native path is disproven by device smoke.
- Device-smoke Codex tool calling through the OpenAI-compatible proxy path: verify `responses`-based tool calls, MCP browser tools, and follow-up `function_call_output` turns all survive the local proxy without flattening into plain text.
- Add `flutter test` to the GitHub Actions gate or run it in a dedicated Flutter SDK environment before the next release candidate; the repo already has Flutter tests, but the current green APK workflow does not execute them.
- Decide the release promotion path for the next build: which branch is authoritative, which remote is used for cloud builds, who bumps the build number, and where changelog/release notes are cut from.
- Reconcile the current branch topology before the next release push: local `codex-terminal-ime-lag-fix` is `ahead 25, behind 9` versus local `shwiki/main`, and GitHub `main`, the GitHub feature branch, and `origin/main` are not one linear history.
- Reconcile broad Android permissions and actual logs/config storage with privacy/data-safety documentation before the next public release.

## Ready
- Device-smoke the dual script assistant on a narrow Android screen and a wide/landscape screen: verify column stacking, long source editing, paste import, Codex save, confirmation before execution, and persistence after app restart.
- Design and review a native Android WebView file-selector bridge before adding `browser_upload_file`; it must not expose arbitrary shared-storage paths or bypass user consent.
- Design a native bitmap capture path before promising screenshot/OCR automation; the existing `browser_capture_snapshot` is DOM/text only.
- Prepare a release-readiness checklist covering broad permissions/privacy review, rootfs asset restore/fallback expectations, version bump discipline, artifact verification, and install/update smoke before the next public release.
- Replace `softprops/action-gh-release@v2` or otherwise update the release step before GitHub fully enforces the Node.js 20 deprecation warning now shown on run `29355437073`.
- Device-smoke Codex browser multi-tab and UA behavior on Android: open multiple pages, switch tabs, close a tab, use back/forward/reload, switch desktop/mobile UA, and verify desktop pages no longer fall back to the mobile layout on representative sites.
- Device-smoke Codex terminal performance: start a long Codex CLI conversation, open/close the compact browser sidecar while output is active, verify the sidecar reconnects cleanly after disposal, terminal input still works, and the terminal screen catches up after closing the sidecar.
- Device-smoke the browser automation hardening: verify `browser_control` and `browser-script` fallback commands can complete snapshot/read/type/click flows on a live WebView, then confirm the compact right browser sidecar still stays connected after close/reopen.
- Device-smoke the freshly built arm64 APK on Android: first browser open shows the `Codex 浏览器自动化控制` instructions page, self-test, open URL, wait selector, scroll, type, press Enter, select option, capture snapshot, then close/reopen the compact right browser sidecar and verify it still shows `浏览器已连接`.
- Device-smoke the Codex browser script assistant: perform a short browser flow, stage a pending-save draft with `browser_script_stage`, save it, reopen the script directory, rename it, copy `browser-script run <id>`, run it from the Codex terminal, delete the script, and verify the WebView remains attached throughout.
- Pick the next product/code task and scope it to existing owners: setup/runtime, gateway, node capabilities, terminal, local model, backup, update, or UI polish.
- Review whether `flutter_app/assets/bootstrap/claude-code-2.1.148-bundle.tar.gz` should remain declared/ignored/published under the current resource policy.

## Blocked
- Local Termux environment does not have `flutter`, so Flutter analyze/test/build are blocked locally.

## Deferred
- Add device/emulator smoke checklist for first run, setup with local/remote resources, gateway start/stop, Web dashboard, backup/restore, terminal, and update install.
- Reconcile privacy policy/data-safety notes with broad Android permissions and actual logs/config storage behavior.
- Implement or clearly hide/label Canvas capability if it remains an unavailable placeholder.
- Add migration/backward-compatibility notes if config, snapshot, backup, or shared preference schemas change.

## Do Not Forget
- Device testing showed `5.7 / 176` can leave Codex unbound when the first and only shared API is created; use `5.8 / 177` or later for validating the configuration-save fix.
- Keep app version/build number updated before every new cloud build.
- The latest local terminal redesign is not another `TerminalScreen` compensation tweak; it changes the active CLI launch path to `NativeTerminalActivity`. Future agents should not assume the old Flutter terminal route is still the production path for CLI tools.
- Source metadata remains `2.5.0+143`; the latest published GitHub Release is `CiYuanXia-v5.4-173-arm64-v8a.apk` (Actions `29538124523`), while `CiYuanXia-v5.7-176-arm64-v8a.apk` (Actions `29584749891`) is the latest unreleased feature candidate.
- The next fresh cloud build must use a new logical build greater than `176`; do not reuse withdrawn builds `154` or `155`, or failed/reserved historical build numbers.
- The current APK workflow is green without running `flutter test`; keep that gap visible until CI or a dedicated SDK environment closes it.
- Keep Node.js `24.15.0` for arm64/x86_64 and `22.22.3` for armv7 aligned across constants, RootFS scripts, setup l10n copy, docs, bootstrap resource names, license/source notices, legacy installer URLs, and `lib/test.js` unless a future task upgrades the runtime asset set.
- `inspect_app_project.py` only auto-detects the root Node shell here; manually verify Flutter/Kotlin facts from `flutter_app/` before editing or reporting architecture.
- Keep the stable `browser_control` MCP entrypoint and `browser-script call/control` fallbacks in sync with the bridge action aliases.
- Keep the Codex `responses` proxy bridge in sync with upstream `function_call` / `function_call_output` semantics; do not silently drop tool-call structure during compatibility translation.
- Keep terminal display throttling scoped to rendering/scrollback only; do not route CLI context management through Flutter terminal display text.
- Update `.codex-app/state.md` and the latest session handoff after meaningful changes.
- Preserve `AGENTS.md`: only build/release Android `arm64-v8a` APK unless explicitly asked.
- Keep Codex/Claude CLI installation inside Ubuntu RootFS dedicated prefixes under `/opt/openclaw-cli/<tool>` with wrappers in `/usr/local/bin`.
- Do not switch CLI installation back to plain global `npm install -g`.
