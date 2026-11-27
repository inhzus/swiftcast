#!/usr/bin/env bash
# Creates the self-signed code signing certificate releases are signed with, once.
#
# Signing every release with the same certificate keeps the app's designated requirement
# stable, so macOS keeps the user's Accessibility grant across updates. Ad-hoc signatures
# change with every build.
#
# Writes build/signing/SwiftCast-Self-Signed.p12 and its password. Keep both secret: anyone
# holding the private key can sign a binary that macOS treats as SwiftCast and hands
# SwiftCast's permissions to. Store them in the MACOS_CERT_P12 / MACOS_CERT_PASSWORD repo
# secrets and a password manager, never in git. Replacing the certificate makes every user
# re-grant permissions once.
set -euo pipefail

cd "$(dirname "$0")/.."

OPENSSL=/usr/bin/openssl # LibreSSL: writes a .p12 that `security import` reads
NAME="SwiftCast Self-Signed"
OUT="build/signing"
P12="$OUT/SwiftCast-Self-Signed.p12"

if [[ -e "$P12" ]]; then
    echo "$P12 already exists; move it away to make a new certificate." >&2
    exit 1
fi

mkdir -p "$OUT"
chmod 700 "$OUT"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = ext
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
subjectKeyIdentifier = hash
EOF

# 20 years: a new certificate means a new designated requirement and a re-grant for everyone.
"$OPENSSL" req -x509 -newkey rsa:2048 -nodes -sha256 -days 7300 \
    -config "$TMP/cert.cnf" -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null

PASSWORD="$("$OPENSSL" rand -base64 24)"
(umask 077
 "$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -name "$NAME" \
     -passout "pass:$PASSWORD" -out "$P12"
 printf '%s' "$PASSWORD" > "$P12.password")

echo "Wrote $P12 and $P12.password"
"$OPENSSL" x509 -in "$TMP/cert.pem" -noout -subject -enddate -fingerprint -sha256
cat <<EOF

Upload it as the release workflow's signing secrets:

  base64 -i $P12 | gh secret set MACOS_CERT_P12
  gh secret set MACOS_CERT_PASSWORD < $P12.password

Then back both files up somewhere safe and delete them from build/.
EOF
