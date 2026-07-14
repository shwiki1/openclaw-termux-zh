# Build And Verification

## Local Checks Only
- Formatting: not run in this session; Flutter/Dart SDK unavailable locally.
- 2026-07-14 terminal native IME input-strip follow-up: `npm test` passed with 23 checks; `npm run lint -- --no-warn-ignored` passed; `git diff --check` passed; `gh auth status` confirmed the authenticated `shwiki1` GitHub session; `gh api repos/shwiki1/openclaw-termux-zh/branches/main --jq .commit.sha` confirmed remote `main` is still `ff961e903cd9c04ac1a8523f8751c33c4f12f638`; local `flutter`, `dart`, and `kotlinc` remain unavailable, so Flutter analyze/test and native compile checks were not run locally.
- 2026-07-14 IME/browser/version cloud-build completion: `npm test` passed with 22 checks; `npm run lint -- --no-warn-ignored` passed; `git diff --check` passed; `gh auth status` confirmed the authenticated `shwiki1` GitHub session. Local `flutter`, `dart`, and `kotlinc` remain unavailable, so Flutter analyze/test and native compile checks were not run locally.
- 2026-07-14 terminal IME adjustPan fix: `npm test` passed with 22 checks; `npm run lint -- --no-warn-ignored` passed; `git diff --check` passed. Local `flutter`, `dart`, and `kotlinc` remain unavailable, so Flutter analyze/test and native compile checks were not run locally.
- 2026-07-14 version-display auto-progression fix: `git diff --check` passed; `npm test` passed with 18 checks; `npm run lint -- --no-warn-ignored` passed; `python3 -B -m py_compile scripts/build_release.py scripts/versioning.py` passed; `bash -n scripts/build-apk.sh` passed. Local `flutter`, `dart`, and `kotlinc` remain unavailable, so Flutter analyze/test were not run locally.
- 2026-07-14 Node engine-floor cloud-build retry prep: source metadata bumped to `2.0.50+142`; `git diff --check` passed; `npm test` passed with 14 checks; `npm run lint -- --no-warn-ignored` passed; `bash -n scripts/build-apk.sh`, `bash -n scripts/build-prebuilt-rootfs.sh`, `bash -n scripts/prebuilt-rootfs-metadata.sh`, `bash -n scripts/fetch-prebuilt-rootfs-asset.sh`, and `python3 -B -m py_compile scripts/build_release.py` passed. Local `dart`, `flutter`, and `kotlinc` remain unavailable.
- 2026-07-14 Codex browser tabs/UA cloud-build prep: source metadata bumped to `2.0.50+141`; `git diff --check` passed; `npm test` passed with 14 checks; `npm run lint -- --no-warn-ignored` passed; `bash -n scripts/build-apk.sh`, `bash -n scripts/build-prebuilt-rootfs.sh`, `bash -n scripts/prebuilt-rootfs-metadata.sh`, `bash -n scripts/fetch-prebuilt-rootfs-asset.sh`, and `python3 -B -m py_compile scripts/build_release.py` passed. Local `dart`, `flutter`, and `kotlinc` remain unavailable; the GitHub Actions run is expected to use `APP_VERSION_CODE=142` because the latest remote successful run already consumed `141`.
- 2026-07-14 Codex browser multi-tab/UA fixes: `git diff --check` passed; `npm test` passed with 14 checks; `npm run lint -- --no-warn-ignored` passed; focused `rg` checks confirmed generated tab/UA MCP and `browser-script` entries and found no stale `重命名标签`/`tab_rename` changelog or source references. Local `dart`, `flutter`, and `kotlinc` commands remain unavailable, so Dart format, Flutter analyze, Flutter tests, and Kotlin compiler checks were not run.
- Source `2.0.50+140` cloud-build prep: `git diff --check` passed; `npm test` passed with 11 checks; `npm run lint -- --no-warn-ignored` passed. Local `dart`, `flutter`, and `kotlinc` commands remain unavailable.
- Browser desktop UA/zoom and script pending-draft changes: `git diff --check` passed; `npm test` passed with 11 checks; `npm run lint -- --no-warn-ignored` passed on 2026-07-13. Local `dart`, `flutter`, and `kotlinc` commands remain unavailable.
- Lint/static analysis: `npm run lint -- --no-warn-ignored` passed on 2026-07-13 after Codex browser script assistant changes and the bridge-only `browser_get_state` fix.
- Typecheck/analyze: local `dart`/`flutter` commands are unavailable; run `cd flutter_app && flutter analyze` in a Flutter SDK environment or GitHub Actions.
- Unit tests: `npm test` passed on 2026-07-13 with 11 passed, 0 failed after Codex browser script assistant changes and the bridge-only `browser_get_state` fix; Flutter tests exist in `flutter_app/test/` but were not run locally.
- Browser control hardening: `git diff --check` passed; `npm test` passed with 11 checks; `npm run lint -- --no-warn-ignored` passed after adding `browser_control`, `browser-script` fallback commands, and bridge action normalization.
- Terminal sidecar/performance polish: `git diff --check` passed; `npm test` passed with 11 checks; `npm run lint -- --no-warn-ignored` passed after removing browser sidecar header back/forward buttons, adding terminal display repaint throttling, and reducing Codex terminal display transcript rows. Local `dart`, `flutter`, and `kotlinc` commands were unavailable, and no executable `flutter_app/android/gradlew` was present.
- Browser/terminal cloud-build retry: `git diff --check` passed; `npm test` passed with 11 checks; `npm run lint -- --no-warn-ignored` passed after escaping the generated `browser-script type` JavaScript regex and bumping source metadata to `2.0.50+139`.
- Version-display stabilization: `git diff --check` passed; `npm test` passed with 13 checks; `npm run lint -- --no-warn-ignored` passed; `python3 -m py_compile scripts/build_release.py` passed; `bash -n scripts/build-apk.sh` passed. Local `flutter`/`dart` remain unavailable.
- 2026-07-14 project-management analysis: `git diff --check` passed; `npm test` passed with 13 checks; `npm run lint -- --no-warn-ignored` passed; `python3 -m py_compile scripts/build_release.py` passed; `bash -n scripts/build-apk.sh` passed; `bash -n scripts/build-prebuilt-rootfs.sh` passed. Local `flutter`, `dart`, and `kotlinc` remain unavailable; `gradle` exists in Termux but Android/Flutter build verification still belongs in GitHub Actions or a full SDK environment.
- 2026-07-14 Node/runtime documentation fix: `git diff --check` passed; `npm test` passed with 14 checks; `npm run lint -- --no-warn-ignored` passed; `bash -n scripts/build-apk.sh`, `bash -n scripts/build-prebuilt-rootfs.sh`, `bash -n scripts/prebuilt-rootfs-metadata.sh`, and `python3 -B -m py_compile scripts/build_release.py` passed. A focused `rg` check found no remaining stale Node version or obsolete terminal stack references in current source/docs targets. Local `flutter`, `dart`, and `kotlinc` remain unavailable.

