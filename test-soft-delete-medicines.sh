#!/usr/bin/env bash
set -euo pipefail

# Config
REALM="clinic-mouzaia-hub"
KEYCLOAK_HOST="http://hubkeycloak.mouzaiaclinic.local"
CLIENT_ID="krakend-gateway"
USERNAME="pharmacist"
PASSWORD="DummyPassword123!"
TOKEN_URL="$KEYCLOAK_HOST/realms/$REALM/protocol/openid-connect/token"

API_HOST="http://hubapi.mouzaiaclinic.local"
ENDPOINT="/pharmacy/medicines"

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
BASE64_STD=$(printf "%s" "$PAYLOAD_RAW" | tr '_-' '/+')
PAD_N=$(( (4 - ${#BASE64_STD} % 4) % 4 ))
PADDED="$BASE64_STD$(printf '=%.0s' $(seq 1 $PAD_N))"
DECODED=$(printf "%s" "$PADDED" | base64 -d 2>/dev/null || true)

printf "\nDecoded token claims (subset):\n"
printf "%s" "$DECODED" | jq '{sub, iss, exp, resource_access}'

printf "\nRoles under client krakend-gateway:\n"
printf "%s" "$DECODED" | jq -r '.resource_access["krakend-gateway"].roles // [] | join(", ")'

printf "\nRoles under client pharmacy:\n"
printf "%s" "$DECODED" | jq -r '.resource_access["pharmacy"].roles // [] | join(", ")'

# Step 1: Create a test medicine
printf "\n========================================\n"
printf "Step 1: Creating test medicine...\n"
printf "========================================\n"

TEST_MEDICINE='{"dci":"TestDelete","nomCommercial":"Medicine To Delete","stock":50,"cout":10.00,"prixDeVente":20.00}'

CREATE_RESP=$(curl -sS -i -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$TEST_MEDICINE" \
  "$API_HOST$ENDPOINT")

CREATE_CODE=$(echo "$CREATE_RESP" | awk 'NR==1{print $2}')
CREATE_BODY=$(echo "$CREATE_RESP" | awk 'BEGIN{body=0} /^\r?$/{body=1; next} body{print}')

echo "Status: $CREATE_CODE"

if [[ "$CREATE_CODE" != "201" ]]; then
  echo "✗ Failed to create medicine"
  printf "%s\n" "$CREATE_BODY" | (jq . 2>/dev/null || cat)
  exit 1
fi

echo "✓ Medicine created successfully"
printf "%s\n" "$CREATE_BODY" | jq .

# Extract the medicine ID
MEDICINE_ID=$(printf "%s" "$CREATE_BODY" | jq -r '.id')
echo ""
echo "Medicine ID: $MEDICINE_ID"

# Step 2: Delete the medicine (soft delete)
printf "\n========================================\n"
printf "Step 2: Deleting medicine (soft delete)...\n"
printf "========================================\n"

DELETE_RESP=$(curl -sS -i -X DELETE \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  "$API_HOST$ENDPOINT/$MEDICINE_ID/soft-delete")

DELETE_CODE=$(echo "$DELETE_RESP" | awk 'NR==1{print $2}')
DELETE_BODY=$(echo "$DELETE_RESP" | awk 'BEGIN{body=0} /^\r?$/{body=1; next} body{print}')

echo "Status: $DELETE_CODE"

if [[ "$DELETE_CODE" != "200" ]]; then
  echo "✗ Failed to delete medicine"
  printf "%s\n" "$DELETE_BODY" | (jq . 2>/dev/null || cat)
  exit 1
fi

echo "✓ Medicine soft-deleted successfully"
printf "%s\n" "$DELETE_BODY" | jq .

# Verify the deleted flag is set to true
DELETED_FLAG=$(printf "%s" "$DELETE_BODY" | jq -r '.deleted')
if [[ "$DELETED_FLAG" == "true" ]]; then
  echo ""
  echo "✓ Verified: 'deleted' field is set to true"
else
  echo ""
  echo "✗ Warning: 'deleted' field is not true (value: $DELETED_FLAG)"
fi

printf "\n========================================\n"
printf "Test completed successfully!\n"
printf "========================================\n"
