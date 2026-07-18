# 2026-07-17 11:37 UTC - Project Management Governance

## Goal

Rebuild current project truth from the repository and GitHub, verify available quality gates and artifacts, and refresh persistent project-management records without changing application source.

## Repo Facts Read

- App memory, latest session, architecture, UI, build, backlog, audit, `AGENTS.md`, package/version files, workflow, Git history, remotes, Actions runs, Releases, and downloaded artifacts.
- Stack remains Flutter/Dart + Kotlin Android + PRoot Ubuntu + Node compatibility CLI; only Android `arm64-v8a` APK is in scope.

## Changes Made

- Updated project memory to distinguish the published `5.4 / 173` release from the successful unreleased `5.6 / 175` feature candidate.
- Recorded current local/remote branch topology, cloud run provenance, artifact hashes, manifest/alignment/native-library/signature verification, and the unresolved signing-log discrepancy.
- Refreshed the priority backlog and project-management audit. No application source, dependency, permission, signing file, or workflow was changed.

## Checks Run

- `npm test`: 31 passed, 0 failed.
- `npm run lint -- --no-warn-ignored`: passed.
- `git diff --check`: passed before governance edits.
- `bash -n` on four release scripts: passed.
- `python3 -B -m py_compile` on `build_release.py` and `versioning.py`: passed.
- Candidate ZIP/APK integrity, `zipalign -c -p 4`, `aapt dump badging`, PRoot library presence, and `apksigner verify --print-certs`: passed.
- Local Flutter/Dart/Kotlin checks were unavailable because `flutter`, `dart`, and `kotlinc` are not installed.

## Cloud Build

- Latest successful candidate: run `29551560421`, branch `codex-terminal-ime-lag-fix`, remote SHA `28a3c243ba4bce4c65b3300f1514934c45a6c5b6`, build `5.6 / 175`.
- Latest published release remains run `29538124523`, GitHub `main` SHA `02602bb2bed28feae0b9c4af9d3db20c83f329a3`, release `v5.4.0 / 5.4 / 173`.

## Version And Artifacts

- Source anchor: `2.5.0+143`.
- Candidate artifact ID: `8396000246`.
- Candidate ZIP SHA-256: `ffa9da0a92b841d76d3a826a44a927c648875050ef2166f69a766dd2b16bdb96`.
- Candidate APK SHA-256: `83b31215f3bbf7b29c16720a11f55cad7d06f1cb7a148a455505fdb25fa94413`.
- Next fresh cloud build must be greater than `175`.

## Known Risks

- Candidate has not been device-smoked and is not published.
- Actions logged missing `KEYSTORE_BASE64`, while Gradle should then use the runner debug keystore and the APK instead verifies with the established custom release signer. No committed `key.properties`/keystore explains this, so signing provenance is unresolved.
- Local and GitHub feature heads share a source tree but have different parent histories.
- Flutter unit tests remain absent from the workflow.

## Next Actions

- Device-smoke the `5.6 / 175` candidate on Android 10+ arm64, including update install from `5.4` and native terminal/browser workflows.
- Resolve signing provenance and choose the authoritative promotion path before publication.
- Add `flutter test` to CI or explicitly record a release waiver.
