# 2026-07-16 UTC - Codex IME Shortcut Release 4.5

## Goal

Prepare the Codex native terminal shortcut-bar responsiveness fix for the next arm64-v8a GitHub release.

## Repo Facts Read

- GitHub `main` is at the published `v4.4.0 / 4.4 / 163` baseline.
- The release workflow derives a fresh build from `flutter_app/pubspec.yaml` source anchor `2.5.0+143` and its committed minimum release floor.

## Changes Made

- Kept IME compensation coalesced, then delayed the transition finish by 32 ms so shortcut-bar layout completes before terminal repaint resumes.
- Restored pending terminal updates through the normal refresh throttle instead of an immediate repaint.
- Set the workflow release floor to build `164`, which derives semantic version `4.5.0` and install-visible version `4.5` from source anchor `2.5.0+143`.

## Checks Run

- Pending: `npm test`, ESLint, project-memory validation, and GitHub Actions arm64-v8a build.

## Cloud Build

- Pending GitHub Actions release build after this focused branch is pushed to `main`.

## Version And Artifacts

- Planned release: `v4.5.0 / 4.5 / 164`, arm64-v8a only.
- Previous installed release: `v4.4.0 / 4.4 / 163`.

## Known Risks

- The IME timing adjustment requires Android device smoke testing with a long Codex transcript after the new APK is installed.
- The current GitHub workflow runs Flutter analysis but does not run the repository's Flutter unit-test suite.

## Next Actions

1. Push this focused release branch to GitHub `main` after local checks pass.
2. Watch the GitHub Actions build and release jobs.
3. Record the run, artifact, checksum, and Android device smoke result before promoting the build.
