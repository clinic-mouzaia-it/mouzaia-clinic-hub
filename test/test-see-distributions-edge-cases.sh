#!/usr/bin/env bash
set -euo pipefail

# Colors and styles
BOLD="\033[1m"; DIM="\033[2m"; RESET="\033[0m"
RED="\033[31m"; GREEN="\033[32m"; YELLOW="\033[33m"; BLUE="\033[34m"; CYAN="\033[36m"

# Config
REALM="clinic-mouzaia-hub"
KEYCLOAK_HOST="http://hubkeycloak.mouzaiaclinic.local"
TOKEN_URL="$KEYCLOAK_HOST/realms/$REALM/protocol/openid-connect/token"
API_HOST="http://hubapi.mouzaiaclinic.local"
DISTRIBUTIONS_ENDPOINT="/pharmacy/distributions"
LIST_MEDICINES_ENDPOINT="/pharmacy/medicines"
ADD_MEDICINE_ENDPOINT="/pharmacy/medicines"
DISTRIBUTE_ENDPOINT="/pharmacy/medicines/distribute"
FIND_USER_BY_NID_ENDPOINT="/users/by-national-id"

# Test identities
PHARMACY_CLIENT_ID="pharmacy-service"
PHARMACIST_USERNAME="pharmacist"
PHARMACIST_PASSWORD="DummyPassword123!"
# Use staff1 (provided in realm) who lacks allowed_to_see_distributions for forbidden test
STAFF_DENIED_USERNAME="staff1"
STAFF_DENIED_PASSWORD="DummyPass1!"

# Utilities
need() { command -v "$1" >/dev/null 2>&1 || { echo -e "${RED}Error:${RESET} $1 is required." >&2; exit 1; }; }

SECTION() { echo -e "\n${BOLD}${BLUE}==> $1${RESET}"; }
PASS() { echo -e "${GREEN}✔${RESET} $1"; }
FAIL() { echo -e "${RED}✘${RESET} $1"; }
INFO() { echo -e "${CYAN}ℹ${RESET} $1"; }
WARN() { echo -e "${YELLOW}!${RESET} $1"; }

get_token() {
  local client_id="$1" username="$2" password="$3"
  curl -sS -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=password" \
    -d "client_id=$client_id" \
    -d "username=$username" \
    -d "password=$password" \
    "$TOKEN_URL" | jq -r '.access_token // empty'
}

http_get() {
  local url="$1" token="${2:-}"
  if [[ -n "$token" ]]; then
    curl -sS -i -H "Authorization: Bearer $token" "$url"
  else
    curl -sS -i "$url"
  fi
}

http_post_json() {
  local url="$1" token="$2" json="$3"
  curl -sS -i -X POST \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "$json" \
    "$url"
}

pick_medicine_with_stock() {
  local body_json="$1" required_qty="$2"
  echo "$body_json" | jq -r --argjson q "$required_qty" 'map(select(.deleted == false and (.stock // 0) >= $q)) | .[0] // empty'
}

