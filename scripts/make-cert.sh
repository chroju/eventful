#!/bin/bash
# Create a self-signed code-signing certificate (one-time setup).
#
# NOTE: creating a code-signing certificate purely from the CLI is one of the
# rougher corners of the `security` command, and add-trusted-cert behavior
# varies across macOS versions. If this script fails, fall back to the GUI:
# Keychain Access.app > Certificate Assistant > Create a Certificate...
#   Name: eventful-selfsigned, Certificate Type: Code Signing
set -euo pipefail
CN="eventful-selfsigned"

if security find-certificate -c "$CN" >/dev/null 2>&1; then
  echo "certificate '$CN' already exists; nothing to do"
  exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/ext.cnf" <<'EOF'
[v3]
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
basicConstraints = critical, CA:false
EOF
openssl req -x509 -newkey rsa:2048 -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
  -days 3650 -nodes -subj "/CN=$CN" -extensions v3 -config "$TMP/ext.cnf"
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -out "$TMP/cert.p12" -passout pass:temp
security import "$TMP/cert.p12" -k ~/Library/Keychains/login.keychain-db \
  -P temp -T /usr/bin/codesign
# Trust for code signing (expect an administrator password prompt)
sudo security add-trusted-cert -d -r trustRoot -p codeSign \
  -k /Library/Keychains/System.keychain "$TMP/cert.pem"
echo "OK: certificate '$CN' created"
