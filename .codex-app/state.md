# Current App State

Last updated: 2026-07-13 17:16 UTC

## Current Truth
- App: `次元虾`, a Chinese Android integration for OpenClaw Gateway without a Termux app dependency.
- Repository root: `/storage/emulated/0/ZeroTermux/开发/openclaw-termux-zh-5.5`.
- Stack: Flutter/Dart Android app shell, Kotlin native Android services, PRoot Ubuntu RootFS runtime, and a legacy Node.js CLI package.
- Package manager: npm at repo root with `package-lock.json`; Flutter dependencies are in `flutter_app/pubspec.yaml` and `flutter_app/pubspec.lock` is ignored.
- Active branch: `codex-termux-runtime-fix`.
- Remotes: `origin` is Gitee `https://gitee.com/cds-y-code/openclaw-termux-zh.git`; `shwiki` is GitHub `https://github.com/shwiki1/openclaw-termux-zh.git`.
- Cloud build: `.github/workflows/flutter-build.yml` builds an `arm64-v8a` APK and can create a GitHub Release.
- Current source version: root `package.json` `2.0.50`; Flutter `pubspec.yaml` `2.0.50+135`.
- App version: `2.0.50`.
- Build number: `135` in `flutter_app/pubspec.yaml`; CI may use a higher GitHub run number.
- Version metadata is aligned to `2.0.50+135` in Flutter defaults, README files, STRUCTURE, and CHANGELOG.
- Last artifact: GitHub Actions run `29262431252` produced `CiYuanXia-v2.0.50-135-arm64-v8a.apk` from `shwiki/codex-termux-runtime-fix` head `844f49aa9d21dd54f3521c43d19bef8b25920171`; local download path is `artifacts/github-run-29262431252/ciyuanxia-apks/CiYuanXia-v2.0.50-135-arm64-v8a.apk`; APK SHA256 `f601685c47dd189889c7cfe86f1b09761e691c61d40eae937c1970ea4e01a847`.

## Active Task
- Preparing a new GitHub Actions cloud build for the Codex browser sidecar keep-alive and default instructions page fixes.

## Recently Changed
- Extended Codex browser automation with `browser_wait_for_selector`, `browser_scroll`, `browser_press_key`, and `browser_select_option`.
- Updated Flutter browser bridge interfaces and WebView execution in `BrowserAutomationService` and `TerminalBrowserPanel`.
- Updated generated Codex MCP script and `browser-operator` skill guidance in `CliApiConfigService`.
- Added Flutter test assertions for the generated browser MCP tools.
- Added an Unreleased changelog note for Codex browser automation enhancement.
- Updated `flutter_app/lib/constants.dart` default build number from `126` to `133`.
- Updated `README.md`, `docs/README_en.md`, `STRUCTURE.md`, and `CHANGELOG.md` to match `2.0.50+133`.
- Bumped Flutter source/build metadata from `2.0.50+133` to `2.0.50+134` before the next cloud build.
- Bumped Flutter source/build metadata from `2.0.50+134` to `2.0.50+135` before the next cloud build.
- Corrected `STRUCTURE.md` notes that incorrectly described the current repo state and CI as multi-architecture/AAB oriented.
- Watched GitHub Actions workflow `Build OpenClaw Apps` run `29262431252` to successful completion and downloaded the `ciyuanxia-apks` artifact.
- Escaped shell variable references in `flutter_app/test/cli_api_config_service_test.dart` so Dart no longer interprets `$codex_config` as a test identifier.
- Re-verified the repo map, stack, version source, and build workflow against `package.json`, `flutter_app/pubspec.yaml`, `flutter_app/android/app/build.gradle`, `flutter_app/android/app/src/main/AndroidManifest.xml`, `flutter_app/lib/main.dart`, `flutter_app/lib/app.dart`, `flutter_app/lib/constants.dart`, `flutter_app/lib/services/native_bridge.dart`, and `.github/workflows/flutter-build.yml` for this project-management checkpoint.
- Reworked the compact Codex terminal browser sidecar in `flutter_app/lib/screens/terminal_screen.dart`: replaced `Scaffold.endDrawer` with an in-page persistent `Stack`/`AnimatedPositioned` panel, added right-edge swipe open, scrim/back close, and kept `TerminalBrowserPanel` mounted while hidden.
- Updated `CHANGELOG.md` Unreleased notes for the Codex browser sidecar keep-alive fix.
- Reworked `TerminalBrowserPanel` default loading in `flutter_app/lib/widgets/terminal_browser_panel.dart`: removed `PreferencesService.dashboardUrl` auto-open behavior, added a richer built-in `Codex 浏览器自动化控制` instructions page, and kept pending URL/tool-requested opens intact.
- Updated `CHANGELOG.md` Unreleased notes for the Codex browser default instructions page.

