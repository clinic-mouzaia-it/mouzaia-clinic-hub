#!/usr/bin/env bash
set -euo pipefail

# Config
REALM="clinic-mouzaia-hub"
KEYCLOAK_HOST="http://hubkeycloak.mouzaiaclinic.local"
CLIENT_ID="krakend-gateway"
API_HOST="http://hubapi.mouzaiaclinic.local"
ENDPOINT="/pharmacy/medicines"

# Check for jq
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not installed. Please install jq and re-run." >&2
  exit 1
fi

# Helper function to get token
get_token() {
  local username=$1
  local password=$2
  TOKEN_URL="$KEYCLOAK_HOST/realms/$REALM/protocol/openid-connect/token"
  
  TOKEN_RESP=$(curl -sS -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=password" \
    -d "client_id=$CLIENT_ID" \
    -d "username=$username" \
    -d "password=$password" \
    "$TOKEN_URL")
  
  echo "$TOKEN_RESP" | jq -r '.access_token // empty'
}

echo "=========================================="
echo "Testing GET /pharmacy/medicines"
echo "=========================================="

# Test 1: No authentication token
printf "\n=== TEST 1: No authentication token ===\n"
RESP=$(curl -sS -i "$API_HOST$ENDPOINT" 2>&1 || true)
HTTP_CODE=$(echo "$RESP" | awk 'NR==1{print $2}')
echo "Status: $HTTP_CODE"
if [[ "$HTTP_CODE" == "401" ]]; then
  echo "✓ PASS - Correctly rejected request without token"
else
  echo "✗ FAIL - Expected 401, got $HTTP_CODE"
fi

# Test 2: Invalid token
printf "\n=== TEST 2: Invalid token ===\n"
RESP=$(curl -sS -i -H "Authorization: Bearer invalid.token.here" "$API_HOST$ENDPOINT" 2>&1 || true)
HTTP_CODE=$(echo "$RESP" | awk 'NR==1{print $2}')
echo "Status: $HTTP_CODE"
if [[ "$HTTP_CODE" == "401" ]]; then
  echo "✓ PASS - Correctly rejected invalid token"
else
  echo "✗ FAIL - Expected 401, got $HTTP_CODE"
fi

# Test 3: Valid token but no permission (staff2 doesn't have allowed_to_see_medicines)
printf "\n=== TEST 3: Valid token without permission ===\n"
echo "Getting token for staff2 (no permissions)..."
STAFF2_TOKEN=$(get_token "staff2" "DummyPass2!")
RESP=$(curl -sS -i -H "Authorization: Bearer $STAFF2_TOKEN" "$API_HOST$ENDPOINT" 2>&1 || true)
HTTP_CODE=$(echo "$RESP" | awk 'NR==1{print $2}')
echo "Status: $HTTP_CODE"
if [[ "$HTTP_CODE" == "403" ]]; then
  echo "✓ PASS - Correctly rejected request without permission"
else
  echo "✗ FAIL - Expected 403, got $HTTP_CODE"
fi

# Test 4: Valid token with permission - list medicines
printf "\n=== TEST 4: Valid request with proper permission ===\n"
echo "Getting token for pharmacist..."
PHARMACIST_TOKEN=$(get_token "pharmacist" "DummyPassword123!")

RESP=$(curl -sS -i -H "Authorization: Bearer $PHARMACIST_TOKEN" "$API_HOST$ENDPOINT")
HTTP_CODE=$(echo "$RESP" | awk 'NR==1{print $2}')
BODY=$(echo "$RESP" | awk 'BEGIN{body=0} /^\r?$/{body=1; next} body{print}')

echo "Status: $HTTP_CODE"
if [[ "$HTTP_CODE" == "200" ]]; then
  echo "✓ PASS - Successfully retrieved medicines"
  echo ""
  echo "Response:"
  printf "%s\n" "$BODY" | jq .
  
  # Count medicines
  COUNT=$(printf "%s" "$BODY" | jq 'length')
  echo ""
  echo "Total medicines returned: $COUNT"
  
  # Check if any deleted medicines are included (should be 0)
  DELETED_COUNT=$(printf "%s" "$BODY" | jq '[.[] | select(.deleted == true)] | length')
  if [[ "$DELETED_COUNT" == "0" ]]; then
    echo "✓ Verified: No deleted medicines in response"
  else
    echo "✗ Warning: Found $DELETED_COUNT deleted medicines in response (should be 0)"
  fi
else
  echo "✗ FAIL - Expected 200, got $HTTP_CODE"
  printf "%s\n" "$BODY" | (jq . 2>/dev/null || cat)
fi

echo ""
echo "=========================================="
echo "Testing complete!"
echo "=========================================="
