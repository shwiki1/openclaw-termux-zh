# Install Visible Version Name

## Context

Android split APKs were showing confusing version strings during install and in-app settings. The raw `versionCode` from split artifacts can include ABI offsets, and the previous `base+logicalBuildNumber` rule made the installer/app UI surface long strings such as `2.0.50+143` when users only needed a short build series.

## Decision

- Keep the repo anchor in semantic form `x.y.0+build`, with `flutter_app/pubspec.yaml` as the Flutter source of truth and `package.json` aligned for the compatibility CLI baseline.
- Make the APK manifest `versionName` and app UI show the short display form `x.y`.
- Use `2.5.0+143` as the current series anchor in source, so the next fresh artifact starts at display `2.5`.
- Derive future artifact versions automatically from the target build number instead of manually editing the display version for every build:
  `144 -> 2.5.0 / 2.5`, `145 -> 2.6.0 / 2.6`, `146 -> 2.7.0 / 2.7`, `147 -> 2.8.0 / 2.8`, `148 -> 2.9.0 / 2.9`, `149 -> 3.0.0 / 3.0`.
- Keep Android `versionCode` and update comparison numeric build numbers separate from the short display version.
- Drive installer/app synchronization through `flutter.androidVersionName`, `APP_VERSION_NAME`, and `APP_VERSION_DISPLAY`, all derived by the shared build-version helper.

## Consequences

- Install screens and in-app version surfaces now show a short human-readable series such as `2.5`.
- Internal compatibility/version checks still use the derived semantic version plus build number, for example `2.6.0+145`.
- The settings page uses the manifest `versionName` directly.
- Future build automation must keep the shared derivation helper wired into local builds, release-helper builds, and GitHub Actions so installer/app/release metadata stay synchronized.
