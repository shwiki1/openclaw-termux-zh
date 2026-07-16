# Dual Script Assistant

Date: 2026-07-16

## Decision

The browser script assistant presents two distinct libraries: Codex automation workflows and traditional website user scripts. Traditional scripts are stored as source code plus metadata, can be added or pasted for import, and can be saved by Codex through `browser_user_script_save`.

## Safety

Codex may generate and save source but cannot execute it through the save API. The app asks the user for confirmation before running a stored traditional script in the active WebView. Traditional scripts are not a substitute for Tampermonkey's extension APIs; `GM_*` APIs are unavailable in the embedded WebView.

## UI

Wide sheets show two columns; constrained widths stack the columns. This preserves a usable editor and 48dp-class action controls on phones.
