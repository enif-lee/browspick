#!/bin/bash
# Creates the dedicated signing keychain + self-signed "Browspick Local Signing"
# identity used by `make bundle`. A stable identity keeps TCC grants (browser
# profile/history file access) valid across rebuilds — adhoc signing changes
# the cdhash every build and silently invalidates them.
#
# The keychain's unlock password is generated randomly and stored as a generic
# password item named "browspick-signing" in the *login* keychain, where the
# Makefile reads it. Run once per machine.
set -euo pipefail

KEYCHAIN="$HOME/Library/Keychains/browspick-signing.keychain-db"
IDENTITY="Browspick Local Signing"
SERVICE="browspick-signing"

if [ -f "$KEYCHAIN" ]; then
  echo "Signing keychain already exists: $KEYCHAIN"
  exit 0
fi

PASSWORD="$(uuidgen | tr -d '-' | tr 'A-F' 'a-f')"

security create-keychain -p "$PASSWORD" "$KEYCHAIN"
security set-keychain-settings "$KEYCHAIN"
security unlock-keychain -p "$PASSWORD" "$KEYCHAIN"
security add-generic-password -s "$SERVICE" -a browspick -w "$PASSWORD" -T /usr/bin/security

# Self-signed code-signing certificate (10 y). -k targets the new keychain.
security create-certificate-identity \
  -c "$IDENTITY" -t codesigning -d 3650 \
  -k "$KEYCHAIN" 2>/dev/null || {
    # Older macOS lacks create-certificate-identity — fall back to certtool.
    TDIR="$(mktemp -d)"
    cat > "$TDIR/cert.conf" <<'CONF'
[ req ]
distinguished_name = dn
x509_extensions = exts
[ dn ]
CN = Browspick Local Signing
[ exts ]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
basicConstraints = critical,CA:false
CONF
    openssl req -x509 -newkey rsa:2048 -keyout "$TDIR/key.pem" \
      -out "$TDIR/cert.pem" -days 3650 -nodes -config "$TDIR/cert.conf" \
      -subj "/CN=$IDENTITY"
    openssl pkcs12 -export -inkey "$TDIR/key.pem" -in "$TDIR/cert.pem" \
      -out "$TDIR/id.p12" -passout pass:"$PASSWORD" -name "$IDENTITY"
    security import "$TDIR/id.p12" -k "$KEYCHAIN" -P "$PASSWORD" \
      -T /usr/bin/codesign -T /usr/bin/security
    rm -rf "$TDIR"
  }

# Let codesign use the key without prompting.
security set-key-partition-list -S apple-tool:,apple:,codesign: \
  -s -k "$PASSWORD" "$KEYCHAIN" >/dev/null

echo "Created $KEYCHAIN with identity '$IDENTITY'."
echo "Unlock password stored in login keychain as '$SERVICE'."
