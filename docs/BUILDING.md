# Building Liduo

## Tools

Use an Apple silicon Mac, macOS 26+, Xcode 26.4+, and XcodeGen.
Open Xcode once to complete its installation and select it in Settings → Locations
if `xcodebuild -version` points to a different installation.

```sh
brew install xcodegen
./scripts/fetch-sparkle.sh
xcodegen generate
open Liduo.xcodeproj
```

The generated Xcode project is intentionally ignored by Git. Change `project.yml`
when adding files or changing build settings. Sparkle 2.9.6 is the only third-party
runtime dependency; its official archive is checksum-pinned and cached under `.build/`.

## Compile check

```sh
./build.sh check
```

This builds an unsigned arm64 Release app in a temporary directory and prints
its path. It does not install the app or create a public download.
The `LIDUO_DERIVED_DATA` environment variable can select a reusable build directory.

## Build without an Apple certificate

```sh
./build.sh adhoc
```

This creates `dist/Liduo-v0.2.6-macos-arm64-adhoc.zip` and a SHA-256 file without an
Apple account or signing certificate. It is not notarized.

To package that exact app into a drag-to-install DMG:

```sh
brew install uv
./scripts/build-dmg.sh dist/Liduo-v0.2.6-macos-arm64-adhoc.zip
```

The script runs dmgbuild 1.6.7 in an isolated tool environment. It creates
`dist/Liduo-v0.2.6-macos-arm64.dmg` and its SHA-256 file, with a Finder layout,
Applications shortcut, and offline Russian guide. It verifies the disk image,
app signature, and unchanged app contents. Existing output files are never overwritten.
Users do not need uv or any other build tools to install from this DMG.
The background asset can be regenerated with
`xcrun swift installer/dmg/draw-background.swift installer/dmg/background.tiff`.

Only when preparing an update for existing Liduo users, run:

```sh
./scripts/prepare-update.sh dist/Liduo-v0.2.6-macos-arm64-adhoc.zip
```

This uses the existing
Liduo update key in Keychain to sign the feed and archive, and pins the exact archive
hash in the Homebrew cask and npx manifest. Independent forks need their own feed
URL and public/private update key before distributing builds. See [INSTALLING.md](INSTALLING.md)
for first launch and [RELEASING.md](RELEASING.md) for publication.

## Local development build

Choose your own Team in Xcode's Signing & Capabilities, or use an installed
Apple Development certificate with the command-line build:

```sh
security find-identity -v -p codesigning
export LIDUO_TEAM_ID="YOUR_TEAM_ID"
export LIDUO_SIGN_IDENTITY="YOUR_CERTIFICATE_SHA1"
./build.sh development
```

The script creates `dist/Liduo-v0.2.6-local-arm64.zip`. It will not overwrite an
existing archive. The app uses `local.laplapaw.Liduo` as its existing bundle ID;
it is kept stable for current installations. Use a distinct ID for an independent
fork, and expect macOS to ask for screen access for that new application identity.

Development-signed apps are for local testing. Keep the same bundle ID, certificate,
and install location when updating your local app. An ad-hoc signature can invalidate
recognition of previously granted screen access. This workflow does not create or
import certificates, change Keychain settings, or reset system permissions.

## Tests

```sh
./scripts/test.sh unit   # logic and cursor-ownership tests; used in CI
./scripts/test.sh all    # also includes Metal, window, and physical-display tests
```

The complete test suite must run with an unlocked graphical session on a MacBook
with an active built-in display. It displays a full-screen animation briefly.
Do not interpret a hosted runner's inability to present a physical display as a
performance measurement. See [TESTING.md](TESTING.md).

`LIDUO_TEST_RESULTS` can specify a new `.xcresult` path. Xcode refuses to reuse an
existing result bundle. Both scripts build without code signing for test execution.

## Optional diagnostics

For local troubleshooting, launch a development build with:

```sh
open -n /Applications/Liduo.app --args --diagnostics /tmp/liduo-status.json
```

First quit any running copy to avoid two active instances. The file contains
state and frame counters, never screen images. Review it before sharing.

For public application distribution, use [RELEASING.md](RELEASING.md).
