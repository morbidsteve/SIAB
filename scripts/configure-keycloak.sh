#!/bin/bash
# SIAB Keycloak Configuration Script
# Creates realm, clients, roles, groups, and default admin user

set -euo pipefail

# Check for required dependencies
check_dependencies() {
    local missing=()
    for cmd in curl jq openssl kubectl; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "\033[0;31m[ERROR]\033[0m Missing required dependencies: ${missing[*]}"
        echo "Please install them before running this script."
        exit 1
    fi
}

check_dependencies

# Configuration
KEYCLOAK_URL="${KEYCLOAK_URL:-https://keycloak.siab.local}"
KEYCLOAK_INTERNAL_URL="${KEYCLOAK_INTERNAL_URL:-http://keycloak.keycloak.svc.cluster.local:80}"
REALM_NAME="siab"
SIAB_DOMAIN="${SIAB_DOMAIN:-siab.local}"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Load credentials
SIAB_CONFIG_DIR="${SIAB_CONFIG_DIR:-/etc/siab}"
if [[ -f "${SIAB_CONFIG_DIR}/credentials.env" ]]; then
    source "${SIAB_CONFIG_DIR}/credentials.env"
else
    log_error "Credentials file not found at ${SIAB_CONFIG_DIR}/credentials.env"
    exit 1
fi

ADMIN_USER="${KEYCLOAK_ADMIN_USER:-admin}"
ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD}"

if [[ -z "$ADMIN_PASSWORD" ]]; then
    log_error "KEYCLOAK_ADMIN_PASSWORD not set"
    exit 1
fi

# Generate client secrets
OAUTH2_PROXY_CLIENT_SECRET=$(openssl rand -base64 32 | tr -d '=+/' | head -c 32)
DASHBOARD_CLIENT_SECRET=$(openssl rand -base64 32 | tr -d '=+/' | head -c 32)
DEPLOYER_CLIENT_SECRET=$(openssl rand -base64 32 | tr -d '=+/' | head -c 32)

# Default user password (user should change on first login)
DEFAULT_USER_PASSWORD=$(openssl rand -base64 16 | tr -d '=+/' | head -c 16)

# Wait for Keycloak to be ready
wait_for_keycloak() {
    log_step "Waiting for Keycloak to be ready..."
    local max_attempts=60
    local attempt=0

    while [[ $attempt -lt $max_attempts ]]; do
        if curl -sf "${KEYCLOAK_INTERNAL_URL}/health/ready" >/dev/null 2>&1; then
            log_info "Keycloak is ready"
            return 0
        fi
        attempt=$((attempt + 1))
        echo -n "."
        sleep 5
    done

    log_error "Keycloak did not become ready in time"
    return 1
}

# Get admin access token
get_admin_token() {
    local token
    token=$(curl -sf -X POST "${KEYCLOAK_INTERNAL_URL}/realms/master/protocol/openid-connect/token" \
        -H "Content-Type: application/x-www-form-urlencoded" \
        -d "username=${ADMIN_USER}" \
        -d "password=${ADMIN_PASSWORD}" \
        -d "grant_type=password" \
        -d "client_id=admin-cli" | jq -r '.access_token')

    if [[ -z "$token" || "$token" == "null" ]]; then
        log_error "Failed to get admin token"
        return 1
    fi

    echo "$token"
}

# Check if realm exists
realm_exists() {
    local token="$1"
    curl -sf -o /dev/null -w "%{http_code}" \
        -H "Authorization: Bearer $token" \
        "${KEYCLOAK_INTERNAL_URL}/admin/realms/${REALM_NAME}" | grep -q "200"
}

# Create realm
create_realm() {
    local token="$1"
    log_step "Creating SIAB realm..."

    local realm_config='{
        "realm": "'"${REALM_NAME}"'",
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
        "registrationEmailAsUsername": false,
        "rememberMe": true,
        "verifyEmail": false,
        "loginTheme": "keycloak",
        "accountTheme": "keycloak.v2",
        "adminTheme": "keycloak.v2",
        "emailTheme": "keycloak",
        "accessTokenLifespan": 3600,
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
    }'

    local http_code
    http_code=$(curl -sf -o /dev/null -w "%{http_code}" -X POST "${KEYCLOAK_INTERNAL_URL}/admin/realms" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$realm_config")

    if [[ "$http_code" == "201" ]] || [[ "$http_code" == "409" ]]; then
        log_info "Realm created successfully"
        return 0
    else
        log_error "Failed to create realm (HTTP $http_code)"
        return 1
    fi
}

