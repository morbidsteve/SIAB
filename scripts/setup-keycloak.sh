#!/bin/bash
#
# SIAB Keycloak Setup Script
#
# This script initializes Keycloak with:
# - SIAB realm with proper settings
# - Default roles (admin, operator, user, viewer)
# - Default groups (administrators, operators, users)
# - OAuth2/OIDC clients for dashboard and apps
# - Default admin user
#
# Usage: ./setup-keycloak.sh [--admin-password <password>] [--admin-email <email>]
#

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIAB_DIR="$(dirname "$SCRIPT_DIR")"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Configuration
KEYCLOAK_URL="${KEYCLOAK_URL:-https://keycloak.siab.local}"
SIAB_DOMAIN="${SIAB_DOMAIN:-siab.local}"
REALM_NAME="siab"

# Parse arguments
ADMIN_PASSWORD=""
ADMIN_EMAIL="admin@${SIAB_DOMAIN}"
FIRST_USER_PASSWORD=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --admin-password)
            ADMIN_PASSWORD="$2"
            shift 2
            ;;
        --admin-email)
            ADMIN_EMAIL="$2"
            shift 2
            ;;
        --first-user-password)
            FIRST_USER_PASSWORD="$2"
            shift 2
            ;;
        --help|-h)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --admin-password <pass>    Password for the first admin user"
            echo "  --admin-email <email>      Email for the first admin user"
            echo "  --first-user-password <p>  Password for siab-admin user (default: generated)"
            echo "  --help                     Show this help"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

echo "========================================"
echo "  SIAB Keycloak Setup"
echo "========================================"
echo ""

# Get Keycloak admin credentials
echo -e "${BLUE}Getting Keycloak admin credentials...${NC}"
KC_ADMIN_USER=$(kubectl get secret -n keycloak keycloak-credentials -o jsonpath='{.data.admin-user}' | base64 -d)
KC_ADMIN_PASS=$(kubectl get secret -n keycloak keycloak-credentials -o jsonpath='{.data.admin-password}' | base64 -d)

if [ -z "$KC_ADMIN_USER" ] || [ -z "$KC_ADMIN_PASS" ]; then
    echo -e "${RED}Error: Could not get Keycloak admin credentials${NC}"
    exit 1
fi

echo -e "${GREEN}Got admin credentials for user: ${KC_ADMIN_USER}${NC}"

# Function to get admin token
get_admin_token() {
    curl -sk -X POST "${KEYCLOAK_URL}/realms/master/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${KC_ADMIN_USER}" \
        -d "password=${KC_ADMIN_PASS}" \
        -d "grant_type=password" \
        -d "client_id=admin-cli" | jq -r '.access_token'
}

# Function to make authenticated API calls
kc_api() {
    local method="$1"
    local endpoint="$2"
    local data="$3"
    local token=$(get_admin_token)

    if [ -z "$data" ]; then
        curl -sk -X "$method" "${KEYCLOAK_URL}/admin/realms${endpoint}" \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json"
    else
        curl -sk -X "$method" "${KEYCLOAK_URL}/admin/realms${endpoint}" \
            -H "Authorization: Bearer ${token}" \
            -H "Content-Type: application/json" \
            -d "$data"
    fi
}

echo ""
echo -e "${BLUE}Step 1: Creating SIAB realm...${NC}"

# Check if realm exists
REALM_EXISTS=$(kc_api GET "/${REALM_NAME}" 2>/dev/null | jq -r '.realm // empty')

if [ "$REALM_EXISTS" = "$REALM_NAME" ]; then
    echo -e "${YELLOW}Realm '${REALM_NAME}' already exists, updating...${NC}"
else
    echo "Creating new realm '${REALM_NAME}'..."
fi

