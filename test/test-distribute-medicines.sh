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
LIST_MEDICINES_ENDPOINT="/pharmacy/medicines"
ADD_MEDICINE_ENDPOINT="/pharmacy/medicines"
DISTRIBUTE_ENDPOINT="/pharmacy/medicines/distribute"
FIND_USER_BY_NID_ENDPOINT="/users/by-national-id"

# Test data
STAFF_NATIONAL_ID_ALLOWED="S1-0001"   # staff1 has allowed_to_take_medicines
STAFF_NATIONAL_ID_DENIED="S2-0002"    # staff2 lacks allowed_to_take_medicines

REQUIRED_QUANTITY=${REQUIRED_QUANTITY:-5}

# Utilities
need() { command -v "$1" >/dev/null 2>&1 || { echo "Error: $1 is required." >&2; exit 1; }; }

echo "[1/6] Checking requirements (jq, curl, base64)..."
need jq; need curl; need base64

get_token() {
  local username="$1" password="$2"
  curl -sS -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    -d "grant_type=password" \
    -d "client_id=$CLIENT_ID" \
    -d "username=$username" \
    -d "password=$password" \
    "$TOKEN_URL" | jq -r '.access_token // empty'
}

fetch_staff_user_by_nid() {
  local token="$1" national_id="$2"
  curl -sS -i \
    -H "Authorization: Bearer $token" \
    "$API_HOST$FIND_USER_BY_NID_ENDPOINT?nationalId=$(printf %s "$national_id" | jq -sRr @uri)"
}

get_medicines() {
  local token="$1"
  curl -sS -i \
    -H "Authorization: Bearer $token" \
    "$API_HOST$LIST_MEDICINES_ENDPOINT"
}

add_medicine() {
  local token="$1" name_suffix="$2" stock="$3"
  local payload
  payload=$(jq -n \
    --arg dci "Paracetamol" \
    --arg name "TestMed $name_suffix" \
    --arg ddp "2026-12-31" \
    --arg lot "LOT-$RANDOM" \
    --argjson cout 2.50 \
    --argjson prix 5.00 \
    --argjson stock "$stock" \
    '{dci: $dci, nomCommercial: $name, stock: $stock, ddp: $ddp, lot: $lot, cout: $cout, prixDeVente: $prix}')

  curl -sS -i -X POST \
    -H "Authorization: Bearer $token" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$API_HOST$ADD_MEDICINE_ENDPOINT"
}

pick_medicine_with_stock() {
  local body_json="$1" required_qty="$2"
  echo "$body_json" | jq -r --argjson q "$required_qty" 'map(select(.deleted == false and (.stock // 0) >= $q)) | .[0] // empty'
}

# 1) Authenticate
printf "\n[2/6] Requesting pharmacist access token...\n"
ACCESS_TOKEN=$(get_token "$USERNAME" "$PASSWORD")
if [[ -z "$ACCESS_TOKEN" ]]; then
  echo "Failed to obtain access token." >&2
  exit 1
fi

# 2) Ensure we have a medicine with enough stock
printf "\n[3/6] Ensuring a medicine with stock >= %s exists...\n" "$REQUIRED_QUANTITY"
HTTP_RESP=$(get_medicines "$ACCESS_TOKEN")
HTTP_CODE=$(echo "$HTTP_RESP" | awk 'NR==1{print $2}')
BODY=$(echo "$HTTP_RESP" | awk 'BEGIN{body=0} /^\r?$/{body=1; next} body{print}')

if [[ "$HTTP_CODE" != "200" ]]; then
  echo "List medicines failed ($HTTP_CODE):" >&2
  printf "%s\n" "$BODY" | (jq . 2>/dev/null || cat) >&2
  exit 1
fi

CANDIDATE=$(pick_medicine_with_stock "$BODY" "$REQUIRED_QUANTITY")
if [[ -z "$CANDIDATE" || "$CANDIDATE" == "null" ]]; then
  echo "No suitable medicine found; creating a new one with sufficient stock..."
  CREATE_RESP=$(add_medicine "$ACCESS_TOKEN" "Dist" "$((REQUIRED_QUANTITY + 10))")
  CREATE_CODE=$(echo "$CREATE_RESP" | awk 'NR==1{print $2}')
  CREATE_BODY=$(echo "$CREATE_RESP" | awk 'BEGIN{body=0} /^\r?$/{body=1; next} body{print}')
  if [[ "$CREATE_CODE" != "201" ]]; then
    echo "Add medicine failed ($CREATE_CODE):" >&2
    printf "%s\n" "$CREATE_BODY" | (jq . 2>/dev/null || cat) >&2
    exit 1
  fi
  CANDIDATE=$(printf "%s" "$CREATE_BODY" | jq -c '.')
