# 2026-07-22 12:59 UTC - Open Source License Entry Performance

## Goal
- User reported Settings -> Open Source Licenses takes too long before navigation. Optimize the license page entry path so tapping the settings row opens the page quickly while preserving license compliance content.

## Repo Facts Read
- App stack remains Flutter Android shell with Kotlin native services and bundled RootFS.
- Settings opens `OpenSourceLicensesScreen` through a plain `Navigator.push` in `flutter_app/lib/screens/settings_screen.dart`; the click handler itself does not load license documents.
- `OpenSourceLicensesScreen` previously loaded repository index immediately in `initState`, then started full notice aggregation after the first frame.
- Full notice loading calls `OpenSourceLicenseService.loadOpenSourceNotices()`, which reads bundled notice/source-offer assets and iterates `LicenseRegistry.licenses`; this can still compete with route transition/initial rendering on the main isolate.

## Changes Made
- Changed `OpenSourceLicensesScreen` to enter with a lightweight first frame and no immediate document read.
- Repository/source index now starts after the first frame instead of during `initState`.
- Full bundled notice/license aggregation now starts 350 ms later, after the route has had time to settle.
- Repository/source index renders as selectable plain text instead of Markdown to avoid Markdown parsing on the top section.
- Full notice Markdown is no longer selectable, reducing layout and selection overhead for the very long document.
- Updated `lib/test.js` drift guard to assert the delayed full-notice load, selectable plain-text repository section, and non-selectable long Markdown rendering.

## Checks Run
- `npm test` passed 39/39.
- `npm run lint -- --no-warn-ignored` passed.
- `git diff --check` passed.
- `python3 /data/data/com.termux/files/home/.codex/skills/app-development-governor/scripts/audit_performance_static.py --project .` completed with existing broad static findings; the changed screen only has a generic non-const widget cue.
- `python3 /data/data/com.termux/files/home/.codex/skills/app-development-governor/scripts/validate_app_memory.py --project .` passed with no errors or warnings before memory update.

## Cloud Build
- No cloud build was run for this local performance fix.
- The change is local source only until the next GitHub Actions APK build.

## Version And Artifacts
- No cloud build was run for this local performance fix.
- Latest packaged artifact remains `8.9 / 208` from GitHub Actions run `29915338517`.
- Next fresh cloud build must use logical build `> 208`.

## Known Risks
- Local Flutter/Dart/adb are unavailable in Termux, so Flutter analyze, APK compile, and Android device smoke were not run locally.
- Device smoke should verify tap latency from Settings -> Open Source Licenses, top repository text visibility, delayed full-license rendering, and acceptable scroll performance after the long document loads.

## Next Actions
- If the user wants an installable APK with this performance fix, push/build through GitHub Actions with a new build number greater than `208` and then download/verify the artifact.