# Create realm roles
create_realm_roles() {
    local token="$1"
    log_step "Creating realm roles..."

    local roles=("siab-admin" "siab-operator" "siab-user")
    local descriptions=(
        "Full administrative access to SIAB platform"
        "Operator access - can deploy and manage applications"
        "Standard user access - can use deployed applications"
    )

    for i in "${!roles[@]}"; do
        local role="${roles[$i]}"
        local desc="${descriptions[$i]}"

        local role_config='{
            "name": "'"${role}"'",
            "description": "'"${desc}"'",
            "composite": false,
            "clientRole": false
        }'

        curl -sf -X POST "${KEYCLOAK_INTERNAL_URL}/admin/realms/${REALM_NAME}/roles" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "$role_config" >/dev/null 2>&1 || true

        log_info "  Created role: ${role}"
    done
}

# Create groups
create_groups() {
    local token="$1"
    log_step "Creating groups..."

    local groups=("administrators" "operators" "users")
    local roles=("siab-admin" "siab-operator" "siab-user")

    for i in "${!groups[@]}"; do
        local group="${groups[$i]}"
        local role="${roles[$i]}"

        # Create group
        local group_config='{"name": "'"${group}"'"}'
        curl -sf -X POST "${KEYCLOAK_INTERNAL_URL}/admin/realms/${REALM_NAME}/groups" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "$group_config" >/dev/null 2>&1 || true

        # Get group ID
        local group_id
        group_id=$(curl -sf "${KEYCLOAK_INTERNAL_URL}/admin/realms/${REALM_NAME}/groups?search=${group}" \
            -H "Authorization: Bearer $token" | jq -r '.[0].id // empty')

        if [[ -n "$group_id" ]]; then
            # Assign role to group
            local role_id
            role_id=$(curl -sf "${KEYCLOAK_INTERNAL_URL}/admin/realms/${REALM_NAME}/roles/${role}" \
                -H "Authorization: Bearer $token" | jq -r '.id // empty')

            if [[ -n "$role_id" ]]; then
                curl -sf -X POST "${KEYCLOAK_INTERNAL_URL}/admin/realms/${REALM_NAME}/groups/${group_id}/role-mappings/realm" \
                    -H "Authorization: Bearer $token" \
                    -H "Content-Type: application/json" \
                    -d '[{"id": "'"${role_id}"'", "name": "'"${role}"'"}]' >/dev/null 2>&1 || true
            fi
        fi

        log_info "  Created group: ${group} (with ${role} role)"
    done
}

