# 2026-07-23 SMS/MMS Permission Removal

## Goal
- Remove SMS/MMS permissions that the user reported seeing in Android software permission management.

## Repo Facts Read
- Source `flutter_app/android/app/src/main/AndroidManifest.xml` did not actively declare SMS/MMS permissions before this change.
- Repository search found no SMS/MMS API usage or telephony message permission references outside the new manifest removal rules.
- Generic `audit_native_config.py` lists every `<uses-permission>` string and does not understand `tools:node="remove"`.

## Changes Made
- Added manifest merge removals for `READ_SMS`, `RECEIVE_SMS`, `SEND_SMS`, `RECEIVE_MMS`, and `RECEIVE_WAP_PUSH` in `flutter_app/android/app/src/main/AndroidManifest.xml`.
- Added a Node drift guard in `lib/test.js` requiring those permissions to appear only with `tools:node="remove"` and never as active declarations.
- Updated app memory with the permission policy and current source permission list.

## Checks Run
- `npm test -- --runInBand` passed 41/41.
- `npm run lint -- --no-warn-ignored` passed.
- `git diff --check -- flutter_app/android/app/src/main/AndroidManifest.xml lib/test.js` passed.
- `audit_native_config.py --project .` completed with existing warnings for exported launcher component and cleartext traffic, but also listed the SMS/MMS removal-rule strings as permissions because the script is text-based.

## Cloud Build
- Not triggered in this step.
- Final merged-manifest/APK verification still requires GitHub Actions or another Android build environment because local Flutter/Dart/adb are unavailable.

## Version And Artifacts
- No new version or artifact produced.
- Latest packaged candidate remains `9.5 / 214`; it does not include this source-only permission fix yet.

## Known Risks
- Until a new APK is built and installed, Android permission management will continue reflecting the previously installed artifact.
- Verify the final merged APK Manifest after the next cloud build because the reported SMS/MMS permission may have been introduced by manifest merging from a dependency.

## Next Actions
- On the next requested APK build, use a fresh Android build number greater than `214`, then inspect the merged/final APK Manifest to confirm SMS/MMS permissions are absent.
