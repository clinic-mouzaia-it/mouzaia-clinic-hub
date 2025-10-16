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

# Config
REALM="clinic-mouzaia-hub"
KEYCLOAK_HOST="http://hubkeycloak.mouzaiaclinic.local"
CLIENT_ID="pharmacy-service"
USERNAME="pharmacist"
PASSWORD="DummyPassword123!"
TOKEN_URL="$KEYCLOAK_HOST/realms/$REALM/protocol/openid-connect/token"

API_HOST="http://hubapi.mouzaiaclinic.local"
BASE_ENDPOINT="/pharmacy/medicines"

# Dependencies
if ! command -v jq >/dev/null 2>&1; then
  err "jq is required but not installed. Please install jq and re-run." >&2
  exit 1
fi

title "Update Medicine - Happy Path"
step "Requesting token for user '${USERNAME}' (client_id=${CLIENT_ID})"
TOKEN_RESP=$(curl -sS -X POST \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=$CLIENT_ID" \
  -d "username=$USERNAME" \
  -d "password=$PASSWORD" \
  "$TOKEN_URL")

ACCESS_TOKEN=$(echo "$TOKEN_RESP" | jq -r '.access_token // empty')
if [[ -z "${ACCESS_TOKEN}" ]]; then
  err "Failed to obtain access token. Full response:"
  echo "$TOKEN_RESP" | jq . >&2 || echo "$TOKEN_RESP" >&2
  exit 1
fi

step "Creating a test medicine to update"
CREATE_BODY='{"dci":"TestDCI","nomCommercial":"TestMed 100mg","stock":10,"ddp":"2027-01-01","lot":"LOT-UPD-001","cout":1.25,"prixDeVente":2.50}'
CREATE_RESP=$(curl -sS -i -X POST \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$CREATE_BODY" \
  "$API_HOST$BASE_ENDPOINT")
CREATE_CODE=$(echo "$CREATE_RESP" | awk 'NR==1{print $2}')
CREATE_JSON=$(echo "$CREATE_RESP" | awk 'BEGIN{b=0} /^\r?$/{b=1; next} b{print}')

if [[ "$CREATE_CODE" != "201" ]]; then
  err "Failed to create test medicine (HTTP $CREATE_CODE)"
  echo "$CREATE_JSON" | (jq . 2>/dev/null || cat)
  exit 1
fi

MED_ID=$(echo "$CREATE_JSON" | jq -r '.id')
OLD_STOCK=$(echo "$CREATE_JSON" | jq -r '.stock')
ok "Created medicine id=$MED_ID stock=$OLD_STOCK"

# 1) Partial update: change stock and prixDeVente only
PATCH_BODY='{"stock":22,"prixDeVente":3.75}'
step "PATCH updating stock and prixDeVente"
PATCH_RESP=$(curl -sS -i -X PATCH \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PATCH_BODY" \
  "$API_HOST$BASE_ENDPOINT/$MED_ID")
PATCH_CODE=$(echo "$PATCH_RESP" | awk 'NR==1{print $2}')
PATCH_JSON=$(echo "$PATCH_RESP" | awk 'BEGIN{b=0} /^\r?$/{b=1; next} b{print}')

info "HTTP Status: $PATCH_CODE"
if [[ "$PATCH_CODE" != "200" ]]; then
  err "PATCH failed"
  echo "$PATCH_JSON" | (jq . 2>/dev/null || cat)
  exit 1
fi

NEW_STOCK=$(echo "$PATCH_JSON" | jq -r '.stock')
NEW_PDV=$(echo "$PATCH_JSON" | jq -r '.prixDeVente')
ok "Updated stock=$NEW_STOCK prixDeVente=$NEW_PDV"

# 2) Update text fields
PATCH2_BODY='{"dci":"UpdatedDCI","nomCommercial":"Updated Name"}'
step "PATCH updating dci and nomCommercial"
PATCH2_RESP=$(curl -sS -i -X PATCH \
  -H "Authorization: Bearer $ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d "$PATCH2_BODY" \
  "$API_HOST$BASE_ENDPOINT/$MED_ID")
PATCH2_CODE=$(echo "$PATCH2_RESP" | awk 'NR==1{print $2}')
PATCH2_JSON=$(echo "$PATCH2_RESP" | awk 'BEGIN{b=0} /^\r?$/{b=1; next} b{print}')

info "HTTP Status: $PATCH2_CODE"
if [[ "$PATCH2_CODE" != "200" ]]; then
  err "PATCH 2 failed"
  echo "$PATCH2_JSON" | (jq . 2>/dev/null || cat)
  exit 1
fi

NEW_DCI=$(echo "$PATCH2_JSON" | jq -r '.dci')
NEW_NAME=$(echo "$PATCH2_JSON" | jq -r '.nomCommercial')
ok "Updated dci=$NEW_DCI nomCommercial=$NEW_NAME"

title "${GREEN}✓ Update endpoint happy-path tests passed${RESET}"
