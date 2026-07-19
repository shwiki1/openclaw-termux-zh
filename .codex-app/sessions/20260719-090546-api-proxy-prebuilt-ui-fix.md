# Session 2026-07-19 09:05 UTC - API Proxy, Prebuilt OpenClaw, Proxy UI Performance

## User Request
- Stop OpenClaw from downloading/installing when the prebuilt RootFS should already contain it.
- Fix logic between original `管理 API` and the local `api2py` relay: add a default local relay profile `127.0.0.1:9999/v1`, but never add/save that local relay as an upstream provider into api2py.
- Keep original API manager protocol choices in sync with api2py-supported protocols.
- Investigate and reduce local proxy management page lag.

## Changes
- `CliApiConfigService` now injects a protected built-in shared profile `本地中转代理` -> `http://127.0.0.1:9999/v1` with placeholder key `openclaw-local-proxy` for CLI selection.
- The built-in local relay profile is filtered out of persisted shared profiles and out of provider sync to `/root/.openclaw/api2py/data/config.json`; any normalized local `127.0.0.1:9999`/`localhost:9999` URL is skipped to avoid recursive proxying.
- Original API protocol set now matches api2py: `openai`, `responses`, `anthropic`, `ollama`; Ollama model discovery can use `/api/tags`.
- `BootstrapService` now reads `/etc/openclaw-prebuilt-rootfs` and reuses the prebuilt OpenClaw version instead of requiring target-version equality and running install/download.
- api2py static UI removed remote Google Fonts and forced serif fonts, reduces animations/transitions on smaller WebViews, debounces search renders, and batches Lucide icon replacement via `requestAnimationFrame`.
- `lib/test.js` guards the new local-relay filtering/default profile, protocol sync, prebuilt marker reuse, and page performance changes.

## Checks
- `npm test` passed 37/37.
- `npm run lint -- --no-warn-ignored` passed.
- `bash -n scripts/build-prebuilt-rootfs.sh scripts/fetch-prebuilt-rootfs-asset.sh scripts/publish-prebuilt-rootfs-asset.sh flutter_app/assets/api2py/start.sh flutter_app/assets/api2py/stop.sh` passed.
- `git diff --check` passed.
- Focused search confirmed no `fonts.googleapis`/`Noto Serif` remain in the api2py page and only the scheduler wrapper calls `window.lucide.createIcons()`.

## Remaining Verification
- Local Flutter/Dart/Kotlin compilers are unavailable in Termux, so Flutter analyze, Android compile, and device/WebView smoke require GitHub Actions or device testing.
- Next APK should be device-smoked for prebuilt OpenClaw reuse, non-recursive API save behavior, protocol choices, and proxy page responsiveness.
