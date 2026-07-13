# Architecture

## Stack
- Flutter SDK app (`flutter_app/`) using Material 3, Provider, WebView, HTTP/Dio, WebSocket, shared preferences, path provider, permission handler, and native plugins.
- Android native layer in Kotlin (`flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/`) owns PRoot process management, foreground services, terminal, file manager, media helpers, and platform permissions.
- Runtime payload is Ubuntu 24.04 noble RootFS with Node.js/OpenClaw and CLI tooling.
- Root Node.js package (`lib/`, `bin/`) remains as a compatibility/self-test layer for `openclawx`.

## Runtime And Bridge Boundary
- Native/web/runtime boundary: Flutter calls `NativeBridge` (`flutter_app/lib/services/native_bridge.dart`) over `com.agent.cyx/native`; Kotlin returns logs through `com.agent.cyx/gateway_logs` and `com.agent.cyx/setup_logs`; `NativeTerminalView` has per-view native terminal channels.
- Native terminal display boundary: `NativeTerminalView` display transcript rows and repaint throttling are UI-only performance controls. They must not be treated as CLI conversation storage or context state; CLI tools keep their own process state and files inside the RootFS.
- PRoot boundary: `ProcessManager.kt` builds native PRoot commands and bind mounts; `BootstrapManager.kt` creates/extracts RootFS, Node, OpenClaw, config, workspace, and permissions.
- Gateway boundary: Flutter `GatewayProvider`/`GatewayService` control Kotlin `GatewayService`, which starts OpenClaw inside the RootFS and emits logs.
- Node capability boundary: `NodeProvider` connects to OpenClaw over WebSocket and dispatches capability requests to Dart handlers and native permissions.
- Codex browser automation boundary: `BrowserAutomationService` exposes a loopback/token-protected bridge; `BrowserScriptLibraryService` persists saved browser scripts in `shared_preferences`; `TerminalBrowserPanel` executes WebView actions and displays the script directory; `CliApiConfigService` generates `/root/.openclaw/browser-mcp.mjs`, `/root/.openclaw/bin/browser-script`, and `browser-operator` skill files for Codex. The generated tooling keeps both fine-grained MCP tools and a stable `browser_control`/`browser-script call` fallback so Codex can still perform read/type/click/snapshot flows when individual tool exposure is incomplete.
- Codex browser default-page policy: `TerminalBrowserPanel` must load the built-in Codex browser automation instructions by default. Do not auto-load the Gateway dashboard URL or any token-bearing URL unless the user enters it or a Codex browser action explicitly requests it.
- Compact Codex terminal browser sidecar policy: on screens under 960 px wide, `TerminalScreen` keeps `TerminalBrowserPanel` mounted in an in-page `Stack` and slides it offscreen when closed. Do not move this panel back into `Scaffold.endDrawer`, because drawer disposal can unbind the browser automation delegate and disconnect Codex browser tools.
- Generated native platform folder policy: `flutter_app/android/` is committed and meaningful; local Flutter cache/wrapper/generated files are ignored by `.gitignore`.
- Plugin/native module policy: adding Flutter plugins or native dependencies is release-sensitive because it can change permissions, Android SDK/NDK requirements, ProGuard/packaging, and store data-safety claims.

## Module Boundaries
- UI/screens: `flutter_app/lib/screens/*` render setup, dashboard, providers, config, terminal, local model, package, backup, logs, message platform, and settings flows.
- Shared UI: `flutter_app/lib/widgets/*` contains reusable cards, controls, terminal toolbar/view, dialogs, progress and responsive helpers.
- State: `flutter_app/lib/providers/*` owns top-level state and app lifecycle reactions.
- Services: `flutter_app/lib/services/*` owns persistence, config file reads/writes, updates, downloads, native bridge calls, gateway/node/local-model/backup logic.
- Models: `flutter_app/lib/models/*` are plain Dart contracts for gateway, node frames, install options, providers, CLI tools, optional packages, and setup state.
- Native Android: `MainActivity.kt` registers channels and delegates to managers/services; each foreground service owns its own lifecycle.
- Release/build: `scripts/*`, `.github/workflows/flutter-build.yml`, `release/*`, docs and assets.

