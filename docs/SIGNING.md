# Stable signing without an Apple Developer subscription

From 0.2.7, public builds use one permanent self-signed certificate. Their
designated requirement contains the bundle ID and certificate fingerprint,
rather than a hash that changes whenever the executable changes. The certificate
does not make the app Apple-notarized or remove the first-launch Gatekeeper step.

## Keep the original identity

- `signing/liduo-release.crt` is the public certificate and belongs in Git.
- The encrypted private identity is `~/Library/Application Support/Liduo/Signing/identity.p12`.
- Its password is in the login Keychain, service `local.laplapaw.Liduo.selfsigned`,
  account `distribution`.
- `LIDUO_SIGNING_DIR` can select a restored private identity folder.

Back up the encrypted identity and its password securely, outside the repository.
Restore both when moving to another signing Mac. Do not generate another
certificate to fix a missing-key error: that would change the app's identity.
The build checks the private identity against the committed public certificate.
DMG and update preparation independently reject a mismatched or ad-hoc signature.

`scripts/create-signing-identity.sh` is a one-time bootstrap, not an update step.
It refuses to replace an existing public certificate or private identity. The
Liduo identity is already created; releases only need `./build.sh selfsigned`.
Independent forks must choose their own bundle ID, certificate, Keychain service,
and Sparkle feed/key. They cannot publish updates for existing Liduo installations.

The certificate lasts 20 years. Signing uses the pinned official rcodesign 0.29.0
tool, with no certificate trust-store changes. All nested Sparkle executables are
signed as part of the bundle. The app is then verified with macOS `codesign`.

## Update signing is separate

Sparkle's existing Ed25519 key still authenticates the feed and downloaded archive.
Do not replace it when changing the application signing setup. App identity and
update authenticity solve different problems; releases need both checks.

## Moving from old builds

Versions up to 0.2.6 used ad-hoc signatures in public downloads. macOS may retain
permission for that old identity rather than the newly installed app. This
transition cannot silently transfer the user's consent to a different identity.

General Settings offers **Доступ включен, но не работает?** when access is denied.
It explains how to remove Liduo from the screen-recording list, add the installed
copy again, and enable access, then opens that macOS settings pane. The app does
not reset permissions itself, edit the TCC database, or change global Gatekeeper settings.
An attempted automatic reset with `tccutil` could not resolve the registered test
bundle on this Mac, so the recovery flow deliberately uses the system interface.

## Verified behavior

On macOS 26.5.1 / MacBook Pro M4 Pro, an isolated app received screen permission.
Its executable was then replaced by a different build signed with the same
self-signed certificate at the same path. `CGPreflightScreenCaptureAccess()`
remained true after relaunch without another permission grant. The certificate
was not installed as a trusted root. An isolated full Liduo also retained access
after a Sparkle update and relaunch; re-signing that copy ad-hoc reproduced the
denied-access state. A second Mac and other macOS versions have
not been tested; keep the bundle ID, certificate, and installation path stable.

Apple describes identity tracking through designated requirements in
[TN2206](https://developer.apple.com/library/archive/technotes/tn2206/_index.html).
