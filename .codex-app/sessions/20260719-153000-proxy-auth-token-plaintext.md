# Session Handoff: Proxy Auth Token Plaintext Display

Date: 2026-07-19 UTC

## Summary
- User asked for the proxy backend settings `认证 Token` to display in plaintext.
- The settings page already renders `cfg-tokens` as a plaintext `textarea`, but backend `redact_config()` masked `auth_tokens` in `/api/config`, so the UI only received masked values.
- Changed `flutter_app/assets/api2py/app/config.py` so `redact_config()` returns `auth_tokens` as plaintext strings.
- Kept `admin_tokens` and provider API keys masked.
- Added Node guard assertions for this distinction.

## Files Changed
- `flutter_app/assets/api2py/app/config.py`
- `lib/test.js`
- `.codex-app/state.md`
- `.codex-app/sessions/20260719-153000-proxy-auth-token-plaintext.md`

## Checks
- `python3 -m py_compile flutter_app/assets/api2py/app/config.py` passed.
- `npm test` passed 37/37.
- `npm run lint -- --no-warn-ignored` passed.
- `git diff --check` passed.

## Next
- Build on request; device/browser smoke should confirm `设置 -> 认证 Token` shows full token values after loading config.
