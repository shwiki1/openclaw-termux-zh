# 2026-07-17 02:19 UTC - Native Codex Space And Script Parity

## Goal
- Recover terminal/browser viewport space after the over-rounded native Codex pager polish, restore the old compact look for ordinary CLI terminals, and continue bringing the native browser script library back toward the older Flutter script-assistant behavior.

## Repo Facts Read
- `.codex-app/state.md`
- `.codex-app/manifest.md`
- `.codex-app/architecture.md`
- `.codex-app/ui-system.md`
- `.codex-app/backlog.md`
- `.codex-app/sessions/20260717-001916-native-codex-pager-ui-stabilization.md`
- `flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/NativeTerminalSessionView.kt`
- `flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/NativeTerminalPagerActivity.kt`
- `flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/NativeCodexBrowserView.kt`
- `flutter_app/lib/widgets/terminal_browser_panel.dart`
- `lib/test.js`

## Changes Made
- Added `useCodexChrome` to `NativeTerminalSessionConfig` and used it only from `NativeTerminalPagerActivity`, so ordinary CLI sessions keep a tighter classic toolbar while Codex pager sessions alone use the denser red-accented chrome.
- Reduced native pager/browser outer margins, button radii, top-strip paddings, and icon/button dimensions so the terminal and WebView reclaim more vertical space.
- Expanded the native browser script library from a read-only list into an operational tool surface:
  - save recent browser flow into a reusable automation script
  - automation run, rename, inspect steps, copy command, copy Codex prompt, delete
  - traditional script add, import, edit, run on current page, copy source, copy Codex generation prompt, delete
- Kept the remaining parity gap explicit: pending-save drafts produced by Flutter-side `browser_script_stage` are still not surfaced in the native dialog.
- Updated `lib/test.js` source guards for the Codex-only chrome split and the restored native script-library actions.

## Checks Run
- `npm test`
- `npm run lint -- --no-warn-ignored`
- `git diff --check`

## Cloud Build
- Not started in this turn.

## Version And Artifacts
- Source anchor unchanged: `2.5.0+143`
- No new build number or APK artifact produced in this turn

## Known Risks
- Local Termux environment still has no `flutter`, `dart`, or `kotlinc`, so there was no native compile or Flutter analyzer coverage for the Kotlin/UI changes.
- Native browser script-library parity is much better, but Flutter-side pending-save draft state from `browser_script_stage` still remains outside the native UI.

## Next Actions
- Device-smoke ordinary CLI terminals and the Codex pager on Android to confirm the chrome split behaves as intended.
- Verify native browser script-library add/import/edit/run/delete flows on a real device.
- If device behavior is acceptable, bump the build number and submit the next arm64 cloud build.