# Create OIDC clients
create_clients() {
    local token="$1"
    log_step "Creating OIDC clients..."

    # Dashboard client (public - for browser login)
    local dashboard_client='{
        "clientId": "siab-dashboard",
        "name": "SIAB Dashboard",
        "description": "SIAB Dashboard and Deployer Applications",
        "enabled": true,
        "publicClient": true,
        "directAccessGrantsEnabled": true,
        "standardFlowEnabled": true,
        "implicitFlowEnabled": true,
        "serviceAccountsEnabled": false,
        "protocol": "openid-connect",
        "rootUrl": "https://dashboard.'"${SIAB_DOMAIN}"'",
        "baseUrl": "https://dashboard.'"${SIAB_DOMAIN}"'",
        "redirectUris": [
            "https://dashboard.'"${SIAB_DOMAIN}"'/*",
            "https://deployer.'"${SIAB_DOMAIN}"'/*",
            "https://catalog.'"${SIAB_DOMAIN}"'/*",
            "https://*.apps.'"${SIAB_DOMAIN}"'/*",
            "https://'"${SIAB_DOMAIN}"'/*"
        ],
        "webOrigins": [
            "https://dashboard.'"${SIAB_DOMAIN}"'",
            "https://deployer.'"${SIAB_DOMAIN}"'",
            "https://catalog.'"${SIAB_DOMAIN}"'",
            "https://'"${SIAB_DOMAIN}"'",
            "+"
        ],
        "attributes": {
            "pkce.code.challenge.method": "S256",
            "post.logout.redirect.uris": "+"
        },
        "defaultClientScopes": ["openid", "profile", "email", "roles"],
        "optionalClientScopes": ["address", "phone", "offline_access"]
    }'

    curl -sf -X POST "${KEYCLOAK_INTERNAL_URL}/admin/realms/${REALM_NAME}/clients" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$dashboard_client" >/dev/null 2>&1 || true
    log_info "  Created client: siab-dashboard (public)"

    # OAuth2 Proxy client (confidential - for SSO enforcement)
    local oauth2_proxy_client='{
        "clientId": "siab-oauth2-proxy",
        "name": "SIAB OAuth2 Proxy",
        "description": "OAuth2 Proxy for SSO enforcement",
        "enabled": true,
        "publicClient": false,
        "secret": "'"${OAUTH2_PROXY_CLIENT_SECRET}"'",
        "directAccessGrantsEnabled": false,
        "standardFlowEnabled": true,
        "implicitFlowEnabled": false,
        "serviceAccountsEnabled": false,
        "protocol": "openid-connect",
        "rootUrl": "https://auth.'"${SIAB_DOMAIN}"'",
        "redirectUris": [
            "https://auth.'"${SIAB_DOMAIN}"'/oauth2/callback",
            "https://*.apps.'"${SIAB_DOMAIN}"'/oauth2/callback",
            "https://grafana.'"${SIAB_DOMAIN}"'/login/generic_oauth",
            "https://k8s-dashboard.'"${SIAB_DOMAIN}"'/oauth2/callback"
        ],
        "webOrigins": ["+"],
        "attributes": {
            "pkce.code.challenge.method": "S256",
            "post.logout.redirect.uris": "+"
        },
        "defaultClientScopes": ["openid", "profile", "email", "roles"]
    }'

    curl -sf -X POST "${KEYCLOAK_INTERNAL_URL}/admin/realms/${REALM_NAME}/clients" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$oauth2_proxy_client" >/dev/null 2>&1 || true
    log_info "  Created client: siab-oauth2-proxy (confidential)"

    # Admin services client (for Grafana, K8s Dashboard, etc.)
    local admin_client='{
        "clientId": "siab-admin-services",
        "name": "SIAB Admin Services",
        "description": "Admin services authentication",
        "enabled": true,
        "publicClient": false,
        "secret": "'"${DASHBOARD_CLIENT_SECRET}"'",
        "directAccessGrantsEnabled": true,
        "standardFlowEnabled": true,
        "implicitFlowEnabled": false,
        "serviceAccountsEnabled": true,
        "protocol": "openid-connect",
        "redirectUris": [
            "https://grafana.'"${SIAB_DOMAIN}"'/login/generic_oauth",
            "https://k8s-dashboard.'"${SIAB_DOMAIN}"'/*",
            "https://minio.'"${SIAB_DOMAIN}"'/*",
            "https://longhorn.'"${SIAB_DOMAIN}"'/*"
        ],
        "webOrigins": ["+"],
        "defaultClientScopes": ["openid", "profile", "email", "roles"]
    }'

    curl -sf -X POST "${KEYCLOAK_INTERNAL_URL}/admin/realms/${REALM_NAME}/clients" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$admin_client" >/dev/null 2>&1 || true
    log_info "  Created client: siab-admin-services (confidential)"
}

# Create protocol mappers for roles in tokens
create_role_mappers() {
    local token="$1"
    log_step "Creating protocol mappers for role claims..."

    # Get dashboard client ID
    local client_id
    client_id=$(curl -sf "${KEYCLOAK_INTERNAL_URL}/admin/realms/${REALM_NAME}/clients?clientId=siab-dashboard" \
        -H "Authorization: Bearer $token" | jq -r '.[0].id // empty')

    if [[ -n "$client_id" ]]; then
        # Create realm roles mapper
        local mapper='{
            "name": "realm-roles",
            "protocol": "openid-connect",
            "protocolMapper": "oidc-usermodel-realm-role-mapper",
            "consentRequired": false,
            "config": {
                "multivalued": "true",
                "userinfo.token.claim": "true",
                "id.token.claim": "true",
                "access.token.claim": "true",
                "claim.name": "roles",
                "jsonType.label": "String"
            }
        }'

        curl -sf -X POST "${KEYCLOAK_INTERNAL_URL}/admin/realms/${REALM_NAME}/clients/${client_id}/protocol-mappers/models" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "$mapper" >/dev/null 2>&1 || true

        # Create groups mapper
        local groups_mapper='{
            "name": "groups",
            "protocol": "openid-connect",
            "protocolMapper": "oidc-group-membership-mapper",
            "consentRequired": false,
            "config": {
                "full.path": "false",
                "userinfo.token.claim": "true",
                "id.token.claim": "true",
                "access.token.claim": "true",
                "claim.name": "groups"
            }
        }'

        curl -sf -X POST "${KEYCLOAK_INTERNAL_URL}/admin/realms/${REALM_NAME}/clients/${client_id}/protocol-mappers/models" \
            -H "Authorization: Bearer $token" \
            -H "Content-Type: application/json" \
            -d "$groups_mapper" >/dev/null 2>&1 || true

        log_info "  Created role and group mappers"
    fi
}

