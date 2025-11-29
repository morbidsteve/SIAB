#!/bin/bash
# Display SIAB credentials stored in Kubernetes secrets
# Usage: ./show-credentials.sh [service-name]

NAMESPACE="siab-system"

show_credential() {
    local secret_name="$1"
    local cred_type="$2"

    echo "----------------------------------------"

    # Get all fields
    local service_name=$(kubectl get secret "$secret_name" -n $NAMESPACE -o jsonpath='{.data.service-name}' 2>/dev/null | base64 -d)
    local url=$(kubectl get secret "$secret_name" -n $NAMESPACE -o jsonpath='{.data.url}' 2>/dev/null | base64 -d)
    local notes=$(kubectl get secret "$secret_name" -n $NAMESPACE -o jsonpath='{.data.notes}' 2>/dev/null | base64 -d)

    echo "Service: $service_name"
    echo "URL: $url"

    if [ "$cred_type" = "token" ]; then
        local token=$(kubectl get secret "$secret_name" -n $NAMESPACE -o jsonpath='{.data.token}' 2>/dev/null | base64 -d)
        echo "Token: $token"
    else
        local username=$(kubectl get secret "$secret_name" -n $NAMESPACE -o jsonpath='{.data.username}' 2>/dev/null | base64 -d)
        local password=$(kubectl get secret "$secret_name" -n $NAMESPACE -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)
        echo "Username: $username"
        echo "Password: $password"
    fi

    echo "Notes: $notes"
    echo ""
}

if [ -n "$1" ]; then
    # Show specific credential
    SERVICE="$1"

    # Check for system credential first
    if kubectl get secret "system-creds-$SERVICE" -n $NAMESPACE >/dev/null 2>&1; then
        echo ""
        echo "=== System Credential: $SERVICE ==="
        # Check if it's a token-based credential
        if kubectl get secret "system-creds-$SERVICE" -n $NAMESPACE -o jsonpath='{.data.token}' >/dev/null 2>&1; then
            show_credential "system-creds-$SERVICE" "token"
        else
            show_credential "system-creds-$SERVICE" "password"
        fi
    # Check for app credential
    elif kubectl get secret "app-creds-$SERVICE" -n $NAMESPACE >/dev/null 2>&1; then
        echo ""
        echo "=== App Credential: $SERVICE ==="
        show_credential "app-creds-$SERVICE" "password"

        # Check for OIDC config
        local oidc_client=$(kubectl get secret "app-creds-$SERVICE" -n $NAMESPACE -o jsonpath='{.data.oidc_client_id}' 2>/dev/null | base64 -d)
        if [ -n "$oidc_client" ]; then
            echo "OIDC Client ID: $oidc_client"
            local oidc_secret=$(kubectl get secret "app-creds-$SERVICE" -n $NAMESPACE -o jsonpath='{.data.oidc_client_secret}' 2>/dev/null | base64 -d)
            echo "OIDC Client Secret: $oidc_secret"
            echo "OIDC Issuer: https://keycloak.siab.local/realms/siab"
        fi
    else
        echo "No credentials found for: $SERVICE"
        echo ""
        echo "Available credentials:"
        kubectl get secrets -n $NAMESPACE -l siab.local/credential-type -o custom-columns='NAME:.metadata.labels.siab\.local/service-name,TYPE:.metadata.labels.siab\.local/credential-type' 2>/dev/null | grep -v "^<none>"
        kubectl get secrets -n $NAMESPACE -l siab.local/credential-type=app-credentials -o custom-columns='NAME:.metadata.labels.siab\.local/app-name' 2>/dev/null | grep -v "^<none>" | sed 's/^/app: /'
        exit 1
    fi
else
    # Show all credentials
    echo ""
    echo "=========================================="
    echo "       SIAB System Credentials"
    echo "=========================================="

    # List system credentials
    for secret in $(kubectl get secrets -n $NAMESPACE -l siab.local/credential-type=system-credentials -o name 2>/dev/null); do
        secret_name=$(echo "$secret" | sed 's/secret\///')
        if kubectl get secret "$secret_name" -n $NAMESPACE -o jsonpath='{.data.token}' 2>/dev/null | grep -q .; then
            show_credential "$secret_name" "token"
        else
            show_credential "$secret_name" "password"
        fi
    done

    echo ""
    echo "=========================================="
    echo "       SIAB App Credentials"
    echo "=========================================="

    # List app credentials
    for secret in $(kubectl get secrets -n $NAMESPACE -l siab.local/credential-type=app-credentials -o name 2>/dev/null); do
        secret_name=$(echo "$secret" | sed 's/secret\///')
        show_credential "$secret_name" "password"
    done

    if [ -z "$(kubectl get secrets -n $NAMESPACE -l siab.local/credential-type -o name 2>/dev/null)" ]; then
        echo "No credentials stored yet."
        echo "Run ./store-system-credentials.sh to store system credentials."
    fi
fi
