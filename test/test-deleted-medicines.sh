#!/usr/bin/env bash
set -euo pipefail

# Config
REALM="clinic-mouzaia-hub"
KEYCLOAK_HOST="http://hubkeycloak.mouzaiaclinic.local"
CLIENT_ID="pharmacy-service"
USERNAME="pharmacist"
PASSWORD="DummyPassword123!"
TOKEN_URL="$KEYCLOAK_HOST/realms/$REALM/protocol/openid-connect/token"

API_HOST="http://hubapi.mouzaiaclinic.local"
ENDPOINT="/pharmacy/medicines/deleted"

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Usage help
if [[ "${1:-}" == "--help" ]]; then
  cat <<EOF
Usage: $0 [--debug]

Test script for fetching deleted medicines endpoint.
Requires role: allowed_to_see_deleted_medicines

Environment variables:
  USERNAME        Username to authenticate with (default: pharmacist)
  PASSWORD        Password for the user (default: DummyPassword123!)
  CLIENT_ID       Keycloak client_id to use (default: pharmacy-service)
  KEYCLOAK_HOST   Keycloak public URL (default: $KEYCLOAK_HOST)
  API_HOST        API Gateway URL (default: $API_HOST)
EOF
  exit 0
fi

# Check for jq
if ! command -v jq >/dev/null 2>&1; then
  echo "Error: jq is required but not installed. Please install jq and re-run." >&2
  exit 1
fi

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}Testing Deleted Medicines Endpoint${NC}"
echo -e "${BLUE}========================================${NC}\n"

# Get access token using password grant
echo -e "${YELLOW}[1/3] Requesting token for user '$USERNAME' (client_id=$CLIENT_ID, realm=$REALM)...${NC}"
TOKEN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=$CLIENT_ID" \
  -d "username=$USERNAME" \
  -d "password=$PASSWORD" \
  "$TOKEN_URL")

ACCESS_TOKEN=$(echo "$TOKEN_RESP" | jq -r '.access_token // empty')
if [[ -z "${ACCESS_TOKEN}" ]]; then
  echo -e "${RED}Failed to obtain access token. Full response:${NC}" >&2
  echo "$TOKEN_RESP" | jq . >&2 || echo "$TOKEN_RESP" >&2
  exit 1
fi
echo -e "${GREEN}✓ Token obtained successfully${NC}\n"

# Decode JWT payload (base64url decode)
PAYLOAD_RAW=$(echo "$ACCESS_TOKEN" | awk -F. '{print $2}')
BASE64_STD=$(printf "%s" "$PAYLOAD_RAW" | tr '_-' '/+')
PAD_N=$(( (4 - ${#BASE64_STD} % 4) % 4 ))
PADDED="$BASE64_STD$(printf '=%.0s' $(seq 1 $PAD_N))"
DECODED=$(printf "%s" "$PADDED" | base64 -d 2>/dev/null || true)

echo -e "${YELLOW}[2/3] Token Claims:${NC}"
printf "%s" "$DECODED" | jq '{sub, iss, exp, resource_access}'

printf "\n${BLUE}Roles under client pharmacy-service:${NC}\n"
printf "%s" "$DECODED" | jq -r '.resource_access["pharmacy-service"].roles // [] | join(", ")'

# Call the protected endpoint
printf "\n${YELLOW}[3/3] Calling GET %s%s ...${NC}\n" "$API_HOST" "$ENDPOINT"
HTTP_RESP=$(curl -sS -i -H "Authorization: Bearer $ACCESS_TOKEN" "$API_HOST$ENDPOINT")
HTTP_CODE=$(echo "$HTTP_RESP" | awk 'NR==1{print $2}')
BODY=$(echo "$HTTP_RESP" | awk 'BEGIN{body=0} /^\r?$/{body=1; next} body{print}')

echo -e "\n${BLUE}Status: $HTTP_CODE${NC}"

if [[ "$HTTP_CODE" == "200" ]]; then
  echo -e "${GREEN}✓ Success! Retrieved deleted medicines${NC}"
  echo -e "\n${BLUE}Response body:${NC}"
  MEDICINE_COUNT=$(printf "%s\n" "$BODY" | jq 'length')
  echo -e "${YELLOW}Total deleted medicines: $MEDICINE_COUNT${NC}"
  printf "%s\n" "$BODY" | jq '.'
elif [[ "$HTTP_CODE" == "403" ]]; then
  echo -e "${RED}✗ Forbidden: User does not have required role${NC}"
  echo -e "\n${BLUE}Response body:${NC}"
  printf "%s\n" "$BODY" | jq . 2>/dev/null || printf "%s\n" "$BODY"
elif [[ "$HTTP_CODE" == "401" ]]; then
  echo -e "${RED}✗ Unauthorized: Invalid or missing token${NC}"
  echo -e "\n${BLUE}Response body:${NC}"
  printf "%s\n" "$BODY" | jq . 2>/dev/null || printf "%s\n" "$BODY"
else
  echo -e "${RED}✗ Unexpected status code${NC}"
  echo -e "\n${BLUE}Response body:${NC}"
  printf "%s\n" "$BODY" | jq . 2>/dev/null || printf "%s\n" "$BODY"
fi

echo -e "\n${BLUE}========================================${NC}"
echo -e "${BLUE}Test Complete${NC}"
echo -e "${BLUE}========================================${NC}"
