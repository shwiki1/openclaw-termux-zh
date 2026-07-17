# 2026-07-17 00:19 UTC - Native Codex Pager UI Stabilization

## Goal
- Stabilize the native Codex dual-page terminal/browser UI after device feedback reported top clipping, terminal shortcut-bar IME misplacement, and major browser UI parity gaps versus the previous Flutter browser panel.

## Repo Facts Read
- `.codex-app/state.md`
- `.codex-app/manifest.md`
- `.codex-app/architecture.md`
- `.codex-app/ui-system.md`
- `.codex-app/backlog.md`
- `flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/NativeTerminalPagerActivity.kt`
- `flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/NativeTerminalSessionView.kt`
- `flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/NativeCodexBrowserView.kt`
- `flutter_app/lib/widgets/terminal_browser_panel.dart`

## Changes Made
- Reworked `NativeTerminalPagerActivity.kt` so the native pager root now applies system-bar insets, keeps browser and terminal pages in one resized activity tree, and hides terminal-only action chips while the browser page is active.
- Added `requestToolbarVisible()` in `NativeTerminalSessionView.kt` and changed native-toolbar IME visibility requests to target the toolbar strip rectangle instead of bailing out early for `useNativeToolbar`.
- Rebuilt the native browser header in `NativeCodexBrowserView.kt` into separate status/tab/nav/address strips, swapped text-only controls for Lucide-style icon buttons where available, added a popup tools menu, recent-actions strip, snapshot preview dialog, and a native inspector for interactables/links.
- Updated `lib/test.js` source guards to cover the new native pager/browser structure and the new native-toolbar visibility path.

## Checks Run
- `git diff --check`
- `npm test`
- `npm run lint -- --no-warn-ignored`

## Cloud Build
- Not started in this turn.

## Version And Artifacts
- Source anchor unchanged: `2.5.0+143`
- Latest known published release remains `v5.4.0 / 5.4 / 173`
- No new APK artifact produced in this turn

## Known Risks
- Local Termux environment still has no `flutter`, `dart`, or `kotlinc`, so there was no native compile or Flutter analyzer coverage for the Kotlin/UI changes.
- Native browser now has better parity for top-level UI chrome, but script-library parity with the old Flutter browser panel is still incomplete on the native page.
- IME behavior and safe-area fixes still require Android device smoke on a real keyboard and real cutout/status-bar environment.

## Next Actions
- Device-smoke the native pager on Android with a full terminal transcript and repeated IME open/close cycles.
- Verify the browser page top area is no longer clipped and the native inspector/recent-actions UI remains responsive.
- If the behavior is good enough, bump the build number and submit the next GitHub cloud build; otherwise keep fixes scoped to the native pager instead of reviving Flutter compensation.
