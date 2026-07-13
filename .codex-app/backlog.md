# Backlog

## Ready
- Watch the GitHub Actions cloud build for the `2.0.50+134` metadata commit and record artifact details.
- Run Flutter checks in a machine or CI environment with Flutter installed: `cd flutter_app && flutter pub get && flutter analyze && flutter test`.
- Device-smoke Codex browser automation from the terminal screen: self-test, open URL, wait selector, scroll, type, press Enter, select option, capture snapshot.
- Pick the next product/code task and scope it to existing owners: setup/runtime, gateway, node capabilities, terminal, local model, backup, update, or UI polish.
- Review whether `flutter_app/assets/bootstrap/claude-code-2.1.148-bundle.tar.gz` should remain declared/ignored/published under the current resource policy.

## Blocked
- Local Termux environment does not have `flutter`, so Flutter analyze/test/build are blocked locally.
- Cloud build/push/dispatch requires configured GitHub auth (`GH_TOKEN`, `GITHUB_TOKEN`, or `gh auth login`).

## Deferred
- Add device/emulator smoke checklist for first run, setup with local/remote resources, gateway start/stop, Web dashboard, backup/restore, terminal, and update install.
- Reconcile privacy policy/data-safety notes with broad Android permissions and actual logs/config storage behavior.
- Implement or clearly hide/label Canvas capability if it remains an unavailable placeholder.
- Add migration/backward-compatibility notes if config, snapshot, backup, or shared preference schemas change.

## Do Not Forget
- Keep app version/build number updated before every new cloud build.
- Current metadata is aligned at `2.0.50+134`; record the exact GitHub run version/build after the cloud artifact is produced.
- Update `.codex-app/state.md` and the latest session handoff after meaningful changes.
- Preserve `AGENTS.md`: only build/release Android `arm64-v8a` APK unless explicitly asked.
- Keep Codex/Claude CLI installation inside Ubuntu RootFS dedicated prefixes under `/opt/openclaw-cli/<tool>` with wrappers in `/usr/local/bin`.
- Do not switch CLI installation back to plain global `npm install -g`.