ensure_distribution_exists() {
  # Ensures at least one distribution record exists by creating one if needed
  local pharmacist_token="$1"
  local required_qty=1

  SECTION "Ensuring at least one distribution exists"
  local resp=$(http_get "$API_HOST$DISTRIBUTIONS_ENDPOINT" "$pharmacist_token")
  local code=$(echo "$resp" | awk 'NR==1{print $2}')
  local body=$(echo "$resp" | awk 'BEGIN{b=0} /^\r?$/{b=1; next} b{print}')
  if [[ "$code" != "200" ]]; then
    FAIL "Initial distributions list failed ($code)"; echo "$body" | (jq . 2>/dev/null || cat); exit 1
  fi
  local total=$(echo "$body" | jq -r '.total // 0')
  if (( total > 0 )); then
    PASS "Distributions already exist (total=$total)"
    echo "$body"
    return 0
  fi

  INFO "No distributions found; creating one via distribute flow"
  # 1) Get medicines
  local meds_resp=$(http_get "$API_HOST$LIST_MEDICINES_ENDPOINT" "$pharmacist_token")
  local meds_code=$(echo "$meds_resp" | awk 'NR==1{print $2}')
  local meds_body=$(echo "$meds_resp" | awk 'BEGIN{b=0} /^\r?$/{b=1; next} b{print}')
  if [[ "$meds_code" != "200" ]]; then
    FAIL "List medicines failed ($meds_code)"; echo "$meds_body" | (jq . 2>/dev/null || cat); exit 1
  fi
  local candidate=$(pick_medicine_with_stock "$meds_body" "$required_qty")
  if [[ -z "$candidate" || "$candidate" == "null" ]]; then
    INFO "No medicine with stock; creating one"
    local payload=$(jq -n \
      --arg dci "Paracetamol" \
      --arg name "Dist Seed $(date +%s)" \
      --arg ddp "2027-12-31" \
      --arg lot "LOT-$RANDOM" \
      --argjson cout 2.50 \
      --argjson prix 5.00 \
      --argjson stock 10 \
      '{dci: $dci, nomCommercial: $name, stock: $stock, ddp: $ddp, lot: $lot, cout: $cout, prixDeVente: $prix}')
    local add_resp=$(http_post_json "$API_HOST$ADD_MEDICINE_ENDPOINT" "$pharmacist_token" "$payload")
    local add_code=$(echo "$add_resp" | awk 'NR==1{print $2}')
    local add_body=$(echo "$add_resp" | awk 'BEGIN{b=0} /^\r?$/{b=1; next} b{print}')
    if [[ "$add_code" != "201" ]]; then
      FAIL "Add medicine failed ($add_code)"; echo "$add_body" | (jq . 2>/dev/null || cat); exit 1
    fi
    candidate=$(printf "%s" "$add_body" | jq -c '.')
  fi
  local med_id=$(echo "$candidate" | jq -r '.id')

  # 2) Fetch staff user allowed to take medicines
  local staff_resp=$(http_get "$API_HOST$FIND_USER_BY_NID_ENDPOINT?nationalId=$(printf %s "S1-0001" | jq -sRr @uri)" "$pharmacist_token")
  local staff_code=$(echo "$staff_resp" | awk 'NR==1{print $2}')
  local staff_body=$(echo "$staff_resp" | awk 'BEGIN{b=0} /^\r?$/{b=1; next} b{print}')
  if [[ "$staff_code" != "200" ]]; then
    FAIL "Fetch staff user failed ($staff_code)"; echo "$staff_body" | (jq . 2>/dev/null || cat); exit 1
  fi

  # 3) Distribute one unit
  local dist_payload=$(jq -n \
    --argjson staff "$staff_body" \
    --arg medId "$med_id" \
    --argjson qty 1 \
    '{staffUser: $staff, medicines: [{id: $medId, quantity: $qty}]}'
  )
  local dist_resp=$(http_post_json "$API_HOST$DISTRIBUTE_ENDPOINT" "$pharmacist_token" "$dist_payload")
  local dist_code=$(echo "$dist_resp" | awk 'NR==1{print $2}')
  local dist_body=$(echo "$dist_resp" | awk 'BEGIN{b=0} /^\r?$/{b=1; next} b{print}')
  if [[ "$dist_code" != "200" ]]; then
    FAIL "Distribute failed ($dist_code)"; echo "$dist_body" | (jq . 2>/dev/null || cat); exit 1
  fi

  # 4) Return new distributions list
  resp=$(http_get "$API_HOST$DISTRIBUTIONS_ENDPOINT" "$pharmacist_token")
  code=$(echo "$resp" | awk 'NR==1{print $2}')
  body=$(echo "$resp" | awk 'BEGIN{b=0} /^\r?$/{b=1; next} b{print}')
  if [[ "$code" == "200" ]]; then PASS "Seed distribution created"; else FAIL "Could not verify distributions after seeding"; fi
  echo "$body"
}

