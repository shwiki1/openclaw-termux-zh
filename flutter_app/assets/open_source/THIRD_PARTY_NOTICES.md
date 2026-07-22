# Third-Party Notices

This file records third-party material used by this repository or distributed
in generated APKs. Project-owned code is licensed under the MIT License in
`LICENSE`; entries below keep their original licenses.

This is engineering compliance documentation, not legal advice. Before a public
release, regenerate notices from the exact dependency lockfile and built APK.

## Flutter SDK and Dart SDK

- Version: resolved by the build environment.
- License: BSD-style.
- Used as: Flutter application framework and Dart runtime/toolchain.
- Upstream: https://github.com/flutter/flutter and https://github.com/dart-lang/sdk
- Source for distributed binary: upstream SDK repositories and release archives.
- Modifications: none.
- Required notices: preserve upstream copyright and BSD-style license text.

## Flutter Pub Dependencies

- Version: resolved from `flutter_app/pubspec.yaml` by `flutter pub get`.
- License: package-specific; most direct dependencies are BSD-style or MIT.
- Used as: Flutter plugins and Dart libraries.
- Upstream: https://pub.dev/
- Source for distributed binary: package archives from pub.dev or mirrored pub
  package hosts.
- Modifications: none.
- Required notices: preserve each package `LICENSE`, `NOTICE`, and copyright.

Direct dependencies currently declared:

- `webview_flutter`, `webview_flutter_android`
- `dio`
- `http`
- `provider`
- `shared_preferences`
- `path_provider`
- `google_fonts`
- `uuid`

## Runtime-Installed CLI Tools

These tools are not bundled inside the APK itself. The app provides official
installers that fetch them into the Ubuntu rootfs at runtime under
`/opt/openclaw-cli/`.

### Google Gemini CLI

- Version: installed from the latest npm release at runtime; verified current
  latest on 2026-07-11 as `0.50.0`.
- License: Apache-2.0.
- Used as: optional CLI tool installed by the app after first-run environment
  setup.
- Upstream: https://github.com/google-gemini/gemini-cli
- Source for distributed binary: npm package `@google/gemini-cli`.
- Modifications: none to upstream package contents; the app adds wrapper
  scripts and workspace config around the installed package.
- Required notices: preserve upstream Apache-2.0 license text when
  redistributing the installed package outside the rootfs.

### Gen CLI

- Version: installed from the latest npm release at runtime; verified current
  latest on 2026-07-11 as `0.1.13`.
- License: Apache-2.0.
- Used as: optional CLI tool installed by the app as the official
  `Generic Agent` implementation.
- Upstream: https://github.com/gen-cli/gen-cli
- Source for distributed binary: npm package `@gen-cli/gen-cli`.
- Modifications: none to upstream package contents; the app adds wrapper
  scripts, workspace config, and an OpenAI-compatible fallback bridge.
- Required notices: preserve upstream Apache-2.0 license text when
  redistributing the installed package outside the rootfs.

### Hermes Agent

- Version: installed from the latest PyPI release at runtime; verified current
  latest on 2026-07-11 as `0.18.2`.
- License: MIT.
- Used as: optional CLI tool installed by the app after first-run environment
  setup.
- Upstream: https://github.com/NousResearch/hermes-agent
- Source for distributed binary: Python package `hermes-agent` from PyPI.
- Modifications: none to upstream package contents; the app adds wrapper
  scripts and generated config files around the installed package.
- Required notices: preserve upstream MIT license text when redistributing the
  installed package outside the rootfs.

## Termux Terminal View

- Version: v0.118.0.
- License: Apache-2.0 for the terminal-view/terminal-emulator library modules
  used by this app.
- Used as: Android native terminal UI and emulator library.
- Upstream: https://github.com/termux/termux-app
- Source for distributed binary: https://github.com/termux/termux-app/tree/v0.118.0
- Modifications: none.
- Required notices: preserve upstream license and notices.

## DejaVu Sans Mono Fonts

- Version: bundled TTF files in `flutter_app/assets/fonts/`.
- License: Bitstream Vera Fonts license and DejaVu font extensions license.
- Used as: monospace UI font for terminal/license text rendering.
- Upstream: https://dejavu-fonts.github.io/
- Source for distributed binary: upstream DejaVu font release archives.
- Modifications: none.
- Required notices: preserve upstream font license and copyright notices.

## @tailwindcss/browser

- Version: 4.3.2.
- License: MIT.
- Used as: local browser-side Tailwind runtime for the bundled api2py
  management frontend.
- Upstream: https://github.com/tailwindlabs/tailwindcss/tree/main/packages/@tailwindcss-browser
- Source for distributed binary: npm package `@tailwindcss/browser@4.3.2`.
- Modifications: none; api2py's local `tailwind.js` copy is bundled at
  `flutter_app/assets/api2py/public/static/lib/tailwind.js`.
- Required notices: preserve upstream MIT license text.

## Lucide

- Version: 1.23.0.
- License: ISC.
- Used as: local UMD icon runtime for the bundled api2py management frontend.
- Upstream: https://github.com/lucide-icons/lucide/tree/main/packages/lucide
- Source for distributed binary: npm package `lucide@1.23.0`.
- Modifications: none; api2py's local `lucide.js` copy is bundled at
  `flutter_app/assets/api2py/public/static/lib/lucide.js`.
- Required notices: preserve upstream ISC license text.

## Lucide Icons

- Version: `main` branch snapshot fetched on 2026-07-08.
- License: ISC License, with a subset of icons additionally covered by the
  Feather MIT license text included in the upstream `LICENSE`.
