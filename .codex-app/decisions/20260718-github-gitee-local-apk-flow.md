# 2026-07-18 GitHub To Gitee To Local APK Flow

## Decision
All future Android APK update deliveries for this project must use this fixed path:

1. Build the arm64 APK in GitHub Actions.
2. Upload the APK split parts directly from the GitHub Actions runner to a temporary Gitee branch named `apk-transfer-<github-run-id>`.
3. Download locally only from Gitee by cloning that temporary branch.
4. Reassemble the APK into the project directory under `dist/gitee-run-<github-run-id>/`.
5. Verify the reassembled APK with the `.sha256` file from Gitee.
6. Delete the temporary Gitee branch after local verification succeeds.

## Required Local Output Path
The final local APK must be written under this project tree:

`/storage/emulated/0/ZeroTermux/开发/openclaw-termux-zh-5.5/dist/gitee-run-<github-run-id>/<apk-name>.apk`

Do not use a local output directory outside this project's `dist/` for the final APK.

## Forbidden Shortcut
Do not download the GitHub Actions APK artifact to local first and then upload that local file to Gitee as the delivery path. That path does not solve the user's GitHub-to-local download failure problem.

It is acceptable to query GitHub artifact metadata for provenance, but local APK bytes for user installation must come from the Gitee temporary branch.

## Standard Commands
Use the real run ID for `<run-id>` and keep tokens out of logs:

```bash
set -a
. "/storage/emulated/0/ZeroTermux/开发/Git Token/.env"
set +a
run_id=<run-id>
branch="apk-transfer-${run_id}"
repo="https://oauth2:${GITEE_KEY}@gitee.com/cds-y-code/openclaw-termux-zh.git"
clone_dir="/storage/emulated/0/ZeroTermux/开发/gitee-apk-download-${run_id}"
out_dir="/storage/emulated/0/ZeroTermux/开发/openclaw-termux-zh-5.5/dist/gitee-run-${run_id}"
rm -rf "$clone_dir" "$out_dir"
GIT_TERMINAL_PROMPT=0 git clone --depth 1 --branch "$branch" "$repo" "$clone_dir"
mkdir -p "$out_dir"
sha_file=$(find "$clone_dir/apks" -maxdepth 1 -type f -name '*.sha256' | head -n 1)
apk_name=$(basename "$sha_file" .sha256)
cat "$clone_dir/apks/${apk_name}.parts"/part-* > "$out_dir/$apk_name"
(cd "$out_dir" && sha256sum -c "$sha_file")
```

After verification:

```bash
GIT_TERMINAL_PROMPT=0 git push "$repo" --delete "$branch"
```

## Rationale
GitHub direct downloads to the local device are unreliable for the user. Gitee is faster locally, but the APK exceeds Gitee's single-file limit, so the runner must split the APK before uploading and local must clone/reassemble the split parts.
