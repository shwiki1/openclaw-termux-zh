# Session: CodeBuddy Local Alias

## Goal
Investigate why the same model works in Codex but fails in CodeBuddy with `500 max_tokens exceeds the limit of 65536`, then fix CodeBuddy compatibility without reducing high-output model capability globally.

## Repo Facts Read
- Project memory from `.codex-app/state.md`, `.codex-app/manifest.md`, `.codex-app/architecture.md`, and `.codex-app/backlog.md`.
- `flutter_app/lib/services/cli_api_config_service.dart` generates CodeBuddy `~/.codebuddy/models.json`, `~/.codebuddy/settings.json`, tool env files, and api2py model mappings.
- The current bundled CodeBuddy package documentation says custom `models.json` entries support `maxInputTokens` and `maxOutputTokens`.
- CodeBuddy source inspection showed custom models without explicit `maxOutputTokens` omit `max_tokens`, while models that match the built-in catalog may receive catalog-derived max-token settings.

## Changes Made
- Reverted the earlier global api2py `65536` output-token clamp direction.
- Added a stable CodeBuddy-only local model alias `openclaw-codebuddy-model` when CodeBuddy is routed through the local api2py relay.
- Updated api2py model mapping generation so `openclaw-codebuddy-model` maps to the real upstream model selected in app settings.
- Updated CodeBuddy env/settings generation so CodeBuddy sees and requests the local alias instead of a real upstream model name that may collide with its built-in catalog.
- Added test guards that api2py does not globally clamp output tokens and CodeBuddy uses the local alias path.

## Checks Run
- `npm test` passed 37/37.
- `npm run lint -- --no-warn-ignored` passed.
- `python3 -m py_compile flutter_app/assets/api2py/app/config.py flutter_app/assets/api2py/app/main.py flutter_app/assets/api2py/app/protocol.py flutter_app/assets/api2py/app/proxy.py` passed.
- `git diff --check` passed.

## Cloud Build
- Not run in this session. The fix is local source only until the next requested APK build.

## Known Risks
- Local Termux still cannot run Flutter analyze/test or Android compile.
- Device smoke is needed to verify CodeBuddy no longer sends a bad max-token request for a simple prompt and Codex tool-calling remains healthy.

## Next Actions
- When the user requests a new build, bump/use a logical build greater than `202`, reuse the prebuilt RootFS, and download the GitHub artifact locally.
- Device-smoke CodeBuddy with the same model that already works in Codex through the local `api2py` relay.
