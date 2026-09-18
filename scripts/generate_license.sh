#!/bin/bash
# Issue a NightCat license for a buyer.
#
#   scripts/generate_license.sh buyer@example.com
#
# Prints a `NC1.<payload>.<signature>` license string — send it to the buyer;
# they paste it into Settings ▸ About ▸ Enter License.
#
# Requires the Ed25519 private key generated once via:
#   openssl genpkey -algorithm ed25519 -out license_private.pem
# The key file is gitignored; keep a backup outside this repo.
set -euo pipefail
cd "$(dirname "$0")/.."

EMAIL="${1:?usage: scripts/generate_license.sh buyer@example.com}"
PRIV="${LICENSE_PRIVATE_KEY:-license_private.pem}"
[ -f "$PRIV" ] || { echo "error: private key not found at $PRIV"; exit 1; }

PAYLOAD="NightCat license for $EMAIL"
# Ed25519 one-shot signing needs a real file, not a pipe.
TMP_PAYLOAD=$(mktemp)
printf '%s' "$PAYLOAD" > "$TMP_PAYLOAD"
SIGNATURE=$(openssl pkeyutl -sign -inkey "$PRIV" -rawin -in "$TMP_PAYLOAD" | base64)
rm -f "$TMP_PAYLOAD"
PAYLOAD_B64=$(printf '%s' "$PAYLOAD" | base64)

echo "NC1.$PAYLOAD_B64.$SIGNATURE"
