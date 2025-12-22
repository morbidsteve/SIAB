#!/bin/bash
# SIAB - SSO Configuration Module
# SSO enforcement and Istio gateway configuration

# Requires: logging.sh, config.sh, progress/status.sh

# Configure SSO enforcement for all applications
configure_sso() {
    start_step "SSO Configuration"

    log_info "Configuring SSO enforcement policies..."

    # Apply SSO enforcement policies
    if [[ -f "${SIAB_REPO_DIR}/manifests/istio/auth/sso-enforcement.yaml" ]]; then
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

# Create Istio Gateway configurations for admin and user planes
create_istio_gateway() {
    start_step "Istio Gateways"

    # Check if gateways already exist
    if kubectl get gateway admin-gateway -n istio-system &>/dev/null && \
       kubectl get gateway user-gateway -n istio-system &>/dev/null; then
        skip_step "Istio Gateways" "Already configured"
        return 0
    fi

    log_info "Creating Istio Gateway configurations..."

    # Create certificate for gateways
    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: siab-gateway-cert
  namespace: istio-system
spec:
  secretName: siab-gateway-cert
  issuerRef:
    name: siab-ca-issuer
    kind: ClusterIssuer
  commonName: "*.${SIAB_DOMAIN}"
  dnsNames:
    - "*.${SIAB_DOMAIN}"
    - "${SIAB_DOMAIN}"
EOF

    # Create Admin Gateway
    cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: admin-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingress-admin
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*.${SIAB_DOMAIN}"
    tls:
      httpsRedirect: false
  - port:
      number: 443
      name: https
      protocol: HTTPS
    hosts:
    - "*.${SIAB_DOMAIN}"
    tls:
      mode: SIMPLE
      credentialName: siab-gateway-cert
EOF

    # Create User Gateway
    cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: user-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingress-user
  servers:
  - port:
      number: 80
      name: http
      protocol: HTTP
    hosts:
    - "*.apps.${SIAB_DOMAIN}"
    tls:
      httpsRedirect: false
  - port:
      number: 443
      name: https
      protocol: HTTPS
    hosts:
    - "*.apps.${SIAB_DOMAIN}"
    tls:
      mode: SIMPLE
      credentialName: siab-gateway-cert
EOF

    complete_step "Istio Gateways"
    log_info "Istio Gateway configurations created"
}

# Fix mTLS for services that don't have Istio sidecars
fix_istio_mtls_for_non_sidecar_services() {
    log_info "Configuring mTLS exceptions for non-sidecar services..."

    # Allow permissive mTLS for longhorn-system namespace
    cat <<EOF | kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: longhorn-permissive
  namespace: longhorn-system
spec:
  mtls:
    mode: PERMISSIVE
EOF

    log_info "mTLS exceptions configured"
}

# Final configuration steps
final_configuration() {
    start_step "Final Configuration"

    log_info "Running final configuration steps..."

    # Fix mTLS for non-sidecar services
    fix_istio_mtls_for_non_sidecar_services

    # Update hosts file
    update_hosts_file 2>/dev/null || true

    # Setup non-root user access
    setup_nonroot_access 2>/dev/null || true

    # Generate dashboard token and save it
    log_info "Generating Kubernetes Dashboard access token..."
    local dashboard_token
    dashboard_token=$(kubectl get secret siab-admin-token -n kubernetes-dashboard -o jsonpath='{.data.token}' 2>/dev/null | base64 -d || echo "")

    if [[ -n "$dashboard_token" ]]; then
        echo "" >> "${SIAB_CONFIG_DIR}/credentials.env"
        echo "# Kubernetes Dashboard Token" >> "${SIAB_CONFIG_DIR}/credentials.env"
        echo "KUBERNETES_DASHBOARD_TOKEN=${dashboard_token}" >> "${SIAB_CONFIG_DIR}/credentials.env"
    fi

    complete_step "Final Configuration"
    log_info "Final configuration complete"
}
