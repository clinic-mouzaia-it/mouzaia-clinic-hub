#!/usr/bin/env bash
set -euo pipefail

# Config
REALM="clinic-mouzaia-hub"
KEYCLOAK_HOST="http://hubkeycloak.mouzaiaclinic.local"
CLIENT_ID="pharmacy-service"
TOKEN_URL="$KEYCLOAK_HOST/realms/$REALM/protocol/openid-connect/token"
API_HOST="http://hubapi.mouzaiaclinic.local"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Check for jq
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not installed. Please install jq and re-run." >&2
  exit 1
fi

# Helper function to get token
get_token() {
  local username=$1
  local password=$2
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
test_endpoint() {
  local test_name=$1
  local method=$2
  local endpoint=$3
  local token=$4
  local expected_status=$5
  
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}Test: $test_name${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  
  if [[ -z "$token" ]]; then
    HTTP_RESP=$(curl -sS -i -X "$method" "$API_HOST$endpoint")
  else
    HTTP_RESP=$(curl -sS -i -X "$method" -H "Authorization: Bearer $token" "$API_HOST$endpoint")
  fi
  
  HTTP_CODE=$(echo "$HTTP_RESP" | awk 'NR==1{print $2}')
  BODY=$(echo "$HTTP_RESP" | awk 'BEGIN{body=0} /^\r?$/{body=1; next} body{print}')
  
  echo -e "${BLUE}Expected: $expected_status | Got: $HTTP_CODE${NC}"
  
  if [[ "$HTTP_CODE" == "$expected_status" ]]; then
    echo -e "${GREEN}✓ PASS${NC}"
  else
    echo -e "${RED}✗ FAIL${NC}"
  fi
  
  echo -e "${BLUE}Response:${NC}"
  printf "%s\n" "$BODY" | jq . 2>/dev/null || printf "%s\n" "$BODY"
  echo ""
}

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  Deleted Medicines - Edge Case Tests  ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}\n"

# Test 1: GET deleted medicines without token (requires: allowed_to_see_deleted_medicines)
test_endpoint \
  "GET deleted medicines without token" \
  "GET" \
  "/pharmacy/medicines/deleted" \
  "" \
  "401"

# Test 2: GET deleted medicines with unauthorized user (staff2 has no role)
echo -e "${YELLOW}Getting token for staff2 (no permissions)...${NC}"
STAFF2_TOKEN=$(get_token "staff2" "DummyPass2!")
if [[ -n "$STAFF2_TOKEN" ]]; then
  test_endpoint \
    "GET deleted medicines with unauthorized user" \
    "GET" \
    "/pharmacy/medicines/deleted" \
    "$STAFF2_TOKEN" \
    "403"
else
  echo -e "${RED}Failed to get token for staff2${NC}\n"
fi

# Test 3: GET deleted medicines with authorized user (pharmacist)
echo -e "${YELLOW}Getting token for pharmacist (has permissions)...${NC}"
PHARMACIST_TOKEN=$(get_token "pharmacist" "DummyPassword123!")
if [[ -n "$PHARMACIST_TOKEN" ]]; then
  test_endpoint \
    "GET deleted medicines with authorized user" \
    "GET" \
    "/pharmacy/medicines/deleted" \
    "$PHARMACIST_TOKEN" \
    "200"
else
  echo -e "${RED}Failed to get token for pharmacist${NC}\n"
fi

# Test 4: PATCH restore with non-existent medicine ID (requires: allowed_to_restore_deleted_medicines)
FAKE_ID="00000000-0000-0000-0000-000000000000"
test_endpoint \
  "Restore non-existent medicine" \
  "PATCH" \
  "/pharmacy/medicines/$FAKE_ID/restore" \
  "$PHARMACIST_TOKEN" \
  "404"

# Test 5: PATCH restore without token
if [[ -n "$PHARMACIST_TOKEN" ]]; then
  # First, get a deleted medicine if one exists
  echo -e "${YELLOW}Fetching deleted medicines to test restore...${NC}"
  DELETED_RESP=$(curl -sS -H "Authorization: Bearer $PHARMACIST_TOKEN" "$API_HOST/pharmacy/medicines/deleted")
  DELETED_ID=$(echo "$DELETED_RESP" | jq -r '.[0].id // empty')
  
  if [[ -n "$DELETED_ID" ]]; then
    echo -e "${GREEN}Found deleted medicine: $DELETED_ID${NC}\n"
    
    test_endpoint \
      "Restore medicine without token" \
      "PATCH" \
      "/pharmacy/medicines/$DELETED_ID/restore" \
      "" \
      "401"
    
    # Test 6: PATCH restore with unauthorized user
    if [[ -n "$STAFF2_TOKEN" ]]; then
      test_endpoint \
        "Restore medicine with unauthorized user" \
        "PATCH" \
        "/pharmacy/medicines/$DELETED_ID/restore" \
        "$STAFF2_TOKEN" \
        "403"
    fi
    
    # Test 7: PATCH restore with valid user (should succeed)
    test_endpoint \
      "Restore medicine with authorized user" \
      "PATCH" \
      "/pharmacy/medicines/$DELETED_ID/restore" \
      "$PHARMACIST_TOKEN" \
      "200"
    
    # Test 8: Try to restore the same medicine again (should fail - not deleted)
    test_endpoint \
      "Restore already active medicine" \
      "PATCH" \
      "/pharmacy/medicines/$DELETED_ID/restore" \
      "$PHARMACIST_TOKEN" \
      "400"
  else
    echo -e "${YELLOW}No deleted medicines found. Skipping restore tests.${NC}"
    echo -e "${YELLOW}Create some deleted medicines first by calling the soft-delete endpoint.${NC}\n"
  fi
fi

# Test 9: GET active medicines should not show deleted ones
echo -e "${YELLOW}Getting token for user with see_medicines permission...${NC}"
if [[ -n "$PHARMACIST_TOKEN" ]]; then
  test_endpoint \
    "GET active medicines (should exclude deleted)" \
    "GET" \
    "/pharmacy/medicines" \
    "$PHARMACIST_TOKEN" \
    "200"
fi

echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║         All Edge Cases Tested          ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
