# Session: Local API Relay Integration

Date: 2026-07-18 UTC

## User Request
- Bundle `/storage/emulated/0/ZeroTermux/开发/api2py/` into the app as a local relay proxy to replace the old unified API configuration flow.
- Add a `中转代理` button below `管理 API`.
- The proxy should auto-start when the app opens; the proxy dialog must explain usage and show `重启代理` and `API 管理` buttons.
- `API 管理` opens a dedicated built-in browser with address bar, back/forward, and refresh.

## Changes
- Added sanitized bundled assets under `flutter_app/assets/api2py/`:
  - source files, `requirements.txt`, `server.py`, `start.sh`, `stop.sh`, static management page, migration script, and `data/config.example.json`.
  - excluded runtime logs, pid files, SQLite databases, sessions, caches, and pyc files.
  - removed the local copied `admin_account` password hash from the config template.
- Added `LocalApiProxyService` to install bundled files into `/root/.openclaw/api2py`, initialize `data/config.json`, install Python dependencies if needed, start `http://127.0.0.1:9999/`, and restart the relay on demand.
- Added `LocalApiProxyBrowserScreen`, a focused WebView manager with URL field, back, forward, and refresh.
- Updated `SplashScreen` to auto-start the relay in the background once RootFS setup is complete.
- Updated `CliToolsScreen` API card to show `API 接入`, keep legacy `管理 API`, and add the requested `中转代理` button below it. The dialog includes `重启代理` and `API 管理` at the top plus concise usage text.
- Follow-up in the same session removed local `api2py` setup/login friction: local API/admin requests bypass auth, the frontend boots straight into the management app, and generated relay config keeps `admin_account` empty with local unauthenticated access enabled.
- The old `管理 API` save path now writes providers and model mappings into `/root/.openclaw/api2py/data/config.json`; managed CLI configs use `http://127.0.0.1:9999/v1` as their Base URL. The old generated Codex 8787 proxy is no longer started from CLI config or install/runtime templates; remaining 8787 code is only stale-process cleanup for migration.
- Per user clarification, `api2py` is project-owned/user-authored code, so no third-party notice/license blocker is required.
- Previous native Codex icon alignment work remains in the same working tree: icon-only TextView controls now center left drawables with `includeFontPadding = false`.

## Checks
- `npm test` passed 35/35.
- `npm run lint -- --no-warn-ignored` passed.
- `git diff --check` passed.
- Local `dart` and `flutter` are not installed, so `flutter analyze` and Android compilation were not run locally.

## Risks / Follow-Up
- Device smoke required after next installable APK: start relay, open management WebView directly without first-run setup/login, configure providers/mappings, save via the existing `管理 API` path, and verify all managed CLI API base URLs route to `http://127.0.0.1:9999/v1` without starting the old 8787 proxy.
- Device smoke auto-start and restart behavior after the next installable APK.
