# Session Handoff: Local Relay Startup Diagnostics

Date: 2026-07-18 UTC

## Goal
- Diagnose the installed `7.2 / 191` local api2py relay failure where pip dependencies installed successfully but startup ended with `Python 服务启动失败，请查看 /root/.openclaw/api2py/server.log`.
- Do not create branches/worktrees or trigger a cloud build unless the user explicitly asks.

## Findings
- The pasted user log shows dependency installation completed; the failure happens after `bash start.sh` starts the Python service.
- The previous app surfaced only the generic `server.log` path, so the visible PlatformException did not include the actual Python traceback/log tail.
- `requirements.txt` had broad dependency ranges and an unused `fastapi>=0.110` entry, which caused extra packages and future/latest dependency combinations to be installed.

## Changes Made
- `flutter_app/assets/api2py/requirements.txt`: removed unused FastAPI and capped Starlette/Uvicorn/HTTPX/aiosqlite ranges.
- `flutter_app/assets/api2py/start.sh`: clears stale `server.log` on each launch, kills the child on failed startup, and prints the latest 80 log lines to stderr.
- `flutter_app/lib/services/local_api_proxy_service.dart`: pip install now retries against official PyPI after the configured/default index fails, and final startup errors append the current `server.log` tail.
- `lib/test.js`: added guards for the capped requirements, PyPI fallback install commands, and `server.log` tail surfacing.

## Checks Run
- Local Python venv installed the capped api2py requirements from official PyPI, then `PORT=19999 bash start.sh` returned `/api/health` OK; generated runtime artifacts were removed from bundled assets afterward.
- `bash -n flutter_app/assets/api2py/start.sh flutter_app/assets/api2py/stop.sh`: passed.
- `npm test`: 35/35 passed.
- `npm run lint -- --no-warn-ignored`: passed.
- `git diff --check`: passed.

## Known Limits
- Local Termux still lacks Flutter/Dart/Kotlin compilers; Android compile and device verification require cloud build and install smoke after user approval.
- The original device-side `server.log` was not available in the repo. This fix makes the next failure self-report the log tail in the app error.

## Next Actions
- Only after explicit user request, package a fresh APK with logical build `> 191`.
- Device-smoke `重启代理`: verify pip bootstrap, dependency install/fallback, `9999` health check, direct API management UI, and improved failure text if startup still fails.
