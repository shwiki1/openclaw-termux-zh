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
