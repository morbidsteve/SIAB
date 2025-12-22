#!/bin/bash
# SIAB - SIAB Applications Module
# SIAB Dashboard and Deployer installation

# Requires: logging.sh, config.sh, utils.sh, progress/status.sh

# Install SIAB landing page dashboard
install_dashboard() {
    start_step "SIAB Dashboard"

    # Check if dashboard is already running
    if kubectl get deployment siab-dashboard -n siab-dashboard -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -q "[1-9]"; then
        skip_step "SIAB Dashboard" "Already installed and running"
        return 0
    fi

    log_info "Installing SIAB Dashboard..."

    # Create namespace
    run_quiet_ok kubectl create namespace siab-dashboard
    run_quiet_ok kubectl label namespace siab-dashboard istio-injection=enabled --overwrite

    # Read the HTML content from the frontend
    local html_content=""
    if [[ -f "${SIAB_REPO_DIR}/dashboard/frontend/index.html" ]]; then
        html_content=$(cat "${SIAB_REPO_DIR}/dashboard/frontend/index.html")
        html_content=$(echo "$html_content" | sed "s/siab\.local/${SIAB_DOMAIN}/g")
    else
        log_warn "Dashboard HTML not found, using placeholder"
        html_content='<!DOCTYPE html><html><head><title>SIAB Dashboard</title></head><body><h1>SIAB Dashboard</h1><p>Welcome to SIAB!</p></body></html>'
    fi

    # Create the ConfigMap with the actual HTML content
    kubectl create configmap siab-dashboard-html \
        --from-literal=index.html="$html_content" \
        -n siab-dashboard \
        --dry-run=client -o yaml 2>/dev/null | run_quiet kubectl apply -f -

    # Deploy dashboard manifests (ConfigMap is already created above)
    if [[ -f "${SIAB_REPO_DIR}/manifests/dashboard/siab-dashboard.yaml" ]]; then
        sed "s/siab\.local/${SIAB_DOMAIN}/g" "${SIAB_REPO_DIR}/manifests/dashboard/siab-dashboard.yaml" | \
            run_quiet kubectl apply -f -
        log_info "Dashboard manifests applied"
    else
        log_warn "Dashboard manifest not found at ${SIAB_REPO_DIR}/manifests/dashboard/siab-dashboard.yaml"
    fi

    # Wait for dashboard to be ready
    log_info "Waiting for SIAB Dashboard to be ready..."
    local max_wait=120
    local elapsed=0
    while [[ $elapsed -lt $max_wait ]]; do
        if kubectl get deployment siab-dashboard -n siab-dashboard -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -q "[1-9]"; then
            log_info "Dashboard is ready"
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    complete_step "SIAB Dashboard"
    log_info "Dashboard setup complete"
}

# Install SIAB Application Deployer
install_deployer() {
    start_step "SIAB Deployer"

    # Check if deployer is already running
    if kubectl get deployment app-deployer-frontend -n siab-deployer -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -q "[1-9]"; then
        skip_step "SIAB Deployer" "Already installed and running"
        return 0
    fi

    log_info "Installing SIAB Application Deployer..."

    # Check if deployer deployment manifest exists
    local deployer_manifest="${SIAB_REPO_DIR}/app-deployer/deploy/deployer-deployment.yaml"
    if [[ ! -f "$deployer_manifest" ]]; then
        log_warn "Deployer manifest not found at $deployer_manifest"
        skip_step "SIAB Deployer" "Manifest not found"
        return 0
    fi

    # Create namespace with istio injection
    run_quiet_ok kubectl create namespace siab-deployer
    run_quiet_ok kubectl label namespace siab-deployer istio-injection=enabled --overwrite

    # Create backend code ConfigMap from actual source files
    local backend_dir="${SIAB_REPO_DIR}/app-deployer/backend"
    if [[ -f "${backend_dir}/app-deployer-api.py" ]] && [[ -f "${backend_dir}/requirements.txt" ]]; then
        kubectl create configmap deployer-backend-code \
            --from-file=app-deployer-api.py="${backend_dir}/app-deployer-api.py" \
            --from-file=requirements.txt="${backend_dir}/requirements.txt" \
            -n siab-deployer \
            --dry-run=client -o yaml 2>/dev/null | run_quiet kubectl apply -f -
        log_info "Backend code ConfigMap created from ${backend_dir}"
    else
        log_error "Backend source files not found at ${backend_dir}"
        log_error "Expected: app-deployer-api.py and requirements.txt"
        fail_step "SIAB Deployer" "Backend source files missing"
        return 1
    fi

    # Read and inject frontend HTML content if it exists
    local frontend_html="${SIAB_REPO_DIR}/app-deployer/frontend/index.html"
    if [[ -f "$frontend_html" ]]; then
        local html_content
        html_content=$(cat "$frontend_html" | sed "s/siab\.local/${SIAB_DOMAIN}/g")

        kubectl create configmap app-deployer-frontend-html \
            --from-literal=index.html="$html_content" \
            -n siab-deployer \
            --dry-run=client -o yaml 2>/dev/null | run_quiet kubectl apply -f -

        kubectl create configmap deployer-frontend-html \
            --from-literal=index.html="$html_content" \
            -n siab-deployer \
            --dry-run=client -o yaml 2>/dev/null | run_quiet kubectl apply -f -
    fi

    # Apply the deployer manifest with domain substitution
    sed "s/siab\.local/${SIAB_DOMAIN}/g" "$deployer_manifest" | \
        run_quiet kubectl apply -f -
    log_info "Deployer manifests applied"

    # Wait for deployer to be ready
    log_info "Waiting for SIAB Deployer to be ready..."
    local max_wait=180
    local elapsed=0
    while [[ $elapsed -lt $max_wait ]]; do
        if kubectl get deployment app-deployer-frontend -n siab-deployer -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -q "[1-9]"; then
            log_info "Deployer frontend is ready"
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    complete_step "SIAB Deployer"
    log_info "Deployer setup complete"
}

