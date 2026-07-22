# 2026-07-22 Fix Terminal Title And Proxy Mapping

## Goal
- Address user-reported regressions after the CLI/terminal-only cleanup:
  - Main dashboard should show two functions named `CLI 工具` and `终端`.
  - CLI API model mapping must write into the local api2py relay `model_mappings` again.

## Repo Facts Read
- `DashboardScreen` uses l10n keys `dashboardCliToolsTitle` and `dashboardTerminalTitle` for the two cards.
- `CliApiConfigService._mergeLocalApiProxyConfig()` previously skipped any resolved config whose base URL was the built-in local proxy, which prevented recursive providers but also prevented model alias updates when a tool selected `本地中转代理`.
- The local proxy config file path remains `/root/.openclaw/api2py/data/config.json`.

## Changes Made
- Changed `dashboardTerminalTitle` translations from CLI-tools-plus-terminal wording to standalone Terminal wording in zh-Hans, zh-Hant, en, and ja.
- Updated `_mergeLocalApiProxyConfig()` so local proxy configs are no longer skipped entirely.
- For local proxy configs, provider creation is still skipped to avoid recursive upstreams, but mappings are written using the existing `default_provider` or first existing provider in api2py.
- Added `_providerIdForLocalProxyMapping()` helper.
- Updated `lib/test.js` guards to require the local-proxy mapping path and reject the old skip condition.

## Checks Run
- `npm test` passed 41/41.
- `npm run lint -- --no-warn-ignored` passed.
- `git diff --check` passed.
- Focused source scan confirmed dashboard titles are `CLI 工具` and `终端`, and `_providerIdForLocalProxyMapping()` is used.

## Version And Artifacts
- No APK built in this turn.
- Latest built APK remains `9.2 / 211` and does not include this fix.

## Cloud Build
- Not run yet for this fix.

## Known Risks
- Local Flutter/Dart/adb are unavailable, so Flutter analyze/APK compile/device smoke require GitHub Actions/device testing.
- If api2py has no providers at all, local-proxy mapping sync intentionally skips instead of creating a recursive provider; the user must configure at least one upstream provider in api2py or through shared API management.

## Next Actions
- Push and run a fresh cloud build if the user wants an installable APK with these fixes.
- Next fresh cloud build must use Android build greater than `211`.
