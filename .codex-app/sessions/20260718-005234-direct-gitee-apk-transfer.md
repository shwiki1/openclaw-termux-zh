# 2026-07-18 Direct GitHub Runner To Gitee APK Transfer

## Goal
- Use the correct accelerated delivery path: GitHub Actions runner uploads APK split parts directly to Gitee, then local downloads from Gitee and reassembles the APK.
- Avoid the incorrect path where the APK is first downloaded from GitHub to local and only then uploaded to Gitee.

## Result
- GitHub Actions run `29623644999` succeeded on branch `codex-terminal-ime-lag-fix` at remote commit `c485344e6c51db8ad2987a06d45759f30a66cd62`.
- Workflow step `Upload APK parts to Gitee transfer branch` completed successfully after the workflow was changed to invoke the script with `bash`.
- The runner split `CiYuanXia-v6.5-184-arm64-v8a.apk` into four Gitee-safe parts and pushed them to temporary branch `apk-transfer-29623644999`.

## Repo Facts Read
- Gitee rejects the current APK as a single file because it exceeds the 100MB limit.
- `scripts/upload-apk-parts-to-gitee-branch.sh` is the runner-side split/upload script used by the workflow.
- The final local installable APK must live under this project's `dist/` tree, not an external transfer directory.

## Changes Made
- Added a persistent project decision for the fixed `GitHub Actions -> Gitee split branch -> local dist/` APK delivery flow.
- Updated build/backlog memory to require local reassembly under `/storage/emulated/0/ZeroTermux/开发/openclaw-termux-zh-5.5/dist/gitee-run-<run-id>/`.

## Checks Run
- `gh run watch 29623644999 --repo shwiki1/openclaw-termux-zh --exit-status` completed successfully.
- Local Gitee clone/reassembly verification passed with `sha256sum -c`.
- App memory validation was run after recording the result.

## Cloud Build
- Run `29623644999` completed successfully and uploaded the split APK parts directly from the GitHub runner to Gitee.

## Local Gitee Download Verification
- Local download cloned Gitee branch `apk-transfer-29623644999`; no GitHub APK artifact was downloaded for this verification path.
- Reassembled APK: `dist/gitee-run-29623644999/CiYuanXia-v6.5-184-arm64-v8a.apk`.
- SHA-256: `82ba2aa3d3ed64eaa9a4e7a3b3087f489e5e3f06318419219725e6c3d4ddf447`.
- `sha256sum -c` passed against the checksum file from Gitee.
- Gitee temporary branch `apk-transfer-29623644999` was deleted after verification.

## Build Metadata
- GitHub artifact: `ciyuanxia-apks`, ID `8423154536`, digest `sha256:60786597f847c7ad7bd19baedbea5461ed4b1586f40a78c0f4a0803610f6b7de`.
- Artifact size metadata: `302880497` bytes.
- Gitee split sizes observed locally: `part-00` 94371840 bytes, `part-01` 94371840 bytes, `part-02` 94371840 bytes, `part-03` 33461359 bytes.

## Known Risks
- Gitee may keep unreachable large git objects until server-side garbage collection even after the temporary branch is deleted.
- Device smoke is still required to verify the runtime Codex proxy/config fix inside the installed app.

## Next Actions
- Install and device-smoke `6.5 / 184` from the Gitee-reassembled APK.
- Specifically validate Codex config save: saved upstream must be used through the embedded proxy at `127.0.0.1:8787`, and Codex must not use stale provider config or fail on occupied-port startup.
