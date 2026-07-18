# Project Management Audit - 2026-07-18

## Scope
Local governance audit with the app-development-governor skill. No application source, dependency, signing, permission, or release-workflow changes were made in this turn.

## Verified Baseline
- Product: `次元虾`, Flutter Android + Kotlin native services + PRoot Ubuntu runtime + legacy Node compatibility CLI.
- Package: `com.agent.cyx`
- Release constraint: build/release only `arm64-v8a` APK unless explicitly requested otherwise.
- Source version anchor: Flutter `2.5.0+143`; Node package `2.5.0`.
- Active branch: `codex-terminal-ime-lag-fix` @ `f6c94bab2ac003f59b4d6e7317dd9044383c0356`, currently `ahead 44, behind 9` versus local `shwiki/main`.
- Remotes: Gitee `origin`, GitHub `shwiki`.
- Latest published release: `v5.4.0 / 5.4 / 173`, Actions `29538124523`, APK SHA-256 `cd632f6fb96c4f4f454c23dd70f44dc804ac86a9800aa5fb7656735e1ae256e7`.
- Latest successful unreleased candidate: `6.5 / 184`, Actions `29623644999`, remote SHA `c485344e6c51db8ad2987a06d45759f30a66cd62`.
- Preferred local install path: `dist/gitee-run-29623644999/CiYuanXia-v6.5-184-arm64-v8a.apk` (SHA-256 `82ba2aa3d3ed64eaa9a4e7a3b3087f489e5e3f06318419219725e6c3d4ddf447`).
- Fixed APK delivery path: GitHub Actions runner uploads split parts to Gitee temp branch `apk-transfer-<run-id>`; local clones Gitee only, reassembles under project `dist/gitee-run-<run-id>/`, verifies SHA, deletes temp branch.

## Architecture Snapshot
- Flutter owns screens/providers/services and the loopback browser automation bridge.
- Kotlin owns PRoot/bootstrap/gateway/node services and the production terminal surfaces:
  - ordinary CLI -> `NativeTerminalActivity`
  - Codex -> `NativeTerminalPagerActivity` + `NativeCodexBrowserView`
  - shared terminal core -> `NativeTerminalSessionView`
- RootFS runtime hosts Node/OpenClaw and CLI wrappers under `/opt/openclaw-cli/<tool>`.
- Cloud packaging is GitHub Actions only; local Termux is limited to Node lint/tests and artifact verification.

## Quality Status

| Gate | Result | Evidence |
| --- | --- | --- |
| App memory validation | Passed | no errors / no warnings |
| Node lint | Passed | `npm run lint -- --no-warn-ignored` |
| Node compatibility tests | Passed | `npm test` 32/32 |
| Worktree whitespace | Passed | `git diff --check` |
| Candidate APK SHA | Passed | Gitee-reassembled `6.5/184` |
| Flutter/Kotlin local checks | Blocked locally | no `flutter` / `dart` / `kotlinc` |
| Cloud Flutter tests | Missing | workflow builds/analyzes APK but does not run `flutter test` |
| Device smoke | Missing | required for `6.5/184` |

## Delivery Risks
1. `6.5 / 184` is packaged and locally verified, but not device-smoked.
2. Branch history is divergent; promotion must pin exact remote SHA rather than branch-name assumptions.
3. Some historical Actions logs reported missing `KEYSTORE_BASE64` while APKs still used the established release signer; signing provenance still needs an explicit answer before public promotion.
4. Flutter unit tests exist (12 files) but are outside the current green APK path.
5. Broad Android permissions/privacy claims still need release-time reconciliation.
6. Gitee Release attachments cannot host the current APK size; only the split-branch transfer path is valid for China-side acceleration.

## Management Decision For This Checkpoint
- Freeze new feature churn until `6.5 / 184` is device-smoked.
- Keep source anchor at `2.5.0+143`.
- Require next fresh cloud build logical number `> 184`.
- Preserve the GitHub -> Gitee split-branch -> local `dist/gitee-run-<id>/` delivery decision.

## Next Milestone
1. Device-smoke `6.5 / 184` for update install, Codex proxy `127.0.0.1:8787` ownership after config save, native terminal/pager IME behavior, and browser/script basics.
2. Record promotion path + signing provenance.
3. Add or explicitly waive `flutter test` as a release gate.
4. Only then choose the next scoped product task.
