#!/bin/bash
# SIAB - Istio Module
# Service mesh installation with dual-gateway architecture

# Requires: logging.sh, config.sh, progress/status.sh, checks/preflight.sh

# Install Istio with dual-gateway architecture (admin + user planes)
install_istio() {
    start_step "Istio Service Mesh"

    # Check if Istio is already properly installed
    if check_istio_installed; then
        skip_step "Istio Service Mesh" "Already installed with dual gateways"
        return 0
    fi

    log_info "Installing Istio ${ISTIO_VERSION} with dual-gateway architecture..."

    # Install Istio base
    helm upgrade --install istio-base istio/base \
        --namespace istio-system \
        --create-namespace \
        --version "${ISTIO_VERSION}" \
        --wait

    # Install Istio control plane with security settings
    helm upgrade --install istiod istio/istiod \
        --namespace istio-system \
        --version "${ISTIO_VERSION}" \
        --set global.proxy.privileged=false \
        --set global.mtls.enabled=true \
        --set meshConfig.enableAutoMtls=true \
        --set meshConfig.accessLogFile=/dev/stdout \
        --set pilot.autoscaleEnabled=true \
        --set pilot.autoscaleMin=2 \
        --wait

    # Wait for Istio control plane to be ready
    kubectl wait --for=condition=Available deployment --all -n istio-system --timeout=300s

    # Install ADMIN ingress gateway (for administrative interfaces)
    log_info "Installing admin ingress gateway..."
    helm upgrade --install istio-ingress-admin istio/gateway \
        --namespace istio-system \
        --version "${ISTIO_VERSION}" \
        --set replicaCount=2 \
        --set service.type=LoadBalancer \
        --set "service.annotations.metallb\\.universe\\.tf/address-pool=admin-pool" \
        --set "service.ports[0].name=http" \
        --set "service.ports[0].port=80" \
        --set "service.ports[0].targetPort=8080" \
        --set "service.ports[1].name=https" \
        --set "service.ports[1].port=443" \
        --set "service.ports[1].targetPort=8443" \
        --set "labels.istio=ingress-admin" \
        --wait

    # Install USER ingress gateway (for user applications)
    log_info "Installing user ingress gateway..."
    helm upgrade --install istio-ingress-user istio/gateway \
        --namespace istio-system \
        --version "${ISTIO_VERSION}" \
        --set replicaCount=2 \
        --set service.type=LoadBalancer \
        --set "service.annotations.metallb\\.universe\\.tf/address-pool=user-pool" \
        --set "service.ports[0].name=http" \
        --set "service.ports[0].port=80" \
        --set "service.ports[0].targetPort=8080" \
        --set "service.ports[1].name=https" \
        --set "service.ports[1].port=443" \
        --set "service.ports[1].targetPort=8443" \
        --set "labels.istio=ingress-user" \
        --wait

    # Wait for gateways to get IPs
    log_info "Waiting for LoadBalancer IPs to be assigned..."
    local max_wait=120
    local elapsed=0
    while [[ $elapsed -lt $max_wait ]]; do
        local admin_ip
        admin_ip=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        local user_ip
        user_ip=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        if [[ -n "$admin_ip" ]] && [[ -n "$user_ip" ]]; then
            log_info "Admin gateway IP: ${admin_ip}"
            log_info "User gateway IP: ${user_ip}"
            echo "ADMIN_GATEWAY_ACTUAL_IP=${admin_ip}" >> "${SIAB_CONFIG_DIR}/network.env"
            echo "USER_GATEWAY_ACTUAL_IP=${user_ip}" >> "${SIAB_CONFIG_DIR}/network.env"
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    # Apply strict mTLS policy
    cat <<EOF | kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
EOF

    complete_step "Istio Service Mesh"
    log_info "Istio installed with admin and user gateways"
}

# Install istioctl CLI
install_istioctl() {
    log_info "Installing istioctl ${ISTIO_VERSION}..."

    local istio_url="https://github.com/istio/istio/releases/download/${ISTIO_VERSION}/istio-${ISTIO_VERSION}-linux-amd64.tar.gz"

    if curl -fsSL "${istio_url}" -o /tmp/istio.tar.gz; then
        cd /tmp
        tar xzf istio.tar.gz
        mv "istio-${ISTIO_VERSION}/bin/istioctl" "${SIAB_BIN_DIR}/istioctl"
        chmod +x "${SIAB_BIN_DIR}/istioctl"
        rm -rf "istio-${ISTIO_VERSION}" istio.tar.gz
        cd - >/dev/null
        log_info "istioctl installed at ${SIAB_BIN_DIR}/istioctl"
    else
        log_warn "Failed to download istioctl, skipping..."
    fi
}

# Uninstall Istio
uninstall_istio() {
    log_info "Uninstalling Istio..."

    helm uninstall istio-ingress-user -n istio-system 2>/dev/null || true
    helm uninstall istio-ingress-admin -n istio-system 2>/dev/null || true
    helm uninstall istiod -n istio-system 2>/dev/null || true
    helm uninstall istio-base -n istio-system 2>/dev/null || true

    kubectl delete namespace istio-system --wait=false 2>/dev/null || true

    rm -f "${SIAB_BIN_DIR}/istioctl"

    log_info "Istio uninstalled"
}

# Create Istio Gateway configurations for admin and user planes
create_istio_gateway() {
    start_step "Istio Gateways"

    log_info "Creating Istio Gateway configurations..."

    # Admin Gateway - for Keycloak, Grafana, MinIO, etc.
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
---
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
    - "*.${SIAB_DOMAIN}"
    - "*.apps.${SIAB_DOMAIN}"
    tls:
      httpsRedirect: false
  - port:
      number: 443
      name: https
      protocol: HTTPS
    hosts:
    - "*.${SIAB_DOMAIN}"
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
