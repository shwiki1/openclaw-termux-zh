Build-time bootstrap archives live here.

The release workflow generates and packages this archive into the arm64-v8a
APK:

- `openclaw-rootfs-noble-arm64.tar.gz`

It is produced by `scripts/build-prebuilt-rootfs.sh` and includes Ubuntu base
packages, Node.js, OpenClaw, and the QQ/Weixin bot plugins. First-run setup
prefers this bundled archive and only falls back to the standard online flow if
the archive is missing, corrupt, or fails validation.

Other archives in this directory are local caches or manual fallback resources
unless they are explicitly declared in `flutter_app/pubspec.yaml`.

Supported fallback file names match upstream download file names, for example:

- `ubuntu-base-24.04.3-base-arm64.tar.gz`
- `node-v24.15.0-linux-arm64.tar.xz`

Prebuilt rootfs archives for local testing can also be placed here:

- `openclaw-rootfs-noble-arm64.tar.gz`
- `openclaw-rootfs-noble-armhf.tar.gz`
- `openclaw-rootfs-noble-amd64.tar.gz`

The arm64 archive should include at least `ca-certificates git python3 make g++
curl wget lsof`, Node.js, and OpenClaw. If extraction or package detection
fails, setup falls back to the standard Ubuntu base rootfs flow.
