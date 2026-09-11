# Releasing

The first GitHub publication can be a **source-only prerelease**. The existing
Apple Development build is for local use and must not be attached as the regular
public application download.

## Source publication

1. Run `./scripts/test.sh unit` and, on a physical MacBook, `./scripts/test.sh all`.
2. Review the staged file list: no generated projects, private logs, signing keys,
   credentials, or local application archives.
3. Confirm the version in `project.yml` and update `CHANGELOG.md`.
4. Create the GitHub repository and push `main` only when publication is approved.
5. Run CI on GitHub. Enable private vulnerability reporting in repository settings
   if you want to use the private-reporting path described in `SECURITY.md`.
6. Use [v0.2.3 release notes](releases/v0.2.3.md) for a draft prerelease. Tag the
   reviewed commit. GitHub can generate source archives from that tag.

There is no automatic publish workflow. Pushing source does not upload a binary.

## Public application archive

A normal download for other Macs needs a **Developer ID Application** certificate
with its private key and successful Apple notarization. Apple Development is a
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
./scripts/notarize.sh dist/Liduo-v0.2.3-macos-arm64-unnotarized.zip
```

`build.sh release` builds in Release mode, signs with hardened runtime and a
secure timestamp, and rejects a non-Developer-ID signature. The intermediate
archive has `-unnotarized` in its name.

`notarize.sh` uploads that archive to Apple. It checks the submission is accepted,
staples the ticket, verifies it and Gatekeeper assessment, and only then creates:

- `dist/Liduo-v0.2.3-macos-arm64.zip`
- `dist/Liduo-v0.2.3-macos-arm64.zip.sha256`

A failed submission does not create a final download. The script retains temporary
files for diagnosis. Use `notarytool log` with the submission ID and the same
Keychain profile to inspect failures. Retry with a fresh output path or move the
previous output aside; release scripts do not overwrite existing archives.

Before uploading the final pair, test that exact archive on another compatible
Mac, including first-launch permission, quitting during an effect, and sleep/wake.
Do not change the signed bundle after stapling. Do not disable Gatekeeper or remove
quarantine as an installation instruction for users.

## Current release boundary

At preparation time, this Mac has Apple Development identities but no Developer ID
Application identity. The notarization script has been syntax-checked; a live
submission cannot be validated without that certificate and a notarization profile.
No public binary is declared ready by this repository preparation.
