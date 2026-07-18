#!/usr/bin/env bash
set -euo pipefail

owner="${GITEE_OWNER:-cds-y-code}"
repo="${GITEE_REPO:-openclaw-termux-zh}"
token="${GITEE_TOKEN:-}"
artifact_dir="${ARTIFACT_DIR:-artifacts}"
branch="${GITEE_TRANSFER_BRANCH:-apk-transfer-${GITHUB_RUN_ID:-local}}"
part_size="${GITEE_PART_SIZE:-45m}"
push_timeout="${GITEE_PUSH_TIMEOUT:-10m}"
low_speed_limit="${GITEE_LOW_SPEED_LIMIT:-1024}"
low_speed_time="${GITEE_LOW_SPEED_TIME:-60}"

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

remote_url="https://oauth2:${token}@gitee.com/${owner}/${repo}.git"
git -C "$work_dir" remote add gitee "$remote_url"

push_to_gitee() {
  local label="$1"
  shift
  echo "Pushing ${label} to Gitee branch ${branch} with timeout ${push_timeout}."
  GIT_TERMINAL_PROMPT=0 timeout "$push_timeout" \
    git -C "$work_dir" \
      -c http.lowSpeedLimit="$low_speed_limit" \
      -c http.lowSpeedTime="$low_speed_time" \
      push --progress "$@" 2>&1 | sed -E 's#oauth2:[^@]+@#oauth2:***@#g'
}

git -C "$work_dir" add README.md "apks/${apk_name}.sha256"
git -C "$work_dir" commit -q -m "create temporary APK transfer ${GITHUB_RUN_ID:-local}"
push_to_gitee "transfer manifest" --force gitee "$branch:$branch"

mapfile -t part_files < <(find "$work_dir/apks/${apk_name}.parts" -maxdepth 1 -type f -name 'part-*' | sort)
total_parts="${#part_files[@]}"
if [[ "$total_parts" -eq 0 ]]; then
  echo "No split APK parts were created." >&2
  exit 1
fi

part_index=0
for part_file in "${part_files[@]}"; do
  part_index=$((part_index + 1))
  rel_part="${part_file#${work_dir}/}"
  git -C "$work_dir" add "$rel_part"
  git -C "$work_dir" commit -q -m "add APK part ${part_index}/${total_parts} ${GITHUB_RUN_ID:-local}"
  push_to_gitee "APK part ${part_index}/${total_parts}" gitee "$branch:$branch"
done

echo "GITEE_TRANSFER_BRANCH=${branch}" >> "${GITHUB_ENV:-/dev/null}"
echo "Gitee transfer branch uploaded: ${branch}"
