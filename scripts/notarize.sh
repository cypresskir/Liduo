#!/bin/zsh
set -euo pipefail
[[ $# -eq 1 ]] || { echo 'Usage: ./scripts/notarize.sh dist/Liduo-vVERSION-macos-arm64-unnotarized.zip' >&2; exit 2; }
: "${LIDUO_NOTARY_PROFILE:?Set LIDUO_NOTARY_PROFILE to a notarytool Keychain profile}"
liduo_archive="${1:A}"
[[ -f "$liduo_archive" ]] || { echo "Archive not found: $liduo_archive" >&2; exit 2; }
[[ "$liduo_archive" == *-macos-arm64-unnotarized.zip ]] || { echo 'Expected an unnotarized release archive from build.sh release' >&2; exit 2; }
liduo_output="${liduo_archive%-unnotarized.zip}.zip"
[[ ! -e "$liduo_output" && ! -e "$liduo_output.sha256" ]] || { echo "Output already exists: $liduo_output" >&2; exit 2; }
liduo_stage="$(mktemp -d "${TMPDIR:-/private/tmp}/LiduoNotarize.XXXXXX")"
ditto -x -k "$liduo_archive" "$liduo_stage"
liduo_app="$liduo_stage/Liduo.app"
codesign --verify --strict -R '=anchor apple generic and certificate leaf[field.1.2.840.113635.100.6.1.13] exists' "$liduo_app"
codesign -d --entitlements :- "$liduo_app" > "$liduo_stage/entitlements.plist" 2>/dev/null
if /usr/libexec/PlistBuddy -c 'Print :com.apple.security.get-task-allow' "$liduo_stage/entitlements.plist" 2>/dev/null | /usr/bin/grep -q true; then
  echo 'Release must not have get-task-allow enabled' >&2
  exit 1
fi
# Validate before uploading; credentials stay in Keychain.
xcrun notarytool submit "$liduo_archive" --keychain-profile "$LIDUO_NOTARY_PROFILE" \
  --wait --output-format json > "$liduo_stage/notarization.json"
/usr/bin/plutil -extract status raw -o - "$liduo_stage/notarization.json" | /usr/bin/grep -qx Accepted
xcrun stapler staple "$liduo_app"
xcrun stapler validate "$liduo_app"
codesign --verify --strict "$liduo_app"
spctl --assess --type execute --verbose=2 "$liduo_app"
ditto -c -k --norsrc --noextattr --keepParent "$liduo_app" "$liduo_output"
(cd "${liduo_output:h}" && shasum -a 256 "${liduo_output:t}" > "${liduo_output:t}.sha256")
echo "Notarized archive: $liduo_output"
echo "Notarization result: $liduo_stage/notarization.json"