- Used as: Android PNG UI assets for native terminal and browser controls.
- Upstream: https://github.com/lucide-icons/lucide
- Source for distributed binary: `third_party/lucide/icons/*.svg`
- Modifications: converted selected SVG icons to
  `flutter_app/android/app/src/main/res/drawable-nodpi/lucide_*.png`.
- Required notices: `third_party/licenses/lucide-LICENSE.txt`.

Included icons:

`app-window`, `bot`, `chevron-left`, `clipboard-paste`, `copy`,
`external-link`, `eye`, `eye-off`, `file-code`, `globe`, `hard-drive`,
`layout-list`, `link`, `mouse-pointer-click`, `panel-right`, `play`, `plus`,
`refresh-cw`, `route`, `save`, `scan-search`, `square-pen`, `star`, `trash-2`,
`upload`, `workflow`, `x`

## PRoot From Termux Packages

- Version: resolved from the Termux stable package index at build time.
- License: GPL-2.0-or-later for PRoot.
- Used as: native binary packaged as `libproot.so` plus loader files in APK
  `lib/arm64-v8a/`.
- Upstream: https://github.com/proot-me/proot
- Source for distributed binary: see `OPEN_SOURCE_SOURCES.md`.
- Modifications: renamed/copied into Android `jniLibs`; no source changes.
- Required notices: provide corresponding source for the distributed binary.

## libtalloc From Termux Packages

- Version: resolved from the Termux stable package index at build time.
- License: LGPL-3.0-or-later.
- Used as: native runtime library packaged as `libtalloc.so`.
- Upstream: https://talloc.samba.org/
- Source for distributed binary: see `OPEN_SOURCE_SOURCES.md`.
- Modifications: renamed/copied into Android `jniLibs`; no source changes.
- Required notices: provide library source and modification information.

## libandroid-shmem From Termux Packages

- Version: resolved from the Termux stable package index at build time.
- License: BSD-style.
- Used as: native runtime library packaged as `libandroid-shmem.so`.
- Upstream: https://github.com/termux/libandroid-shmem
- Source for distributed binary: see `OPEN_SOURCE_SOURCES.md`.
- Modifications: renamed/copied into Android `jniLibs`; no source changes.
- Required notices: preserve upstream license and copyright notices.

## Apache Commons Compress

- Version: 1.26.0.
- License: Apache-2.0.
- Used as: Android archive extraction dependency.
- Upstream: https://commons.apache.org/proper/commons-compress/
- Source for distributed binary: Maven Central source artifact or upstream tag.
- Modifications: none.
- Required notices: preserve Apache-2.0 license and NOTICE if present.

## XZ for Java

- Version: 1.9.
- License: public domain / XZ for Java upstream terms.
- Used as: XZ archive support.
- Upstream: https://tukaani.org/xz/java.html
- Source for distributed binary: Maven Central source artifact or upstream source.
- Modifications: none.
- Required notices: record provenance.

## zstd-jni

- Version: 1.5.6-4.
- License: BSD-style.
- Used as: Zstandard archive support.
- Upstream: https://github.com/luben/zstd-jni
- Source for distributed binary: Maven Central source artifact or upstream tag.
- Modifications: none.
- Required notices: preserve upstream license and copyright notices.

## Node.js

- Version: 24.15.0 for arm64, 22.22.3 for armv7 configuration.
- License: MIT-style Node.js license with third-party notices.
- Used as: Node.js runtime inside the bundled/prebuilt proot environment, and
  as a fallback downloaded runtime archive where configured.
- Upstream: https://nodejs.org/
- Source for distributed binary: https://github.com/nodejs/node
- Modifications: none.
- Required notices: preserve Node.js license and included third-party notices.

## Ubuntu Base Rootfs

- Version: Ubuntu Base 24.04.3 ("noble").
- License: mixed open-source package licenses.
- Used as: base Linux rootfs for the bundled/prebuilt proot environment.
- Upstream: https://ubuntu.com/download/base
- Source for distributed binary: Ubuntu source package repositories and package
  copyright files under `/usr/share/doc/*/copyright` inside the installed rootfs.
- Modifications: apt sources are configured to domestic mirrors during setup.
- Required notices: each installed package keeps its own license terms.

## Bundled CiYuanXia Prebuilt Rootfs

- Version: generated at APK build time by `scripts/build-prebuilt-rootfs.sh`
  from Ubuntu Base 24.04.3 for arm64.
- License: aggregate of Ubuntu packages, Node.js, Python packages used by the
  local API relay, and their transitive dependencies; see the component entries
  in this file.
- Used as: `assets/bootstrap/openclaw-rootfs-noble-arm64.tar.gz` packaged
  inside the APK to avoid slow first-run environment and plugin downloads.
- Companion manifest: `assets/bootstrap/openclaw-rootfs-noble-arm64.json`
  records the exact resolved package versions, fingerprint, SHA256, and build
  timestamp used for the current prebuilt bundle and the reusable
  `basic-resource` GitHub Release.
- Upstream: Ubuntu Base, Node.js, PyPI packages used by the bundled local API
  relay, and their transitive dependencies.
- Source for distributed binary: see `OPEN_SOURCE_SOURCES.md` and package
  metadata/license files retained inside the rootfs under npm package folders.
- Modifications: installs base packages, Node.js, local API relay Python
  dependencies, and npm mirror config. The current prebuilt RootFS no longer
  preinstalls OpenClaw or the OpenClaw QQ/Weixin plugins.
- Required notices: preserve all component licenses and provide GPL/LGPL source
  access for system packages included in the generated rootfs. The prebuilt
  cleanup keeps `/usr/share/doc/**/copyright` files while removing other docs,
  manpages, info pages, caches, logs, bytecode, and examples to reduce APK size.