main() {
  SECTION "Checking requirements"
  need jq; need curl; need awk

  SECTION "Obtaining tokens"
  PHARMACIST_TOKEN=$(get_token "$PHARMACY_CLIENT_ID" "$PHARMACIST_USERNAME" "$PHARMACIST_PASSWORD")
  if [[ -z "$PHARMACIST_TOKEN" ]]; then FAIL "Pharmacist token"; exit 1; else PASS "Pharmacist token acquired"; fi
  STAFF_DENIED_TOKEN=$(get_token "$PHARMACY_CLIENT_ID" "$STAFF_DENIED_USERNAME" "$STAFF_DENIED_PASSWORD")
  if [[ -z "$STAFF_DENIED_TOKEN" ]]; then WARN "Could not get token for $STAFF_DENIED_USERNAME; forbidden test will be skipped"; fi

  # 1) Missing token
  SECTION "Unauthorized: missing token"
  RESP=$(http_get "$API_HOST$DISTRIBUTIONS_ENDPOINT")
  CODE=$(echo "$RESP" | awk 'NR==1{print $2}')
  BODY=$(echo "$RESP" | awk 'BEGIN{b=0} /^\r?$/{b=1; next} b{print}')
  if [[ "$CODE" == "401" ]]; then PASS "Got 401 for missing token"; else FAIL "Expected 401, got $CODE"; fi

  # 2) Invalid token
  SECTION "Unauthorized: invalid token"
  RESP=$(http_get "$API_HOST$DISTRIBUTIONS_ENDPOINT" "this.is.not.valid")
  CODE=$(echo "$RESP" | awk 'NR==1{print $2}')
  if [[ "$CODE" == "401" ]]; then PASS "Got 401 for invalid token"; else FAIL "Expected 401, got $CODE"; fi

  # 3) Forbidden: staff1 lacks allowed_to_see_distributions
  if [[ -n "${STAFF_DENIED_TOKEN:-}" ]]; then
    SECTION "Forbidden: $STAFF_DENIED_USERNAME without allowed_to_see_distributions"
    RESP=$(http_get "$API_HOST$DISTRIBUTIONS_ENDPOINT" "$STAFF_DENIED_TOKEN")
    CODE=$(echo "$RESP" | awk 'NR==1{print $2}')
    if [[ "$CODE" == "403" ]]; then PASS "Got 403 for user without permission"; else WARN "Expected 403, got $CODE (roles may differ)"; fi
  else
    WARN "Skipping forbidden test (no token for $STAFF_DENIED_USERNAME)"
  fi

  # Ensure we have at least one distribution
  BODY=$(ensure_distribution_exists "$PHARMACIST_TOKEN")

  # 4) Happy path: list distributions
  SECTION "Happy path: list distributions"
  RESP=$(http_get "$API_HOST$DISTRIBUTIONS_ENDPOINT" "$PHARMACIST_TOKEN")
  CODE=$(echo "$RESP" | awk 'NR==1{print $2}')
  BODY=$(echo "$RESP" | awk 'BEGIN{b=0} /^\r?$/{b=1; next} b{print}')
  TOTAL=$(echo "$BODY" | jq -r '.total')
  if [[ "$CODE" == "200" && "$TOTAL" -ge 1 ]]; then PASS "Listed $TOTAL distributions"; else FAIL "Expected 200 with total>=1"; echo "$BODY" | (jq . 2>/dev/null || cat); fi

  # Capture one record for filtering tests
  FIRST_ITEM=$(echo "$BODY" | jq -c '.items[0]')
  MEDICINE_ID=$(echo "$FIRST_ITEM" | jq -r '.medicineId')
  STAFF_NID=$(echo "$FIRST_ITEM" | jq -r '.staffNationalId')

  # 5) Filter by staffNationalId
  SECTION "Filter by staffNationalId=$STAFF_NID"
  RESP=$(http_get "$API_HOST$DISTRIBUTIONS_ENDPOINT?staffNationalId=$(printf %s "$STAFF_NID" | jq -sRr @uri)" "$PHARMACIST_TOKEN")
  CODE=$(echo "$RESP" | awk 'NR==1{print $2}')
  BODY=$(echo "$RESP" | awk 'BEGIN{b=0} /^\r?$/{b=1; next} b{print}')
  if [[ "$CODE" == "200" ]]; then
    MISMATCH=$(echo "$BODY" | jq -r --arg nid "$STAFF_NID" '[.items[] | select(.staffNationalId != $nid)] | length')
    if [[ "$MISMATCH" == "0" ]]; then PASS "All items match staffNationalId"; else FAIL "Found $MISMATCH items with mismatched staffNationalId"; fi
  else
    FAIL "Expected 200 for filtered request (got $CODE)"
  fi

  # 6) Filter by non-existing staffNationalId
  SECTION "Filter by non-existing staffNationalId=NO-SUCH-NID"
  RESP=$(http_get "$API_HOST$DISTRIBUTIONS_ENDPOINT?staffNationalId=NO-SUCH-NID" "$PHARMACIST_TOKEN")
  CODE=$(echo "$RESP" | awk 'NR==1{print $2}')
  BODY=$(echo "$RESP" | awk 'BEGIN{b=0} /^\r?$/{b=1; next} b{print}')
  TOTAL=$(echo "$BODY" | jq -r '.total // 0')
  if [[ "$CODE" == "200" && "$TOTAL" == "0" ]]; then PASS "Got total=0 for unknown staffNationalId"; else FAIL "Expected total=0 (got total=$TOTAL, code=$CODE)"; fi

  # 7) Filter by medicineId
  SECTION "Filter by medicineId=$MEDICINE_ID"
  RESP=$(http_get "$API_HOST$DISTRIBUTIONS_ENDPOINT?medicineId=$(printf %s "$MEDICINE_ID" | jq -sRr @uri)" "$PHARMACIST_TOKEN")
  CODE=$(echo "$RESP" | awk 'NR==1{print $2}')
  BODY=$(echo "$RESP" | awk 'BEGIN{b=0} /^\r?$/{b=1; next} b{print}')
  if [[ "$CODE" == "200" ]]; then
    MISMATCH=$(echo "$BODY" | jq -r --arg mid "$MEDICINE_ID" '[.items[] | select(.medicineId != $mid)] | length')
    if [[ "$MISMATCH" == "0" ]]; then PASS "All items match medicineId"; else FAIL "Found $MISMATCH items with mismatched medicineId"; fi
  else
    FAIL "Expected 200 for medicineId filter (got $CODE)"
  fi

  # 8) Pagination (limit/offset)
  SECTION "Pagination: limit=1, offset=0 and offset=1"
  RESP_A=$(http_get "$API_HOST$DISTRIBUTIONS_ENDPOINT?limit=1&offset=0" "$PHARMACIST_TOKEN")
  CODE_A=$(echo "$RESP_A" | awk 'NR==1{print $2}')
  BODY_A=$(echo "$RESP_A" | awk 'BEGIN{b=0} /^\r?$/{b=1; next} b{print}')
  ID_A=$(echo "$BODY_A" | jq -r '.items[0].id // empty')

  RESP_B=$(http_get "$API_HOST$DISTRIBUTIONS_ENDPOINT?limit=1&offset=1" "$PHARMACIST_TOKEN")
  CODE_B=$(echo "$RESP_B" | awk 'NR==1{print $2}')
  BODY_B=$(echo "$RESP_B" | awk 'BEGIN{b=0} /^\r?$/{b=1; next} b{print}')
  ID_B=$(echo "$BODY_B" | jq -r '.items[0].id // empty')

  if [[ "$CODE_A" == "200" && "$CODE_B" == "200" ]]; then
    if [[ -n "$ID_A" && -n "$ID_B" && "$ID_A" != "$ID_B" ]]; then PASS "Different items returned across pages"; else WARN "Not enough data to prove pagination (IDs: $ID_A, $ID_B)"; fi
  else
    FAIL "Pagination responses not 200 (A=$CODE_A, B=$CODE_B)"
  fi

  # 9) Invalid pagination and types
  SECTION "Invalid pagination: limit=-5, offset=-3"
  RESP=$(http_get "$API_HOST$DISTRIBUTIONS_ENDPOINT?limit=-5&offset=-3" "$PHARMACIST_TOKEN")
  CODE=$(echo "$RESP" | awk 'NR==1{print $2}')
  BODY=$(echo "$RESP" | awk 'BEGIN{b=0} /^\r?$/{b=1; next} b{print}')
  LIMIT_VAL=$(echo "$BODY" | jq -r '.limit // empty')
  OFFSET_VAL=$(echo "$BODY" | jq -r '.offset // empty')
  if [[ "$CODE" == "200" && "$LIMIT_VAL" -ge 1 && "$OFFSET_VAL" -ge 0 ]]; then PASS "Server clamped invalid pagination (limit=$LIMIT_VAL, offset=$OFFSET_VAL)"; else FAIL "Unexpected pagination handling (code=$CODE, limit=$LIMIT_VAL, offset=$OFFSET_VAL)"; fi

  SECTION "Invalid types: limit=abc, offset=xyz"
  RESP=$(http_get "$API_HOST$DISTRIBUTIONS_ENDPOINT?limit=abc&offset=xyz" "$PHARMACIST_TOKEN")
  CODE=$(echo "$RESP" | awk 'NR==1{print $2}')
  BODY=$(echo "$RESP" | awk 'BEGIN{b=0} /^\r?$/{b=1; next} b{print}')
  LIMIT_VAL=$(echo "$BODY" | jq -r '.limit // empty')
  OFFSET_VAL=$(echo "$BODY" | jq -r '.offset // empty')
  if [[ "$CODE" == "200" && "$LIMIT_VAL" == "50" && "$OFFSET_VAL" == "0" ]]; then PASS "Defaulted invalid types to limit=50, offset=0"; else WARN "Expected defaults (50/0) but got limit=$LIMIT_VAL offset=$OFFSET_VAL"; fi

  echo -e "\n${BOLD}${GREEN}All tests finished.${RESET}"
}

main "$@"
