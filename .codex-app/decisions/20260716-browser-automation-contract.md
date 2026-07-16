# Browser Automation Contract

Date: 2026-07-16

## Decision

The in-app browser defaults to the mobile Android user agent. Browser automation now uses a readiness health check, event-aware paste, resource matching, overlay enumeration, coordinate fallback clicking, and tab reset through the existing authenticated loopback bridge.

## Rationale

The previous `loading` flag reflected WebView navigation callbacks only, which is insufficient for hydrated web applications. Mobile UA is the correct default for an Android embedded browser, while desktop remains an explicit per-tab override.

## Constraints

- CSS-selector actions remain the primary deterministic control path.
- `browser_capture_snapshot` is not an image screenshot.
- File upload and bitmap/OCR actions are not implemented: the current Flutter WebView integration does not expose a safe native file-selector or screenshot API. Add them only with a reviewed Android bridge, storage/URI boundary, and user-consent model.
- Automatic pending script drafts are off by default. Explicit `browser_script_stage` remains available, and `browser_set_script_auto_draft` opts in for the current session.