## GitHub Cloud Build
- Repository remotes: `origin` Gitee and `shwiki` GitHub. Confirm target remote before push/build operations.
- Branch hygiene: as of 2026-07-14, local `codex-termux-runtime-fix` tracks `shwiki/main` and is ahead by 16 commits. Before the next build or release promotion, explicitly choose the authoritative branch and remote instead of assuming the current local branch should be published as-is.
- Workflow files: `.github/workflows/flutter-build.yml`.
- Artifact path/names: workflow copies `flutter_app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` to `artifacts/CiYuanXia-v<version>-<versionCode>-arm64-v8a.apk` and uploads artifact `ciyuanxia-apks`.
- Runner requirements: Ubuntu latest, Java 17, Flutter stable, Android SDK platform/build-tools 36, NDK 27.0.12077973 and 28.2.13676358, Gradle 8.11.1, host tools including curl/gzip/qemu/xz/zstd.
- Native platform folder policy: `flutter_app/android/` is committed; local `local.properties`, Gradle caches/wrapper binaries, Flutter generated registrant, and build output are ignored.
- Cloud build policy: use GitHub Actions for native packaging/release artifacts. Before dispatch/push, verify GitHub auth token and bump/record version/build.

## Version Management
- Canonical version file: `flutter_app/pubspec.yaml` for Flutter app version/build, plus root `package.json` for npm package version. Keep them aligned for releases.
- Current user-facing version: `2.5`.
- Current build number: anchor `143` in `flutter_app/pubspec.yaml`.
- Current source semantic anchor: `2.5.0` in `flutter_app/pubspec.yaml` and `package.json`.
- Latest successful display-version cloud build: GitHub Actions run `29343651061` used remote commit `ff961e903cd9c04ac1a8523f8751c33c4f12f638`, published release `v2.5.0`, and produced `CiYuanXia-v2.5-144-arm64-v8a.apk`.
- User device feedback on that `144` release: terminal input still is not lifted above the IME, so a native terminal follow-up build is still required even though browser/header/version fixes shipped.
- Next expected cloud build from the current source anchor: target build `145`, semantic/app version `2.6.0`, installer/app display `2.6`.
- Last cloud build version before submitting the browser tabs/UA build: source metadata `2.0.50+140`; GitHub Actions run `29293286907` generated CI version `2.0.50+141` for the arm64 split APK.
- Last cloud build artifact before submitting the browser tabs/UA build: `ciyuanxia-apks` artifact ID `8295917288`, containing `CiYuanXia-v2.0.50-141-arm64-v8a.apk`, artifact ZIP digest `sha256:153c4b895a1bf1838985266fd6dfcd4fb32e021d7704e70e16ed53ccaf7dbfe8`.
- Version bump policy: Increment the numeric build number for every new cloud build. Keep the repo semantic anchor at `2.5.0+143`, then derive artifact versions automatically from the target build number in fixed one-tenth steps: `144 -> 2.5.0 / 2.5`, `145 -> 2.6.0 / 2.6`, `146 -> 2.7.0 / 2.7`, `147 -> 2.8.0 / 2.8`, `148 -> 2.9.0 / 2.9`, `149 -> 3.0.0 / 3.0`.
- Workflow version policy: CI derives logical build number from `pubspec.yaml`, then sets versionCode to `GITHUB_RUN_NUMBER` if greater than pubspec build, otherwise `pubspec build + 1`. The shared `scripts/versioning.py` helper then derives `APP_VERSION_NAME`, `APP_VERSION_DISPLAY`, and artifact naming so installer/app/release metadata stay synchronized.
- Android install-visible version policy: treat `versionName` as the user-visible string in the installer/settings screen. Do not append raw split-AAB/APK `versionCode` values to the display string, because Flutter split-per-ABI offsets can make them look like `2140`, `2141`, etc. Use the manifest `versionName` or `AppConstants.displayVersion`.
- Artifact naming policy: APK filenames use the short display version, for example `CiYuanXia-v2.5-144-arm64-v8a.apk`, while Git tags/releases use the derived semantic version from the build workflow outputs.
- Failed cloud build: GitHub Actions run `29277705784` used remote commit `989e200f1388`, CI `APP_VERSION_CODE=137`, and failed before artifact upload because `Colors.white45` is not a Flutter color constant. Fixed by remote commit `1b0778b16da29083eea6d3101dfc50b69f93ede8`.
- Failed cloud build: GitHub Actions run `29282846337` used remote commit `3559fd14e369`, CI `APP_VERSION_CODE=139`, and failed before artifact upload because a generated shell script regex in `CliApiConfigService` used an unescaped Dart `$` in `browser-script type`.
- GitHub Actions run `29321533131` for the Codex browser tabs/UA build failed before artifact upload in `Build bundled OpenClaw rootfs`. Root cause: `openclaw@latest` rejected Node.js `v24.14.1` and now requires Node.js `>=22.22.3 <23`, `>=24.15.0 <25`, or a newer supported major.
- Successful cloud build: GitHub Actions run `29323908852` used remote commit `97c7861608daca62c22a9ae1c1259d7abe7e02c3`, CI `APP_VERSION_CODE=143`, `APP_FULL_VERSION=2.0.50+143`, and produced `CiYuanXia-v2.0.50-143-arm64-v8a.apk`.
- Successful cloud build: GitHub Actions run `29343651061` used remote commit `ff961e903cd9c04ac1a8523f8751c33c4f12f638`, published release `v2.5.0`, and produced `CiYuanXia-v2.5-144-arm64-v8a.apk`.
- Latest GitHub Release asset: `CiYuanXia-v2.5-144-arm64-v8a.apk`.
- Latest APK SHA256: `2c283b7d810b11d9c7abb381d358aca492419a86726743730148b9cbd1947f31`.
- Latest locally downloaded artifact path: `artifacts/github-run-29323908852/CiYuanXia-v2.0.50-143-arm64-v8a.apk`.
- Latest artifact ZIP digest/SHA256: `sha256:108950af36fc43196b1d81da56c3a8fa7819d2392c37413f21bdbe708d1f6235`.
- Latest artifact ID: `8315303372`.
- Install-visible APK versionName policy: manifest `versionName` now resolves to the short display version, for example semantic `2.5.0` -> installer/app display `2.5`.

