# Current App State

Last updated: 2026-07-13 21:55 UTC

## Current Truth
- App: `次元虾`, a Chinese Android integration for OpenClaw Gateway without a Termux app dependency.
- Repository root: `/storage/emulated/0/ZeroTermux/开发/openclaw-termux-zh-5.5`.
- Stack: Flutter/Dart Android app shell, Kotlin native Android services, PRoot Ubuntu RootFS runtime, and a legacy Node.js CLI package.
- Package manager: npm at repo root with `package-lock.json`; Flutter dependencies are in `flutter_app/pubspec.yaml` and `flutter_app/pubspec.lock` is ignored.
- Active branch: `codex-termux-runtime-fix`.
- Remotes: `origin` is Gitee `https://gitee.com/cds-y-code/openclaw-termux-zh.git`; `shwiki` is GitHub `https://github.com/shwiki1/openclaw-termux-zh.git`.
- Cloud build: `.github/workflows/flutter-build.yml` builds an `arm64-v8a` APK and can create a GitHub Release.
- Current source version: root `package.json` `2.0.50`; Flutter `pubspec.yaml` `2.0.50+140`.
- App version: `2.0.50`.
- Build number: `140` in `flutter_app/pubspec.yaml`; CI may use a higher GitHub run number.
- Version metadata is aligned to `2.0.50+140` in Flutter defaults, README files, STRUCTURE, and CHANGELOG.
- Browser automation now defaults to a desktop UA, keeps WebView zoom enabled with Android text zoom normalization, and stages reusable workflows into a pending-save script draft before the user confirms saving.
- Last artifact: GitHub Actions run `29283260131` produced `CiYuanXia-v2.0.50-140-arm64-v8a.apk` from `shwiki/codex-termux-runtime-fix` head `7d977373176406104c40b391ee2cd4b7fd74c2d5`; local download path is `artifacts/github-run-29283260131/CiYuanXia-v2.0.50-140-arm64-v8a.apk`; APK SHA256 `db236bd4a96d30f59340df9d060ae9b4ae9fbdd80f075ac82d5bf43840348ada`; artifact ZIP digest `sha256:fc8110fa4a2c0f62c21f7a658b1da764ab1f1bb4a7b14fe905be74085a21a0ff`; `aapt dump badging` reports Android manifest `versionCode=2140` and `versionName=2.0.50` for the arm64 split APK.

## Active Task
- Submitting a GitHub Actions arm64-v8a APK build for the browser desktop UA/zoom and pending-save script draft changes using source metadata `2.0.50+140`.

## Recently Changed
- Bumped Flutter source/build metadata and release docs from `2.0.50+139` to `2.0.50+140` before submitting the next cloud build.
- Added desktop UA and Android text zoom defaults to `TerminalBrowserPanel`.
- Added a browser script pending-save draft flow with `browser_script_stage` / `browser_script_clear_pending`, auto-staged drafts from recent browser actions, and a save-pending UI in the script assistant bottom sheet.
- Updated generated browser MCP tools, shell fallback, and `browser-operator` skill guidance so Codex stages reusable browser workflows into the script assistant pending-save area with auto-filled filename and purpose.
- Updated the browser instructions page copy to mention desktop pages, zoom support, and the script assistant pending-save area.
- Added test assertions for the new browser script staging tools and updated generator version text.
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
- Committed and pushed the Codex browser sidecar behavior fix as GitHub commit `42762fd6a4d240c6441234ea89a4ad9cc57db6ce`.
- Watched GitHub Actions workflow `Build OpenClaw Apps` run `29272795310` to successful completion and downloaded the `ciyuanxia-apks` artifact.
- Added top-level `artifacts/` to `.gitignore` so downloaded APK artifacts stay local and are not accidentally committed.
- Added `BrowserScriptLibraryService` to persist saved browser automation scripts in shared preferences with filename, description, ordered steps, variables, source URL/title, timestamps, run count, quick command, and Codex prompt metadata.
- Extended `BrowserAutomationService` with `script_list`, `script_save`, `script_run`, `script_rename`, and `script_delete` bridge actions, plus replay of saved deterministic browser actions.
- Added a script assistant button to `TerminalBrowserPanel`; it opens a bottom-sheet script directory with save-from-recent, run, rename, copy quick command, copy Codex prompt, delete, loading, empty, and error states.
- Updated `CliApiConfigService` to generate browser MCP script tools for saved scripts and a `/root/.openclaw/bin/browser-script` shortcut launcher.
- Updated `browser-operator` generated skill guidance and `CHANGELOG.md` for the script assistant.
- Corrected `browser_get_state` so Codex can inspect browser attachment/state without forcing the browser panel to attach first, and normalized saved-script run responses to include state under a `state` field.
- Fixed the failed cloud-build compile error by replacing invalid `Colors.white45` with `Colors.white.withAlpha(115)`, then bumped Flutter source metadata from `2.0.50+136` to `2.0.50+137` for the retry.
- Pushed the build-color fix through the GitHub API; remote commit `1b0778b16da29083eea6d3101dfc50b69f93ede8` triggered successful GitHub Actions run `29278136954`.
- Added generated MCP tool `browser_control` as a stable single-entry browser automation fallback accepting `action`/`tool` plus `payload`/`arguments` or direct top-level payload fields.
- Extended generated `/root/.openclaw/bin/browser-script` with `state`, `self-test`, `call/control`, `open`, `interactables`, `snapshot`, `click`, `type`, `wait-selector`, `wait-text`, `scroll`, and `press-key` command fallbacks.
- Normalized browser HTTP bridge path actions so direct `/browser_type`, `/browser_click`, `/browser_capture_snapshot`, `/browser_list_interactables`, and related `browser_*` names map to the same internal actions.
- Updated generated `browser-operator` skill guidance, `cli_api_config_service_test.dart`, `CHANGELOG.md`, and architecture memory for the stable browser-control entrypoint.
- Removed browser sidecar header back/forward buttons; underlying `back`/`forward` browser automation actions remain available.
- Changed compact Codex browser sidecar animation from `AnimatedPositioned` layout animation to `AnimatedSlide` with a `RepaintBoundary`.
- Added `NativeTerminalView.renderingPaused` and `transcriptRows` controls; Codex terminal display uses 1200 transcript rows while other terminals keep the previous 3000-row display buffer.
- Added native `TerminalView` repaint throttling at roughly one update per 32 ms and paused terminal repainting while the compact browser sidecar is open.
- Bumped Flutter source/build metadata from `2.0.50+137` to `2.0.50+138` before submitting the next cloud build.
- GitHub Actions run `29282846337` failed before artifact upload because `browser-script type` generated a JavaScript regex containing an unescaped Dart `$`; fixed the string escaping and bumped source metadata to `2.0.50+139` for the retry.
- GitHub Actions run `29283260131` succeeded from remote commit `7d9773731764`; downloaded `CiYuanXia-v2.0.50-140-arm64-v8a.apk` and verified ZIP integrity, arm64 PRoot libraries, APK SHA256, and manifest version fields.

