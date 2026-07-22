# UI System

## Browser Script Assistant
- The script assistant uses two adjacent workspaces on wide layouts: the Codex automation-flow library on the left and the traditional website-script library on the right. Narrow layouts stack the same two workspaces to preserve readable editing controls.
- Traditional scripts use an amber code icon/border to distinguish them from the accent-colored Codex automation cards. Both surfaces retain explicit labels, empty states, and destructive-action confirmations.

## Design Direction
Operational Android utility app for managing an OpenClaw runtime. Existing screens are dashboard/control-panel oriented, not landing-page oriented. Preserve dense, scannable controls, clear status, explicit loading/error states, and mobile-first ergonomics.

## Tokens
- Color: `AppColors` in `flutter_app/lib/app.dart`; red accent `#DC2626`, dark backgrounds `#0A0A0A/#121212/#1A1A1A`, light backgrounds `#FFFFFF/#F9F9F9`, status green/amber/red/grey.
- Typography: Google Fonts Inter for app themes; terminal uses bundled DejaVuSansMono fonts.
- Spacing: common page padding via `ResponsiveLayout.pagePadding`; compact width 360, wide width 720, max content width 980, max text scale 1.25.
- Shape: theme buttons/inputs/snackbars use 8px radius; some existing cards/icon wells use 12px; terminal toolbar keys use 6px.
- Elevation/shadow: mostly Material cards and low-emphasis borders; keep surfaces restrained.

## Components
- `OpenSourceLicensesScreen`: Settings -> Open Source Licenses uses a full-screen Flutter page, not a dialog, for long compliance text. The page must show repository/source addresses first, then the full bundled notices/source-offer/package licenses below. Keep the body scrollable, selectable, responsive via `ResponsiveLayout`, and with loading/error/empty states; load the long full-notice document after the first frame so opening the page is not blocked by license aggregation.
- `NativeTerminalPagerActivity` multi-session controls should stay parity with ordinary `NativeTerminalActivity` and the old Flutter terminal: always expose `新建`, a session switcher/menu, and `关闭会话`, plus a title badge when more than one Codex terminal session exists.
- Native Codex pager/browser action controls should be icon-only rounded buttons using existing Lucide-style PNG drawables, with `contentDescription`, selected/pressed rounded state backgrounds, and `HapticFeedbackConstants.KEYBOARD_TAP` on tap. Do not regress these dense action controls back to text-only buttons.
- Native browser script assistant should present two workspaces like the old Flutter sheet: `Codex 自动化` and `传统脚本`, with top actions for `保存最近流程` / `新增传统脚本` / `导入`, not a single mixed scroll list. The dialog should feel like a dense dark workbench: icon header, workspace counts, selected tab states, pending-draft card, compact icon action buttons, and high-contrast empty states.
- Native browser script-library sub-dialogs should use the same dense dark workbench chrome as the main assistant: icon header, framed content region, icon+text action buttons, visible destructive styling, and in-dialog close/cancel actions. Do not add raw AlertDialog title/message/positive-button popups for page snapshots, script details, import/edit forms, delete confirmations, run confirmations, variable prompts, or run logs.
- `NativeTerminalActivity` owns the ordinary CLI top chrome and must apply system-bar/IME insets at the activity root. Its title and action rows use compact native cards; this is separate from Codex pager chrome and must not change the ordinary terminal shortcut strip into Codex styling.
- `StatusCard`: repeated navigation/status card with icon, title, subtitle, optional trailing, optional tap.
- `GatewayControls`, `NodeControls`: operational controls tied to gateway/node lifecycle.
- `ProgressStep`, `OpenClawReleaseSelector`: setup and install flow components.
- `ResponsiveLayout`: content width/text-scale clamps.
- `TerminalToolbar`, `NativeTerminalView`, `NativeProotTerminal`: terminal input and native terminal surfaces. `TerminalScreen` now uses the native `NativeTerminalView` key strip (`useNativeToolbar: true`) so the terminal prompt and shortcut bar move as one Android surface during IME transitions. Both the native terminal shortcut bar and the Flutter fallback toolbar now provide explicit press-state background changes plus haptic feedback on taps.
- Shared native terminal chrome must stay scoped: ordinary CLI sessions should keep the tighter, simpler terminal toolbar styling, while the Codex pager may opt into denser/red-accented chrome. Do not restyle `NativeTerminalSessionView` globally for Codex and accidentally shrink other CLI terminal viewports again.
- `CliApiConfigDialog` / `CliApiProfilesDialog`: configuration dialogs.
- `TerminalBrowserPanel` now includes a horizontal tab strip, add/close tab controls, a dedicated full-width address-bar row, a separate high-contrast navigation/tool row, a UA switch button, and a more menu for low-frequency tools. The script assistant remains available from the more menu and opens a bottom-sheet script directory with a pending-save draft card, save/edit pending draft, save-from-recent, run, rename, copy command/prompt, delete, loading, empty, and error states.
- `NativeCodexBrowserView` should mirror the same information hierarchy on the native pager path: status row, horizontal tab strip, icon-based nav/tool row, dedicated address row, optional recent-actions strip, and optional inspector panel. Keep the native browser dense and operational rather than falling back to plain text-button scaffolding once the screen carries more than one control row.
- The native browser script library should keep near-parity with the old Flutter script assistant for saved content: native `browser_script_stage` pending drafts, save/edit pending draft, save recent flow, automation run/rename/copy/delete, and traditional script add/import/edit/run/delete/copy actions. Old Flutter fallback-panel in-memory drafts remain separate unless a future explicit cross-controller bridge is designed.