## Dependencies And Release Safety
- Package manager and lockfile: npm with `package-lock.json`; Flutter uses `pubspec.yaml` and intentionally ignores `pubspec.lock`.
- Dependency audit command: no project-specific audit script; use `npm audit` only when dependency/security work is requested and record results.
- Flutter dependencies: Provider, WebView, Dio/http, shared_preferences/path_provider, permission_handler, url_launcher, web_socket_channel, cryptography, google_fonts, uuid, camera, geolocator, flutter_blue_plus, usb_serial, flutter_markdown_plus.
- Android dependencies: Termux terminal-view, RecyclerView, Media3, ffmpeg-kit-full, commons-compress, xz, zstd-jni.
- Signing: workflow accepts `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`; if absent, release artifacts use debug signing fallback.
- Release artifact naming: `CiYuanXia-v<version>-<versionCode>-arm64-v8a.apk`.
- Last successful artifact checksum: APK SHA256 `2c283b7d810b11d9c7abb381d358aca492419a86726743730148b9cbd1947f31`; artifact ZIP digest `sha256:108950af36fc43196b1d81da56c3a8fa7819d2392c37413f21bdbe708d1f6235`.
- Secret hygiene: `.gitignore` excludes `.env`, `flutter_app/android/key.properties`, `*.jks`, `*.keystore`, local configs with API keys, and build output.
- Runtime assets: `openclaw-rootfs-noble-arm64.tar.gz` is currently a Git LFS pointer; `basic-resource` Release stores large runtime assets and SHA256 values.
- Runtime Node defaults are aligned to Node.js `24.15.0` for arm64/x86_64 and `22.22.3` for armv7. Future Node upgrades must update Flutter constants, RootFS scripts, setup l10n copy, primary docs, resource docs, legacy installer URLs, cached asset names, license/source notices, and the `lib/test.js` drift guard together.

