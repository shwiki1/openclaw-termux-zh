# 2026-07-18 Codex Pager Density And Browser Menu

## Goal
- Remove rounded outer frames from the Codex CLI terminal and shortcut-key chrome.
- Remove the browser WebView border.
- Compress browser buttons/address/status into a compact top band.
- Replace the browser more menu with a prettier dense list.
- Do not build or submit a cloud package.

## Repo Facts Read
- `NativeTerminalPagerActivity.kt`
- `NativeTerminalSessionView.kt`
- `NativeCodexBrowserView.kt`
- `lib/test.js`
- `.codex-app/ui-system.md`

## Changes Made
- `NativeTerminalPagerActivity`: removed the rounded `pagesContainer` frame and action-row background; flattened Codex pager buttons.
- `NativeTerminalSessionView`: Codex toolbar strip and shortcut keys no longer draw rounded card backgrounds.
- `NativeCodexBrowserView`: merged browser navigation/address/open/UA/more controls into one compact row; status/meta row is shorter; tab strip is flatter; WebView has no border/padding; default `PopupMenu` replaced with a custom dense `AlertDialog` list.
- `lib/test.js`: added source guards for flattened chrome, unframed browser, compact controls, and custom more menu.

## Checks Run
- `npm test`: 32/32
- `npm run lint -- --no-warn-ignored`: passed
- App memory validation: no errors, no warnings
- Local Flutter/Dart/Kotlin compilers remain unavailable

## Cloud Build
- Not requested; none launched.

## Version And Artifacts
- Source anchor remains `2.5.0+143`
- No APK produced
- Next cloud build must be logical build `> 184` if packaging is later requested

## Known Risks
- Needs device visual smoke for height target: browser top chrome should stay around one-fifth of screen height on common phone sizes.
- Kotlin/Flutter compile not available locally.
- Pending-save draft is still not bridged into native script assistant.

## Next Actions
1. Device-smoke the native Codex pager layout after packaging is requested.
2. Check compact/large screens for top chrome height, address input usability, WebView viewport gain, and more-menu touch targets.
3. Package only on explicit request.
