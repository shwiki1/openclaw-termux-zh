# Backlog

## Ready
- Device-smoke Codex browser multi-tab and UA behavior on Android: open multiple pages, switch tabs, close a tab, use back/forward/reload, switch desktop/mobile UA, and verify desktop pages no longer fall back to the mobile layout on representative sites.
- Device-smoke Codex terminal performance: start a long Codex CLI conversation, open/close the compact browser sidecar while output is active, verify the sidecar stays connected, terminal input still works, and the terminal screen catches up after closing the sidecar.
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
- Current metadata is aligned at source `2.0.50+142` for the Node engine-floor retry; the latest completed GitHub artifact before the browser tabs/UA build submission was CI version `2.0.50+141` from run `29293286907`, and run `29321533131` failed before APK upload; bump build metadata before any later new cloud build.
- Current browser automation work is being submitted to GitHub Actions; after the APK is available, the next browser smoke target is Android device verification of tab/UA/mobile-desktop behavior.
- Keep Node.js `24.15.0` for arm64/x86_64 and `22.22.3` for armv7 aligned across constants, RootFS scripts, setup l10n copy, docs, bootstrap resource names, license/source notices, legacy installer URLs, and `lib/test.js` unless a future task upgrades the runtime asset set.
- `inspect_app_project.py` only auto-detects the root Node shell here; manually verify Flutter/Kotlin facts from `flutter_app/` before editing or reporting architecture.
- Keep the stable `browser_control` MCP entrypoint and `browser-script call/control` fallbacks in sync with the bridge action aliases.
- Keep terminal display throttling scoped to rendering/scrollback only; do not route CLI context management through Flutter terminal display text.
- Update `.codex-app/state.md` and the latest session handoff after meaningful changes.
- Preserve `AGENTS.md`: only build/release Android `arm64-v8a` APK unless explicitly asked.
- Keep Codex/Claude CLI installation inside Ubuntu RootFS dedicated prefixes under `/opt/openclaw-cli/<tool>` with wrappers in `/usr/local/bin`.
- Do not switch CLI installation back to plain global `npm install -g`.