## Icon Strategy
- Flutter/Dart UI currently uses Material `Icons`.
- Android native floating file manager uses Lucide-style PNG assets in `flutter_app/android/app/src/main/res/drawable-nodpi/`.
- Native Codex pager/browser controls should reuse those existing Lucide-style PNG assets where possible instead of regressing to text-only controls once the surface becomes native.
- For native Codex browser/script-library actions, button labels may remain as accessibility descriptions and source labels, but the visible compact control should prefer semantically matched Lucide icons: `app-window` for browser entry, `external-link` for opening URLs, `panel-right/globe` for UA mode, `scan-search` for inspector, `mouse-pointer-click` for clickable elements, `link` for links, `play` for run, `workflow/route` for automation flows/steps, `file-code` for source scripts, `bot` for Codex generation, `upload` for import, plus save/edit/copy/trash/eye/star/close where appropriate. Pure icon-only controls in native browser surfaces should render an `ImageView` centered inside a fixed-size rounded `FrameLayout`; do not use TextView compound drawables for icon-only buttons. Native script-library popups should use custom dark workbench chrome with in-header close/refresh actions rather than stock AlertDialog positive buttons.
- When adding Flutter UI, prefer existing Material icon style unless the project migrates to a shared icon package intentionally.

## App Icon Pipeline
- Source app icon assets exist in root `assets/ic_launcher.png`, `assets/ic_launcher.svg`, `assets/ic_launcher_512.png`.
- Flutter asset includes `flutter_app/assets/ic_launcher.png`.
- Android launcher resources are committed under `flutter_app/android/app/src/main/res/mipmap-*` and adaptive icon XML under `mipmap-anydpi-v26`.

## Screen QA Notes
- Codex pager density policy: terminal/page chrome should not wrap the terminal, shortcut strip, or WebView in rounded outer cards. Browser controls should fit into a compact top band, leaving most height to the WebView; the more menu should use the custom dense list, not the default platform popup.
- Verify safe areas, keyboard overlap, loading states, empty states, error states, and text fitting.
- Important screens to manually smoke when UI changes: setup wizard, dashboard, terminal, Web dashboard, config editor, provider detail, backup manager, local model screens, settings/update flow.
- For Codex browser UI changes, smoke the terminal browser sidecar on compact and wide widths, including tab strip overflow, add/switch/close tab behavior, back/forward/reload state, desktop/mobile UA switching, desktop UA page layout, pinch/page zoom behavior, more-menu tool access, pending-save script draft card, script assistant bottom sheet, and header icon density.
- For native Codex pager UI changes, additionally smoke the dedicated Android pager header safe area, browser top strips, icon rendering/tint, recent-actions toggle, inspector cards, and address-row editing with IME open/close.
- Keep Codex browser header/menu surfaces explicitly high-contrast on the black panel background. Do not rely on the global `ListTileTheme` muted icon color for popup menu entries inside the browser panel.
- Keep browser IME behavior scoped to actual browser focus: the address bar and WebView form fields should switch the route away from terminal `adjustPan`, while simply keeping the sidecar mounted must not leave the route stuck in browser soft-input mode after the panel is hidden.
- For Codex terminal performance changes, smoke long CLI output and sidecar open/close while output is active; the compact browser sidecar now disposes when closed, so hidden WebView overhead should not linger across IME reopen checks. UI transcript limits must not be described as CLI context limits.
- On the terminal screen, keyboard open/close should use the route-scoped Android `adjustResize` path with `resizeToAvoidBottomInset: true` so the native terminal platform view receives the real IME inset and lifts the shortcut bar with it. The terminal page shortcut bar is native, not a Flutter overlay, and should ride with the terminal as a single surface above the IME without any extra global-layout compensation chain. Native terminal keyboard open should avoid redundant `showSoftInput` retries once focus is already active, so the prompt still appears above the keyboard without the extra lag caused by duplicate initial requests.
- Keep long Chinese/Japanese/English localized strings from overflowing compact Android screens.
