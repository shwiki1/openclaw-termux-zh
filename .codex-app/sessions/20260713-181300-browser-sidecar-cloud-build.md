# 2026-07-13 18:13 UTC - Browser Sidecar Cloud Build

## Goal

Ship the Codex browser sidecar keep-alive and default instructions page fixes, bump the Flutter build metadata, and verify the resulting arm64 APK from GitHub Actions.

## Repo Facts Read

- Read `.codex-app/state.md`, `manifest.md`, `architecture.md`, `build.md`, `backlog.md`, and the latest prior session logs.
- Read `github-api-cloud-build` and `app-development-governor` instructions plus continuity, UI quality, testing matrix, versioning, and GitHub cloud build references.
- Inspected `flutter_app/lib/screens/terminal_screen.dart`, `flutter_app/lib/widgets/terminal_browser_panel.dart`, `flutter_app/test/cli_api_config_service_test.dart`, `flutter_app/pubspec.yaml`, `flutter_app/lib/constants.dart`, `README.md`, `docs/README_en.md`, `STRUCTURE.md`, `CHANGELOG.md`, `.github/workflows/flutter-build.yml`, and `flutter_app/android/app/build.gradle`.

## Changes Made

- Updated Flutter source/build metadata from `2.0.50+134` to `2.0.50+135`.
- Kept the compact Codex terminal browser sidecar mounted while hidden and replaced the default browser landing page with a built-in Codex browser automation instructions page.
- Escaped the generated shell test strings so Dart no longer treats `$codex_config` as interpolation.
- Synchronized README, English README, STRUCTURE, CHANGELOG, and `.codex-app/` memory with the new source build metadata and artifact history.
- Committed and pushed the work to `codex-termux-runtime-fix`.
- Added top-level `artifacts/` to `.gitignore` so downloaded APK artifacts stay local.

## Checks Run

- `git diff --check`: passed.
- `npm test`: passed, 11 checks passed and 0 failed.
- `npm run lint -- --no-warn-ignored`: passed.
- `gh auth status`: authenticated to `github.com` as `shwiki1`.
- `gh run watch 29272795310 --repo shwiki1/openclaw-termux-zh --exit-status`: passed.
- `gh run view 29272795310 --repo shwiki1/openclaw-termux-zh --json ...`: confirmed the build run succeeded.
- `gh run download 29272795310 --repo shwiki1/openclaw-termux-zh --name ciyuanxia-apks --dir artifacts/github-run-29272795310/ciyuanxia-apks`: passed.
- `sha256sum` on the APK: `c3b7985b80b0db156a51f617533298d5916161b26232d3539bf82ea9730361d7`.
- `unzip -l` on the APK: confirmed `lib/arm64-v8a/libproot.so`, `libloader.so`, `libprootloader.so`, `libtalloc.so`, and `libandroid-shmem.so`.
- `aapt dump xmltree` on the APK: manifest `versionCode=2136`, `versionName=2.0.50`.

## Cloud Build

- Workflow: `Build OpenClaw Apps`
- Run: `29272795310`
- Commit SHA: `42762fd6a4d240c6441234ea89a4ad9cc57db6ce`
- Result: success

## Version And Artifacts

- Source metadata: `2.0.50+135`
- CI artifact version: `2.0.50+136`
- Artifact: `ciyuanxia-apks`
- Artifact ID: `8288274347`
- Artifact digest: `sha256:351c9dce99a033293bc9160c6fdf22a5dabbc6e7bd7fe476e0f13871878f549c`
- APK path: `artifacts/github-run-29272795310/ciyuanxia-apks/CiYuanXia-v2.0.50-136-arm64-v8a.apk`

## Known Risks

- Device smoke on Android arm64 still needs to verify browser open/close behavior and the default instructions page.
- Future builds must bump `flutter_app/pubspec.yaml` to at least `2.0.50+136` before another installable artifact.

## Next Actions

- Device-smoke the freshly built arm64 APK on Android.
- For the next build, bump `flutter_app/pubspec.yaml` before dispatching another cloud build.