# Create default admin user
create_admin_user() {
    local token="$1"
    log_step "Creating default admin user..."

    # Check if user exists
    local existing_user
    existing_user=$(curl -sf "${KEYCLOAK_INTERNAL_URL}/admin/realms/${REALM_NAME}/users?username=siab-admin" \
        -H "Authorization: Bearer $token" | jq -r '.[0].id // empty')

    if [[ -n "$existing_user" ]]; then
        log_info "  Admin user already exists, skipping"
        return 0
    fi

    # Create user
    local user_config='{
        "username": "siab-admin",
        "email": "admin@'"${SIAB_DOMAIN}"'",
        "firstName": "SIAB",
        "lastName": "Administrator",
        "enabled": true,
        "emailVerified": true,
        "credentials": [{
            "type": "password",
            "value": "'"${DEFAULT_USER_PASSWORD}"'",
            "temporary": true
        }],
        "groups": ["administrators"],
        "requiredActions": ["UPDATE_PASSWORD"]
    }'

    local http_code
    http_code=$(curl -sf -o /dev/null -w "%{http_code}" -X POST "${KEYCLOAK_INTERNAL_URL}/admin/realms/${REALM_NAME}/users" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -d "$user_config")

    if [[ "$http_code" == "201" ]]; then
        # Get user ID and assign admin role
        local user_id
        user_id=$(curl -sf "${KEYCLOAK_INTERNAL_URL}/admin/realms/${REALM_NAME}/users?username=siab-admin" \
            -H "Authorization: Bearer $token" | jq -r '.[0].id')

        # Get admin role
        local role_id
        role_id=$(curl -sf "${KEYCLOAK_INTERNAL_URL}/admin/realms/${REALM_NAME}/roles/siab-admin" \
            -H "Authorization: Bearer $token" | jq -r '.id')

        if [[ -n "$user_id" && -n "$role_id" ]]; then
            curl -sf -X POST "${KEYCLOAK_INTERNAL_URL}/admin/realms/${REALM_NAME}/users/${user_id}/role-mappings/realm" \
                -H "Authorization: Bearer $token" \
                -H "Content-Type: application/json" \
                -d '[{"id": "'"${role_id}"'", "name": "siab-admin"}]' >/dev/null 2>&1 || true
        fi

        log_info "  Created user: siab-admin (temporary password: ${DEFAULT_USER_PASSWORD})"
    else
        log_warn "  Failed to create admin user (may already exist)"
    fi
}

# Save client secrets for other components
save_client_secrets() {
    log_step "Saving client secrets..."

    # Create secrets directory
    mkdir -p "${SIAB_CONFIG_DIR}/keycloak"
    chmod 700 "${SIAB_CONFIG_DIR}/keycloak"

    # Save OAuth2 proxy client secret
    cat > "${SIAB_CONFIG_DIR}/keycloak/oauth2-proxy.env" <<EOF
# OAuth2 Proxy Client Credentials
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
OAUTH2_PROXY_CLIENT_ID=siab-oauth2-proxy
OAUTH2_PROXY_CLIENT_SECRET=${OAUTH2_PROXY_CLIENT_SECRET}
EOF
    chmod 600 "${SIAB_CONFIG_DIR}/keycloak/oauth2-proxy.env"

    # Save admin services client secret
    cat > "${SIAB_CONFIG_DIR}/keycloak/admin-services.env" <<EOF
# Admin Services Client Credentials
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
ADMIN_CLIENT_ID=siab-admin-services
ADMIN_CLIENT_SECRET=${DASHBOARD_CLIENT_SECRET}
EOF
    chmod 600 "${SIAB_CONFIG_DIR}/keycloak/admin-services.env"

    # Save default user credentials
    cat > "${SIAB_CONFIG_DIR}/keycloak/default-user.env" <<EOF
# Default Admin User Credentials
# Generated: $(date -u +"%Y-%m-%d %H:%M:%S UTC")
# NOTE: User must change password on first login
DEFAULT_ADMIN_USER=siab-admin
DEFAULT_ADMIN_PASSWORD=${DEFAULT_USER_PASSWORD}
EOF
    chmod 600 "${SIAB_CONFIG_DIR}/keycloak/default-user.env"

    # Update main credentials file
    cat >> "${SIAB_CONFIG_DIR}/credentials.env" <<EOF

# Keycloak Realm Credentials (appended by configure-keycloak.sh)
SIAB_REALM=siab
OAUTH2_PROXY_CLIENT_SECRET=${OAUTH2_PROXY_CLIENT_SECRET}
DEFAULT_SIAB_USER=siab-admin
DEFAULT_SIAB_PASSWORD=${DEFAULT_USER_PASSWORD}
EOF

    log_info "  Client secrets saved to ${SIAB_CONFIG_DIR}/keycloak/"
}

