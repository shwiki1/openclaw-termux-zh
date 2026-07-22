# Dashboard CLI And Terminal Only

## Goal
Reduce the main app surface to only CLI tools and terminal, and remove related unused files/code while preserving the CLI local API relay and terminal/browser automation paths.

## Repo Facts Read
- Repo root: `/storage/emulated/0/ZeroTermux/开发/openclaw-termux-zh-5.5`.
- Dashboard now intentionally exposes only `CliToolsScreen` and `TerminalScreen`.
- The preserved CLI boundary is `CliToolsScreen`, `CliApiConfigService`, `LocalApiProxyService`, `LocalApiProxyBrowserScreen`, bundled `assets/api2py`, terminal services, and native Codex browser automation.
- Local Flutter/Dart/adb are unavailable in this Termux environment.

## Changes Made
- Continued the previous OpenClaw-removal pass and confirmed the dashboard only renders CLI tools and terminal cards.
- Removed two remaining zero-reference Dart files: `custom_provider_preset.dart` and `screenshot_service.dart`.
- Renamed the old `OpenClawInstallOptions` setup model to `RuntimeInstallOptions`, removed the unused OpenClaw installation/version selection fields, and reduced it to the RootFS/Node resource overrides actually used by setup.
- Cleaned user-visible native notification text from `Running OpenClaw task...` / `OpenClaw URLs` to generic CLI wording.
- Slimmed the four localization maps to current Dart `l10n.t(...)` callers and restored missing dashboard keys for `dashboardTitle`, `dashboardCliToolsTitle`, and `dashboardCliToolsSubtitle`.
- Updated first-run setup copy to describe a CLI runtime instead of OpenClaw installation.

## Checks Run
- `npm test` passed 41/41.
- `npm run lint -- --no-warn-ignored` passed.
- `git diff --check` passed.
- `flutter --version` failed because Flutter is not installed in this Termux environment, so Flutter analyze/test and Android compile still require GitHub Actions.
- Source scans confirmed no references remain to `custom_provider_preset`, `screenshot_service`, `OpenClawInstallOptions`, or `installOpenClaw` outside test guards.

## Cloud Build
- No cloud build was triggered in this session.
- Latest packaged cloud candidate remains `8.9 / 208`; the next APK claiming this removal must use build `> 208`, and should rebuild RootFS if the packaged RootFS identity needs to stop using older OpenClaw-named assets.

## Version And Artifacts
- No version/build bump was made.
- No APK artifact was produced.

## Known Risks
- Flutter analyzer and Kotlin/Gradle compile were not run locally because local Flutter is unavailable.
- Several compatibility names intentionally remain, including `/root/.openclaw`, `openclaw-rootfs-*`, `openclaw/native_terminal`, and OpenClaw-named generated CLI/browser bridge strings. These are compatibility surfaces for existing CLI workspace/runtime assets, not dashboard UI.
- The working tree already contained broad previous deletion changes before this session; this session built on them and did not revert them.

## Next Actions
- Run GitHub Actions compile/build before installing this large cleanup on device.
- Device-smoke first setup, dashboard two-card navigation, CLI tools, local API relay `中转代理` / `API 管理`, ordinary terminal, and Codex terminal/browser automation.
