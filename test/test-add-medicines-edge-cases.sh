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

# Helper function to test endpoint
test_case() {
  local description=$1
  local token=$2
  local payload=$3
  local expected_status=$4
  
  printf "\n=== TEST: %s ===\n" "$description"
  
  if [[ -z "$token" ]]; then
    HTTP_RESP=$(curl -sS -i -X POST \
      -H "Content-Type: application/json" \
      -d "$payload" \
      "$API_HOST$ENDPOINT" 2>&1 || true)
  else
    HTTP_RESP=$(curl -sS -i -X POST \
      -H "Authorization: Bearer $token" \
      -H "Content-Type: application/json" \
      -d "$payload" \
      "$API_HOST$ENDPOINT" 2>&1 || true)
  fi
  
  HTTP_CODE=$(echo "$HTTP_RESP" | awk 'NR==1{print $2}')
  BODY=$(echo "$HTTP_RESP" | awk 'BEGIN{body=0} /^\r?$/{body=1; next} body{print}')
  
  echo "Expected: $expected_status | Actual: $HTTP_CODE"
  
  if [[ "$HTTP_CODE" == "$expected_status" ]]; then
    echo "✓ PASS"
  else
    echo "✗ FAIL"
  fi
  
  echo "Response:"
  printf "%s\n" "$BODY" | (jq . 2>/dev/null || cat)
}

echo "=========================================="
echo "Testing POST /pharmacy/medicines Edge Cases"
echo "=========================================="

# Get valid token for pharmacist (has permission)
echo "Getting token for pharmacist..."
PHARMACIST_TOKEN=$(get_token "pharmacist" "DummyPassword123!")

# Get token for staff2 (no permissions)
echo "Getting token for staff2 (no permissions)..."
STAFF2_TOKEN=$(get_token "staff2" "DummyPass2!")

# Test 1: No authentication token
test_case "No authentication token" \
  "" \
  '{"dci":"Test","nomCommercial":"Test Med","cout":5,"prixDeVente":10}' \
  "401"

# Test 2: Invalid/malformed token
test_case "Invalid token" \
  "invalid.token.here" \
  '{"dci":"Test","nomCommercial":"Test Med","cout":5,"prixDeVente":10}' \
  "401"

# Test 3: Valid token but no permission (staff2 doesn't have allowed_to_add_medicines)
test_case "Valid token but no permission" \
  "$STAFF2_TOKEN" \
  '{"dci":"Test","nomCommercial":"Test Med","cout":5,"prixDeVente":10}' \
  "403"

# Test 4: Missing required field (dci)
test_case "Missing required field: dci" \
  "$PHARMACIST_TOKEN" \
  '{"nomCommercial":"Test Med","cout":5,"prixDeVente":10}' \
  "500"

# Test 5: Missing required field (nomCommercial)
test_case "Missing required field: nomCommercial" \
  "$PHARMACIST_TOKEN" \
  '{"dci":"Test","cout":5,"prixDeVente":10}' \
  "500"

# Test 6: Missing required field (cout)
test_case "Missing required field: cout" \
  "$PHARMACIST_TOKEN" \
  '{"dci":"Test","nomCommercial":"Test Med","prixDeVente":10}' \
  "500"

# Test 7: Missing required field (prixDeVente)
test_case "Missing required field: prixDeVente" \
  "$PHARMACIST_TOKEN" \
  '{"dci":"Test","nomCommercial":"Test Med","cout":5}' \
  "500"

# Test 8: Invalid JSON
test_case "Invalid JSON payload" \
  "$PHARMACIST_TOKEN" \
  '{this is not valid json}' \
  "400"

# Test 9: Wrong data type for cout (string instead of number)
test_case "Wrong data type: cout as string" \
  "$PHARMACIST_TOKEN" \
  '{"dci":"Test","nomCommercial":"Test Med","cout":"not-a-number","prixDeVente":10}' \
  "500"

# Test 10: Wrong data type for stock (string instead of number)
test_case "Wrong data type: stock as string" \
  "$PHARMACIST_TOKEN" \
  '{"dci":"Test","nomCommercial":"Test Med","stock":"abc","cout":5,"prixDeVente":10}' \
  "500"

# Test 11: Negative cout value
test_case "Negative cout value" \
  "$PHARMACIST_TOKEN" \
  '{"dci":"Test","nomCommercial":"Test Med","cout":-5,"prixDeVente":10}' \
  "500"

# Test 12: Negative prixDeVente value
test_case "Negative prixDeVente value" \
  "$PHARMACIST_TOKEN" \
  '{"dci":"Test","nomCommercial":"Test Med","cout":5,"prixDeVente":-10}' \
  "500"

# Test 13: Negative stock value
test_case "Negative stock value" \
  "$PHARMACIST_TOKEN" \
  '{"dci":"Test","nomCommercial":"Test Med","stock":-5,"cout":5,"prixDeVente":10}' \
  "500"

# Test 14: Zero cout (should fail, must be > 0)
test_case "Zero cout value" \
  "$PHARMACIST_TOKEN" \
  '{"dci":"Test","nomCommercial":"Test Med","cout":0,"prixDeVente":10}' \
  "500"

# Test 15: Zero prixDeVente (should fail, must be > 0)
test_case "Zero prixDeVente value" \
  "$PHARMACIST_TOKEN" \
  '{"dci":"Test","nomCommercial":"Test Med","cout":5,"prixDeVente":0}' \
  "500"

# Test 16: Zero stock (should pass, >= 0 allowed)
test_case "Zero stock value (valid)" \
  "$PHARMACIST_TOKEN" \
  '{"dci":"Test Stock Zero","nomCommercial":"Test Med","stock":0,"cout":5,"prixDeVente":10}' \
  "201"

# Test 17: Valid minimal payload (only required fields)
test_case "Valid minimal payload" \
  "$PHARMACIST_TOKEN" \
  '{"dci":"Aspirin","nomCommercial":"Aspegic 100mg","cout":1.50,"prixDeVente":3.00}' \
  "201"

# Test 18: Valid complete payload (all fields)
test_case "Valid complete payload" \
  "$PHARMACIST_TOKEN" \
  '{"dci":"Metformin","nomCommercial":"Glucophage 850mg","stock":200,"ddp":"2027-06-30","lot":"LOT-999","cout":4.00,"prixDeVente":8.50}' \
  "201"

echo ""
echo "=========================================="
echo "Edge case testing complete!"
echo "=========================================="
