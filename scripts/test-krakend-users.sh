#!/usr/bin/env bash
set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}     Fixing KrakenD Configuration${NC}"
echo -e "${BLUE}================================================${NC}"
echo ""

# Setup service account permissions
echo "Setting up service account permissions..."
KEYCLOAK_BASE="http://localhost:8081"
REALM="clinic-mouzaia-hub"
CLIENT_ID="krakend-gateway"
CLIENT_SECRET="RLNH2Y731jI8EKOiXwhgAk6Nh3hKUWzn"

# Get admin token
ADMIN_TOKEN=$(curl -sS -X POST \
    "$KEYCLOAK_BASE/realms/master/protocol/openid-connect/token" \
    -d 'grant_type=password&client_id=admin-cli&username=admin&password=admin' 2>/dev/null |
    python3 -c "import sys, json; print(json.load(sys.stdin).get('access_token', ''))" 2>/dev/null || echo "")

if [ -n "$ADMIN_TOKEN" ]; then
    # Get client UUID
    CLIENT_UUID=$(curl -sS \
        "$KEYCLOAK_BASE/admin/realms/$REALM/clients?clientId=$CLIENT_ID" \
        -H "Authorization: Bearer $ADMIN_TOKEN" 2>/dev/null |
        python3 -c "import sys, json; c=json.load(sys.stdin); print(c[0]['id'] if c else '')" 2>/dev/null || echo "")

    if [ -n "$CLIENT_UUID" ]; then
        # Enable service account
        curl -sS -X PUT \
            "$KEYCLOAK_BASE/admin/realms/$REALM/clients/$CLIENT_UUID" \
            -H "Authorization: Bearer $ADMIN_TOKEN" \
            -H "Content-Type: application/json" \
            -d "{\"serviceAccountsEnabled\": true, \"secret\": \"$CLIENT_SECRET\"}" >/dev/null 2>&1

        # Get service account user
        SERVICE_USER=$(curl -sS \
            "$KEYCLOAK_BASE/admin/realms/$REALM/clients/$CLIENT_UUID/service-account-user" \
            -H "Authorization: Bearer $ADMIN_TOKEN" 2>/dev/null |
            python3 -c "import sys, json; print(json.load(sys.stdin)['id'])" 2>/dev/null || echo "")

        if [ -n "$SERVICE_USER" ]; then
            # Get realm-management client
            REALM_MGMT=$(curl -sS \
                "$KEYCLOAK_BASE/admin/realms/$REALM/clients?clientId=realm-management" \
                -H "Authorization: Bearer $ADMIN_TOKEN" 2>/dev/null |
                python3 -c "import sys, json; print(json.load(sys.stdin)[0]['id'])" 2>/dev/null || echo "")

            if [ -n "$REALM_MGMT" ]; then
                # Assign roles
                curl -sS -X POST \
                    "$KEYCLOAK_BASE/admin/realms/$REALM/users/$SERVICE_USER/role-mappings/clients/$REALM_MGMT" \
                    -H "Authorization: Bearer $ADMIN_TOKEN" \
                    -H "Content-Type: application/json" \
                    -d '[{"name":"view-users"},{"name":"manage-users"},{"name":"view-realm"}]' >/dev/null 2>&1
                echo "✅ Service account permissions configured"
            fi
        fi
    fi
fi
echo ""

# Final test
echo -e "${YELLOW}Testing the fixed configuration...${NC}"
echo ""

# Get user token
TOKEN=$(curl -sS -X POST \
    "$KEYCLOAK_BASE/realms/$REALM/protocol/openid-connect/token" \
    -d "grant_type=password&client_id=$CLIENT_ID&client_secret=$CLIENT_SECRET&username=testuser&password=useruser" 2>/dev/null |
    python3 -c "import sys,json; print(json.load(sys.stdin).get('access_token',''))" 2>/dev/null || echo "")

if [ -z "$TOKEN" ]; then
    echo -e "${RED}❌ Failed to get user token${NC}"
    echo "Make sure testuser exists with password 'useruser'"
    exit 1
fi

# Test KrakenD
echo "Calling http://localhost:8080/api/users..."
RESPONSE=$(curl -sS -w '\nHTTP_CODE:%{http_code}' \
    -H "Authorization: Bearer $TOKEN" \
    "http://localhost:8080/api/users" 2>/dev/null || echo "HTTP_CODE:0")

CODE=$(echo "$RESPONSE" | grep 'HTTP_CODE:' | cut -d: -f2)
BODY=$(echo "$RESPONSE" | grep -v 'HTTP_CODE:')

if [ "$CODE" = "200" ]; then
    echo -e "${GREEN}✅ SUCCESS! KrakenD is working!${NC}"
    echo ""
    echo "Users returned:"
    echo "$BODY" | python3 -c "
import sys, json
try:
    users = json.load(sys.stdin)
    for i, user in enumerate(users[:3]):
        print(f\"  {i+1}. {user.get('username', 'N/A')}\")
    if len(users) > 3:
        print(f\"  ... and {len(users)-3} more\")
except:
    print('  [Could not parse users]')
" 2>/dev/null || echo "  [Could not parse response]"
else
    echo -e "${RED}❌ Failed with HTTP $CODE${NC}"
    echo "Response: $BODY" | head -c 300
    echo ""
    echo "Check logs: docker logs mouzaia-clinic-hub-krakend-1"
fi

echo ""
echo -e "${BLUE}================================================${NC}"
if [ "$CODE" = "200" ]; then
    echo -e "${GREEN}     Configuration Fixed and Working!${NC}"
else
    echo -e "${YELLOW}     Please check the logs for errors${NC}"
fi
echo -e "${BLUE}================================================${NC}"
