#!/usr/bin/env bash
# Builds the Play Store bundle signed with the UPLOAD key
# (android/upload.properties) and checks the signature. GitHub/sideload APKs
# are built normally (`flutter build apk --release`) and use the app signing
# key from android/key.properties.
set -euo pipefail
cd "$(dirname "$0")/.."

# SHA-256 of the upload certificate (public, not a secret).
UPLOAD_SHA256="82:B0:43:30:3C:FB:E6:94:B1:78:40:D6:A8:91:94:F1:83:B6:27:43:35:A6:40:97:AF:A7:FB:A6:BC:8F:15:5D"
KEYTOOL="${KEYTOOL:-/Applications/Android Studio.app/Contents/jbr/Contents/Home/bin/keytool}"

flutter build appbundle --release -P beandSigning=upload "$@"

AAB=build/app/outputs/bundle/release/app-release.aab
if "$KEYTOOL" -printcert -jarfile "$AAB" | grep -q "SHA256: $UPLOAD_SHA256"; then
  echo "OK: $AAB is signed with the upload key."
else
  echo "ERROR: $AAB is NOT signed with the upload key." >&2
  exit 1
fi