## Test Matrix
- Static checks: npm ESLint and `git diff --check` passed after the version-display format fix; the GitHub Actions workflow runs `flutter analyze --no-fatal-infos` before the APK build.
- Unit tests: Node self-test passed again after the version-display auto-progression fix with 18 checks; Flutter tests were not run locally and are not currently part of the workflow, which runs analyze and the APK build.
- Current release-management gap: `.github/workflows/flutter-build.yml` can produce a green APK artifact without executing `flutter test`, even though focused Flutter unit tests exist under `flutter_app/test/`.
- Current browser automation test coverage includes generated MCP/browser-script string assertions for tab list/new/switch/close and UA switching in `flutter_app/test/cli_api_config_service_test.dart`, but those Flutter tests could not be executed locally without the Flutter SDK.
- Current Node self-test includes the runtime-version drift guard, browser header/menu guards, route-scoped terminal IME guards, and the native terminal input-strip guard; it now passes with 23 checks.
- Auto-inspection caveat: `inspect_app_project.py` currently detects only the root Node shell for this repo; future agents must verify the Flutter/Kotlin app manually from `flutter_app/pubspec.yaml`, `flutter_app/android/app/build.gradle`, and source entry points.
- Integration/E2E tests: no Flutter `integration_test`, Maestro, Appium, or emulator test workflow found.
- Device/emulator/browser smoke target: none run in this session. Use Android 10+ arm64 device/emulator for install/setup/gateway smoke.

## Privacy And Observability
- User data collected/stored/transmitted: OpenClaw configs/API keys, provider/message platform settings, Gateway logs, workspace files/backups, downloaded runtime/model/update files, browser page content and saved local browser automation scripts when the user invokes Codex browser tools, and local device capability data when enabled.
- Networking: downloads from GitHub/Ubuntu/Node/npm/model sources, app update manifest `http://api.lziyu.cn/openclaw/latest.json`, local gateway/model endpoints, WebSocket node connection.
- Android permissions: internet, foreground services, notifications, wake lock, ignore battery optimization, overlay, camera, fine/coarse location, vibration, body/high-rate sensors, external/all-files storage, install packages, Bluetooth, USB host.
- Analytics/crash reporting/logging: no analytics or crash-reporting SDK detected; gateway/setup/browser action logs exist and must not expose secrets.
- Store data-safety/privacy notes: broad permissions and all-files access need accurate user-facing/privacy policy explanations before public release.
- Source map/symbol upload policy: none detected; no mapping upload configured.

## Required Secrets
- GitHub token: `GH_TOKEN` or `GITHUB_TOKEN` in environment or authenticated `gh` session.
- Signing secrets: `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD` for GitHub Actions release signing.

## Notes
- Do not commit secret values.
- Use GitHub Actions for native packaging and release artifacts.
- Project instruction: build/release only Android `arm64-v8a` APK unless the user explicitly asks for another ABI/AAB.
