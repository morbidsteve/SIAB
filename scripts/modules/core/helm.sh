#!/bin/bash
# SIAB - Helm Module
# Helm package manager installation

# Requires: logging.sh, config.sh, progress/status.sh, checks/preflight.sh

# Install Helm package manager
install_helm() {
    start_step "Helm Package Manager"

    # Check if Helm is already properly installed
    if check_helm_installed; then
        skip_step "Helm Package Manager" "Already installed with required repos"
        export PATH="${SIAB_BIN_DIR}:${PATH}"
        return 0
    fi

    log_info "Installing Helm ${HELM_VERSION}..."

    # Download and extract Helm
    local helm_url="https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
    log_info "Downloading Helm from ${helm_url}..."

    if ! curl -fsSL "${helm_url}" -o /tmp/helm.tar.gz; then
        log_error "Failed to download Helm"
        fail_step "Helm Package Manager" "Download failed"
        return 1
    fi

    cd /tmp
    tar xzf helm.tar.gz
    mv linux-amd64/helm "${SIAB_BIN_DIR}/helm"
    rm -rf linux-amd64 helm.tar.gz
    chmod +x "${SIAB_BIN_DIR}/helm"
    cd - >/dev/null

    # Verify helm binary exists
    if [[ ! -x "${SIAB_BIN_DIR}/helm" ]]; then
        log_error "Helm binary not found at ${SIAB_BIN_DIR}/helm"
        fail_step "Helm Package Manager" "Binary not installed"
        return 1
    fi

    log_info "Helm binary installed at ${SIAB_BIN_DIR}/helm"

    # Ensure PATH is updated
    export PATH="${SIAB_BIN_DIR}:${PATH}"
    hash -r 2>/dev/null || true

    # Add Helm repos using full path
    log_info "Adding Helm repositories..."
    "${SIAB_BIN_DIR}/helm" repo add istio https://istio-release.storage.googleapis.com/charts || true
    "${SIAB_BIN_DIR}/helm" repo add jetstack https://charts.jetstack.io || true
    "${SIAB_BIN_DIR}/helm" repo add codecentric https://codecentric.github.io/helm-charts || true
    "${SIAB_BIN_DIR}/helm" repo add aqua https://aquasecurity.github.io/helm-charts/ || true
    "${SIAB_BIN_DIR}/helm" repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts || true
    "${SIAB_BIN_DIR}/helm" repo add minio https://charts.min.io/ || true
    "${SIAB_BIN_DIR}/helm" repo add prometheus-community https://prometheus-community.github.io/helm-charts || true
    "${SIAB_BIN_DIR}/helm" repo add kubernetes-dashboard https://kubernetes.github.io/dashboard/ || true
    "${SIAB_BIN_DIR}/helm" repo add longhorn https://charts.longhorn.io || true
    "${SIAB_BIN_DIR}/helm" repo add metallb https://metallb.github.io/metallb || true
    "${SIAB_BIN_DIR}/helm" repo add oauth2-proxy https://oauth2-proxy.github.io/manifests || true
    "${SIAB_BIN_DIR}/helm" repo update

    complete_step "Helm Package Manager"
    log_info "Helm installed successfully"
}

# Uninstall Helm
uninstall_helm() {
    log_info "Removing Helm..."
    rm -f "${SIAB_BIN_DIR}/helm"
    rm -rf ~/.config/helm
    rm -rf ~/.cache/helm
    log_info "Helm removed"
}
