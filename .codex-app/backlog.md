# Backlog

## Priority Now
- Device-smoke the published `CiYuanXia-v3.2-151-arm64-v8a.apk` on Android, prioritizing terminal prompt visibility above the IME, native shortcut-bar co-movement, shortcut-key haptic/press feedback, browser address-bar stability, WebView input-field lift behavior, compact-sidecar hide/show recovery, and installer/app version text.
- Re-smoke terminal IME reopen on Android with the latest local source behavior: first open, repeated dismiss/reopen inside one session, and leave/re-enter terminal screen. Old Flutter terminal overlay logic is no longer the main suspect; if lag remains, focus the next investigation on native platform-view/session reattach timing and the compact browser sidecar lifecycle.
- Device-smoke the published `CiYuanXia-v3.0-149-arm64-v8a.apk` on Android, prioritizing terminal input visibility above the IME, native shortcut-bar co-movement, browser address-bar/readability checks, installer/app version text, first-run bootstrap, browser multi-tab, UA switching, script assistant, browser fallbacks, and compact sidecar reconnect behavior.
- Device-smoke the published `CiYuanXia-v2.8-147-arm64-v8a.apk` on Android, prioritizing terminal input visibility above the IME, the compensated bottom shortcut bar, browser address-bar/readability checks, first-run bootstrap, browser multi-tab, UA switching, script assistant, browser fallbacks, and compact sidecar reconnect behavior.
- Add `flutter test` to the GitHub Actions gate or run it in a dedicated Flutter SDK environment before the next release candidate; the repo already has Flutter tests, but the current green APK workflow does not execute them.
- If device smoke still shows the terminal prompt hidden behind the keyboard or the shortcut bar still over-lifts, keep investigation focused on native Android `TerminalView`/`adjustPan` interactions and `NativeTerminalView.kt` global-layout overlap compensation rather than Flutter `TextField` behavior.
- Decide the release promotion path for the next build: which branch is authoritative, which remote is used for cloud builds, who bumps the build number, and where changelog/release notes are cut from.

## Ready
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
- Current source metadata anchor is `2.5.0+143`; latest successful GitHub Release asset is `CiYuanXia-v3.0-149-arm64-v8a.apk`, which includes the native terminal IME compensation follow-up and still needs Android device smoke.
- Current source metadata anchor is `2.5.0+143`; latest successful GitHub Release asset is `CiYuanXia-v3.1-150-arm64-v8a.apk`, which includes the browser/terminal IME focus handoff follow-up and still needs Android device smoke.
- Current source metadata anchor is `2.5.0+143`; latest successful GitHub Release asset is `CiYuanXia-v3.2-151-arm64-v8a.apk`, which includes the terminal shortcut-key feedback follow-up and still needs Android device smoke.
- Remote `main` is now at `c5be0df884a6e066fdedb07d6d245af03802a0fc`, and GitHub Actions run `29370762550` completed successfully for the native-toolbar follow-up targeting `2.9 / 148`.
- Remote `main` is now at `db7ce2e9e992be903fa80df9146362aee6c291c2`, and GitHub Actions run `29373389340` completed successfully for the native terminal IME compensation follow-up targeting `3.0 / 149`.
- Remote `main` is now at `92b8b59d29a298a05dcb01f290f32df34beb1254`, and GitHub Actions run `29375096798` completed successfully for the browser/terminal IME focus handoff follow-up targeting `3.1 / 150`.
- Remote `main` is now at `f250722d5dd2709b388ee42030c10559977aba74`, and GitHub Actions run `29377510459` completed successfully for the terminal shortcut-key feedback follow-up targeting `3.2 / 151`.
- Future user-facing builds now derive automatically from the target build number: `148 -> 2.9`, `149 -> 3.0`, `150 -> 3.1`, `151 -> 3.2`, `152 -> 3.3`, `153 -> 3.4`.
- The next fresh build should be `152 -> 3.3` if another new artifact is required after device smoke or workflow/test changes.
- Current browser automation work is being submitted to GitHub Actions; after the APK is available, the next browser smoke target is Android device verification of tab/UA/mobile-desktop behavior.
- The current APK workflow is green without running `flutter test`; keep that gap visible until CI or a dedicated SDK environment closes it.
- Keep Node.js `24.15.0` for arm64/x86_64 and `22.22.3` for armv7 aligned across constants, RootFS scripts, setup l10n copy, docs, bootstrap resource names, license/source notices, legacy installer URLs, and `lib/test.js` unless a future task upgrades the runtime asset set.
- `inspect_app_project.py` only auto-detects the root Node shell here; manually verify Flutter/Kotlin facts from `flutter_app/` before editing or reporting architecture.
- Keep the stable `browser_control` MCP entrypoint and `browser-script call/control` fallbacks in sync with the bridge action aliases.
- Keep terminal display throttling scoped to rendering/scrollback only; do not route CLI context management through Flutter terminal display text.
- Update `.codex-app/state.md` and the latest session handoff after meaningful changes.
- Preserve `AGENTS.md`: only build/release Android `arm64-v8a` APK unless explicitly asked.
- Keep Codex/Claude CLI installation inside Ubuntu RootFS dedicated prefixes under `/opt/openclaw-cli/<tool>` with wrappers in `/usr/local/bin`.
- Do not switch CLI installation back to plain global `npm install -g`.
