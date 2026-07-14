# 2026-07-14 15:17 UTC - IME Visibility Cloud Build

## Goal

Close out the terminal/browser IME visibility fix without regressing input behavior, repair the one-line CI compile failure, and submit a fresh cloud build.

## Repo Facts Read

- Re-read the GitHub cloud-build skill and the app governor skill references for versioning, GitHub Actions flow, and quality gates.
- Verified the remaining worktree change in `flutter_app/lib/services/online_model_catalog_service.dart` and confirmed it was the only pending delta after the larger IME/browser/version batch.
- Checked `.codex-app/state.md`, `.codex-app/build.md`, and the previous terminal IME session log before updating project memory.

## Changes Made

- Kept the IME/input visibility implementation from the prior batch: terminal route acquires Android `adjustPan`, `TerminalScreen` stays at `resizeToAvoidBottomInset: false`, and the browser header keeps a dedicated full-width address-bar row with high-contrast controls.
- Restored `OnlineModelCatalogService._userAgent` to `static const` so the CI build no longer fails on a non-constant Dart expression.
- Committed the hotfix locally as `4b5e915` (`fix: restore const model catalog user agent`).
- Pushed the current `HEAD` tree to GitHub `main` through the API helper, producing remote commit `ff961e903cd9c04ac1a8523f8751c33c4f12f638`.
- Watched GitHub Actions run `29343651061` to success; it built the arm64 APK and published GitHub Release `v2.5.0`.
- Updated `.codex-app/state.md` and `.codex-app/build.md` with the successful build and release metadata.

## Checks Run

- `npm test`: passed with 22 checks.
- `npm run lint -- --no-warn-ignored`: passed.
- `git diff --check`: passed.
- `gh auth status`: passed with authenticated account `shwiki1`.
- GitHub Actions `Build OpenClaw Apps` run `29343651061`: succeeded.
- Local `flutter`, `dart`, and `kotlinc` remain unavailable, so Flutter analyze/test and native compile checks were not run locally.

## Cloud Build

- Workflow: `Build OpenClaw Apps`
- Run: `29343651061`
- URL: `https://github.com/shwiki1/openclaw-termux-zh/actions/runs/29343651061`
- Remote commit: `ff961e903cd9c04ac1a8523f8751c33c4f12f638`
- Jobs:
  - `Build arm64-v8a APK`: success in `7m25s`
  - `Create GitHub Release`: success in `43s`

## Version And Artifacts

- Source anchor stayed at `2.5.0+143`.
- Successful cloud artifact used installer/app version `2.5` and build `144`.
- Release tag/name: `v2.5.0` / `次元虾 v2.5.0`.
- Release asset: `CiYuanXia-v2.5-144-arm64-v8a.apk`
- Release asset SHA256: `2c283b7d810b11d9c7abb381d358aca492419a86726743730148b9cbd1947f31`
- Actions artifact ID: `8315303372`
- Actions artifact ZIP digest: `sha256:108950af36fc43196b1d81da56c3a8fa7819d2392c37413f21bdbe708d1f6235`

## Known Risks

- The IME/input visibility fix still needs Android device smoke on both terminal input and browser-page input fields.
- The latest build was verified through CI and release metadata, but not installed on-device from this Termux session.
- GitHub Actions still does not run `flutter test`, so the release path remains lighter than the repo's existing test inventory.

## Next Actions

- Install `CiYuanXia-v2.5-144-arm64-v8a.apk` on Android and confirm terminal and browser inputs stay above the keyboard while `adjustPan` is active.
- Verify the installer, settings page, and in-app version text all show `2.5`.
- After device smoke, keep the versioning helper policy intact so the next fresh build advances to `145 -> 2.6`.
