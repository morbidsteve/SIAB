#!/bin/bash
# SIAB - Cert-Manager Module
# Certificate management installation and configuration

# Requires: logging.sh, config.sh, progress/status.sh, checks/preflight.sh

# Install cert-manager
install_cert_manager() {
    start_step "cert-manager"

    # Check if cert-manager is already properly installed
    if check_cert_manager_installed; then
        skip_step "cert-manager" "Already installed and configured"
        return 0
    fi

    log_info "Installing cert-manager ${CERTMANAGER_VERSION}..."

    # Install CRDs first
    kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERTMANAGER_VERSION}/cert-manager.crds.yaml"

    # Install cert-manager via Helm
    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --create-namespace \
        --version "${CERTMANAGER_VERSION}" \
        --set installCRDs=false \
        --set global.leaderElection.namespace=cert-manager \
        --set securityContext.runAsNonRoot=true \
        --wait

    # Wait for cert-manager to be ready
    kubectl wait --for=condition=Available deployment --all -n cert-manager --timeout=300s

    # Create self-signed cluster issuer for internal use
    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: siab-selfsigned-issuer
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: siab-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: siab-ca
  secretName: siab-ca-secret
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: siab-selfsigned-issuer
    kind: ClusterIssuer
    group: cert-manager.io
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: siab-ca-issuer
spec:
  ca:
    secretName: siab-ca-secret
EOF

    complete_step "cert-manager"
    log_info "cert-manager installed"
}

# Uninstall cert-manager
uninstall_cert_manager() {
    log_info "Uninstalling cert-manager..."

    # Remove Helm release
    helm uninstall cert-manager -n cert-manager 2>/dev/null || true

    # Remove CRDs
    kubectl delete -f "https://github.com/cert-manager/cert-manager/releases/download/${CERTMANAGER_VERSION}/cert-manager.crds.yaml" 2>/dev/null || true

    # Remove namespace
    kubectl delete namespace cert-manager --wait=false 2>/dev/null || true

    log_info "cert-manager uninstalled"
}
