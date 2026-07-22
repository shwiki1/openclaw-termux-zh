## Bundled CiYuanXia Ubuntu Rootfs

- Generated artifact: `flutter_app/assets/bootstrap/openclaw-rootfs-noble-arm64.tar.gz`
- Companion manifest: `flutter_app/assets/bootstrap/openclaw-rootfs-noble-arm64.json`
- Generator: `scripts/build-prebuilt-rootfs.sh`
- Ubuntu base: Ubuntu Base 24.04.3 arm64, downloaded from Ubuntu cdimage
  mirrors configured in the generator script.
- Installed Ubuntu packages: `ca-certificates`, `git`, `python3`, `make`,
  `g++`, `curl`, `wget`, `lsof`, plus their transitive dependencies.
- Additional runtime packages: Node.js 24.15.0 arm64 and Python packages
  required by the bundled local API relay (`starlette`, `uvicorn`, `httpx`,
  `aiosqlite`, plus their transitive dependencies). The current prebuilt RootFS
  no longer preinstalls OpenClaw or the OpenClaw QQ/Weixin plugins.

### Source Access

Ubuntu package source code is available from Ubuntu source repositories for
the `noble`, `noble-updates`, `noble-backports`, and `noble-security` suites.
Each package also retains its Debian/Ubuntu copyright metadata under:

- `/usr/share/doc/<package>/copyright`

Node.js source is available from:

- https://github.com/nodejs/node

The generated manifest shipped beside the archive records the resolved package
versions where applicable, bundle fingerprint, SHA256, and build time used for
the current prebuilt bundle and the reusable `basic-resource` GitHub Release.

### Project Modifications

The generated rootfs is not a modified Ubuntu source tree. The build process:

- Configures apt to use domestic Ubuntu mirrors.
- Installs the packages listed above.
- Installs Node.js under `/usr/local`.
- Writes `/root/.npmrc` mirror settings.
- Preinstalls the bundled local API relay Python dependencies.
- Keeps package copyright files under `/usr/share/doc/**/copyright` for
  license inspection while removing non-license documentation, manpages, info
  pages, logs, caches, bytecode, source maps, and test/example trees to reduce
  the APK size.
