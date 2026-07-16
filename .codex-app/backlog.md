# Backlog

## Priority Now
- Push the Codex terminal redesign retry to GitHub `main`, watch the next arm64 release build, and record the resulting `4.7 / 166` provenance before any further code work.
- Device-smoke the latest published `CiYuanXia-v4.4-163-arm64-v8a.apk` on Android: first-run bootstrap, installer/app version `4.4`, update compatibility, terminal IME prompt visibility, native shortcut-bar co-movement/feedback, browser address-bar/input lift, compact-sidecar reconnect, browser tabs/UA, and browser-script workflow.
- Device-smoke the redesigned Codex terminal shortcut path on Android: native shortcut bar inside the terminal platform view, repeated IME dismiss/reopen, immediate shortcut-key taps after IME close, and leave/re-enter terminal. If lag remains, focus on native `TerminalView`/`adjustPan` and platform-view/session reattach timing rather than reviving compensation layers.
- Device-smoke Codex tool calling through the OpenAI-compatible proxy path: verify `responses`-based tool calls, MCP browser tools, and follow-up `function_call_output` turns all survive the local proxy without flattening into plain text.
- Add `flutter test` to the GitHub Actions gate or run it in a dedicated Flutter SDK environment before the next release candidate; the repo already has Flutter tests, but the current green APK workflow does not execute them.
- Decide the release promotion path for the next build: which branch is authoritative, which remote is used for cloud builds, who bumps the build number, and where changelog/release notes are cut from.
- Reconcile the current branch topology before the next release push: `codex-terminal-ime-lag-fix` is `ahead 8, behind 9` versus `shwiki/main`, and `main` also diverges from `origin/main`.
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
- Keep app version/build number updated before every new cloud build.
- Source metadata remains `2.5.0+143`; the latest recorded successful GitHub Release asset is `CiYuanXia-v4.4-163-arm64-v8a.apk` (Actions `29479840309`). It still needs Android device smoke plus local artifact verification before promotion confidence is established.
- The next fresh cloud build must use a new logical build greater than `165`; do not reuse withdrawn builds `154` or `155`, and do not reuse failed builds `157`, `158`, `160`, `161`, or `165`.
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
