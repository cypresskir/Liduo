#!/bin/zsh
set -euo pipefail
umask 077
[[ $# -eq 1 ]] || { echo 'Usage: scripts/sign-selfsigned.sh APP' >&2; exit 2; }
liduo_root="$(cd "$(dirname "$0")/.." && pwd)"
liduo_app="${1:A}"
liduo_private="${LIDUO_SIGNING_DIR:-$HOME/Library/Application Support/Liduo/Signing}"
liduo_public="$liduo_root/signing/liduo-release.crt"
[[ -f "$liduo_public" && -f "$liduo_private/identity.p12" ]] || { echo 'Restore the original Liduo signing identity before building a release.' >&2; exit 2; }
liduo_stage=$(mktemp -d "${TMPDIR:-/private/tmp}/LiduoSign.XXXXXX")
trap 'rm -rf "$liduo_stage"' EXIT
security find-generic-password -a distribution -s local.laplapaw.Liduo.selfsigned -w > "$liduo_stage/password"
/usr/bin/openssl pkcs12 -in "$liduo_private/identity.p12" -passin "file:$liduo_stage/password" \
  -clcerts -nokeys -out "$liduo_stage/certificate.pem"
liduo_expected=$(/usr/bin/openssl x509 -in "$liduo_public" -noout -fingerprint -sha256)
[[ "$(/usr/bin/openssl x509 -in "$liduo_stage/certificate.pem" -noout -fingerprint -sha256)" == "$liduo_expected" ]] || {
  echo 'Signing certificate changed. Restore the original identity to preserve screen permission.' >&2; exit 2
}
"$liduo_root/scripts/fetch-rcodesign.sh"
"$liduo_root/.build/apple-codesign-0.29.0-aarch64-apple-darwin/rcodesign" sign \
  --p12-file "$liduo_private/identity.p12" --p12-password-file "$liduo_stage/password" \
  --timestamp-url none "$liduo_app"
"$liduo_root/scripts/verify-release-signature.sh" "$liduo_app"
