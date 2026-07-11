#!/usr/bin/env bash

set -euo pipefail

REPO="${GITHUB_REPO:-shwiki1/openclaw-termux-zh}"
ARTIFACT_NAME="${ARTIFACT_NAME:-openclaw-apks}"
WORKFLOW_NAME="${WORKFLOW_NAME:-Build OpenClaw Apps}"
DEST_ROOT="${1:-dist}"
RUN_ID="${2:-}"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: missing required command: $1" >&2
    exit 1
  fi
}

require_cmd gh
require_cmd python3

mkdir -p "$DEST_ROOT"

if [ -z "$RUN_ID" ]; then
  RUN_ID="$(
    gh run list \
      --repo "$REPO" \
      --workflow "$WORKFLOW_NAME" \
      --branch main \
      --limit 20 \
      --json databaseId,status,conclusion \
      | python3 -c '
import json
import sys

for run in json.load(sys.stdin):
    if run.get("status") == "completed" and run.get("conclusion") == "success":
        print(run["databaseId"])
        break
' \
  )"
fi

if [ -z "$RUN_ID" ]; then
  echo "ERROR: no successful workflow run found for $REPO" >&2
  exit 1
fi

DEST_DIR="${DEST_ROOT%/}/github-run-${RUN_ID}"
rm -rf "$DEST_DIR"
mkdir -p "$DEST_DIR"

echo "Downloading artifact ${ARTIFACT_NAME} from run ${RUN_ID} into ${DEST_DIR}"
gh run download "$RUN_ID" \
  --repo "$REPO" \
  --name "$ARTIFACT_NAME" \
  --dir "$DEST_DIR"

echo "Downloaded files:"
find "$DEST_DIR" -maxdepth 1 -type f -printf '%f\n' | sort