# Create Kubernetes secrets for OAuth2 proxy
create_k8s_secrets() {
    log_step "Creating Kubernetes secrets for OAuth2 proxy..."

    # Generate cookie secret (use python3 if available, otherwise openssl)
    local cookie_secret
    if command -v python3 &>/dev/null; then
        cookie_secret=$(python3 -c 'import os,base64; print(base64.urlsafe_b64encode(os.urandom(32)).decode())')
    else
        # Fallback to openssl base64
        cookie_secret=$(openssl rand -base64 32 | tr -d '\n')
    fi

    # Create oauth2-proxy namespace if it doesn't exist
    kubectl create namespace oauth2-proxy 2>/dev/null || true
    kubectl label namespace oauth2-proxy istio-injection=enabled --overwrite 2>/dev/null || true

    # Create client secret
    kubectl create secret generic oauth2-proxy-client \
        --namespace oauth2-proxy \
        --from-literal=client-secret="${OAUTH2_PROXY_CLIENT_SECRET}" \
        --dry-run=client -o yaml | kubectl apply -f -

    # Update cookie secret
    kubectl create secret generic oauth2-proxy-secret \
        --namespace oauth2-proxy \
        --from-literal=cookie-secret="${cookie_secret}" \
        --dry-run=client -o yaml | kubectl apply -f -

    log_info "  Kubernetes secrets created"
}

# Main execution
main() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║         SIAB Keycloak Configuration                            ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    wait_for_keycloak

    log_step "Authenticating with Keycloak..."
    local token
    token=$(get_admin_token)

    if [[ -z "$token" ]]; then
        log_error "Failed to authenticate with Keycloak"
        exit 1
    fi
    log_info "Authenticated successfully"

    # Check if realm exists
    if realm_exists "$token"; then
        log_warn "Realm '${REALM_NAME}' already exists. Updating configuration..."
    else
        create_realm "$token"
    fi

    # Refresh token after realm creation
    token=$(get_admin_token)

    create_realm_roles "$token"
    create_groups "$token"
    create_clients "$token"
    create_role_mappers "$token"
    create_admin_user "$token"
    save_client_secrets
    create_k8s_secrets

    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║         Keycloak Configuration Complete!                       ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BLUE}Realm:${NC} ${REALM_NAME}"
    echo -e "  ${BLUE}URL:${NC} ${KEYCLOAK_URL}/realms/${REALM_NAME}"
    echo ""
    echo -e "  ${BLUE}Default Admin User:${NC}"
    echo -e "    Username: siab-admin"
    echo -e "    Password: ${DEFAULT_USER_PASSWORD}"
    echo -e "    ${YELLOW}(Password must be changed on first login)${NC}"
    echo ""
    echo -e "  ${BLUE}Roles:${NC}"
    echo -e "    - siab-admin (Full administrative access)"
    echo -e "    - siab-operator (Deploy and manage applications)"
    echo -e "    - siab-user (Use deployed applications)"
    echo ""
    echo -e "  ${BLUE}Groups:${NC}"
    echo -e "    - administrators (siab-admin role)"
    echo -e "    - operators (siab-operator role)"
    echo -e "    - users (siab-user role)"
    echo ""
    echo -e "  ${BLUE}Clients:${NC}"
    echo -e "    - siab-dashboard (public - for browser apps)"
    echo -e "    - siab-oauth2-proxy (confidential - for SSO)"
    echo -e "    - siab-admin-services (confidential - for admin tools)"
    echo ""
}

main "$@"
