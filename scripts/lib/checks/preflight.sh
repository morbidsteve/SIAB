#!/bin/bash
# SIAB - Preflight Checks Library
# System requirements and component installation checks

# Requires: logging.sh, config.sh to be sourced first

# Check system requirements (CPU, RAM, disk)
check_requirements() {
    log_info "Checking system requirements..."

    # Check OS
    log_info "Detected OS: ${OS_NAME} (${OS_ID} ${OS_VERSION_ID})"
    log_info "OS Family: ${OS_FAMILY}"

    # Check CPU cores
    local cpu_cores
    cpu_cores=$(nproc)
    if [[ $cpu_cores -lt 4 ]]; then
        log_error "Minimum 4 CPU cores required (found: $cpu_cores)"
        return 1
    fi
    log_info "CPU cores: $cpu_cores (minimum: 4)"

    # Check RAM
    local total_ram
    total_ram=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $total_ram -lt 14 ]]; then
        log_error "Minimum 16GB RAM required (found: ${total_ram}GB)"
        return 1
    fi
    log_info "RAM: ${total_ram}GB (minimum: 16GB)"

    # Check disk space
    local free_space
    free_space=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $free_space -lt 25 ]]; then
        log_error "Minimum 30GB free disk space required (found: ${free_space}GB)"
        return 1
    fi
    log_info "Free disk space: ${free_space}GB (minimum: 30GB)"

    log_info "System requirements met"
    return 0
}

