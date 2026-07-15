# 2026-07-15 21:28 UTC - Prepare 3.7 From 3.4 Baseline

## Goal

Publish the verified 3.4 source baseline with a fresh Android versionCode after withdrawing 3.5 and 3.6.

## Repo Facts Read

- Local `f206113` and remote `e698148` share source tree `697c7a469947fb4e7ca7268f14979609c42182c9`.
- GitHub `v3.5.0` and `v3.6.0`, their tags/assets, and related Actions runs have been deleted; `v3.4.0` is latest.
- The source anchor remains `2.5.0+143`. Without an override, the restored workflow would choose withdrawn build `154`.

## Changes Made

- Added `MINIMUM_RELEASE_BUILD=156` to the workflow version calculation.
- Added Node assertions that build `156` derives display version `3.7` and that the workflow carries the version floor.

## Checks Run

- `npm test` passed: 28 checks, 0 failures.
- `npm run lint -- --no-warn-ignored` passed.
- `git diff --check` passed.
- `scripts/versioning.py` derives `3.7.0 / 3.7 / 156` from the stable source anchor.

## Cloud Build

- Not started at this handoff; the next push must produce only an `arm64-v8a` APK.

## Version And Artifacts

- Planned release: `3.7.0 / 3.7 / 156`.
- Functional source baseline: `3.4`.

## Known Risks

- Local Flutter/Dart/Kotlin tooling remains unavailable; GitHub Actions is required for Android compilation.

## Next Actions

- Commit, push through the GitHub API, watch the cloud build, and download/verify the resulting ARM64 APK.