fi

MEDICINE_ID=$(echo "$CANDIDATE" | jq -r '.id')
MEDICINE_NAME=$(echo "$CANDIDATE" | jq -r '.nomCommercial')
MEDICINE_STOCK=$(echo "$CANDIDATE" | jq -r '.stock')

echo "Using medicine: $MEDICINE_NAME (id=$MEDICINE_ID, stock=$MEDICINE_STOCK)"

# 3) Fetch staff user (allowed)
printf "\n[4/6] Fetching staff user with national ID %s...\n" "$STAFF_NATIONAL_ID_ALLOWED"
USER_RESP=$(fetch_staff_user_by_nid "$ACCESS_TOKEN" "$STAFF_NATIONAL_ID_ALLOWED")
USER_CODE=$(echo "$USER_RESP" | awk 'NR==1{print $2}')
USER_BODY=$(echo "$USER_RESP" | awk 'BEGIN{body=0} /^\r?$/{body=1; next} body{print}')
if [[ "$USER_CODE" != "200" ]]; then
  echo "Fetch staff user failed ($USER_CODE):" >&2
  printf "%s\n" "$USER_BODY" | (jq . 2>/dev/null || cat) >&2
  exit 1
fi

# 4) Distribute
printf "\n[5/6] Distributing %s unit(s) of %s to staff %s...\n" "$REQUIRED_QUANTITY" "$MEDICINE_NAME" "$STAFF_NATIONAL_ID_ALLOWED"
PAYLOAD=$(jq -n \
  --argjson staff "$USER_BODY" \
  --arg medId "$MEDICINE_ID" \
  --argjson qty "$REQUIRED_QUANTITY" \
  '{staffUser: $staff, medicines: [{id: $medId, quantity: $qty}]}'
)

DIST_RESP=$(curl -sS -i -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD" \
  "$API_HOST$DISTRIBUTE_ENDPOINT")

DIST_CODE=$(echo "$DIST_RESP" | awk 'NR==1{print $2}')
DIST_BODY=$(echo "$DIST_RESP" | awk 'BEGIN{body=0} /^\r?$/{body=1; next} body{print}')

echo "Status: $DIST_CODE"
printf "%s\n" "$DIST_BODY" | (jq . 2>/dev/null || cat)

# 5) Negative test (optional): staff without permission
if [[ "${NEGATIVE_TEST:-1}" == "1" ]]; then
  printf "\n[6/6] Negative test: staff without allowed_to_take_medicines (%s) ...\n" "$STAFF_NATIONAL_ID_DENIED"
  USER2_RESP=$(fetch_staff_user_by_nid "$ACCESS_TOKEN" "$STAFF_NATIONAL_ID_DENIED")
  USER2_CODE=$(echo "$USER2_RESP" | awk 'NR==1{print $2}')
  USER2_BODY=$(echo "$USER2_RESP" | awk 'BEGIN{body=0} /^\r?$/{body=1; next} body{print}')
  if [[ "$USER2_CODE" == "200" ]]; then
    PAYLOAD2=$(jq -n \
      --argjson staff "$USER2_BODY" \
      --arg medId "$MEDICINE_ID" \
      --argjson qty 1 \
      '{staffUser: $staff, medicines: [{id: $medId, quantity: $qty}]}'
    )
    NEG_RESP=$(curl -sS -i -X POST \
      -H "Authorization: Bearer $ACCESS_TOKEN" \
      -H "Content-Type: application/json" \
      -d "$PAYLOAD2" \
      "$API_HOST$DISTRIBUTE_ENDPOINT")
    NEG_CODE=$(echo "$NEG_RESP" | awk 'NR==1{print $2}')
    NEG_BODY=$(echo "$NEG_RESP" | awk 'BEGIN{body=0} /^\r?$/{body=1; next} body{print}')
    echo "Negative test status: $NEG_CODE (expected 403)"
    printf "%s\n" "$NEG_BODY" | (jq . 2>/dev/null || cat)
  else
    echo "Could not fetch user $STAFF_NATIONAL_ID_DENIED ($USER2_CODE)"
    printf "%s\n" "$USER2_BODY" | (jq . 2>/dev/null || cat)
  fi
fi

echo "\nDone."
