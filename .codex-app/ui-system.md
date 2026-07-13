# UI System

## Design Direction
Operational Android utility app for managing an OpenClaw runtime. Existing screens are dashboard/control-panel oriented, not landing-page oriented. Preserve dense, scannable controls, clear status, explicit loading/error states, and mobile-first ergonomics.

## Tokens
- Color: `AppColors` in `flutter_app/lib/app.dart`; red accent `#DC2626`, dark backgrounds `#0A0A0A/#121212/#1A1A1A`, light backgrounds `#FFFFFF/#F9F9F9`, status green/amber/red/grey.
- Typography: Google Fonts Inter for app themes; terminal uses bundled DejaVuSansMono fonts.
- Spacing: common page padding via `ResponsiveLayout.pagePadding`; compact width 360, wide width 720, max content width 980, max text scale 1.25.
- Shape: theme buttons/inputs/snackbars use 8px radius; some existing cards/icon wells use 12px; terminal toolbar keys use 6px.
- Elevation/shadow: mostly Material cards and low-emphasis borders; keep surfaces restrained.

## Components
- `StatusCard`: repeated navigation/status card with icon, title, subtitle, optional trailing, optional tap.
- `GatewayControls`, `NodeControls`: operational controls tied to gateway/node lifecycle.
- `ProgressStep`, `OpenClawReleaseSelector`: setup and install flow components.
- `ResponsiveLayout`: content width/text-scale clamps.
- `TerminalToolbar`, `NativeTerminalView`, `NativeProotTerminal`: terminal input and native terminal surfaces.
- `CliApiConfigDialog` / `CliApiProfilesDialog`: configuration dialogs.
- `TerminalBrowserPanel` now includes a compact script assistant button (`Icons.playlist_play`) that opens a bottom-sheet script directory with save-from-recent, run, rename, copy command/prompt, delete, loading, empty, and error states.

## Icon Strategy
- Flutter/Dart UI currently uses Material `Icons`.
- Android native floating file manager uses Lucide-style PNG assets in `flutter_app/android/app/src/main/res/drawable-nodpi/`.
- When adding Flutter UI, prefer existing Material icon style unless the project migrates to a shared icon package intentionally.

## App Icon Pipeline
- Source app icon assets exist in root `assets/ic_launcher.png`, `assets/ic_launcher.svg`, `assets/ic_launcher_512.png`.
- Flutter asset includes `flutter_app/assets/ic_launcher.png`.
- Android launcher resources are committed under `flutter_app/android/app/src/main/res/mipmap-*` and adaptive icon XML under `mipmap-anydpi-v26`.

## Screen QA Notes
- Verify safe areas, keyboard overlap, loading states, empty states, error states, and text fitting.
- Important screens to manually smoke when UI changes: setup wizard, dashboard, terminal, Web dashboard, config editor, provider detail, backup manager, local model screens, settings/update flow.
- For Codex browser UI changes, smoke the terminal browser sidecar on compact and wide widths, including the script assistant bottom sheet and header icon density.
- Keep long Chinese/Japanese/English localized strings from overflowing compact Android screens.
