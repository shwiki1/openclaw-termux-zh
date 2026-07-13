# 2026-07-13 10:37 UTC - Fix Version Metadata

## Goal
Fix the verified metadata drift recorded during project analysis.

## Repo Facts Read
- `.codex-app/state.md`, `manifest.md`, `architecture.md`, `build.md`, `backlog.md`, latest session, and decision `0001-project-memory.md`.
- `README.md`, `docs/README_en.md`, `CHANGELOG.md`, `STRUCTURE.md`, `flutter_app/lib/constants.dart`, and `flutter_app/pubspec.yaml`.
- Current environment facts: Node.js `v24.14.1`, npm `11.13.0`, Git worktree present, branch `codex-termux-runtime-fix`.

## Changes Made
- Updated `flutter_app/lib/constants.dart` default `APP_VERSION_CODE` from `126` to `133`.
- Updated Chinese and English README version/build examples to `2.0.50+133`.
- Updated CHANGELOG unreleased metadata from `2.0.50+126` to `2.0.50+133`.
- Updated STRUCTURE header/artifact/build examples to `2.0.50+133`.
- Corrected STRUCTURE notes that said the current directory was not a Git repository and that CI built multi-architecture APK/AAB artifacts.

## Checks Run
- `rg` checks for current-version `126` references: no current docs/source hits.
- `git diff --check`: passed.
- `npm test`: passed, 11 passed and 0 failed.
- `npm run lint -- --no-warn-ignored`: passed.
- `flutter --version`: failed because `flutter` is not installed in this Termux environment.
- `validate_app_memory.py --project .`: passed with no errors and no warnings.

## Cloud Build
- Not run.

## Version And Artifacts
- Source version remains `2.0.50+133`.
- No artifact produced.

## Known Risks
- Flutter analyze/test/build still require a Flutter SDK environment or GitHub Actions.
- Before a new cloud artifact, decide whether to reuse `133` or bump to a new build number.

## Next Actions
- Continue with the next focused feature or run GitHub cloud build only after GitHub auth and version/build decision.
