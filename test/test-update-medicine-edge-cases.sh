#!/usr/bin/env bash
set -euo pipefail

# Colors and styling
if [[ -t 1 ]]; then
  BOLD="\033[1m"; DIM="\033[2m"; RESET="\033[0m"
  RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[34m"; CYAN="\033[36m"; MAGENTA="\033[35m"
else
  BOLD=""; DIM=""; RESET=""; RED=""; GREEN=""; YELLOW=""; BLUE=""; CYAN=""; MAGENTA=""
fi

title() { echo -e "\n${BOLD}${BLUE}==> $*${RESET}"; }
step()  { echo -e "${BOLD}${CYAN}•${RESET} $*"; }
ok()    { echo -e "${GREEN}✓${RESET} $*"; }
err()   { echo -e "${RED}✗${RESET} $*"; }
info()  { echo -e "${DIM}$*${RESET}"; }

REALM="clinic-mouzaia-hub"
KEYCLOAK_HOST="http://hubkeycloak.mouzaiaclinic.local"
CLIENT_ID="pharmacy-service"
TOKEN_URL="$KEYCLOAK_HOST/realms/$REALM/protocol/openid-connect/token"
API_HOST="http://hubapi.mouzaiaclinic.local"
BASE_ENDPOINT="/pharmacy/medicines"

require_jq() {
  if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is required but not installed. Please install jq and re-run." >&2
    exit 1
  fi
}

get_token() {
  local username="$1"
  local password="$2"
  curl -sS -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=password" \
    -d "client_id=$CLIENT_ID" \
    -d "username=$username" \
    -d "password=$password" \
    "$TOKEN_URL" | jq -r '.access_token // empty'
}

create_medicine() {
  local token="$1"
  local body="$2"
  curl -sS -i -X POST \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "$body" \
    "$API_HOST$BASE_ENDPOINT"
}

soft_delete_medicine() {
  local token="$1"
  local id="$2"
  curl -sS -i -X DELETE \
    -H "Authorization: Bearer $token" \
    "$API_HOST$BASE_ENDPOINT/$id/soft-delete"
}

print_status_and_body() {
  local resp="$1"
  local code=$(echo "$resp" | awk 'NR==1{print $2}')
  local body=$(echo "$resp" | awk 'BEGIN{b=0} /^\r?$/{b=1; next} b{print}')
  echo "Status: $code"
  echo "$body" | (jq . 2>/dev/null || cat)
}

require_jq

title "Update Medicine - Edge Cases"

# Tokens
step "Requesting token for pharmacist"
PHARMACIST_TOKEN=$(get_token "pharmacist" "DummyPassword123!")
if [[ -z "$PHARMACIST_TOKEN" ]]; then echo "Failed to get pharmacist token" >&2; exit 1; fi
step "Requesting token for staff1 (no update role)"
STAFF1_TOKEN=$(get_token "staff1" "DummyPass1!")
if [[ -z "$STAFF1_TOKEN" ]]; then echo "Failed to get staff1 token" >&2; exit 1; fi

# Prepare a medicine to use in tests
step "Creating reference medicine for tests"
CREATE_BODY='{"dci":"EdgeDCI","nomCommercial":"EdgeMed 10mg","stock":5,"cout":0.5,"prixDeVente":1.0}'
CREATE_RESP=$(create_medicine "$PHARMACIST_TOKEN" "$CREATE_BODY")
CREATE_CODE=$(echo "$CREATE_RESP" | awk 'NR==1{print $2}')
CREATE_JSON=$(echo "$CREATE_RESP" | awk 'BEGIN{b=0} /^\r?$/{b=1; next} b{print}')
if [[ "$CREATE_CODE" != "201" ]]; then echo "Failed to create med"; print_status_and_body "$CREATE_RESP"; exit 1; fi
MED_ID=$(echo "$CREATE_JSON" | jq -r '.id')

step "1) No token -> expect 401"
RESP1=$(curl -sS -i -X PATCH \
  -H "Content-Type: application/json" \
  -d '{"stock":9}' \
  "$API_HOST$BASE_ENDPOINT/$MED_ID")
print_status_and_body "$RESP1"
CODE1=$(echo "$RESP1" | awk 'NR==1{print $2}')
[[ "$CODE1" == "401" ]] || { echo "Expected 401"; exit 1; }

step "2) User without role (staff1) -> expect 403"
RESP2=$(curl -sS -i -X PATCH \
  -H "Authorization: Bearer $STAFF1_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"stock":9}' \
  "$API_HOST$BASE_ENDPOINT/$MED_ID")
print_status_and_body "$RESP2"
CODE2=$(echo "$RESP2" | awk 'NR==1{print $2}')
[[ "$CODE2" == "403" ]] || { echo "Expected 403"; exit 1; }

step "3) Non-existent id -> expect 404"
RESP3=$(curl -sS -i -X PATCH \
  -H "Authorization: Bearer $PHARMACIST_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"stock":9}' \
  "$API_HOST$BASE_ENDPOINT/00000000-0000-0000-0000-000000000000")
print_status_and_body "$RESP3"
CODE3=$(echo "$RESP3" | awk 'NR==1{print $2}')
[[ "$CODE3" == "404" ]] || { echo "Expected 404"; exit 1; }

step "4) Empty body -> expect 400"
RESP4=$(curl -sS -i -X PATCH \
  -H "Authorization: Bearer $PHARMACIST_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{}' \
  "$API_HOST$BASE_ENDPOINT/$MED_ID")
print_status_and_body "$RESP4"
CODE4=$(echo "$RESP4" | awk 'NR==1{print $2}')
[[ "$CODE4" == "400" ]] || { echo "Expected 400"; exit 1; }

step "5) Invalid field types (stock:-1, prixDeVente:'x') -> expect 400"
RESP5=$(curl -sS -i -X PATCH \
  -H "Authorization: Bearer $PHARMACIST_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"stock":-1,"prixDeVente":"x"}' \
  "$API_HOST$BASE_ENDPOINT/$MED_ID")
print_status_and_body "$RESP5"
CODE5=$(echo "$RESP5" | awk 'NR==1{print $2}')
[[ "$CODE5" == "400" ]] || { echo "Expected 400"; exit 1; }

step "6) Attempt to update restricted field 'deleted' -> expect 400"
RESP6=$(curl -sS -i -X PATCH \
  -H "Authorization: Bearer $PHARMACIST_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"deleted":false}' \
  "$API_HOST$BASE_ENDPOINT/$MED_ID")
print_status_and_body "$RESP6"
CODE6=$(echo "$RESP6" | awk 'NR==1{print $2}')
[[ "$CODE6" == "400" ]] || { echo "Expected 400"; exit 1; }

step "7) Update on a deleted medicine -> expect 403"
# Create and delete a new medicine
step "Creating and soft-deleting a medicine for test 7"
CREATE2=$(create_medicine "$PHARMACIST_TOKEN" '{"dci":"Del","nomCommercial":"DelMed","stock":1,"cout":0.1,"prixDeVente":0.2}')
C2_CODE=$(echo "$CREATE2" | awk 'NR==1{print $2}')
C2_JSON=$(echo "$CREATE2" | awk 'BEGIN{b=0} /^\r?$/{b=1; next} b{print}')
[[ "$C2_CODE" == "201" ]] || { echo "Failed to create med2"; print_status_and_body "$CREATE2"; exit 1; }
MED2_ID=$(echo "$C2_JSON" | jq -r '.id')
DEL_RESP=$(soft_delete_medicine "$PHARMACIST_TOKEN" "$MED2_ID")
DEL_CODE=$(echo "$DEL_RESP" | awk 'NR==1{print $2}')
[[ "$DEL_CODE" == "200" ]] || { echo "Failed to soft delete med2"; print_status_and_body "$DEL_RESP"; exit 1; }
RESP7=$(curl -sS -i -X PATCH \
  -H "Authorization: Bearer $PHARMACIST_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"stock":3}' \
  "$API_HOST$BASE_ENDPOINT/$MED2_ID")
print_status_and_body "$RESP7"
CODE7=$(echo "$RESP7" | awk 'NR==1{print $2}')
[[ "$CODE7" == "403" ]] || { echo "Expected 403"; exit 1; }

title "${GREEN}✓ Edge case tests passed${RESET}"
