#!/usr/bin/env bash
set -euo pipefail

# Config
REALM="clinic-mouzaia-hub"
KEYCLOAK_HOST="http://hubkeycloak.mouzaiaclinic.local"
CLIENT_ID="krakend-gateway"
USERNAME="testuser"
PASSWORD="useruser"
TOKEN_URL="$KEYCLOAK_HOST/realms/$REALM/protocol/openid-connect/token"

API_HOST="http://hubapi.mouzaiaclinic.local"
ENDPOINT="/users"

# Optional flag: --debug to hit /users?debug=1
if [[ "${1:-}" == "--debug" ]]; then
  ENDPOINT="$ENDPOINT?debug=1"
  echo "[Debug mode enabled: calling $ENDPOINT]"
fi

# Check for jq
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not installed. Please install jq and re-run." >&2
  exit 1
fi

# Get access token using password grant
echo "Requesting token for user '$USERNAME' (client_id=$CLIENT_ID, realm=$REALM)..."
TOKEN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=$CLIENT_ID" \
  -d "username=$USERNAME" \
  -d "password=$PASSWORD" \
  "$TOKEN_URL")

ACCESS_TOKEN=$(echo "$TOKEN_RESP" | jq -r '.access_token // empty')
if [[ -z "${ACCESS_TOKEN}" ]]; then
  echo "Failed to obtain access token. Full response:" >&2
  echo "$TOKEN_RESP" | jq . >&2 || echo "$TOKEN_RESP" >&2
  exit 1
fi

# Decode JWT payload (base64url decode)
PAYLOAD_RAW=$(echo "$ACCESS_TOKEN" | awk -F. '{print $2}')
# Convert base64url to base64 and pad correctly
BASE64_STD=$(printf "%s" "$PAYLOAD_RAW" | tr '_-' '/+')
PAD_N=$(( (4 - ${#BASE64_STD} % 4) % 4 ))
PADDED="$BASE64_STD$(printf '=%.0s' $(seq 1 $PAD_N))"
DECODED=$(printf "%s" "$PADDED" | base64 -d 2>/dev/null || true)

printf "\nDecoded token claims (subset):\n"
printf "%s" "$DECODED" | jq '{sub, iss, exp, resource_access}'

printf "\nRoles under client krakend-gateway:\n"
printf "%s" "$DECODED" | jq -r '.resource_access["krakend-gateway"].roles // [] | join(", ")'

printf "\nRoles under client identity-service:\n"
printf "%s" "$DECODED" | jq -r '.resource_access["identity-service"].roles // [] | join(", ")'

# Call the protected endpoint
printf "\nCalling %s%s ...\n" "$API_HOST" "$ENDPOINT"
HTTP_RESP=$(curl -sS -i -H "Authorization: Bearer $ACCESS_TOKEN" "$API_HOST$ENDPOINT")
HTTP_CODE=$(echo "$HTTP_RESP" | awk 'NR==1{print $2}')
BODY=$(echo "$HTTP_RESP" | awk 'BEGIN{body=0} /^\r?$/{body=1; next} body{print}')

echo "Status: $HTTP_CODE"
echo "Response body:"
printf "%s\n" "$BODY" | (jq . 2>/dev/null || cat)