# Install SIAB tools (status script, etc.)
install_siab_tools() {
    start_step "SIAB Tools"

    log_info "Installing SIAB management tools..."

    # Install siab-status script
    if [[ -f "${SIAB_REPO_DIR}/siab-status.sh" ]]; then
        cp "${SIAB_REPO_DIR}/siab-status.sh" "${SIAB_BIN_DIR}/siab-status"
        chmod +x "${SIAB_BIN_DIR}/siab-status"
        log_info "siab-status command installed"
    fi

    # Install siab-info script
    if [[ -f "${SIAB_REPO_DIR}/siab-info.sh" ]]; then
        cp "${SIAB_REPO_DIR}/siab-info.sh" "${SIAB_BIN_DIR}/siab-info"
        chmod +x "${SIAB_BIN_DIR}/siab-info"
        log_info "siab-info command installed"
    fi

    # Install fix-rke2 script
    if [[ -f "${SIAB_REPO_DIR}/fix-rke2.sh" ]]; then
        cp "${SIAB_REPO_DIR}/fix-rke2.sh" "${SIAB_BIN_DIR}/siab-fix-rke2"
        chmod +x "${SIAB_BIN_DIR}/siab-fix-rke2"
    fi

    # Install uninstall script
    if [[ -f "${SIAB_REPO_DIR}/uninstall.sh" ]]; then
        cp "${SIAB_REPO_DIR}/uninstall.sh" "${SIAB_BIN_DIR}/siab-uninstall"
        chmod +x "${SIAB_BIN_DIR}/siab-uninstall"
    fi

    # Install fix-istio-routing script
    if [[ -f "${SIAB_REPO_DIR}/fix-istio-routing.sh" ]]; then
        cp "${SIAB_REPO_DIR}/fix-istio-routing.sh" "${SIAB_BIN_DIR}/siab-fix-istio"
        chmod +x "${SIAB_BIN_DIR}/siab-fix-istio"
    fi

    # Install diagnostic script
    if [[ -f "${SIAB_REPO_DIR}/siab-diagnose.sh" ]]; then
        cp "${SIAB_REPO_DIR}/siab-diagnose.sh" "${SIAB_BIN_DIR}/siab-diagnose"
        chmod +x "${SIAB_BIN_DIR}/siab-diagnose"
    fi

    complete_step "SIAB Tools"
    log_info "SIAB tools installed"
}

# Install SIAB CRDs
install_siab_crds() {
    start_step "SIAB CRDs"

    log_info "Installing SIAB Custom Resource Definitions..."

    # Install CRDs from repo
    if [[ -d "${SIAB_REPO_DIR}/crds" ]]; then
        kubectl apply -f "${SIAB_REPO_DIR}/crds/"
        log_info "SIAB CRDs installed from ${SIAB_REPO_DIR}/crds/"
    else
        log_warn "CRDs directory not found, skipping CRD installation"
    fi

    # Copy CRDs to SIAB directory for reference
    if [[ -d "${SIAB_REPO_DIR}/crds" ]]; then
        cp -r "${SIAB_REPO_DIR}/crds" "${SIAB_DIR}/"
    fi

    # Copy examples for reference
    if [[ -d "${SIAB_REPO_DIR}/examples" ]]; then
        cp -r "${SIAB_REPO_DIR}/examples" "${SIAB_DIR}/"
        log_info "Example manifests copied to ${SIAB_DIR}/examples/"
    fi

    # Copy manifests for reference
    if [[ -d "${SIAB_REPO_DIR}/manifests" ]]; then
        cp -r "${SIAB_REPO_DIR}/manifests" "${SIAB_DIR}/"
        log_info "Manifests copied to ${SIAB_DIR}/manifests/"
    fi

    complete_step "SIAB CRDs"
    log_info "SIAB CRDs installed"
}

# Uninstall SIAB Dashboard
uninstall_siab_dashboard() {
    log_info "Uninstalling SIAB Dashboard..."
    kubectl delete namespace siab-dashboard --wait=false 2>/dev/null || true
    log_info "SIAB Dashboard uninstalled"
}

# Uninstall SIAB Deployer
uninstall_siab_deployer() {
    log_info "Uninstalling SIAB Deployer..."
    kubectl delete namespace siab-deployer --wait=false 2>/dev/null || true
    log_info "SIAB Deployer uninstalled"
}

# Uninstall SIAB Tools
uninstall_siab_tools() {
    log_info "Removing SIAB tools..."
    rm -f "${SIAB_BIN_DIR}/siab-status"
    rm -f "${SIAB_BIN_DIR}/siab-info"
    rm -f "${SIAB_BIN_DIR}/siab-fix-rke2"
    rm -f "${SIAB_BIN_DIR}/siab-uninstall"
    rm -f "${SIAB_BIN_DIR}/siab-fix-istio"
    rm -f "${SIAB_BIN_DIR}/siab-diagnose"
    log_info "SIAB tools removed"
}
