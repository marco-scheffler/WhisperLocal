#!/usr/bin/env bash
# Creates a self-signed code-signing certificate "WhisperLocal Dev" in the user's
# login keychain. macOS TCC entries (Microphone / Accessibility / Input Monitoring)
# are bound to the signing identity, so signing with a stable identity makes the
# granted permissions persist across rebuilds.
#
# Idempotent: if the identity already exists, exits successfully.

set -euo pipefail

NAME="WhisperLocal Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "Identity '$NAME' already exists. Nothing to do."
    exit 0
fi

TMP="$(mktemp -d)"
trap "rm -rf $TMP" EXIT

cat > "$TMP/openssl.cnf" <<EOF
[req]
distinguished_name = dn
prompt = no
x509_extensions = v3_codesign

[dn]
CN = $NAME

[v3_codesign]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:FALSE
EOF

# Use macOS LibreSSL (/usr/bin/openssl), not Homebrew's. macOS `security
# import` reads LibreSSL-produced PKCS12 cleanly; Homebrew openssl 3.x
# produces PKCS12 files with MAC encodings the security tool rejects.
OPENSSL=/usr/bin/openssl
if [ ! -x "$OPENSSL" ]; then
    echo "Need /usr/bin/openssl (LibreSSL). Falling back to PATH openssl." >&2
    OPENSSL=$(command -v openssl)
fi

echo "Generating self-signed code-signing certificate (using $OPENSSL)..."
"$OPENSSL" req -x509 -newkey rsa:2048 -days 3650 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -config "$TMP/openssl.cnf" 2>&1 | tail -2

P12PASS="wl-dev-cert"
"$OPENSSL" pkcs12 -export \
    -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$TMP/cert.p12" \
    -passout pass:"$P12PASS"

echo "Importing into login keychain..."
security import "$TMP/cert.p12" -k "$KEYCHAIN" -T /usr/bin/codesign -A -P "$P12PASS"

# Allow codesign and SecurityAgent to use the key without prompting.
security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

echo ""
echo "Done. Verify with: security find-identity -v -p codesigning"
echo "Then rebuild: ./Scripts/make-app-bundle.sh"
