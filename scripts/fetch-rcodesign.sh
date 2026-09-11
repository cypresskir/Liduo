#!/bin/zsh
set -euo pipefail
liduo_root="$(cd "$(dirname "$0")/.." && pwd)"
liduo_version=0.29.0
liduo_name="apple-codesign-$liduo_version-aarch64-apple-darwin"
liduo_sha=d1a532150adaf90048260d76359261aa716abafc45c53c5dc18845029184334a
liduo_archive="$liduo_root/.build/$liduo_name.tar.gz"
mkdir -p "$liduo_root/.build"
if [[ ! -f "$liduo_archive" ]]; then
  liduo_download=$(mktemp "$liduo_root/.build/rcodesign-download.XXXXXX")
  trap 'rm -f "$liduo_download"' EXIT
  curl --fail --location --proto '=https' --proto-redir '=https' --retry 2 \
    --connect-timeout 15 --max-time 120 \
    "https://github.com/indygreg/apple-platform-rs/releases/download/apple-codesign/$liduo_version/$liduo_name.tar.gz" \
    --output "$liduo_download"
  [[ "$(shasum -a 256 "$liduo_download" | cut -d ' ' -f 1)" == "$liduo_sha" ]] || { echo 'rcodesign checksum mismatch' >&2; exit 1; }
  mv "$liduo_download" "$liduo_archive"
fi
[[ "$(shasum -a 256 "$liduo_archive" | cut -d ' ' -f 1)" == "$liduo_sha" ]] || { echo 'Cached rcodesign checksum mismatch' >&2; exit 1; }
tar -xzf "$liduo_archive" -C "$liduo_root/.build"
echo "rcodesign $liduo_version ready (SHA-256 verified)."