# Create/update realm
REALM_JSON=$(cat <<EOF
{
    "realm": "${REALM_NAME}",
    "enabled": true,
    "displayName": "SIAB - Secure Infrastructure Application Box",
    "displayNameHtml": "<div class=\"kc-logo-text\"><span>SIAB</span></div>",
    "loginWithEmailAllowed": true,
    "duplicateEmailsAllowed": false,
    "resetPasswordAllowed": true,
    "editUsernameAllowed": false,
    "bruteForceProtected": true,
    "permanentLockout": false,
    "maxFailureWaitSeconds": 900,
    "minimumQuickLoginWaitSeconds": 60,
    "waitIncrementSeconds": 60,
    "quickLoginCheckMilliSeconds": 1000,
    "maxDeltaTimeSeconds": 43200,
    "failureFactor": 5,
    "sslRequired": "external",
    "registrationAllowed": false,
    "registrationEmailAsUsername": true,
    "rememberMe": true,
    "verifyEmail": false,
    "loginTheme": "keycloak",
    "accountTheme": "keycloak.v2",
    "adminTheme": "keycloak.v2",
    "emailTheme": "keycloak",
    "accessTokenLifespan": 300,
    "accessTokenLifespanForImplicitFlow": 900,
    "ssoSessionIdleTimeout": 1800,
    "ssoSessionMaxLifespan": 36000,
    "offlineSessionIdleTimeout": 2592000,
    "accessCodeLifespan": 60,
    "accessCodeLifespanUserAction": 300,
    "accessCodeLifespanLogin": 1800,
    "actionTokenGeneratedByAdminLifespan": 43200,
    "actionTokenGeneratedByUserLifespan": 300,
    "defaultSignatureAlgorithm": "RS256",
    "revokeRefreshToken": false,
    "refreshTokenMaxReuse": 0,
    "internationalizationEnabled": false,
    "defaultLocale": "en",
    "browserFlow": "browser",
    "registrationFlow": "registration",
    "directGrantFlow": "direct grant",
    "resetCredentialsFlow": "reset credentials",
    "clientAuthenticationFlow": "clients"
}
EOF
)

if [ "$REALM_EXISTS" = "$REALM_NAME" ]; then
    kc_api PUT "/${REALM_NAME}" "$REALM_JSON" > /dev/null
else
    kc_api POST "" "$REALM_JSON" > /dev/null
fi

echo -e "${GREEN}Realm '${REALM_NAME}' configured${NC}"

echo ""
echo -e "${BLUE}Step 2: Creating realm roles...${NC}"

# Define roles
declare -A ROLES=(
    ["siab-admin"]="Full administrative access to SIAB platform"
    ["siab-operator"]="Can deploy and manage applications"
    ["siab-user"]="Can access deployed applications"
    ["siab-viewer"]="Read-only access to dashboard"
)

for role in "${!ROLES[@]}"; do
    echo -n "  Creating role '${role}'... "
    ROLE_JSON=$(cat <<EOF
{
    "name": "${role}",
    "description": "${ROLES[$role]}",
    "composite": false,
    "clientRole": false
}
EOF
)
    RESULT=$(kc_api POST "/${REALM_NAME}/roles" "$ROLE_JSON" 2>&1)
    if echo "$RESULT" | grep -q "Role with name ${role} already exists"; then
        echo -e "${YELLOW}exists${NC}"
    else
        echo -e "${GREEN}created${NC}"
    fi
done

echo ""
echo -e "${BLUE}Step 3: Creating groups...${NC}"

# Define groups with their roles
declare -A GROUPS=(
    ["administrators"]="siab-admin"
    ["operators"]="siab-operator"
    ["users"]="siab-user"
    ["viewers"]="siab-viewer"
)

for group in "${!GROUPS[@]}"; do
    echo -n "  Creating group '${group}'... "
    GROUP_JSON="{\"name\": \"${group}\"}"
    RESULT=$(kc_api POST "/${REALM_NAME}/groups" "$GROUP_JSON" 2>&1)

    if echo "$RESULT" | grep -q "409"; then
        echo -e "${YELLOW}exists${NC}"
    else
        echo -e "${GREEN}created${NC}"
    fi

    # Get group ID and assign role
    GROUP_ID=$(kc_api GET "/${REALM_NAME}/groups?search=${group}" | jq -r '.[0].id // empty')
    ROLE_NAME="${GROUPS[$group]}"

    if [ -n "$GROUP_ID" ]; then
        ROLE_DATA=$(kc_api GET "/${REALM_NAME}/roles/${ROLE_NAME}")
        kc_api POST "/${REALM_NAME}/groups/${GROUP_ID}/role-mappings/realm" "[$ROLE_DATA]" > /dev/null 2>&1
        echo "    -> Assigned role '${ROLE_NAME}' to group"
    fi
done

echo ""
echo -e "${BLUE}Step 4: Creating OAuth2/OIDC clients...${NC}"

# Generate client secrets
DASHBOARD_SECRET=$(openssl rand -hex 32)
ISTIO_SECRET=$(openssl rand -hex 32)

