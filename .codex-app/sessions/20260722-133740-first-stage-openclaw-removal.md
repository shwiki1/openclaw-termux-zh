# 2026-07-22 13:37 UTC - First-Stage OpenClaw Removal

## Goal
- User requested a major change: first remove OpenClaw. This pass removes OpenClaw from the new setup/runtime packaging path without attempting a full repository rename or deleting every legacy compatibility service in one step.

## Repo Facts Read
- App is a Flutter Android shell with Kotlin native PRoot services and a bundled Ubuntu RootFS.
- Previous setup required Ubuntu RootFS, Node.js, bionic bypass, and OpenClaw.
- Previous prebuilt RootFS generator installed `openclaw@latest`, `@tencent-connect/openclaw-qqbot`, and `@tencent-weixin/openclaw-weixin`.
- Local Flutter/Dart/adb are unavailable; GitHub Actions is the Android compile path.

## Changes Made
- `BootstrapManager` completion now requires RootFS + bash + Node.js + bionic bypass, and reports `runtimeReady`; it no longer detects or requires OpenClaw.
- `BootstrapService` removed the OpenClaw install/reuse step and now finishes after Node.js and bionic bypass setup.
- `SetupState` removed the OpenClaw install step; setup progress now has five steps.
- `SetupWizardScreen` removed OpenClaw version loading, picker UI, install switch, and network calls during entry. It always passes `installOpenClaw: false` while that compatibility option still exists.
- Dashboard no longer exposes OpenClaw gateway controls, message platform entry, configure entry, config editor entry, or logs shortcut.
- Settings system info now shows `Runtime environment` backed by `runtimeReady` instead of an OpenClaw installed status row.
- `scripts/build-prebuilt-rootfs.sh` no longer installs OpenClaw or OpenClaw QQ/Weixin plugins and no longer writes plugin entries into `openclaw.json`.
- `scripts/prebuilt-rootfs-metadata.sh` now writes `ciyuanxia-prebuilt-rootfs-manifest` format and removes OpenClaw/plugin package version fingerprinting.
- `scripts/fetch-prebuilt-rootfs-asset.sh` rejects old `openclaw-prebuilt-rootfs-manifest` assets, forcing an intentional RootFS rebuild before an APK can truly exclude OpenClaw from the packaged archive.
- GitHub workflow step labels were changed from OpenClaw rootfs to CiYuanXia rootfs.
- Open-source repository/source/notice documents were updated so current RootFS notices no longer claim OpenClaw or its plugins are preinstalled.
- `lib/test.js` drift guards now assert that runtime setup no longer requires bundled OpenClaw and that the dashboard does not expose the message-platform entry.

## Checks Run
- `npm test` passed 39/39.
- `npm run lint -- --no-warn-ignored` passed.
- `bash -n scripts/build-prebuilt-rootfs.sh scripts/prebuilt-rootfs-metadata.sh scripts/fetch-prebuilt-rootfs-asset.sh scripts/publish-prebuilt-rootfs-asset.sh` passed.
- `python3 /data/data/com.termux/files/home/.codex/skills/app-development-governor/scripts/audit_github_actions.py --project .` passed with no warnings.
- `python3 /data/data/com.termux/files/home/.codex/skills/app-development-governor/scripts/check_dependency_licenses.py --project .` found 0 unknown npm direct licenses.
- `git diff --check` passed.
- `audit_ui_static.py --project .` and `audit_i18n_copy.py --project .` returned existing broad review prompts; no new blocker specific to this pass was identified.

## Cloud Build
- No cloud build was run in this turn.
- Because old `basic-resource` currently contains OpenClaw, the next installable APK for this change must intentionally rebuild and publish RootFS instead of restoring the old asset.

## Version And Artifacts
- Latest packaged artifact remains `8.9 / 208` from GitHub Actions run `29915338517`; it still contains the old prebuilt RootFS.
- Next fresh build must use logical build `> 208`.

## Known Risks
- Legacy OpenClaw-related source files and strings still exist for compatibility/history, including gateway services, backup compatibility, release docs, old asset names, and optional message-platform services. The first-stage goal was to remove OpenClaw from new setup/prebuild and hide the broken user-facing entries, not to finish a full repository rename.
- Local Flutter analyze, Android compile, APK inspection, and device smoke were not run locally because Flutter/Dart/adb are unavailable.

## Next Actions
- Push/build with GitHub Actions using `rebuild_rootfs=true`, verify the new RootFS archive manifest is `ciyuanxia-prebuilt-rootfs-manifest`, and inspect the APK RootFS for absence of `openclaw`, `openclaw-qqbot`, and `openclaw-weixin` packages.