## Checks
- `rg` consistency checks confirmed the new browser tools are present in the bridge, WebView delegate, MCP generator, generated skill text, and test assertions.
- `rg` checks found no remaining current-version `2.0.50+126` / `2.0.50-126` / `build-number 126` / default build `126` references in current docs/source.
- `git diff --check`: passed before and after the test fix.
- `npm test`: passed again after the test fix, 11 checks passed and 0 failed.
- `npm run lint -- --no-warn-ignored`: passed again after the test fix.
- `rg` consistency checks found no remaining current-version `2.0.50+133`, `2.0.50-133`, or default build `133` references in primary version docs/source after the `134` bump.
- `command -v dart` and `command -v flutter`: no local SDK found; Flutter analyze/test/build need a Flutter SDK environment or GitHub Actions.
- GitHub Actions run `29262431252`: completed with conclusion `success`; CI version was `2.0.50+135`; artifact ID `3392725610`; artifact digest `sha256:88cd0292fc7f665e4c0f032d557f249bd9dc98394cfd4389efc2818bd4b4f3ca`.
- CI `flutter analyze --no-fatal-infos` reported 71 issues non-fatally, including `undefined_identifier` errors for `codex_config` in `flutter_app/test/cli_api_config_service_test.dart`.
- Artifact sanity checks: downloaded ZIP was valid, extracted APK size was 74179518 bytes, APK SHA256 matched the recorded checksum, and `lib/arm64-v8a/libproot.so` plus `lib/arm64-v8a/libloader.so` were present.
- `rg -n -P '(?<!\\)\$[A-Za-z_][A-Za-z0-9_]*' flutter_app/test/cli_api_config_service_test.dart`: no unescaped Dart interpolation candidates remain in the test file.
- `git diff --check`: passed after the test fix and memory updates.
- App memory validation: passed after recording the cloud build and test fix.
- `scripts/inspect_app_project.py --project .`: detected npm at the repo root, Flutter app under `flutter_app/`, and `.github/workflows/flutter-build.yml` as the only workflow.
- Project-management checkpoint checks: `git diff --check` passed; `npm test` passed with 11 checks; `npm run lint -- --no-warn-ignored` passed; final app memory validation passed with no errors and no warnings.
- Browser sidecar lifecycle fix checks: `git diff --check` passed; `npm test` passed with 11 checks; `npm run lint -- --no-warn-ignored` passed; final app memory validation passed with no errors and no warnings; `command -v dart` and `command -v flutter` returned no local SDK paths, so Flutter analyze/test were not run locally.
- Browser default instructions page checks: `rg` confirmed no `PreferencesService`/`dashboardUrl` reference remains in `terminal_browser_panel.dart`; `git diff --check` passed; `npm test` passed with 11 checks; `npm run lint -- --no-warn-ignored` passed; final app memory validation passed with no errors and no warnings; local Flutter analyze/test were not run because `dart` and `flutter` are unavailable.

## Memory Validation
- Initial validation before filling memory passed with warnings for placeholder fields.
- Final validation after metadata fixes passed with no errors and no warnings.

## Risks And Blockers
- Local environment cannot run Flutter checks yet.
- The compact browser sidecar keep-alive and default instructions page fixes have not been Flutter-analyzed or device-smoked yet because local Flutter/Android tooling is unavailable in this Termux session.
- CI produced the APK with debug signing fallback because release signing secrets were not configured in the workflow environment.
- Flutter analyzer issues other than the fixed `codex_config` test errors may remain; the build workflow currently records them but does not fail the APK build.
- App declares broad Android permissions including all-files access, overlay, install packages, camera, location, sensors, Bluetooth, notifications, foreground services, and cleartext traffic; treat permission changes as release-critical.
- `flutter_app/assets/bootstrap/openclaw-rootfs-noble-arm64.tar.gz` is a 134-byte Git LFS pointer to a 147 MB asset; cloud/local builds must restore or fetch the real asset when bundling RootFS.
- Project policy in `AGENTS.md`: build/release only Android `arm64-v8a` APK unless explicitly requested.

## Next Actions
- Re-run Flutter analyze/test in CI or a Flutter SDK environment to verify the local Dart changes and triage any remaining analyzer reports.
- Device-smoke a new APK on an Android arm64 device/emulator: launch, setup/runtime bootstrap, gateway start/stop, terminal, Codex browser MCP tools, verify first browser open shows the `Codex 浏览器自动化控制` instructions page instead of Gateway, and verify closing/reopening the compact right browser sidecar keeps `浏览器已连接`.
- Configure GitHub signing secrets before treating a future APK as a signed release artifact.
- New cloud build is expected to generate CI version `2.0.50+136` or higher because the workflow uses the greater of `GITHUB_RUN_NUMBER` and `pubspec build + 1`.
