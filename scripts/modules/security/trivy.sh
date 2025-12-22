#!/bin/bash
# SIAB - Trivy Module
# Security scanning installation

# Requires: logging.sh, config.sh, progress/status.sh, checks/preflight.sh

# Install Trivy Operator
install_trivy() {
    start_step "Trivy Security Scanner"

    # Check if Trivy is already installed
    if check_helm_release_installed "trivy-operator" "trivy-system"; then
        skip_step "Trivy Security Scanner" "Already installed"
        return 0
    fi

    log_info "Installing Trivy Operator ${TRIVY_VERSION}..."

    # Create namespace
    kubectl create namespace trivy-system 2>/dev/null || true

    helm upgrade --install trivy-operator aqua/trivy-operator \
        --namespace trivy-system \
        --version "${TRIVY_VERSION}" \
        --set trivy.ignoreUnfixed=false \
        --set operator.scanJobTimeout=10m \
        --set operator.vulnerabilityScannerEnabled=true \
        --set operator.configAuditScannerEnabled=true \
        --set operator.rbacAssessmentScannerEnabled=true \
        --set operator.infraAssessmentScannerEnabled=true \
        --set operator.clusterComplianceEnabled=true \
        --wait

    complete_step "Trivy Security Scanner"
    log_info "Trivy Operator installed"
}

# Uninstall Trivy
uninstall_trivy() {
    log_info "Uninstalling Trivy Operator..."

    helm uninstall trivy-operator -n trivy-system 2>/dev/null || true
    kubectl delete namespace trivy-system --wait=false 2>/dev/null || true

    log_info "Trivy Operator uninstalled"
}
