# 2026-07-22 Restore System Access Settings

## Goal
- Restore the top-right Settings features requested by the user:
  - Battery optimization control.
  - Shared storage access permission.
  - Floating file manager / overlay access.
- Keep OpenClaw gateway/provider/package/local-model settings removed.

## Repo Facts Read
- Battery optimization and storage permission native handlers still existed in `NativeBridge` / `MainActivity`.
- Overlay and floating file manager bridge methods, manifest service declaration, and `FloatingFileManagerService.kt` had been removed by the CLI/terminal-only cleanup.
- The app already keeps shared storage mount behavior in `TerminalService` / `ProcessManager`, so restoring the permission UI is still relevant to the CLI runtime.

## Changes Made
- Reworked `SettingsScreen` into a stateful screen with:
  - Battery optimization status and request flow with resume polling.
  - Storage access status and Android permission request dialog.
  - Floating file manager switch with overlay permission request.
  - Existing Open Source Licenses entry.
- Restored `FloatingFileManagerService.kt` and wired it back through:
  - `NativeBridge` overlay/floating-file-manager methods.
  - `MainActivity` method-channel handlers.
  - `AndroidManifest.xml` `SYSTEM_ALERT_WINDOW` permission and service declaration.
  - Gradle dependencies for RecyclerView and Media3 used by the floating file manager.
- Replaced restored service references to removed lucide drawables with icons still packaged in the reduced native drawable set.
- Added system-access localization keys for zh-Hans, zh-Hant, en, and ja.
- Updated `lib/test.js` guards so these system access features are intentionally preserved while gateway/Node/local-model/update settings remain removed.

## Checks Run
- `npm test` passed 41/41.
- `npm run lint -- --no-warn-ignored` passed.
- `git diff --check` passed.
- `bash -n scripts/build-prebuilt-rootfs.sh scripts/prebuilt-rootfs-metadata.sh scripts/fetch-prebuilt-rootfs-asset.sh scripts/publish-prebuilt-rootfs-asset.sh scripts/build-apk.sh scripts/download-latest-artifact.sh` passed.
- Focused scan confirmed no missing lucide drawable references from `FloatingFileManagerService.kt`.
- Focused scan found no gateway/Node/provider/update/local-model settings tokens in the restored settings path.

## Version And Artifacts
- No APK built in this turn.
- Latest built APK remains `9.2 / 211`; it does not include this settings restoration.

## Cloud Build
- Not run yet for this fix.

## Known Risks
- Local Flutter/Dart/Kotlin/adb are unavailable, so Android compile and device smoke require GitHub Actions/device testing.
- Floating file manager was restored from the pre-cleanup native service; cloud Kotlin compile should validate compatibility with the currently reduced dependency set.

## Next Actions
- Push and run a fresh cloud build if the user wants an installable APK containing the restored Settings features.
- Next fresh cloud build must use Android build greater than `211`.
