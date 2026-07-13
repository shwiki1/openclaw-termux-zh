# Backlog

## Ready
- Device-smoke Codex terminal performance: start a long Codex CLI conversation, open/close the compact browser sidecar while output is active, verify the sidecar stays connected, terminal input still works, and the terminal screen catches up after closing the sidecar.
- Device-smoke the browser automation hardening: verify `browser_control` and `browser-script` fallback commands can complete snapshot/read/type/click flows on a live WebView, then confirm the compact right browser sidecar still stays connected after close/reopen.
- Device-smoke the freshly built arm64 APK on Android: first browser open shows the `Codex 浏览器自动化控制` instructions page, self-test, open URL, wait selector, scroll, type, press Enter, select option, capture snapshot, then close/reopen the compact right browser sidecar and verify it still shows `浏览器已连接`.
- Device-smoke the Codex browser script assistant: perform a short browser flow, save recent actions as a script, reopen the script directory, rename it, copy `browser-script run <id>`, run it from the Codex terminal, delete the script, and verify the WebView remains attached throughout.
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
- Current metadata is aligned at source `2.0.50+139`; the latest GitHub artifact was CI version `2.0.50+138` from run `29278136954`; failed runs `29277705784` and `29282846337` produced no artifact; the next cloud build should produce CI version `2.0.50+140` or higher.
- Keep the stable `browser_control` MCP entrypoint and `browser-script call/control` fallbacks in sync with the bridge action aliases.
- Keep terminal display throttling scoped to rendering/scrollback only; do not route CLI context management through Flutter terminal display text.
- Update `.codex-app/state.md` and the latest session handoff after meaningful changes.
- Preserve `AGENTS.md`: only build/release Android `arm64-v8a` APK unless explicitly asked.
- Keep Codex/Claude CLI installation inside Ubuntu RootFS dedicated prefixes under `/opt/openclaw-cli/<tool>` with wrappers in `/usr/local/bin`.
- Do not switch CLI installation back to plain global `npm install -g`.
