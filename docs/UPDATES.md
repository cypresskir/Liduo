# Updating Liduo

Liduo 0.2.5 includes Sparkle 2.9.6. **Проверить обновления…** is available in the
application menu, menu-bar menu, and General Settings. Automatic checking is off
by default; enabling it checks once a day. Installation always requires consent.
Sparkle downloads, verifies, installs, and relaunches the app. No npx or Terminal
is needed for subsequent in-app updates, regardless of the initial installer.

The Homebrew cask declares `auto_updates true`. To force a Homebrew-managed update,
use `brew upgrade --cask --greedy cypresskir/liduo/liduo` after quitting the app.
Version 0.2.7 and later use the same Liduo signing certificate across updates.
The transition from 0.2.6 or earlier may require granting screen permission once
again. If the system toggle is on but Liduo cannot use it, choose **Доступ включен,
но не работает?** in General Settings. See [SIGNING.md](SIGNING.md).

## Trust and hosting

The feed is `https://raw.githubusercontent.com/cypresskir/Liduo/main/updates/appcast.xml`.
Both the feed and downloaded archive require valid Ed25519 signatures. Archive
verification happens before extraction. Unsigned feeds do not become accepted
after a timeout. The public key is embedded in `Liduo/Info.plist`.

The private key is stored in the macOS login Keychain under Sparkle's service and
the account `local.laplapaw.Liduo.updates`. It is not in the repository, a release
archive, or a CI variable. Do not generate a replacement key for an existing app:
existing users cannot accept updates signed with a different key. Keep a secure
backup when migrating the signing Mac, following Sparkle's key-export instructions.

Automatic checks are opt-in. System profiling is disabled. See [PRIVACY.md](../PRIVACY.md).

## Prepare each update

1. Increase both `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION` in `project.yml`.
   Match `package.json` to the marketing version. Sparkle compares the build number.
2. Add brief user-facing release notes in `updates/VERSION.md`.
3. Build and prepare the exact archive. DMG packaging needs uv; see [BUILDING.md](BUILDING.md).

   ```sh
   ./build.sh selfsigned
   ./scripts/build-dmg.sh dist/Liduo-v0.2.8-macos-arm64-selfsigned.zip
   ./scripts/prepare-update.sh dist/Liduo-v0.2.8-macos-arm64-selfsigned.zip
   npm test
   ./scripts/test.sh unit
   ```

4. The preparation script verifies the Keychain public key matches the app, pins
   the archive hash in both installers, generates the feed using Sparkle's tools,
   and verifies its signature. Existing feed entries keep their original URLs.
5. Publish the tagged source and attach the DMG, ZIP, and both SHA-256 files to GitHub Releases.
   Publish `updates/appcast.xml` to `main` **after the archive is reachable**. An
   existing user must never be offered an archive that has not been uploaded yet.
6. Test an older installed version against the public feed, including install,
   restart, retained settings, and screen permission. Keep the earlier release
   available for manual rollback.

The feed has an embedded signature. Do not edit or reformat it after generation;
rerun the preparation script after any change. `.gitattributes` prevents Git from
converting its line endings. The scripts do not publish anything automatically.

## Build dependency

`scripts/fetch-sparkle.sh` fetches the official Sparkle 2.9.6 binary distribution,
verifies its pinned SHA-256, and caches it under `.build/`. Run it before opening
the generated project in Xcode. Build/test scripts run it automatically. No
third-party binary is committed to Git. Sparkle's complete license notice is
bundled as `Liduo/Sparkle-LICENSE.txt`.

All signed builds sign Sparkle's nested helpers and framework before signing Liduo.
The self-signed channel uses rcodesign 0.29.0, downloaded with a pinned SHA-256.
It uses no hardened-runtime library validation because it has no Apple Team ID.
Developer ID builds retain hardened runtime.

References: [Sparkle setup](https://sparkle-project.org/documentation/),
[SwiftUI integration](https://sparkle-project.org/documentation/programmatic-setup/),
[security settings](https://sparkle-project.org/documentation/customization/),
[nested signing](https://sparkle-project.org/documentation/sandboxing/).
