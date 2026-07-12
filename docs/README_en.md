# CiYuanXia

[简体中文](../README.md) | [English](README_en.md)

CiYuanXia is a community-maintained Android integration app for OpenClaw, focused on Chinese users and mobile-first setup.

## Current Version

- App name: `次元虾`
- Android package: `com.agent.cyx`
- Version name: `2.0.50`
- Build number: `126`
- Release artifact prefix: `CiYuanXia-v`
- The Dart package name remains `openclaw` for compatibility with existing Flutter test imports.

## What It Does

CiYuanXia runs OpenClaw Gateway directly on Android without requiring Termux or root access. The app uses PRoot to run an Ubuntu RootFS, installs Node.js and OpenClaw inside it, and exposes setup, configuration, logs, backup, foreground services, and device capabilities through Flutter and Kotlin.

Main capabilities:

- One-tap setup for Ubuntu RootFS, Node.js, and OpenClaw.
- Chinese-first setup wizard, dashboard, config editor, logs, and backup center.
- AI provider, message platform, optional package, and node capability management.
- Foreground OpenClaw Gateway service with logs and auto-restart.
- Local model tooling for llama.cpp runtime, GGUF model management, and local chat testing.
- Backup export, backup library switching, config restore, and workspace restore.

## Runtime Defaults

- Ubuntu: `24.04.3 noble`
- arm64 / x86_64 Node.js: `24.14.1`
- armv7 / armhf Node.js: `22.22.2`
- OpenClaw: npm `openclaw@latest` stable release, filtering prerelease tags such as beta, rc, test, and preview.

Large runtime resources should not be assumed to be bundled directly in the APK. The app can restore them from the `basic-resource` release, use custom URLs, import local archives, or download from mirrors during first-run setup.

## Build

```bash
cd flutter_app
flutter pub get
flutter build apk --release
```

Release helper:

```bash
python scripts/build_release.py --version 2.0.50 --build-number 126
```

GitHub Actions artifact naming:

```text
CiYuanXia-v2.0.50-126-arm64-v8a.apk
```

## Verification

Available in a Node-only environment:

```bash
npm test
node node_modules/eslint/bin/eslint.js . --no-warn-ignored
```

Full Android verification requires Flutter and Android SDK:

```bash
cd flutter_app
flutter pub get
flutter analyze
flutter test
flutter build apk --release
```

## Upstream Sources

- Android integration upstream: [`mithun50/openclaw-termux`](https://github.com/mithun50/openclaw-termux)
- Translation base branch: [`TIANLI0/openclaw-termux` (`feature/translation`)](https://github.com/TIANLI0/openclaw-termux/tree/feature/translation)
- OpenClaw core: [`openclaw/openclaw`](https://github.com/openclaw/openclaw)

## Disclaimer

This repository is a community-maintained integration variant and is not an official OpenClaw Android release.

## License

MIT. See [LICENSE](../LICENSE).
