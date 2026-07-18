#!/usr/bin/env bash
set -euo pipefail

owner="${GITEE_OWNER:-cds-y-code}"
repo="${GITEE_REPO:-openclaw-termux-zh}"
token="${GITEE_TOKEN:-}"
artifact_dir="${ARTIFACT_DIR:-artifacts}"
branch="${GITEE_TRANSFER_BRANCH:-apk-transfer-${GITHUB_RUN_ID:-local}}"
part_size="${GITEE_PART_SIZE:-90m}"

if [[ -z "$token" ]]; then
  echo "GITEE_TOKEN is not configured; skipping Gitee transfer branch upload."
  exit 0
fi

mapfile -t apk_files < <(find "$artifact_dir" -maxdepth 1 -type f -name '*.apk' | sort)
if [[ "${#apk_files[@]}" -ne 1 ]]; then
  echo "Expected exactly one APK in ${artifact_dir}, found ${#apk_files[@]}." >&2
  exit 1
fi

apk_path="${apk_files[0]}"
apk_name="$(basename "$apk_path")"
work_dir="$(mktemp -d)"
cleanup() {
  rm -rf "$work_dir"
}
trap cleanup EXIT

echo "Preparing Gitee transfer branch ${branch} for ${apk_name}."
git -C "$work_dir" init -q
git -C "$work_dir" config user.name "OpenClaw Build Bot"
git -C "$work_dir" config user.email "openclaw-build@example.invalid"
git -C "$work_dir" checkout -q --orphan "$branch"

mkdir -p "$work_dir/apks/${apk_name}.parts"
split -b "$part_size" -d -a 2 "$apk_path" "$work_dir/apks/${apk_name}.parts/part-"
sha256sum "$apk_path" | sed "s#  .*#  ${apk_name}#" > "$work_dir/apks/${apk_name}.sha256"
cat > "$work_dir/README.md" <<EOF
# Temporary APK Transfer

- APK: ${apk_name}
- Source GitHub run: ${GITHUB_RUN_ID:-unknown}
- Source commit: ${GITHUB_SHA:-unknown}
- Reassemble: cat apks/${apk_name}.parts/part-* > ${apk_name}
- Verify: sha256sum -c apks/${apk_name}.sha256

This branch is temporary and can be deleted after local download verification.
EOF

git -C "$work_dir" add README.md apks
git -C "$work_dir" commit -q -m "upload temporary split APK ${GITHUB_RUN_ID:-local}"

remote_url="https://oauth2:${token}@gitee.com/${owner}/${repo}.git"
git -C "$work_dir" remote add gitee "$remote_url"
GIT_TERMINAL_PROMPT=0 git -C "$work_dir" push --force gitee "$branch:$branch"

echo "GITEE_TRANSFER_BRANCH=${branch}" >> "${GITHUB_ENV:-/dev/null}"
echo "Gitee transfer branch uploaded: ${branch}"
