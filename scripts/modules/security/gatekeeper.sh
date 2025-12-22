#!/bin/bash
# SIAB - OPA Gatekeeper Module
# Policy engine installation

# Requires: logging.sh, config.sh, progress/status.sh, checks/preflight.sh

# Install OPA Gatekeeper
install_gatekeeper() {
    start_step "OPA Gatekeeper"

    # Check if Gatekeeper is already installed
    if check_helm_release_installed "gatekeeper" "gatekeeper-system"; then
        skip_step "OPA Gatekeeper" "Already installed"
        return 0
    fi

    log_info "Installing OPA Gatekeeper ${GATEKEEPER_VERSION}..."

    # Create namespace
    kubectl create namespace gatekeeper-system 2>/dev/null || true

    helm upgrade --install gatekeeper gatekeeper/gatekeeper \
        --namespace gatekeeper-system \
        --version "${GATEKEEPER_VERSION}" \
        --set replicas=2 \
        --set audit.replicas=1 \
        --set constraintViolationsLimit=100 \
        --set auditInterval=60 \
        --set enableExternalData=true \
        --wait

    # Wait for Gatekeeper to be ready
    kubectl wait --for=condition=Available deployment --all -n gatekeeper-system --timeout=300s

    complete_step "OPA Gatekeeper"
    log_info "OPA Gatekeeper installed"
}

# Apply security policies
apply_security_policies() {
    log_info "Applying security policies..."

    # Apply constraint templates and constraints from repo
    if [[ -d "${SIAB_REPO_DIR}/policies/gatekeeper" ]]; then
        for file in "${SIAB_REPO_DIR}"/policies/gatekeeper/*.yaml; do
            if [[ -f "$file" ]]; then
                kubectl apply -f "$file" 2>/dev/null || true
            fi
        done
        log_info "Security policies applied"
    else
        log_warn "Gatekeeper policies directory not found"
    fi
}

# Uninstall OPA Gatekeeper
uninstall_gatekeeper() {
    log_info "Uninstalling OPA Gatekeeper..."

    helm uninstall gatekeeper -n gatekeeper-system 2>/dev/null || true
    kubectl delete namespace gatekeeper-system --wait=false 2>/dev/null || true

    log_info "OPA Gatekeeper uninstalled"
}
