#!/bin/bash
# One-time: create a local self-signed code-signing certificate "Shortty Dev" in your login keychain.
# Why: ad-hoc signatures (identity "-") change on every build, so macOS forgets the Screen Recording
# grant each time you rebuild. A fixed certificate keeps the app's identity stable across builds.
set -euo pipefail

NAME="Shortty Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "'$NAME' already exists."
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/req.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
basicConstraints = critical,CA:false
CNF

/usr/bin/openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/req.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
/usr/bin/openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/id.p12" -passout pass:shortty

security import "$TMP/id.p12" -k "$KEYCHAIN" -P shortty -T /usr/bin/codesign -T /usr/bin/security
echo "Trusting the certificate for code signing (macOS will ask for your login password once)…"
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem"

security find-identity -v -p codesigning | grep "\"$NAME\"" || { echo "Certificate not usable; see above."; exit 1; }
# Forget any grant tied to an old ad-hoc build so the next capture prompts cleanly once.
tccutil reset ScreenCapture com.shortty.Shortty >/dev/null 2>&1 || true
echo "Done: '$NAME' ready."
