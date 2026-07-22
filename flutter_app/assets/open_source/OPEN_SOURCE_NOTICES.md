# Open Source Notices And Source Offer

This application includes third-party open source software, runtime binaries,
fonts, assets, and a prebuilt Ubuntu RootFS. Project-owned application code may
be distributed separately from those components; third-party components remain
under their own licenses.

The sections below are the notices and source-offer records shipped with this
APK. Flutter package licenses collected from the app runtime are appended in the
Open Source Licenses screen.

## Third-Party Notices

See `THIRD_PARTY_NOTICES.md` in this asset directory.

## Copyleft Source Offer

See `OPEN_SOURCE_SOURCES.md` in this asset directory.

## GPL/LGPL Handling Summary

- PRoot is distributed under GPL-2.0-or-later as an independent runtime tool.
  The app does not modify PRoot source; corresponding upstream source and build
  provenance are recorded in `OPEN_SOURCE_SOURCES.md`.
- libtalloc and FFmpegKit/FFmpeg libraries are distributed under LGPL-family
  terms. The app does not modify those libraries; replacement/rebuild guidance
  and source locations are recorded in `OPEN_SOURCE_SOURCES.md`.
- The bundled Ubuntu RootFS is an aggregate of packages under mixed open-source
  licenses. Package copyright files are retained under `/usr/share/doc` in the
  generated RootFS where practical, and source repository locations are recorded
  in `OPEN_SOURCE_SOURCES.md`.

## Local Copies

- `THIRD_PARTY_NOTICES.md`
- `OPEN_SOURCE_SOURCES.md`
