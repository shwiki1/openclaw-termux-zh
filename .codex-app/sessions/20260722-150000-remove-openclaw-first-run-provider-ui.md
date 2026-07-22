# Remove OpenClaw First-Run And Provider UI

## Goal
Remove OpenClaw first-launch UI/logic and main-screen AI provider/gateway configuration UI/logic while preserving the separate CLI local proxy/API-management features.

## Repo Facts Read
- Repo root: `/storage/emulated/0/ZeroTermux/开发/openclaw-termux-zh-5.5`.
- Flutter app entry is `flutter_app/lib/app.dart`; primary routing starts at `SplashScreen`, then `SetupWizardScreen` or `DashboardScreen`.
- CLI local proxy boundary is `CliToolsScreen`, `CliApiConfigService`, `LocalApiProxyService`, `LocalApiProxyBrowserScreen`, and bundled `assets/api2py`; this remains separate from the removed OpenClaw AI provider UI.
- Local Flutter/Dart/adb are unavailable in this Termux environment, so compile verification must happen in GitHub Actions.

## Changes Made
- Removed the remaining Flutter first-run OpenClaw onboarding/config path: setup now finishes directly to Dashboard after runtime setup or backup restore, and Splash no longer auto-exports `openclaw-snapshot-*.json` or reads `root/.openclaw/openclaw.json` during startup.
- Removed main-screen OpenClaw AI provider/gateway UI and Dart logic: deleted provider screens, config editor, message-platform screens, logs screen, gateway controls, `GatewayProvider`, Dart `GatewayService`, provider/message config services, gateway auth config service, related models, and obsolete Flutter tests.
- Kept the CLI local proxy boundary intact: `CliToolsScreen`, `CliApiConfigService`, `LocalApiProxyService`, `LocalApiProxyBrowserScreen`, api2py assets, and the visible `中转代理` / `API 管理` controls remain.
- Local model startup no longer writes an OpenClaw AI-provider preset or restarts a gateway. Local model chat settings now offer only local and manual endpoint targets, not saved OpenClaw provider configs.
- Settings no longer exposes OpenClaw gateway auto-start, persistent gateway logs, or Bonjour discovery. About copy now says CLI runtime instead of AI gateway.
- Backup center no longer exposes standalone `openclaw.json` config backup/restore. Workspace backup/restore and legacy snapshot compatibility remain for CLI/runtime data continuity.

## Checks Run
- `npm test` passed 39/39 with new drift guards for removed OpenClaw first-run/provider/gateway UI and preserved CLI local proxy/API management.
- `npm run lint -- --no-warn-ignored` passed.
- `bash -n scripts/build-prebuilt-rootfs.sh scripts/prebuilt-rootfs-metadata.sh scripts/fetch-prebuilt-rootfs-asset.sh scripts/publish-prebuilt-rootfs-asset.sh` passed.
- `audit_github_actions.py --project .` passed with no warnings.
- `check_dependency_licenses.py --project .` found 0 unknown npm direct licenses.
- `git diff --check` passed.
- `audit_ui_static.py --project .` and `audit_i18n_copy.py --project .` returned existing broad static review prompts; no blocker was identified for the removed OpenClaw UI paths.
- `rg` confirmed deleted OpenClaw Flutter services/screens have no references under `flutter_app/lib` or `flutter_app/test`.
- Local `flutter` command is unavailable in Termux, so Flutter analyze/test and APK compile were not run locally.

## Cloud Build
- No APK/cloud build was triggered in this session.
- Latest packaged cloud candidate remains `8.9 / 208`; the next APK claiming this removal must use build `> 208` and should run with `rebuild_rootfs=true` so the packaged RootFS no longer comes from the older OpenClaw prebuilt asset.

## Version And Artifacts
- No version/build bump was made and no artifact was produced in this local cleanup session.
- Next packaging run must choose Android build `> 208`.

## Known Risks
- Because Flutter analyze could not run locally, the next cloud build must be watched through the workflow's `flutter analyze --no-fatal-infos` and Android packaging steps.
- Kotlin/native `GatewayService` code may still exist below Android native sources and can be cleaned in a later native pass if no native entry points require it.
- Many l10n keys for deleted legacy screens remain as inert text; they do not compile into routes, but a later localization cleanup can remove them once Flutter analyzer/cloud build is green.

## Next Actions
- Run a cloud build with build `> 208` and `rebuild_rootfs=true` when the user asks for packaging this removal.
- After a green cloud compile, optionally do a l10n dead-key cleanup pass for removed legacy OpenClaw screens.
- Device-smoke setup, dashboard, CLI local proxy `中转代理` / `API 管理`, local model start/chat, backup center, and settings.
