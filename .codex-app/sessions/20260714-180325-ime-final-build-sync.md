# 2026-07-14 18:03 UTC - IME Final Build Sync

## Goal

Record the final terminal IME follow-up build, sync local project memory to the successful `145 / 2.6` release, and pull the published APK down to the local workspace.

## Repo Facts Read

- Re-read `.codex-app/state.md`, `.codex-app/build.md`, `.codex-app/backlog.md`, and the previous session handoff before editing project memory.
- Verified the current source anchor in `flutter_app/pubspec.yaml` (`2.5.0+143`) and `package.json` (`2.5.0`).
- Re-checked `flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/NativeTerminalView.kt`, `flutter_app/lib/screens/terminal_screen.dart`, `.github/workflows/flutter-build.yml`, and `lib/test.js`.
- Confirmed GitHub `main` through `gh api repos/shwiki1/openclaw-termux-zh/branches/main --jq .commit.sha`.

## Changes Made

- Updated `.codex-app/state.md`, `.codex-app/build.md`, and `.codex-app/backlog.md` from the stale `144 / 2.5` state to the final `145 / 2.6` release state.
- Recorded the failed intermediary run `29353875406` (`TerminalView` is final), the successful-but-stale-version run `29354705042` (`144 / 2.5`), and the final successful run `29355437073` (`145 / 2.6`).
- Downloaded GitHub Release `v2.6.0` locally to `dist/github-release-v2.6.0/CiYuanXia-v2.6-145-arm64-v8a.apk`.

## Checks Run

- `python3 /data/data/com.termux/files/home/.codex/skills/app-development-governor/scripts/validate_app_memory.py --project /storage/emulated/0/ZeroTermux/开发/openclaw-termux-zh-5.5`: passed before the memory refresh.
- `gh auth status`: passed with authenticated account `shwiki1`.
- `gh run view 29353875406 --log-failed | rg "final|TerminalView"`: confirmed the compile failure was caused by trying to extend the final `TerminalView`.
- `gh run view 29354705042 --job 87159321179 --log | rg "APP_VERSION_(NAME|DISPLAY|CODE)"`: confirmed the stale `2.5.0 / 2.5 / 144` version derivation.
- `gh run view 29355437073 --job 87161764185 --log | rg "APP_VERSION_(NAME|DISPLAY|CODE)"`: confirmed `2.6.0 / 2.6 / 145`.
- `gh release view v2.6.0 --json tagName,name,assets,isDraft,isPrerelease`: confirmed the published release metadata.
- `gh release download v2.6.0 --clobber --dir dist/github-release-v2.6.0`: pulled the published APK to local storage.
- `sha256sum dist/github-release-v2.6.0/CiYuanXia-v2.6-145-arm64-v8a.apk`: matched the GitHub release digest `069a55a8d36826688f44b8d9d073942b107a9d01d27ac0d432197d438ee23cc5`.
- `npm test`: passed with 24 checks.
- `npm run lint -- --no-warn-ignored`: passed.
- `git diff --check`: passed.
- `python3 /data/data/com.termux/files/home/.codex/skills/app-development-governor/scripts/validate_app_memory.py --project /storage/emulated/0/ZeroTermux/开发/openclaw-termux-zh-5.5`: passed again after the memory refresh with no errors and no warnings.

## Cloud Build

- Workflow: `Build OpenClaw Apps`
- Final successful run: `29355437073`
- Remote commit: `57c25971903dede564b06531378428589a73232e`
- Intermediary failed run: `29353875406` on commit `9d615421ac18b1f5789ca7f304b565516c1107b7`
- Intermediary stale-version run: `29354705042` on commit `4673bf4510177b8aebdd97cdf74c07003e263038`

## Version And Artifacts

- Source anchor stayed at `2.5.0+143`.
- Final successful release used `APP_VERSION_NAME=2.6.0`, `APP_VERSION_DISPLAY=2.6`, and `APP_VERSION_CODE=145`.
- Release tag/name: `v2.6.0` / `次元虾 v2.6.0`.
- Release asset: `CiYuanXia-v2.6-145-arm64-v8a.apk`
- Release asset SHA256: `069a55a8d36826688f44b8d9d073942b107a9d01d27ac0d432197d438ee23cc5`
- Actions artifact ID: `8320095459`
- Actions artifact ZIP digest: `sha256:f37da8b0dda21f21b497d9ab6d13795bf5deb1261653e2f4a05301db0a2408d9`
- Local downloaded APK: `dist/github-release-v2.6.0/CiYuanXia-v2.6-145-arm64-v8a.apk`

## Known Risks

- The latest APK has not been installed or smoke-tested on-device from this Termux session, so the terminal IME visibility fix is still unverified on a real Android keyboard.
- GitHub Actions still does not run `flutter test`, so the release path remains lighter than the repo's existing Flutter test inventory.
- The release job warns that `softprops/action-gh-release@v2` is still on the Node.js 20 deprecation path and should be replaced or updated before GitHub fully removes that compatibility layer.

## Next Actions

- Install and test `CiYuanXia-v2.6-145-arm64-v8a.apk` on Android, confirming terminal and browser inputs stay visible above the IME and installer/settings show `2.6`.
- If the terminal prompt is still hidden, continue debugging in the native Android `TerminalView` / `adjustPan` boundary instead of Flutter text-input widgets.
- Add `flutter test` or equivalent SDK-side coverage before the next fresh artifact (`146 -> 2.7`).