# Dashboard client
echo -n "  Creating 'siab-dashboard' client... "
DASHBOARD_CLIENT=$(cat <<EOF
{
    "clientId": "siab-dashboard",
    "name": "SIAB Dashboard",
    "description": "Central dashboard for SIAB platform",
    "enabled": true,
    "clientAuthenticatorType": "client-secret",
    "secret": "${DASHBOARD_SECRET}",
    "redirectUris": [
        "https://dashboard.${SIAB_DOMAIN}/*",
        "https://*.${SIAB_DOMAIN}/*"
    ],
    "webOrigins": [
        "https://dashboard.${SIAB_DOMAIN}",
        "https://*.${SIAB_DOMAIN}"
    ],
    "protocol": "openid-connect",
    "publicClient": false,
    "bearerOnly": false,
    "standardFlowEnabled": true,
    "implicitFlowEnabled": false,
    "directAccessGrantsEnabled": true,
    "serviceAccountsEnabled": false,
    "authorizationServicesEnabled": false,
    "fullScopeAllowed": true,
    "defaultClientScopes": ["openid", "profile", "email", "roles"],
    "optionalClientScopes": ["offline_access"],
    "attributes": {
        "access.token.lifespan": "300",
        "pkce.code.challenge.method": "S256"
    },
    "protocolMappers": [
        {
            "name": "groups",
            "protocol": "openid-connect",
            "protocolMapper": "oidc-group-membership-mapper",
            "consentRequired": false,
            "config": {
                "full.path": "false",
                "id.token.claim": "true",
                "access.token.claim": "true",
                "claim.name": "groups",
                "userinfo.token.claim": "true"
            }
        },
        {
            "name": "realm-roles",
            "protocol": "openid-connect",
            "protocolMapper": "oidc-usermodel-realm-role-mapper",
            "consentRequired": false,
            "config": {
                "multivalued": "true",
                "id.token.claim": "true",
                "access.token.claim": "true",
                "claim.name": "roles",
                "userinfo.token.claim": "true"
            }
        }
    ]
}
EOF
)
RESULT=$(kc_api POST "/${REALM_NAME}/clients" "$DASHBOARD_CLIENT" 2>&1)
if echo "$RESULT" | grep -q "409"; then
    echo -e "${YELLOW}exists${NC}"
else
    echo -e "${GREEN}created${NC}"
fi

# Istio client for JWT validation
echo -n "  Creating 'siab-istio' client... "
ISTIO_CLIENT=$(cat <<EOF
{
    "clientId": "siab-istio",
    "name": "SIAB Istio",
    "description": "Client for Istio JWT validation",
    "enabled": true,
    "clientAuthenticatorType": "client-secret",
    "secret": "${ISTIO_SECRET}",
    "protocol": "openid-connect",
    "publicClient": false,
    "bearerOnly": true,
    "standardFlowEnabled": false,
    "implicitFlowEnabled": false,
    "directAccessGrantsEnabled": false,
    "serviceAccountsEnabled": false,
    "fullScopeAllowed": true
}
EOF
)
RESULT=$(kc_api POST "/${REALM_NAME}/clients" "$ISTIO_CLIENT" 2>&1)
if echo "$RESULT" | grep -q "409"; then
    echo -e "${YELLOW}exists${NC}"
else
    echo -e "${GREEN}created${NC}"
fi

echo ""
echo -e "${BLUE}Step 5: Creating default admin user...${NC}"

# Generate password if not provided
if [ -z "$FIRST_USER_PASSWORD" ]; then
    FIRST_USER_PASSWORD=$(openssl rand -base64 16 | tr -dc 'a-zA-Z0-9' | head -c 16)
fi

ADMIN_USER_JSON=$(cat <<EOF
{
    "username": "siab-admin",
    "email": "${ADMIN_EMAIL}",
    "emailVerified": true,
    "enabled": true,
    "firstName": "SIAB",
    "lastName": "Administrator",
    "credentials": [{
        "type": "password",
        "value": "${FIRST_USER_PASSWORD}",
        "temporary": true
    }],
    "groups": ["administrators"],
    "realmRoles": ["siab-admin"]
}
EOF
)

echo -n "  Creating 'siab-admin' user... "
RESULT=$(kc_api POST "/${REALM_NAME}/users" "$ADMIN_USER_JSON" 2>&1)
if echo "$RESULT" | grep -q "409"; then
    echo -e "${YELLOW}exists${NC}"