## Checks
- Cloud-build prep checks for source `2.0.50+140`: `git diff --check` passed; `npm test` passed with 11 checks; `npm run lint -- --no-warn-ignored` passed; `command -v dart`, `command -v flutter`, and `command -v kotlinc` returned no local paths.
- `git diff --check`: passed after the desktop UA/zoom and browser script draft changes.
- `npm test`: passed again after the script draft changes, 11 checks passed and 0 failed.
- `npm run lint -- --no-warn-ignored`: passed again after the script draft changes.
- `command -v dart`, `command -v flutter`, and `command -v kotlinc`: no local SDK/compiler paths available in this Termux environment.
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
- New cloud build checks: `npm test` passed; `npm run lint -- --no-warn-ignored` passed; `gh run 29272795310` completed successfully; `gh run view` showed `APP_VERSION_CODE=136` and artifact upload success; `gh run download` pulled `CiYuanXia-v2.0.50-136-arm64-v8a.apk`; `sha256sum` matched `c3b7985b80b0db156a51f617533298d5916161b26232d3539bf82ea9730361d7`; `unzip -l` confirmed arm64 PRoot libraries; `aapt dump xmltree` reported manifest `versionCode=2136`.
- Browser script assistant checks after the bridge-only `browser_get_state` fix: `git diff --check` passed; `npm test` passed with 11 checks; `npm run lint -- --no-warn-ignored` passed; app memory validation passed with no errors and no warnings; `command -v dart` and `command -v flutter` returned no local SDK paths, so Flutter analyze/test were not run locally.
- GitHub Actions run `29277705784` on remote commit `989e200f1388` failed in `Build arm64-v8a APK` before artifact upload; CI set `APP_VERSION_CODE=137`; failure was `lib/widgets/terminal_browser_panel.dart:2723:29: Error: Member not found: 'white45'`.
- GitHub Actions run `29278136954`: completed successfully; CI `APP_VERSION_CODE=138`; artifact `ciyuanxia-apks` ID `8290313722`; artifact ZIP digest `sha256:d10afef19e209374a41c7fcdce9672784822561cdbca7faabf7914277412f731`; downloaded APK `CiYuanXia-v2.0.50-138-arm64-v8a.apk`; APK SHA256 `e8de3ae0f9b6553c3f64c280da713c397658c8df28e197500cc73cd44755f775`; `unzip -t` passed; `unzip -l` confirmed arm64 PRoot libraries; `aapt dump badging` reported `versionCode=2138`, `versionName=2.0.50`.
- GitHub Actions run `29282846337`: failed in `Build arm64-v8a APK` after Dart analyze passed; CI `APP_VERSION_CODE=139`; failure was `cli_api_config_service.dart:2438:62` unescaped `$` inside a generated JavaScript regex; no artifact was uploaded.
- GitHub Actions run `29283260131`: completed successfully; CI `APP_VERSION_CODE=140`; artifact `ciyuanxia-apks` ID `8292276612`; artifact ZIP digest `sha256:fc8110fa4a2c0f62c21f7a658b1da764ab1f1bb4a7b14fe905be74085a21a0ff`; downloaded APK `CiYuanXia-v2.0.50-140-arm64-v8a.apk`; APK SHA256 `db236bd4a96d30f59340df9d060ae9b4ae9fbdd80f075ac82d5bf43840348ada`; `unzip -t` passed; `unzip -l` confirmed arm64 PRoot libraries; `aapt dump badging` reported `versionCode=2140`, `versionName=2.0.50`.
- Browser control stability hardening checks: `git diff --check` passed; `npm test` passed with 11 checks; `npm run lint -- --no-warn-ignored` passed; `command -v dart` and `command -v flutter` returned no local SDK paths, so Flutter analyze/test were not run locally.
- Terminal sidecar/performance polish checks: `git diff --check` passed; `npm test` passed with 11 checks; `npm run lint -- --no-warn-ignored` passed; `command -v dart`, `command -v flutter`, and `command -v kotlinc` returned no local SDK/compiler paths, and no executable `flutter_app/android/gradlew` is available in this environment.

