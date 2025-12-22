#!/bin/bash
# SIAB - OAuth2 Proxy Module
# SSO enforcement proxy installation

# Requires: logging.sh, config.sh, progress/status.sh

# Install OAuth2 Proxy
install_oauth2_proxy() {
    start_step "OAuth2 Proxy"

    # Check if OAuth2 Proxy is already running
    if kubectl get deployment oauth2-proxy -n oauth2-proxy -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -q "[1-9]"; then
        skip_step "OAuth2 Proxy" "Already installed and running"
        return 0
    fi

    log_info "Installing OAuth2 Proxy for SSO enforcement..."

    # Create namespace
    kubectl create namespace oauth2-proxy 2>/dev/null || true
    kubectl label namespace oauth2-proxy istio-injection=enabled --overwrite

    # Apply OAuth2 Proxy manifests (secrets should be created by configure-keycloak.sh)
    if [[ -f "${SIAB_REPO_DIR}/manifests/oauth2-proxy/oauth2-proxy.yaml" ]]; then
        # Replace domain placeholder
        sed "s/siab\.local/${SIAB_DOMAIN}/g" "${SIAB_REPO_DIR}/manifests/oauth2-proxy/oauth2-proxy.yaml" | kubectl apply -f -
    else
        log_warn "OAuth2 Proxy manifest not found"
        skip_step "OAuth2 Proxy" "Manifest not found"
        return 0
    fi

    # Wait for OAuth2 Proxy to be ready
    log_info "Waiting for OAuth2 Proxy to be ready..."
    local max_wait=120
    local elapsed=0
    while [[ $elapsed -lt $max_wait ]]; do
        if kubectl get deployment oauth2-proxy -n oauth2-proxy -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -q "[1-9]"; then
            log_info "OAuth2 Proxy is ready"
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    if [[ $elapsed -ge $max_wait ]]; then
        log_warn "OAuth2 Proxy did not become ready in time (may still be starting)"
    fi

    # Add auth.siab.local to hosts configuration
    local user_gateway_ip
    user_gateway_ip=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    if [[ -n "$user_gateway_ip" ]]; then
        if ! grep -q "auth.${SIAB_DOMAIN}" /etc/hosts; then
            echo "${user_gateway_ip} auth.${SIAB_DOMAIN}" >> /etc/hosts
            log_info "Added auth.${SIAB_DOMAIN} to /etc/hosts"
        fi
    fi

    complete_step "OAuth2 Proxy"
    log_info "OAuth2 Proxy installed"
}

# Configure SSO enforcement for all applications
configure_sso() {
    start_step "SSO Configuration"

    log_info "Configuring SSO enforcement policies..."

    # Apply SSO enforcement policies
    if [[ -f "${SIAB_REPO_DIR}/manifests/istio/auth/sso-enforcement.yaml" ]]; then
        # Replace domain placeholder
        sed "s/siab\.local/${SIAB_DOMAIN}/g" "${SIAB_REPO_DIR}/manifests/istio/auth/sso-enforcement.yaml" | kubectl apply -f -
        log_info "SSO enforcement policies applied"
    else
        log_warn "SSO enforcement manifest not found"
    fi

    # Apply user-apps-auth if it exists
    if [[ -f "${SIAB_REPO_DIR}/manifests/istio/auth/user-apps-auth.yaml" ]]; then
        sed "s/siab\.local/${SIAB_DOMAIN}/g" "${SIAB_REPO_DIR}/manifests/istio/auth/user-apps-auth.yaml" | kubectl apply -f -
        log_info "User apps auth policies applied"
    fi

    complete_step "SSO Configuration"
    log_info "SSO configuration complete"
}

# Uninstall OAuth2 Proxy
uninstall_oauth2_proxy() {
    log_info "Uninstalling OAuth2 Proxy..."

    kubectl delete deployment oauth2-proxy -n oauth2-proxy 2>/dev/null || true
    kubectl delete service oauth2-proxy -n oauth2-proxy 2>/dev/null || true
    kubectl delete secret oauth2-proxy-client oauth2-proxy-secret -n oauth2-proxy 2>/dev/null || true
    kubectl delete namespace oauth2-proxy --wait=false 2>/dev/null || true

    log_info "OAuth2 Proxy uninstalled"
}