# Check if RKE2 is already installed and working correctly
check_rke2_installed() {
    log_info "Checking RKE2 installation status..."

    # Check if RKE2 binary exists
    if [[ ! -f /var/lib/rancher/rke2/bin/kubectl ]]; then
        log_info "RKE2 not installed (kubectl not found)"
        return 1
    fi

    # Check if RKE2 service is running
    if ! systemctl is-active --quiet rke2-server 2>/dev/null; then
        log_warn "RKE2 service is not running"
        return 1
    fi

    # Check if kubeconfig exists
    if [[ ! -f /etc/rancher/rke2/rke2.yaml ]]; then
        log_warn "RKE2 kubeconfig not found"
        return 1
    fi

    # Check if we can communicate with the cluster
    if ! /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes &>/dev/null; then
        log_warn "Cannot communicate with Kubernetes cluster"
        return 1
    fi

    # Check if node is Ready
    local node_status
    node_status=$(/var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    if [[ "$node_status" != "True" ]]; then
        log_warn "Kubernetes node is not Ready (status: $node_status)"
        return 1
    fi

    # Check if core components are running
    local core_pods_running
    core_pods_running=$(/var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get pods -n kube-system --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$core_pods_running" -lt 5 ]]; then
        log_warn "Not enough core pods running (found: $core_pods_running)"
        return 1
    fi

    log_info "RKE2 is properly installed and running"
    return 0
}

# Check if Helm is already installed correctly
check_helm_installed() {
    log_info "Checking Helm installation status..."

    # Check if helm binary exists in expected location
    if [[ ! -x "${SIAB_BIN_DIR}/helm" ]]; then
        # Also check system PATH
        if ! command -v helm &>/dev/null; then
            log_info "Helm not installed"
            return 1
        fi
    fi

    # Verify helm works
    local helm_cmd="${SIAB_BIN_DIR}/helm"
    [[ ! -x "$helm_cmd" ]] && helm_cmd="helm"

    if ! "$helm_cmd" version &>/dev/null; then
        log_warn "Helm binary exists but not working"
        return 1
    fi

    # Check if required repos are configured
    local repos_ok=true
    for repo in istio jetstack prometheus-community kubernetes-dashboard; do
        if ! "$helm_cmd" repo list 2>/dev/null | grep -q "$repo"; then
            log_info "Helm repo '$repo' not configured"
            repos_ok=false
            break
        fi
    done

    if [[ "$repos_ok" == "false" ]]; then
        log_warn "Helm repos not fully configured"
        return 1
    fi

    log_info "Helm is properly installed with required repos"
    return 0
}

# Check if k9s is already installed correctly
check_k9s_installed() {
    log_info "Checking k9s installation status..."

    # Check if k9s binary exists in expected location
    if [[ ! -x "${SIAB_BIN_DIR}/k9s" ]]; then
        # Also check system PATH
        if ! command -v k9s &>/dev/null; then
            log_info "k9s not installed"
            return 1
        fi
    fi

    # Verify k9s works (just check version)
    local k9s_cmd="${SIAB_BIN_DIR}/k9s"
    [[ ! -x "$k9s_cmd" ]] && k9s_cmd="k9s"

    if ! "$k9s_cmd" version &>/dev/null; then
        log_warn "k9s binary exists but not working"
        return 1
    fi

    log_info "k9s is properly installed"
    return 0
}

# Check if cert-manager is already installed correctly
check_cert_manager_installed() {
    log_info "Checking cert-manager installation status..."

    # Check if cert-manager namespace exists
    if ! kubectl get namespace cert-manager &>/dev/null; then
        return 1
    fi

    # Check if cert-manager deployments are ready
    if ! kubectl get deployment cert-manager -n cert-manager &>/dev/null; then
        return 1
    fi

    local ready_replicas
    ready_replicas=$(kubectl get deployment cert-manager -n cert-manager -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [[ "$ready_replicas" -lt 1 ]]; then
        return 1
    fi

    # Check if cluster issuer exists
    if ! kubectl get clusterissuer siab-ca-issuer &>/dev/null; then
        return 1
    fi

    log_info "cert-manager is properly installed"
    return 0
}

# Check if MetalLB is already installed correctly
check_metallb_installed() {
    log_info "Checking MetalLB installation status..."

    # Check if metallb-system namespace exists
    if ! kubectl get namespace metallb-system &>/dev/null; then
        return 1
    fi

    # Check if MetalLB controller is ready
    if ! kubectl get deployment metallb-controller -n metallb-system &>/dev/null; then
        return 1
    fi

    local ready_replicas
    ready_replicas=$(kubectl get deployment metallb-controller -n metallb-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [[ "$ready_replicas" -lt 1 ]]; then
        return 1
    fi

    # Check if IP address pools exist
    if ! kubectl get ipaddresspools -n metallb-system admin-pool &>/dev/null; then
        return 1
    fi

    log_info "MetalLB is properly installed"
    return 0
}

# Check if Longhorn is already installed correctly
check_longhorn_installed() {
    log_info "Checking Longhorn installation status..."

    # Check if longhorn-system namespace exists
    if ! kubectl get namespace longhorn-system &>/dev/null; then
        return 1
    fi

    # Check if Longhorn manager is running
    local running_pods
    running_pods=$(kubectl get pods -n longhorn-system -l app=longhorn-manager --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$running_pods" -lt 1 ]]; then
        return 1
    fi

    # Check if Longhorn StorageClass exists
    if ! kubectl get storageclass longhorn &>/dev/null; then
        return 1
    fi

    log_info "Longhorn is properly installed"
    return 0
}

# Check if Istio is already installed correctly
check_istio_installed() {
    log_info "Checking Istio installation status..."

    # Check if istio-system namespace exists
    if ! kubectl get namespace istio-system &>/dev/null; then
        return 1
    fi

    # Check if istiod is ready
    if ! kubectl get deployment istiod -n istio-system &>/dev/null; then
        return 1
    fi

    local ready_replicas
    ready_replicas=$(kubectl get deployment istiod -n istio-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [[ "$ready_replicas" -lt 1 ]]; then
        return 1
    fi

    # Check if admin gateway exists
    if ! kubectl get deployment istio-ingress-admin -n istio-system &>/dev/null; then
        return 1
    fi

    # Check if user gateway exists
    if ! kubectl get deployment istio-ingress-user -n istio-system &>/dev/null; then
        return 1
    fi

    log_info "Istio is properly installed with dual gateways"
    return 0
}

# Check if a Helm release is installed and ready
# Usage: check_helm_release_installed release_name namespace
check_helm_release_installed() {
    local release_name="$1"
    local namespace="$2"

    if ! helm status "$release_name" -n "$namespace" &>/dev/null; then
        return 1
    fi

    local status
    status=$(helm status "$release_name" -n "$namespace" -o json 2>/dev/null | jq -r '.info.status' 2>/dev/null || echo "")
    if [[ "$status" != "deployed" ]]; then
        return 1
    fi

    return 0
}

# Check if Keycloak is installed
check_keycloak_installed() {
    log_info "Checking Keycloak installation status..."

    if ! kubectl get namespace keycloak &>/dev/null; then
        return 1
    fi

    local ready_replicas
    ready_replicas=$(kubectl get statefulset keycloak -n keycloak -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    if [[ "$ready_replicas" -lt 1 ]]; then
        return 1
    fi

    log_info "Keycloak is properly installed"
    return 0
}

# Check if monitoring stack is installed
check_monitoring_installed() {
    log_info "Checking monitoring stack installation status..."

    if ! kubectl get namespace monitoring &>/dev/null; then
        return 1
    fi

    if ! check_helm_release_installed "kube-prometheus-stack" "monitoring"; then
        return 1
    fi

    log_info "Monitoring stack is properly installed"
    return 0
}

# Run all preflight checks and return overall status
run_all_preflight_checks() {
    local failed=0

    check_requirements || ((failed++))

    log_info "Preflight checks completed with $failed failures"
    return $failed
}
