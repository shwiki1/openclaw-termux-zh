# 2026-07-16 Native Codex Pager

## Decision
- Codex terminal sessions should no longer depend on the Flutter `TerminalScreen` + `TerminalBrowserPanel` mixed layout for the primary path.
- The new primary local prototype is `NativeTerminalPagerActivity`: page 1 native terminal, page 2 native `WebView` browser, both hosted entirely in the Android view tree.
- Browser automation contract stays in Dart for now. `BrowserAutomationService` still owns the loopback bridge, tool aliases, token/env file, and saved-script storage, while `NativeBrowserAutomationDelegate` forwards browser actions into the native browser over `MainActivity`.

## Why
- The IME lag and layout churn are most likely caused by Flutter + `AndroidView` terminal + Flutter browser sidecar relayout interactions.
- Rewriting the entire browser automation stack in Kotlin immediately would be slower and riskier than preserving the existing bridge/script contract and moving only the browser execution surface native first.
- This keeps Codex tool compatibility and script storage stable while testing whether the all-native visible surface fixes the user-reported lag.

## Constraints
- Do not copy GPL ZeroTermux/Termux source.
- Keep `arm64-v8a` as the only build target.
- Do not bump version/build or push cloud builds until the native pager is device-smoked enough to justify a new artifact.

## Follow-up
- Android device smoke for IME smoothness, browser responsiveness, and `browser_*` action parity.
- If parity gaps remain user-visible, decide whether to port script assistant / inspector UI native or fall back selectively.