## Data Flow
- Setup: `SplashScreen` detects setup state -> `SetupWizardScreen` collects options -> `SetupProvider` -> `BootstrapService` -> `NativeBridge` -> `BootstrapManager`/`ProcessManager` -> RootFS/Node/OpenClaw files.
- Gateway: dashboard controls -> `GatewayProvider` -> Dart `GatewayService` -> `NativeBridge` -> Kotlin `GatewayService` -> OpenClaw process -> event-channel logs -> Flutter UI.
- Node: `NodeProvider` starts native foreground service, requests permissions/battery optimization, connects through `NodeService`/`NodeWsService`, parses `NodeFrame`, and invokes capability handlers.
- Config: provider/message platform/API profile services read/write OpenClaw config files, runtime files, and shared preferences; backup services export/restore selected workspace/config data.
- Updates: `UpdateService` reads `AppConstants.appUpdateManifestUrl`, downloads APKs, then `NativeBridge.installApk` opens Android install flow.

## Navigation
- Imperative Flutter navigation via `Navigator.push`, `pushReplacement`, and `MaterialPageRoute`.
- Primary flow: `SplashScreen` -> `SetupWizardScreen` or `DashboardScreen`.
- Dashboard is the hub for gateway controls and feature screens.

## Persistence And Networking
- Persistent preferences: `shared_preferences` through `PreferencesService` and providers.
- Persistent files: Android app files directory, RootFS, `/root/.openclaw` workspace/config, backup exports, downloaded model/runtime/update files.
- Networking: HTTP/Dio downloads for app updates, Ubuntu/Node/OpenClaw resources, release/version queries, model catalog/runtime/model downloads; WebSocket for node/gateway communication.
- Local endpoints: Gateway defaults to `http://127.0.0.1:18789`; local model runtime defaults to localhost ports.
- Android manifest currently allows cleartext traffic for local/internal endpoints.

## API Contracts And Migrations
- API contracts: Method channel method names in `NativeBridge` and `MainActivity.kt`; event channels; JSON node frame structure in `models/node_frame.dart`; OpenClaw config JSON; update manifest response consumed by `UpdateService`; browser bridge actions used by generated Codex MCP.
- Browser MCP tools: `browser_self_test`, `browser_control`, `browser_open`, `browser_back`, `browser_forward`, `browser_reload`, `browser_click`, `browser_type`, `browser_wait_for_text`, `browser_wait_for_selector`, `browser_scroll`, `browser_press_key`, `browser_select_option`, `browser_extract`, `browser_list_links`, `browser_list_interactables`, `browser_highlight`, `browser_capture_snapshot`, `browser_eval`, `browser_script_list`, `browser_script_save`, `browser_script_run`, `browser_script_rename`, `browser_script_delete`, and `browser_get_state`.
- Browser script storage schema: `BrowserScriptLibraryService` stores JSON in shared preference key `browser_automation_scripts_json`. Each script has `id`, `fileName`, `description`, ordered steps with bridge action names and payloads, optional variable names, source URL/title, timestamps, last run time, and run count. Backward compatibility is by tolerant JSON readers and filename normalization.
- Local storage schemas: `shared_preferences` keys in service/provider classes; OpenClaw workspace under RootFS; backup/snapshot JSON formats; CLI API profile/config files.
- Migration strategy: no central migration framework found; schema changes need focused migration code or backward-compatible readers plus tests.
- Rollback considerations: backup restore can overwrite `/root/.openclaw`; RootFS extraction and local model/runtime changes should preserve fallback/retry paths.

## Rules Future Agents Must Preserve
- Prefer existing project patterns.
- Do not introduce new architecture layers without recording a decision.
- Verify facts from source files before changing shared structure.
- Keep Flutter/Kotlin channel contracts in sync on both sides.
- Keep the Codex browser default page as an automation instruction page, not the OpenClaw Gateway dashboard.
- Keep the compact Codex browser sidecar mounted while hidden so browser automation remains attached after users close the right slide-in panel.
- Keep `browser_control` and `browser-script call/control` as stable fallbacks alongside fine-grained browser MCP tools; do not rely on individual tool discovery alone for browser form automation.
- Keep saved Codex browser scripts limited to deterministic bridge actions by default; `browser_eval` should remain a live/manual escape hatch unless a future decision explicitly expands saved-script permissions.
- Build and release only `arm64-v8a` APK unless the user explicitly asks otherwise.
- Install Codex/Claude CLI tooling inside the Ubuntu RootFS under `/opt/openclaw-cli/<tool>` with wrappers in `/usr/local/bin`; do not revert to fragile global npm installs.
- Treat permissions, signing, app ID/package, JNI/PRoot binaries, RootFS assets, and dependency changes as release-critical.
