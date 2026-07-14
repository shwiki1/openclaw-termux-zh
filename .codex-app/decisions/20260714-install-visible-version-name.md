# Install Visible Version Name

## Context

Android split APKs were showing confusing version strings during install and in-app settings. The raw `versionCode` from split artifacts can include ABI offsets, so app settings were ending up with values like `2.0.50+2140` instead of the logical build number.

## Decision

- Make the APK manifest `versionName` equal to `base+logicalBuildNumber`.
- Keep Flutter/App update comparison on base semver plus numeric build number.
- Stop appending raw package `versionCode` in the settings screen.
- Keep `AppConstants.displayVersion` equal to `fullVersion` so app UI matches the installer.

## Consequences

- Install screens now show a changing, human-readable version on every build.
- The settings page uses the manifest `versionName` directly.
- Future build automation must keep `flutter.androidVersionName` or the Gradle fallback in place.

