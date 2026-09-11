# Releasing

GitHub releases include source code and an explicitly labelled
**ad-hoc-signed prerelease**. The Apple Development build remains for local use;
it is not the archive used by Homebrew or npx.

## Source publication

1. Run `./scripts/test.sh unit` and, on a physical MacBook, `./scripts/test.sh all`.
2. Review the staged file list: no generated projects, private logs, signing keys,
   credentials, or local application archives.
3. Confirm the version in `project.yml` and update `CHANGELOG.md`.
4. Push `main` only when publication is approved and the new update ZIP is reachable.
5. Run CI on GitHub. Enable private vulnerability reporting in repository settings
   if you want to use the private-reporting path described in `SECURITY.md`.
6. Use [v0.2.6 release notes](releases/v0.2.6.md) for a draft prerelease. Tag the
   reviewed commit. GitHub can generate source archives from that tag.

There is no automatic publish workflow. Pushing source does not upload a binary.

## DMG, Homebrew and npx without a Developer ID certificate

1. Keep the app version in `project.yml` and `package.json` identical.
2. Run `./build.sh adhoc`. This creates `dist/Liduo-v0.2.6-macos-arm64-adhoc.zip`
   and its SHA-256 file without accessing a certificate or Apple account.
   With uv installed, run
   `./scripts/build-dmg.sh dist/Liduo-v0.2.6-macos-arm64-adhoc.zip` to create
   the DMG and its checksum from the same app. The DMG is the main download;
   the ZIP remains necessary for Sparkle, Homebrew, and npx.
3. Run `./scripts/prepare-update.sh dist/Liduo-v0.2.6-macos-arm64-adhoc.zip`.
   The script verifies the app and the Keychain update identity, then updates
   `Casks/liduo.rb`, `installer/release.json`, and the signed `updates/appcast.xml`.
4. Run `npm test`, `ruby -c Casks/liduo.rb`, and the app checks above. Test installation
   on a compatible Mac. Do not describe this as an Apple-notarized build.
5. Commit the installer files along with the source and tag that commit `v0.2.6`.
   Keep files in `dist/` out of Git. With publication authorized, attach the exact
   DMG, ZIP, and both `.sha256` files to the GitHub prerelease. Publish the feed to `main` only
   after that ZIP is reachable. Rebuilding requires regenerating
   signatures, checksum, and installer files before tagging; do not replace tagged assets.
6. Verify the DMG and both alternative installers from [INSTALLING.md](INSTALLING.md)
   against the published release. Update its examples and both READMEs from 0.2.5
   to 0.2.6 and remove the DMG publication-pending notices.

The cask uses a custom tap backed by this same repository. The two-argument `brew tap`
command is required because the repository is named `Liduo`, not `homebrew-liduo`.
npx reads the installer from the GitHub tag; no npm account or `npm publish` is needed.
Subsequent updates can be installed within Liduo using Sparkle. See [UPDATES.md](UPDATES.md).
`package.json` is private to prevent accidental registry publication.

The prepared repository address is `cypresskir/Liduo`. If it changes, update the
address in `scripts/prepare-installers.mjs` and installation examples, then regenerate
the cask and manifest. Both installers must reference the same bytes and checksum.

Ad-hoc signatures do not provide a stable Apple identity across builds. macOS can
ask for screen access again after updates. The DMG retains quarantine and its guide
uses macOS Privacy & Security → Open Anyway for a trusted build. It does not request
global Gatekeeper changes or TCC resets.

## Optional Developer ID and notarized archive

A download recognized by Gatekeeper without an unnotarized-app exception needs a
**Developer ID Application** certificate with its private key and successful Apple
notarization. Apple Development is a
different certificate type. Follow Apple's [Developer ID guide](https://developer.apple.com/developer-id/)
and [notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

Store notarization credentials locally using `xcrun notarytool store-credentials`.
Use the interactive prompts; never add credentials or certificate exports to Git.
Then:

```sh
export LIDUO_TEAM_ID="YOUR_TEAM_ID"
export LIDUO_SIGN_IDENTITY="YOUR_DEVELOPER_ID_CERTIFICATE_SHA1"
./build.sh release
export LIDUO_NOTARY_PROFILE="YOUR_KEYCHAIN_PROFILE"
./scripts/notarize.sh dist/Liduo-v0.2.6-macos-arm64-unnotarized.zip
```

`build.sh release` builds in Release mode, signs with hardened runtime and a
secure timestamp, and rejects a non-Developer-ID signature. The intermediate
archive has `-unnotarized` in its name.

`notarize.sh` uploads that archive to Apple. It checks the submission is accepted,
staples the ticket, verifies it and Gatekeeper assessment, and only then creates:

- `dist/Liduo-v0.2.6-macos-arm64.zip`
- `dist/Liduo-v0.2.6-macos-arm64.zip.sha256`

A failed submission does not create a final download. The script retains temporary
files for diagnosis. Use `notarytool log` with the submission ID and the same
Keychain profile to inspect failures. Retry with a fresh output path or move the
previous output aside; release scripts do not overwrite existing archives.

Before uploading the final pair, test that exact archive on another compatible
Mac, including first-launch permission, quitting during an effect, and sleep/wake.
Do not change the signed bundle after stapling. A notarized download should not
need quarantine removal. Keep the ad-hoc and notarized release channels distinct;
the current installer generator explicitly accepts only the ad-hoc archive.

## Current release boundary

At preparation time, this Mac has Apple Development identities but no Developer ID
Application identity. The notarization script has been syntax-checked; a live
submission cannot be validated without that certificate and a notarization profile.
An ad-hoc archive is prepared locally. Its GitHub download and first-launch behavior
on a second Mac remain unverified until the release is published and tested there.
