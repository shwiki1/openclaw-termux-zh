# Build And Verification

## Local Checks Only
- Formatting: not run in this session; Flutter/Dart SDK unavailable locally.
- Lint/static analysis: `npm run lint -- --no-warn-ignored` passed on 2026-07-13 after Codex browser automation changes.
- Typecheck/analyze: local `dart`/`flutter` commands are unavailable; run `cd flutter_app && flutter analyze` in a Flutter SDK environment or GitHub Actions.
- Unit tests: `npm test` passed on 2026-07-13 with 11 passed, 0 failed after Codex browser automation changes; Flutter tests exist in `flutter_app/test/` but were not run locally.

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
- Current build number: `134` in `flutter_app/pubspec.yaml`.
- Known drift: none for current `2.0.50+134` metadata after 2026-07-13 cloud-build prep.
- Last cloud build version: pending for `2.0.50+134`.
- Last cloud build artifact: not produced in this session.
- Version bump policy: Increment build number for every new cloud build; bump user-facing version only for release changes.
- Workflow version policy: CI derives version name from `pubspec.yaml`, then sets versionCode to `GITHUB_RUN_NUMBER` if greater than pubspec build, otherwise `pubspec build + 1`.

## Dependencies And Release Safety
- Package manager and lockfile: npm with `package-lock.json`; Flutter uses `pubspec.yaml` and intentionally ignores `pubspec.lock`.
- Dependency audit command: no project-specific audit script; use `npm audit` only when dependency/security work is requested and record results.
- Flutter dependencies: Provider, WebView, Dio/http, shared_preferences/path_provider, permission_handler, url_launcher, web_socket_channel, cryptography, google_fonts, uuid, camera, geolocator, flutter_blue_plus, usb_serial, flutter_markdown_plus.
- Android dependencies: Termux terminal-view, RecyclerView, Media3, ffmpeg-kit-full, commons-compress, xz, zstd-jni.
- Signing: workflow accepts `KEYSTORE_BASE64`, `KEYSTORE_PASSWORD`, `KEY_ALIAS`, `KEY_PASSWORD`; if absent, release artifacts use debug signing fallback.
- Release artifact naming: `CiYuanXia-v<version>-<versionCode>-arm64-v8a.apk`.
- Last successful artifact checksum: not available locally.
- Secret hygiene: `.gitignore` excludes `.env`, `flutter_app/android/key.properties`, `*.jks`, `*.keystore`, local configs with API keys, and build output.
- Runtime assets: `openclaw-rootfs-noble-arm64.tar.gz` is currently a Git LFS pointer; `basic-resource` Release stores large runtime assets and SHA256 values.

## Test Matrix
- Static checks: npm ESLint passed; `git diff --check` passed; Flutter analyze pending SDK/CI.
- Unit tests: Node self-test passed; Flutter tests under `flutter_app/test/` pending SDK/CI.
- Integration/E2E tests: no Flutter `integration_test`, Maestro, Appium, or emulator test workflow found.
- Device/emulator/browser smoke target: none run in this session. Use Android 10+ arm64 device/emulator for install/setup/gateway smoke.

## Privacy And Observability
- User data collected/stored/transmitted: OpenClaw configs/API keys, provider/message platform settings, Gateway logs, workspace files/backups, downloaded runtime/model/update files, browser page content when the user invokes Codex browser tools, and local device capability data when enabled.
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