else
    echo -e "${GREEN}created${NC}"
fi

# Get user ID and add to administrators group
USER_ID=$(kc_api GET "/${REALM_NAME}/users?username=siab-admin" | jq -r '.[0].id // empty')
ADMIN_GROUP_ID=$(kc_api GET "/${REALM_NAME}/groups?search=administrators" | jq -r '.[0].id // empty')

if [ -n "$USER_ID" ] && [ -n "$ADMIN_GROUP_ID" ]; then
    kc_api PUT "/${REALM_NAME}/users/${USER_ID}/groups/${ADMIN_GROUP_ID}" "" > /dev/null 2>&1
    echo "    -> Added to 'administrators' group"
fi

echo ""
echo -e "${BLUE}Step 6: Storing client secrets...${NC}"

# Create/update secret in Kubernetes
kubectl create secret generic siab-oidc-secrets \
    --from-literal=dashboard-client-id=siab-dashboard \
    --from-literal=dashboard-client-secret="${DASHBOARD_SECRET}" \
    --from-literal=istio-client-id=siab-istio \
    --from-literal=istio-client-secret="${ISTIO_SECRET}" \
    --from-literal=issuer-url="${KEYCLOAK_URL}/realms/${REALM_NAME}" \
    -n istio-system \
    --dry-run=client -o yaml | kubectl apply -f -

echo -e "${GREEN}Secrets stored in istio-system/siab-oidc-secrets${NC}"

echo ""
echo -e "${BLUE}Step 7: Configuring Istio authentication...${NC}"

# Create RequestAuthentication
cat <<EOF | kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: siab-jwt-auth
  namespace: istio-system
spec:
  selector:
    matchLabels:
      istio: ingress-user
  jwtRules:
  - issuer: "${KEYCLOAK_URL}/realms/${REALM_NAME}"
    jwksUri: "${KEYCLOAK_URL}/realms/${REALM_NAME}/protocol/openid-connect/certs"
    audiences:
    - siab-dashboard
    - siab-istio
    forwardOriginalToken: true
    fromHeaders:
    - name: Authorization
      prefix: "Bearer "
    fromCookies:
    - siab_token
EOF

echo -e "${GREEN}RequestAuthentication configured${NC}"

echo ""
echo "========================================"
echo -e "${GREEN}  Keycloak Setup Complete!${NC}"
echo "========================================"
echo ""
echo "Keycloak Admin Console: ${KEYCLOAK_URL}/admin/"
echo "  Username: ${KC_ADMIN_USER}"
echo "  Password: ${KC_ADMIN_PASS}"
echo ""
echo "SIAB Realm: ${REALM_NAME}"
echo ""
echo "Default SIAB Admin User:"
echo "  Username: siab-admin"
echo "  Password: ${FIRST_USER_PASSWORD}"
echo "  (Password change required on first login)"
echo ""
echo "Roles created:"
echo "  - siab-admin    : Full administrative access"
echo "  - siab-operator : Can deploy and manage apps"
echo "  - siab-user     : Can access deployed apps"
echo "  - siab-viewer   : Read-only dashboard access"
echo ""
echo "Groups created:"
echo "  - administrators -> siab-admin role"
echo "  - operators      -> siab-operator role"
echo "  - users          -> siab-user role"
echo "  - viewers        -> siab-viewer role"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Log into Keycloak and change the siab-admin password"
echo "2. Create additional users and add them to appropriate groups"
echo "3. The dashboard will use these for access control"
echo ""

# Save credentials to file
CREDS_FILE="${HOME}/.siab-credentials.env"
cat > "$CREDS_FILE" <<EOF
# SIAB Credentials - Generated $(date)
# Keep this file secure!

KEYCLOAK_ADMIN_USER=${KC_ADMIN_USER}
KEYCLOAK_ADMIN_PASSWORD=${KC_ADMIN_PASS}
KEYCLOAK_URL=${KEYCLOAK_URL}

SIAB_ADMIN_USER=siab-admin
SIAB_ADMIN_PASSWORD=${FIRST_USER_PASSWORD}
SIAB_REALM=${REALM_NAME}

DASHBOARD_CLIENT_ID=siab-dashboard
DASHBOARD_CLIENT_SECRET=${DASHBOARD_SECRET}
EOF
chmod 600 "$CREDS_FILE"
echo -e "${GREEN}Credentials saved to: ${CREDS_FILE}${NC}"
