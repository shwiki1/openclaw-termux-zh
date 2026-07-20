# Session 2026-07-20 06:33 UTC - CLI Proxy Protocol Ownership Hotfix

## Goal
- Fix the user-reported regression where switching Codex CLI model protocol once caused other CLI protocol changes to stop taking effect, and api2py backend protocol edits were reverted after opening any CLI terminal.

## Repo Facts Read
- Project root: `/storage/emulated/0/ZeroTermux/开发/openclaw-termux-zh-5.5`.
- Existing branch: `codex-terminal-ime-lag-fix`; no new branch/worktree was created.
- Current latest built APK before this hotfix: local `8.2 / 201` at `dist/github-run-29716934002/CiYuanXia-v8.2-201-arm64-v8a.apk`.
- Relevant files read: `flutter_app/lib/services/cli_api_config_service.dart`, `flutter_app/lib/widgets/cli_api_config_dialog.dart`, `flutter_app/lib/models/cli_api_config.dart`, and `lib/test.js`.

## Changes Made
- In `CliApiConfigService.saveToolSettings()`, when the selected profile is the built-in local proxy, stale tool-level `apiProtocol` is cleared before persisting tool settings.
- In `_resolvedToolConfig()`, the built-in local proxy profile no longer lets stale tool-level `apiProtocol` override the local proxy profile protocol during runtime config resolution.
- In `_toolSettingsJson()`, settings that directly use the local proxy base URL persist an empty `apiProtocol` to clean old local-proxy protocol residue.
- In `_mergeLocalApiProxyConfig()`, existing proxy-side mapping `protocol` is preserved first; tool-level `apiProtocol` is used only when creating a brand-new mapping without an existing protocol, then default protocol applies as fallback.
- In `CliApiConfigDialog._load()`, the displayed `获取模型协议` now reads the proxy-side mapping protocol for any selected alias before falling back to saved tool settings.
- In `CliApiConfigDialog._save()`, explicit protocol dropdown changes call `updateLocalApiProxyModelProtocol()` for the selected alias, not only for the built-in local proxy profile. Ordinary open/save/runtime regeneration does not change existing proxy-side mapping protocol.
- Updated `lib/test.js` guards for the proxy protocol ownership behavior.

## Checks Run
- `npm test` passed 37/37.
- `npm run lint -- --no-warn-ignored` passed.
- `python3 -m py_compile flutter_app/assets/api2py/app/config.py flutter_app/assets/api2py/app/main.py` passed.
- `git diff --check` passed.

## Cloud Build
- Not launched in this hotfix session yet. The next user-approved APK build must use a logical build greater than `201` and should reuse the prebuilt RootFS.

## Known Risks
- Local Flutter/Dart/Kotlin compilers remain unavailable, so Flutter analyze/test and Android compile still require GitHub Actions.
- This hotfix is local source only until the next APK build. Installed `8.2 / 201` still contains the earlier protocol behavior.

## Next Actions
- On the next user-approved build, package this hotfix with a logical build greater than `201`.
- Device-smoke: change a mapping protocol in the api2py backend, open Codex and other CLI terminals, and verify the backend mapping protocol is not reverted. Then explicitly change a CLI dropdown protocol and verify only that selected alias mapping updates once.
