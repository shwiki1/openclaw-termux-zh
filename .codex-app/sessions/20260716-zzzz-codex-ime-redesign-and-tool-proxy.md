# 2026-07-16 14:26 UTC - Codex IME Redesign And Tool Proxy Fix

## Goal

Stop iterating on Codex bottom IME compensation and redesign the shortcut path, then inspect and fix the separate Codex tool-calling failure.

## Repo Facts Read

- `flutter_app/lib/screens/terminal_screen.dart`, `flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/NativeTerminalView.kt`, and `flutter_app/lib/widgets/terminal_toolbar.dart`.
- `flutter_app/lib/services/cli_api_config_service.dart` plus `flutter_app/test/cli_api_config_service_test.dart`.
- Existing `.codex-app` state/build/architecture/backlog notes and recent Codex IME session handoffs.

## Changes Made

- Moved Codex terminal shortcuts out of the native bottom platform view and back into Flutter: Codex sessions now render `TerminalToolbar` above the terminal and pass `useNativeToolbar: false`.
- Limited native bottom-padding IME compensation to sessions that still use the native toolbar. Codex sessions now rely on `adjustPan` plus the terminal input-strip visibility helper instead of more bottom compensation logic.
- Fixed the generated Codex OpenAI-compatible proxy so `/v1/responses` compatibility preserves `function_call`, `function_call_output`, and returned `tool_calls` instead of flattening tool traffic into plain text.
- Extended Node-level source guards in `lib/test.js` for the Codex toolbar split and the `responses` tool-call bridge.

## Checks Run

- `npm test` passed with 31 checks.
- `npm run lint -- --no-warn-ignored` passed.
- `git diff --check` passed.
- Local `flutter`, `dart`, and `kotlinc` remain unavailable in this Termux environment, so Flutter analyze/test and native compile checks were not run locally.

## Cloud Build

- No cloud build, push, or release action was run for this redesign/fix pass.

## Version And Artifacts

- Current published release remains `v4.4.0 / 4.4 / 163`, `arm64-v8a` only.
- The next fresh release of this redesign must use a logical build greater than `163`.

## Known Risks

- The Codex shortcut redesign is not yet verified on a real Android device with long transcripts and repeated IME transitions.
- The Codex tool-call proxy fix is structurally covered by source guards only; it still needs live Codex CLI verification against an OpenAI-compatible upstream with real tool turns.
- Flutter/Dart and native compile checks are still unavailable locally.

## Next Actions

1. On Android, verify that the top Codex shortcut bar stays stable through IME open/close and that immediate post-close shortcut taps still work.
2. In a real Codex session, verify tool calls and follow-up tool outputs through the OpenAI-compatible proxy path.
3. If both pass, cut the next arm64 release with a build number greater than `163`.
