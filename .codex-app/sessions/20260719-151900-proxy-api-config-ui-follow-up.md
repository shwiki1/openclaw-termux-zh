# Session Handoff: Proxy API Config UI Follow-up

Date: 2026-07-19 UTC

## Summary
- User reported that the model protocol switch in per-tool config did not persist, asked to remove the `旧共享 API` tag from the `API 接入` card, and asked for more detailed proxy usage instructions in the `中转代理` dialog.
- Fixed `CliApiConfigDialog._toolSettings()` so the selected `获取模型协议` value is saved as `apiProtocol` and survives later saves/runtime regeneration.
- Removed the old shared-API count/status chip and related unused state from `CliToolsScreen`.
- Replaced the short proxy text in `_LocalApiProxyDialog` with a reusable usage guide card that lists Base URL, default key `sk-123`, health URL, RootFS path, auto-start/restart behavior, provider/mapping ownership, recursion avoidance, and supported protocols.
- Added Node guard assertions to prevent the old shared-API label returning and to ensure the proxy usage guide stays present.

## Files Changed
- `flutter_app/lib/widgets/cli_api_config_dialog.dart`
- `flutter_app/lib/screens/cli_tools_screen.dart`
- `lib/test.js`
- `.codex-app/state.md`
- `.codex-app/sessions/20260719-151900-proxy-api-config-ui-follow-up.md`

## Checks
- `npm test` passed 37/37.
- `npm run lint -- --no-warn-ignored` passed.
- `git diff --check` passed.
- Local Flutter/Dart/Kotlin compilers remain unavailable; compile verification still needs GitHub Actions.

## Next
- Device-smoke or cloud-build on request to verify the protocol persists through actual per-tool saves and generated CLI config files.
