# 2026-07-16 14:15 UTC - Project Management Refresh

## Goal

Refresh project governance files so release, branch, and testing status match the current repository truth.

## Repo Facts Read

- `.codex-app/state.md`, `manifest.md`, `architecture.md`, `build.md`, and `backlog.md`.
- `.codex-app/sessions/20260716-z-codex-ime-settled-compensation.md` and `.codex-app/sessions/20260716-zz-codex-ime-shortcut-post-layout-refresh.md`.
- `flutter_app/pubspec.yaml`, `package.json`, `.github/workflows/flutter-build.yml`, `docs/project-management-audit-2026-07-16.md`, `git branch -vv`, and `git log --oneline`.

## Changes Made

- Updated project-management records from the stale `v3.7 / 156` baseline to the current published `v4.4.0 / 4.4 / 163` baseline.
- Corrected governance notes for branch topology: `codex-terminal-ime-lag-fix` is currently `ahead 8, behind 9` versus `shwiki/main`, so release provenance must continue naming remotes and SHAs explicitly.
- Re-prioritized backlog items around `v4.4.0` Android smoke, local artifact verification, CI `flutter test`, and release-branch reconciliation.
- Refreshed the standalone audit document to match the current release, checks, and risks.

## Checks Run

- `npm test` passed with 30 checks.
- `npm run lint -- --no-warn-ignored` passed.
- `git diff --check` passed.
- `python3 /data/data/com.termux/files/home/.codex/skills/app-development-governor/scripts/validate_app_memory.py --project /storage/emulated/0/ZeroTermux/开发/openclaw-termux-zh-5.5` had already passed with no errors and no warnings before the governance refresh; run it again after these doc updates if a fresh validation stamp is required.
- Local `flutter`, `dart`, and Android device execution remain unavailable in this Termux environment.

## Cloud Build

- No cloud build, push, or release action was run in this governance refresh.

## Version And Artifacts

- Current published release remains `v4.4.0 / 4.4 / 163`, `arm64-v8a` only.
- Source anchor remains `2.5.0+143`.
- The next fresh build must use a logical build number greater than `163`; the immediate candidate is `164 -> 4.5`.
- Local checksum/ZIP/alignment/signing verification for the `dist/github-release-v4.4.0/` download still needs to be recorded.

## Known Risks

- The latest release still lacks the Android device smoke evidence needed for the IME shortcut-bar fix.
- Current branch topology is divergent enough that release ownership can be confused without explicit remote/SHA provenance.
- GitHub Actions still does not run `flutter test`, so APK publication can stay green while Flutter unit regressions slip through.

## Next Actions

1. Device-smoke `v4.4.0 / 163` on Android with repeated IME dismiss/reopen and immediate shortcut-key taps.
2. Finish local verification of the `dist/github-release-v4.4.0/` asset and record checksum, ZIP integrity, `zipalign`, and signer results.
3. Decide which branch and remote are authoritative for the next release, then build with a logical version greater than `163`.
