#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# CONFIG - replace these values
# -----------------------------
KEYCLOAK_URL="http://hubkeycloak.mouzaiaclinic.local"   # Traefik public Keycloak URL
REALM="clinic-mouzaia-hub"

# SERVICE ACCOUNT (client_credentials) - identity-service
SERVICE_CLIENT_ID="identity-service"
# identity-service client secret from Keycloak CHANGE THIS IN PROD
SERVICE_CLIENT_SECRET="3o6528pUArocShteOPUeSfzqNoUdpyOh"

# Test user (password grant) and client to use for password grant
TEST_USERNAME="testuser"
TEST_PASSWORD="useruser"
TEST_CLIENT_ID="test-user-client"   # the client used for password grant (public client)

# Kong/Traefik public URL for the API gateway
KONG_API_URL="http://hubapi.mouzaiaclinic.local"

# Output temp files
TMPDIR=$(mktemp -d)
SERVICE_TOKEN_FILE="${TMPDIR}/service_token.json"
USER_TOKEN_FILE="${TMPDIR}/user_token.json"
DIRECT_USERS_RESP="${TMPDIR}/direct_users_response.txt"
KONG_USERS_RESP="${TMPDIR}/kong_users_response.txt"

cleanup() {
  rm -rf "${TMPDIR}"
}
trap cleanup EXIT

echo "===== STEP 1: Get service account token (client_credentials) ====="
curl -s -X POST \
  -d "grant_type=client_credentials" \
  -d "client_id=${SERVICE_CLIENT_ID}" \
  -d "client_secret=${SERVICE_CLIENT_SECRET}" \
  "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token" \
  -o "${SERVICE_TOKEN_FILE}" \
  -w "\nHTTP_CODE:%{http_code}\n"

echo "--- raw token JSON (service account) ---"
cat "${SERVICE_TOKEN_FILE}"
echo
# extract token for Authorization header (grep fallback)
SERVICE_TOKEN=$(grep -oP '"access_token"\s*:\s*"\K[^"]+' "${SERVICE_TOKEN_FILE}" || true)
if [ -z "${SERVICE_TOKEN}" ]; then
  echo "ERROR: could not extract access_token from service token response. Aborting."
  exit 1
fi

echo
echo "===== STEP 2: Call Keycloak admin /users directly using service account token ====="
curl -s -i -H "Authorization: Bearer ${SERVICE_TOKEN}" \
  "${KEYCLOAK_URL}/admin/realms/${REALM}/users?first=0&max=10" \
  -o "${DIRECT_USERS_RESP}" \
  -w "\nHTTP_CODE:%{http_code}\n"

echo "--- raw Keycloak admin /users response (direct) ---"
cat "${DIRECT_USERS_RESP}"
echo

echo
echo "===== STEP 3: Get user token (password grant) ====="
curl -s -X POST \
  -d "grant_type=password" \
  -d "client_id=${TEST_CLIENT_ID}" \
  -d "username=${TEST_USERNAME}" \
  -d "password=${TEST_PASSWORD}" \
  "${KEYCLOAK_URL}/realms/${REALM}/protocol/openid-connect/token" \
  -o "${USER_TOKEN_FILE}" \
  -w "\nHTTP_CODE:%{http_code}\n"

echo "--- raw token JSON (user) ---"
cat "${USER_TOKEN_FILE}"
echo
USER_TOKEN=$(grep -oP '"access_token"\s*:\s*"\K[^"]+' "${USER_TOKEN_FILE}" || true)
if [ -z "${USER_TOKEN}" ]; then
  echo "ERROR: could not extract access_token from user token response. Aborting."
  exit 1
fi

echo
echo "===== STEP 4: Call Kong API (/users) passing the USER token ====="
# If your Kong route path differs, change the path (/users) below.
curl -s -i -H "Authorization: Bearer ${USER_TOKEN}" \
  "${KONG_API_URL}/users?first=0&max=10" \
  -o "${KONG_USERS_RESP}" \
  -w "\nHTTP_CODE:%{http_code}\n"

echo "--- raw Kong /users response (proxied) ---"
cat "${KONG_USERS_RESP}"
echo

echo "===== DONE ====="
