#!/bin/zsh
set -euo pipefail
umask 077
liduo_root="$(cd "$(dirname "$0")/.." && pwd)"
liduo_private="${LIDUO_SIGNING_DIR:-$HOME/Library/Application Support/Liduo/Signing}"
liduo_public="$liduo_root/signing/liduo-release.crt"
[[ ! -e "$liduo_public" && ! -e "$liduo_private/identity.p12" ]] || {
  echo 'A signing identity already exists. Restore its private key; do not replace the certificate.' >&2; exit 2
}
liduo_stage=$(mktemp -d "${TMPDIR:-/private/tmp}/LiduoIdentity.XXXXXX")
trap 'rm -rf "$liduo_stage"' EXIT
cat > "$liduo_stage/certificate.conf" <<'EOF'
[ req ]
prompt = no
distinguished_name = subject
x509_extensions = codesigning
[ subject ]
CN = Liduo Releases
O = Liduo
[ codesigning ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF
/usr/bin/openssl rand -base64 48 > "$liduo_stage/password"
/usr/bin/openssl req -new -x509 -newkey rsa:3072 -nodes -days 7300 \
  -config "$liduo_stage/certificate.conf" -keyout "$liduo_stage/key.pem" -out "$liduo_stage/certificate.pem"
/usr/bin/openssl pkcs12 -export -inkey "$liduo_stage/key.pem" -in "$liduo_stage/certificate.pem" \
  -name 'Liduo Releases' -out "$liduo_stage/identity.p12" -passout "file:$liduo_stage/password"
security add-generic-password -a distribution -s local.laplapaw.Liduo.selfsigned \
  -w "$(cat "$liduo_stage/password")" -T /usr/bin/security
mkdir -p "$liduo_private" "$liduo_root/signing"
chmod 700 "$liduo_private"
cp "$liduo_stage/identity.p12" "$liduo_private/identity.p12"
cp "$liduo_stage/certificate.pem" "$liduo_public"
chmod 644 "$liduo_public"
echo "Encrypted signing identity: $liduo_private/identity.p12"
echo 'Password stored in login Keychain. Back up both; never create a new identity for an update.'
