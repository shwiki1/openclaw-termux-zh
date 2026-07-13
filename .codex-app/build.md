# Build And Verification

## Local Checks Only
- Formatting: not run in this session; Flutter/Dart SDK unavailable locally.
- Lint/static analysis: `npm run lint -- --no-warn-ignored` passed on 2026-07-13 after Codex browser script assistant changes and the bridge-only `browser_get_state` fix.
- Typecheck/analyze: local `dart`/`flutter` commands are unavailable; run `cd flutter_app && flutter analyze` in a Flutter SDK environment or GitHub Actions.
- Unit tests: `npm test` passed on 2026-07-13 with 11 passed, 0 failed after Codex browser script assistant changes and the bridge-only `browser_get_state` fix; Flutter tests exist in `flutter_app/test/` but were not run locally.

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
- Current build number: `137` in `flutter_app/pubspec.yaml`.
- Known drift: none for current `2.0.50+137` metadata after 2026-07-13 browser cloud-build retry prep.
- Last cloud build version: source metadata `2.0.50+135`; GitHub Actions run `29272795310` generated CI version `2.0.50+136` for the arm64 split APK, and `aapt dump xmltree` reported manifest `versionCode=2136`.
- Last cloud build artifact: `ciyuanxia-apks` artifact ID `8288274347`, containing `CiYuanXia-v2.0.50-136-arm64-v8a.apk`, downloaded to `artifacts/github-run-29272795310/ciyuanxia-apks/`.
- Version bump policy: Increment build number for every new cloud build; bump user-facing version only for release changes.
- Workflow version policy: CI derives version name from `pubspec.yaml`, then sets versionCode to `GITHUB_RUN_NUMBER` if greater than pubspec build, otherwise `pubspec build + 1`.
- Failed cloud build: GitHub Actions run `29277705784` used remote commit `989e200f1388`, CI `APP_VERSION_CODE=137`, and failed before artifact upload because `Colors.white45` is not a Flutter color constant.
- Next expected cloud build version: `2.0.50+138` or higher.

## Dependencies And Release Safety
- Package manager and lockfile: npm with `package-lock.json`; Flutter uses `pubspec.yaml` and intentionally ignores `pubspec.lock`.
- Dependency audit command: no project-specific audit script; use `npm audit` only when dependency/security work is requested and record results.
- Flutter dependencies: Provider, WebView, Dio/http, shared_preferences/path_provider, permission_handler, url_launcher, web_socket_channel, cryptography, google_fonts, uuid, camera, geolocator, flutter_blue_plus, usb_serial, flutter_markdown_plus.
- Android dependencies: Termux terminal-view, RecyclerView, Media3, ffmpeg-kit-full, commons-compress, xz, zstd-jni.
- Signing: workflow accepts `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`; if absent, release artifacts use debug signing fallback.
- Release artifact naming: `CiYuanXia-v<version>-<versionCode>-arm64-v8a.apk`.
- Last successful artifact checksum: APK SHA256 `c3b7985b80b0db156a51f617533298d5916161b26232d3539bf82ea9730361d7`; artifact ZIP digest `sha256:351c9dce99a033293bc9160c6fdf22a5dabbc6e7bd7fe476e0f13871878f549c`.
- Secret hygiene: `.gitignore` excludes `.env`, `flutter_app/android/key.properties`, `*.jks`, `*.keystore`, local configs with API keys, and build output.
- Runtime assets: `openclaw-rootfs-noble-arm64.tar.gz` is currently a Git LFS pointer; `basic-resource` Release stores large runtime assets and SHA256 values.

## Test Matrix
- Static checks: npm ESLint passed again after the browser script assistant changes; `git diff --check` passed; GitHub Actions `flutter analyze --no-fatal-infos` completed successfully in run `29272795310`.
- Unit tests: Node self-test passed again after the test fix; Flutter tests were not run locally or in the current workflow, which only runs analyze and the APK build.
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