## Memory Validation
- Initial validation before filling memory passed with warnings for placeholder fields.
- Final validation after metadata fixes passed with no errors and no warnings.
- Final validation after recording GitHub Actions run `29272795310` passed with no errors and no warnings.
- Final validation after browser script assistant memory updates passed with no errors and no warnings.
- Final validation after recording GitHub Actions run `29283260131` passed with no errors and no warnings.

## Risks And Blockers
- Local environment cannot run Flutter checks yet.
- Browser script assistant changes need Flutter analyzer coverage and Android device smoke; local environment cannot visually inspect the bottom-sheet UI.
- Desktop UA/zoom defaults and the pending-save draft flow still need Android device smoke on a real browser panel.
- The new `browser_control` MCP entrypoint and `browser-script call/control` fallbacks need Android device smoke against a real WebView-attached browser session.
- The terminal repaint throttling and compact sidecar animation need Android device smoke with a long-running Codex conversation producing output; visual performance cannot be verified locally.
- Codex terminal display scrollback is now shorter for UI performance, but CLI process context/history and CLI-managed auto-compression are not modified by this change.
- The compact browser sidecar keep-alive and default instructions page fixes still need an Android device smoke test.
- The new APK was signed with the configured release secrets, but install/update behavior still needs device verification.
- Flutter analyzer issues, if any, did not block the successful APK build because the workflow only treats them as non-fatal; keep an eye on future analyzer output.
- App declares broad Android permissions including all-files access, overlay, install packages, camera, location, sensors, Bluetooth, notifications, foreground services, and cleartext traffic; treat permission changes as release-critical.
- `flutter_app/assets/bootstrap/openclaw-rootfs-noble-arm64.tar.gz` is a 134-byte Git LFS pointer to a 147 MB asset; cloud/local builds must restore or fetch the real asset when bundling RootFS.
- Project policy in `AGENTS.md`: build/release only Android `arm64-v8a` APK unless explicitly requested.

## Next Actions
- Watch the submitted GitHub Actions arm64-v8a build, download the `ciyuanxia-apks` artifact if it succeeds, verify checksum/native libraries/APK manifest, then record provenance.
- In a Flutter SDK or GitHub Actions environment, run `cd flutter_app && flutter analyze && flutter test` for the browser script assistant changes.
- Device-smoke the new browser pending-save flow on Android: stage a script draft, save it, rename it, copy `browser-script run <id>`, run it from the Codex terminal, delete it, and confirm the browser stays attached.
- Device-smoke the Codex browser script assistant on Android: perform a short browser flow, save recent actions, rename the script, copy `browser-script run <id>`, run it from the Codex terminal, delete the script, and verify the WebView remains attached.
- Device-smoke the browser automation tools on Android: verify `browser_get_state`, `browser_control` for `capture_snapshot`, `list_interactables`, `type`, and `click`, plus shell fallbacks `browser-script state`, `browser-script interactables`, `browser-script snapshot`, `browser-script type`, and `browser-script click`; confirm visible WebView content changes after type/click.
- Device-smoke terminal performance on Android: run a long Codex CLI conversation, open/close the right browser sidecar while output is active, verify terminal input/output still works, and verify closing the sidecar refreshes the latest terminal screen.
- Device-smoke the freshly built arm64 APK on Android: launch, setup/runtime bootstrap, gateway start/stop, terminal, Codex browser MCP tools, verify first browser open shows the `Codex 浏览器自动化控制` instructions page instead of Gateway, and verify closing/reopening the compact right browser sidecar keeps `浏览器已连接`.
- The current cloud build submission uses source metadata `2.0.50+140`; the successful GitHub Actions artifact is expected to use CI `APP_VERSION_CODE=141` or higher.
