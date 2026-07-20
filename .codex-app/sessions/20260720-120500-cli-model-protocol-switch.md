# Session: CLI model protocol switching fix

## Goal
- Fix CLI config model protocol switching so it does not fight the api2py backend protocol settings.

## Repo Facts Read
- Repo root: `/storage/emulated/0/ZeroTermux/开发/openclaw-termux-zh-5.5`.
- Branch: `codex-terminal-ime-lag-fix`.
- Relevant UI: `flutter_app/lib/widgets/cli_api_config_dialog.dart`.
- Relevant config sync: `flutter_app/lib/services/cli_api_config_service.dart`.
- api2py semantics: provider `type` is upstream protocol, model mapping `protocol` is external/client protocol.

## Changes Made
- `CliApiConfigDialog` now treats `获取模型协议` as a model-fetch/runtime mapping control, not as a provider upstream protocol override.
- For the built-in `本地中转代理` profile, opening the dialog reads the current api2py model mapping protocol and does not persist a fixed `apiProtocol` into tool settings unless the user explicitly changes the dropdown.
- Saving local-proxy CLI settings now preserves existing api2py provider `type` and mapping `protocol`; explicit dropdown changes update only the selected model alias mapping protocol.
- `CliApiConfigService` added helpers to read/update a local api2py model mapping protocol directly.
- Node guard tests were updated to prevent reintroducing the old protocol overwrite behavior.

## Checks Run
- `npm test` passed 37/37.
- `npm run lint -- --no-warn-ignored` passed.
- `python3 -m py_compile flutter_app/assets/api2py/app/config.py flutter_app/assets/api2py/app/main.py` passed.
- `git diff --check` passed.

## Cloud Build
- No cloud build was run for this fix yet.
- Latest built APK remains `8.1 / 200` from run `29708374513`; this protocol fix is local source only until the next build.

## Known Risks
- Local Flutter/Dart/Kotlin compilers are unavailable, so Flutter analyze and Android compile still require GitHub Actions.
- Device smoke is required after the next APK build to verify Codex no longer overwrites api2py backend protocol settings and non-Codex CLI protocol switches affect the intended mapping.

## Next Actions
- When the user requests it, submit a new cloud build with logical build greater than `200`.
- Device-smoke protocol behavior in the built APK: backend protocol changes persist, explicit CLI dropdown changes update mapping protocol only, and provider `type` remains controlled by the proxy backend.
