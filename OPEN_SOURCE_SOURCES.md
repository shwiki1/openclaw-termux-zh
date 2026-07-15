## FFmpegKit Full

- Version: 6.0-2
- License: LGPL-3.0
- Upstream source: https://github.com/arthenica/ffmpeg-kit/tree/v6.0
- Distributed binary source: https://search.maven.org/artifact/com.arthenica/ffmpeg-kit-full/6.0-2/aar
- Included license texts:
  - `third_party/licenses/LGPL-3.0.txt`
  - `third_party/licenses/GPL-3.0.txt`

### How It Is Used

This project links against the prebuilt `ffmpeg-kit-full` Android library to provide local media conversion and audio extraction features inside the floating file manager.

### Relinking / User Replacement

The app package is built from this repository and can be rebuilt with a modified or replacement FFmpegKit binary by changing the Gradle dependency declared in:

- `flutter_app/android/app/build.gradle`

Android release builds are produced from project source with standard Gradle packaging, so users or redistributors can rebuild the application against a modified version of the LGPL library.

### Project Modifications

No modifications are made to FFmpegKit itself. Project-owned code calls the published library APIs from:

- `flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/MediaToolbox.kt`
- `flutter_app/android/app/src/main/kotlin/com/nxg/openclawproot/FloatingFileManagerService.kt`

## Bundled Ubuntu/OpenClaw Rootfs

- Generated artifact: `flutter_app/assets/bootstrap/openclaw-rootfs-noble-arm64.tar.gz`
- Companion manifest: `flutter_app/assets/bootstrap/openclaw-rootfs-noble-arm64.json`
- Generator: `scripts/build-prebuilt-rootfs.sh`
- Ubuntu base: Ubuntu Base 24.04.3 arm64, downloaded from Ubuntu cdimage
  mirrors configured in the generator script.
- Installed Ubuntu packages: `ca-certificates`, `git`, `python3`, `make`,
  `g++`, `curl`, `wget`, `lsof`, plus their transitive dependencies.
- Additional runtime packages: Node.js 24.15.0 arm64,
  `openclaw@latest` (currently resolving to `2026.7.1`),
  `@tencent-connect/openclaw-qqbot@latest` (currently resolving to `2.0.0`),
  and `@tencent-weixin/openclaw-weixin@latest`
  (currently resolving to `2.4.6`).

### Source Access

Ubuntu package source code is available from Ubuntu source repositories for
the `noble`, `noble-updates`, `noble-backports`, and `noble-security` suites.
Each package also retains its Debian/Ubuntu copyright metadata under:

- `/usr/share/doc/<package>/copyright`

Node.js source is available from:

- https://github.com/nodejs/node

OpenClaw and plugin npm package source/provenance is available from:

- https://github.com/openclaw/openclaw
- https://github.com/tencent-connect/openclaw-qqbot
- npm package metadata for `@tencent-weixin/openclaw-weixin`

The generated manifest shipped beside the archive records the resolved package
versions, bundle fingerprint, SHA256, and build time used for the current
prebuilt bundle and the reusable `basic-resource` GitHub Release.

### Project Modifications

The generated rootfs is not a modified Ubuntu source tree. The build process:

- Configures apt to use domestic Ubuntu mirrors.
- Installs the packages listed above.
- Installs Node.js under `/usr/local`.
- Installs OpenClaw and both messaging plugins with npm.
- Writes `/root/.npmrc` mirror settings.
- Enables `openclaw-qqbot` and `openclaw-weixin` in
  `/root/.openclaw/openclaw.json`.
