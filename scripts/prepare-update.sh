#!/bin/zsh
set -euo pipefail
liduo_root="$(cd "$(dirname "$0")/.." && pwd)"
[[ $# -eq 1 ]] || { echo 'Usage: ./scripts/prepare-update.sh dist/Liduo-vVERSION-macos-arm64-selfsigned.zip' >&2; exit 2; }
liduo_archive="${1:A}"
cd "$liduo_root"
./scripts/fetch-sparkle.sh
liduo_bin="$liduo_root/.build/Sparkle-2.9.6/bin"
liduo_account=local.laplapaw.Liduo.updates
liduo_public=$(/usr/libexec/PlistBuddy -c 'Print :SUPublicEDKey' Liduo/Info.plist)
[[ "$("$liduo_bin/generate_keys" --account "$liduo_account" -p)" == "$liduo_public" ]] || {
  echo 'The update key in Keychain does not match the app. Restore the original key; do not generate a replacement.' >&2; exit 2
}
node scripts/prepare-installers.mjs "$liduo_archive"
liduo_version=$(node -p 'JSON.parse(require("fs").readFileSync("package.json", "utf8")).version')
liduo_stage=$(mktemp -d "${TMPDIR:-/private/tmp}/LiduoAppcast.XXXXXX")
trap 'rm -rf "$liduo_stage"' EXIT
cp "$liduo_archive" "$liduo_stage/"
if [[ -f updates/appcast.xml ]]; then cp updates/appcast.xml "$liduo_stage/appcast.xml"; fi
if [[ -f "updates/$liduo_version.md" ]]; then
  cp "updates/$liduo_version.md" "$liduo_stage/${liduo_archive:t:r}.md"
fi
"$liduo_bin/generate_appcast" --account "$liduo_account" --maximum-deltas 0 --maximum-versions 0 \
  --download-url-prefix "https://github.com/cypresskir/Liduo/releases/download/v$liduo_version/" \
  --embed-release-notes -o "$liduo_stage/appcast.xml" "$liduo_stage"
node scripts/verify-update.mjs "$liduo_stage/appcast.xml" "$liduo_archive"
mkdir -p updates
cp "$liduo_stage/appcast.xml" updates/appcast.xml
echo 'Prepared signed updates/appcast.xml. Upload the ZIP first, then publish the feed.'
