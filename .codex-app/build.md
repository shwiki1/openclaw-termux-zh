# Build And Verification

## Local Checks Only
- Formatting: not run in this session; Flutter/Dart SDK unavailable locally.
- Source `2.0.50+140` cloud-build prep: `git diff --check` passed; `npm test` passed with 11 checks; `npm run lint -- --no-warn-ignored` passed. Local `dart`, `flutter`, and `kotlinc` commands remain unavailable.
- Browser desktop UA/zoom and script pending-draft changes: `git diff --check` passed; `npm test` passed with 11 checks; `npm run lint -- --no-warn-ignored` passed on 2026-07-13. Local `dart`, `flutter`, and `kotlinc` commands remain unavailable.
- Lint/static analysis: `npm run lint -- --no-warn-ignored` passed on 2026-07-13 after Codex browser script assistant changes and the bridge-only `browser_get_state` fix.
- Typecheck/analyze: local `dart`/`flutter` commands are unavailable; run `cd flutter_app && flutter analyze` in a Flutter SDK environment or GitHub Actions.
- Unit tests: `npm test` passed on 2026-07-13 with 11 passed, 0 failed after Codex browser script assistant changes and the bridge-only `browser_get_state` fix; Flutter tests exist in `flutter_app/test/` but were not run locally.
- Browser control hardening: `git diff --check` passed; `npm test` passed with 11 checks; `npm run lint -- --no-warn-ignored` passed after adding `browser_control`, `browser-script` fallback commands, and bridge action normalization.
- Terminal sidecar/performance polish: `git diff --check` passed; `npm test` passed with 11 checks; `npm run lint -- --no-warn-ignored` passed after removing browser sidecar header back/forward buttons, adding terminal display repaint throttling, and reducing Codex terminal display transcript rows. Local `dart`, `flutter`, and `kotlinc` commands were unavailable, and no executable `flutter_app/android/gradlew` was present.
- Browser/terminal cloud-build retry: `git diff --check` passed; `npm test` passed with 11 checks; `npm run lint -- --no-warn-ignored` passed after escaping the generated `browser-script type` JavaScript regex and bumping source metadata to `2.0.50+139`.

## GitHub Cloud Build
- Repository remotes: `origin` Gitee and `shwiki` GitHub. Confirm target remote before push/build operations.
- Workflow files: `.github/workflows/flutter-build.yml`.
- Artifact path/names: workflow copies `flutter_app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk` to `artifacts/CiYuanXia-v<version>-<versionCode>-arm64-v8a.apk` and uploads artifact `ciyuanxia-apks`.
- Runner requirements: Ubuntu latest, Java 17, Flutter stable, Android SDK platform/build-tools 36, NDK 27.0.12077973 and 28.2.13676358, Gradle 8.11.1, host tools including curl/gzip/qemu/xz/zstd.
- Native platform folder policy: `flutter_app/android/` is committed; local `local.properties`, Gradle caches/wrapper binaries, Flutter generated registrant, and build output are ignored.
- Cloud build policy: use GitHub Actions for native packaging/release artifacts. Before dispatch/push, verify GitHub auth token and bump/record version/build.

## Version Management
- Canonical version file: `flutter_app/pubspec.yaml` for Flutter app version/build, plus root `package.json` for npm package version. Keep them aligned for releases.
- Current user-facing version: `2.0.50`.
- Current build number: `140` in `flutter_app/pubspec.yaml`.
- Known drift: none for current `2.0.50+140` metadata after 2026-07-13 browser script draft cloud-build prep.
- Last cloud build version: source metadata `2.0.50+139`; GitHub Actions run `29283260131` generated CI version `2.0.50+140` for the arm64 split APK, and `aapt dump badging` reported manifest `versionCode=2140`, `versionName=2.0.50`.
- Last cloud build artifact: `ciyuanxia-apks` artifact ID `8292276612`, containing `CiYuanXia-v2.0.50-140-arm64-v8a.apk`, downloaded to `artifacts/github-run-29283260131/`.
- Version bump policy: Increment build number for every new cloud build; bump user-facing version only for release changes.
- Workflow version policy: CI derives version name from `pubspec.yaml`, then sets versionCode to `GITHUB_RUN_NUMBER` if greater than pubspec build, otherwise `pubspec build + 1`.
- Failed cloud build: GitHub Actions run `29277705784` used remote commit `989e200f1388`, CI `APP_VERSION_CODE=137`, and failed before artifact upload because `Colors.white45` is not a Flutter color constant. Fixed by remote commit `1b0778b16da29083eea6d3101dfc50b69f93ede8`.
- Failed cloud build: GitHub Actions run `29282846337` used remote commit `3559fd14e369`, CI `APP_VERSION_CODE=139`, and failed before artifact upload because a generated shell script regex in `CliApiConfigService` used an unescaped Dart `$` in `browser-script type`.
- Current cloud build submission source metadata: `2.0.50+140`; expected CI artifact code `141` or higher.

## Dependencies And Release Safety
- Package manager and lockfile: npm with `package-lock.json`; Flutter uses `pubspec.yaml` and intentionally ignores `pubspec.lock`.
- Dependency audit command: no project-specific audit script; use `npm audit` only when dependency/security work is requested and record results.
- Flutter dependencies: Provider, WebView, Dio/http, shared_preferences/path_provider, permission_handler, url_launcher, web_socket_channel, cryptography, google_fonts, uuid, camera, geolocator, flutter_blue_plus, usb_serial, flutter_markdown_plus.
- Android dependencies: Termux terminal-view, RecyclerView, Media3, ffmpeg-kit-full, commons-compress, xz, zstd-jni.
- Signing: workflow accepts `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`; if absent, release artifacts use debug signing fallback.
- Release artifact naming: `CiYuanXia-v<version>-<versionCode>-arm64-v8a.apk`.
- Last successful artifact checksum: APK SHA256 `db236bd4a96d30f59340df9d060ae9b4ae9fbdd80f075ac82d5bf43840348ada`; artifact ZIP digest `sha256:fc8110fa4a2c0f62c21f7a658b1da764ab1f1bb4a7b14fe905be74085a21a0ff`.
- Secret hygiene: `.gitignore` excludes `.env`, `flutter_app/android/key.properties`, `*.jks`, `*.keystore`, local configs with API keys, and build output.
- Runtime assets: `openclaw-rootfs-noble-arm64.tar.gz` is currently a Git LFS pointer; `basic-resource` Release stores large runtime assets and SHA256 values.

## Test Matrix
- Static checks: npm ESLint and `git diff --check` passed again after bumping source metadata to `2.0.50+140`; GitHub Actions `flutter analyze --no-fatal-infos` completed successfully in run `29283260131` for the previous build.
- Unit tests: Node self-test passed again after bumping source metadata to `2.0.50+140`; Flutter tests were not run locally or in the current workflow, which only runs analyze and the APK build.
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
