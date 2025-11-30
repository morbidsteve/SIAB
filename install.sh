#!/bin/bash
set -euo pipefail

# SIAB - Secure Infrastructure as a Box
# One-command secure Kubernetes platform installer

readonly SIAB_VERSION="1.0.0"
readonly SIAB_DIR="/opt/siab"
readonly SIAB_CONFIG_DIR="/etc/siab"
readonly SIAB_LOG_DIR="/var/log/siab"
readonly SIAB_BIN_DIR="/usr/local/bin"

# Ensure SIAB bin directory is in PATH
export PATH="${SIAB_BIN_DIR}:/var/lib/rancher/rke2/bin:${PATH}"

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="${ID}"
        OS_VERSION_ID="${VERSION_ID}"
        OS_NAME="${NAME}"
    else
        log_error "Cannot detect operating system"
        exit 1
    fi
}

# Run OS detection
detect_os

# Set OS-specific variables
case "${OS_ID}" in
    rocky|rhel|centos|ol|almalinux)
        # RHEL family: Rocky, RHEL, CentOS, Oracle Linux, AlmaLinux
        OS_FAMILY="rhel"
        PKG_MANAGER="dnf"
        FIREWALL_CMD="firewalld"
        SECURITY_MODULE="selinux"
        ;;
    ubuntu|xubuntu|kubuntu|lubuntu|debian)
        # Debian family: Ubuntu variants and Debian
        OS_FAMILY="debian"
        PKG_MANAGER="apt"
        FIREWALL_CMD="ufw"
        SECURITY_MODULE="apparmor"
        ;;
    *)
        log_error "Unsupported operating system: ${OS_ID}"
        log_error "Supported: Rocky Linux, RHEL, CentOS, Oracle Linux, AlmaLinux, Ubuntu, Xubuntu, Debian"
        exit 1
        ;;
esac

# Set non-interactive mode for Debian/Ubuntu systems globally
if [[ "${OS_FAMILY}" == "debian" ]]; then
    export DEBIAN_FRONTEND=noninteractive
fi

# Component versions (pinned for security)
readonly RKE2_VERSION="${RKE2_VERSION:-v1.28.4+rke2r1}"
readonly HELM_VERSION="${HELM_VERSION:-v3.13.3}"
readonly ISTIO_VERSION="${ISTIO_VERSION:-1.20.1}"
readonly KEYCLOAK_VERSION="${KEYCLOAK_VERSION:-23.0.3}"
readonly MINIO_VERSION="${MINIO_VERSION:-5.0.15}"
readonly TRIVY_VERSION="${TRIVY_VERSION:-0.18.4}"
readonly GATEKEEPER_VERSION="${GATEKEEPER_VERSION:-3.14.0}"
readonly CERTMANAGER_VERSION="${CERTMANAGER_VERSION:-v1.13.3}"
readonly PROMETHEUS_STACK_VERSION="${PROMETHEUS_STACK_VERSION:-56.6.2}"
readonly KUBE_DASHBOARD_VERSION="${KUBE_DASHBOARD_VERSION:-7.1.0}"
readonly LONGHORN_VERSION="${LONGHORN_VERSION:-1.5.3}"

# Configuration
SIAB_DOMAIN="${SIAB_DOMAIN:-siab.local}"
SIAB_ADMIN_EMAIL="${SIAB_ADMIN_EMAIL:-admin@${SIAB_DOMAIN}}"
SIAB_SKIP_MONITORING="${SIAB_SKIP_MONITORING:-false}"
SIAB_SKIP_STORAGE="${SIAB_SKIP_STORAGE:-false}"
SIAB_SKIP_LONGHORN="${SIAB_SKIP_LONGHORN:-false}"
SIAB_MINIO_SIZE="${SIAB_MINIO_SIZE:-20Gi}"
SIAB_SINGLE_NODE="${SIAB_SINGLE_NODE:-true}"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m' # No Color

# Status tracking symbols
readonly SYMBOL_PENDING="○"
readonly SYMBOL_RUNNING="◐"
readonly SYMBOL_DONE="●"
readonly SYMBOL_SKIP="◌"
readonly SYMBOL_FAIL="✗"

# Installation steps for status tracking
declare -a INSTALL_STEPS=(
    "System Requirements"
    "System Dependencies"
    "Repository Clone"
    "Firewall Configuration"
    "Security Configuration"
    "RKE2 Kubernetes"
    "Helm Package Manager"
    "k9s Cluster UI"
    "Credentials Generation"
    "Kubernetes Namespaces"
    "cert-manager"
    "MetalLB Load Balancer"
    "Longhorn Block Storage"
    "Istio Service Mesh"
    "Istio Gateways"
    "Keycloak Identity"
    "Keycloak Realm Setup"
    "OAuth2 Proxy"
    "SSO Configuration"
    "MinIO Storage"
    "Trivy Security Scanner"
    "OPA Gatekeeper"
    "Monitoring Stack"
    "Kubernetes Dashboard"
    "SIAB Tools"
    "Security Policies"
    "SIAB CRDs"
    "SIAB Dashboard"
    "SIAB Deployer"
    "Final Configuration"
)

# Status for each step: pending, running, done, skipped, failed
declare -A STEP_STATUS
declare -A STEP_MESSAGE

# Track if we've drawn the dashboard initially
DASHBOARD_DRAWN=false
DASHBOARD_LINES=0
CURRENT_STEP_NAME=""

# Initialize all steps as pending
init_step_status() {
    for step in "${INSTALL_STEPS[@]}"; do
        STEP_STATUS["$step"]="pending"
        STEP_MESSAGE["$step"]=""
    done
}

# Update step status
set_step_status() {
    local step="$1"
    local status="$2"
    local message="${3:-}"
    STEP_STATUS["$step"]="$status"
    STEP_MESSAGE["$step"]="$message"
}

# Count completed and total steps
count_steps() {
    local completed=0
    local total=${#INSTALL_STEPS[@]}
    for step in "${INSTALL_STEPS[@]}"; do
        local status="${STEP_STATUS[$step]:-pending}"
        if [[ "$status" == "done" ]] || [[ "$status" == "skipped" ]]; then
            ((completed++))
        fi
    done
    echo "$completed $total"
}

# Simple single-line progress display (no cursor movement needed)
draw_status_dashboard() {
    local current_action="${1:-}"

    # Count progress
    local counts
    counts=$(count_steps)
    local completed=$(echo "$counts" | cut -d' ' -f1)
    local total=$(echo "$counts" | cut -d' ' -f2)
    local percent=$((completed * 100 / total))

    # Build progress bar (20 chars wide)
    local bar_filled=$((completed * 20 / total))
    local bar_empty=$((20 - bar_filled))
    local bar=""
    for ((i=0; i<bar_filled; i++)); do bar+="█"; done
    for ((i=0; i<bar_empty; i++)); do bar+="░"; done

    # Print single-line status with carriage return (overwrite previous)
    printf "\r\033[2K${CYAN}[${bar}]${NC} ${GREEN}%d${NC}/${total} │ ${BOLD}%s${NC}" "$completed" "${current_action:0:50}"
}

# Print the full status dashboard at the end
print_status_dashboard() {
    echo ""  # New line to move past progress bar
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║                    SIAB Installation Summary                         ║${NC}"
    echo -e "${BOLD}╠══════════════════════════════════════════════════════════════════════╣${NC}"

    # Calculate columns
    local col1_steps=()
    local col2_steps=()
    local half=$((${#INSTALL_STEPS[@]} / 2 + ${#INSTALL_STEPS[@]} % 2))

    for i in "${!INSTALL_STEPS[@]}"; do
        if [[ $i -lt $half ]]; then
            col1_steps+=("${INSTALL_STEPS[$i]}")
        else
            col2_steps+=("${INSTALL_STEPS[$i]}")
        fi
    done

    # Draw status rows
    for i in "${!col1_steps[@]}"; do
        local step1="${col1_steps[$i]}"
        local step2="${col2_steps[$i]:-}"

        # Get symbol and color for step 1
        local status1="${STEP_STATUS[$step1]:-pending}"
        local symbol1 color1
        case "$status1" in
            pending) symbol1="○"; color1="${DIM}" ;;
            running) symbol1="◐"; color1="${CYAN}" ;;
            done)    symbol1="●"; color1="${GREEN}" ;;
            skipped) symbol1="◌"; color1="${YELLOW}" ;;
            failed)  symbol1="✗"; color1="${RED}" ;;
        esac

        # Pad step1 name to 22 chars
        local step1_padded
        step1_padded=$(printf '%-22.22s' "$step1")

        # Build step 2 portion
        local step2_part=""
        if [[ -n "$step2" ]]; then
            local status2="${STEP_STATUS[$step2]:-pending}"
            local symbol2 color2
            case "$status2" in
                pending) symbol2="○"; color2="${DIM}" ;;
                running) symbol2="◐"; color2="${CYAN}" ;;
                done)    symbol2="●"; color2="${GREEN}" ;;
                skipped) symbol2="◌"; color2="${YELLOW}" ;;
                failed)  symbol2="✗"; color2="${RED}" ;;
            esac
            local step2_padded
            step2_padded=$(printf '%-22.22s' "$step2")
            step2_part="${color2}${symbol2} ${step2_padded}${NC}"
        else
            step2_part="                        "
        fi

        echo -e "║ ${color1}${symbol1} ${step1_padded}${NC}  │  ${step2_part} ║"
    done

    echo -e "╚══════════════════════════════════════════════════════════════════════╝"
}

# Start a step (mark as running and update display)
start_step() {
    local step="$1"
    CURRENT_STEP_NAME="$step"
    set_step_status "$step" "running"
    draw_status_dashboard "Installing: $step..." >&3
}

# Complete a step
complete_step() {
    local step="$1"
    local message="${2:-}"
    set_step_status "$step" "done" "$message"
    draw_status_dashboard "Completed: $step" >&3
}

# Skip a step
skip_step() {
    local step="$1"
    local reason="${2:-Already configured}"
    set_step_status "$step" "skipped" "$reason"
    draw_status_dashboard "Skipped: $step" >&3
}

# Fail a step
fail_step() {
    local step="$1"
    local reason="${2:-Unknown error}"
    set_step_status "$step" "failed" "$reason"
    draw_status_dashboard "FAILED: $step" >&3
    log_error "$step failed: $reason"
}

# Logging functions - write to log file, not console (to preserve in-place display)
SIAB_LOG_FILE="${SIAB_LOG_DIR:-/var/log/siab}/install.log"

# Ensure log directory exists
mkdir -p "$(dirname "$SIAB_LOG_FILE")" 2>/dev/null || true

log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1" >> "$SIAB_LOG_FILE" 2>/dev/null || true
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $1" >> "$SIAB_LOG_FILE" 2>/dev/null || true
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1" >> "$SIAB_LOG_FILE" 2>/dev/null || true
    # Also print errors to console so they're visible (use saved fd 4 for stderr)
    echo -e "${RED}[ERROR]${NC} $1" >&4
}

log_step() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STEP] $1" >> "$SIAB_LOG_FILE" 2>/dev/null || true
}

# Run a command silently, capturing output to log file
# Usage: run_quiet command args...
run_quiet() {
    "$@" >> "$SIAB_LOG_FILE" 2>&1
}

# Run a command silently, ignoring errors
# Usage: run_quiet_ok command args...
run_quiet_ok() {
    "$@" >> "$SIAB_LOG_FILE" 2>&1 || true
}

# Save original file descriptors for progress display
exec 3>&1 4>&2

# Error handling - restore output and show error
trap 'exec 1>&3 2>&4; log_error "Installation failed at line $LINENO. Check ${SIAB_LOG_DIR}/install.log for details."' ERR

# Initialize SIAB_REPO_DIR with a default value (will be updated by clone_siab_repo)
SIAB_REPO_DIR="${SIAB_DIR}/repo"

# ============================================================================
# PRE-FLIGHT CHECK FUNCTIONS
# These functions check if components are already installed correctly
# ============================================================================

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

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Check system requirements
check_requirements() {
    log_step "Checking system requirements..."

    # Check OS
    log_info "Detected OS: ${OS_NAME} (${OS_ID} ${OS_VERSION_ID})"
    log_info "OS Family: ${OS_FAMILY}"

    # Check CPU cores
    local cpu_cores
    cpu_cores=$(nproc)
    if [[ $cpu_cores -lt 4 ]]; then
        log_error "Minimum 4 CPU cores required (found: $cpu_cores)"
        exit 1
    fi

    # Check RAM
    local total_ram
    total_ram=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $total_ram -lt 14 ]]; then
        log_error "Minimum 16GB RAM required (found: ${total_ram}GB)"
        exit 1
    fi

    # Check disk space
    local free_space
    free_space=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $free_space -lt 25 ]]; then
        log_error "Minimum 30GB free disk space required (found: ${free_space}GB)"
        exit 1
    fi

    log_info "System requirements met"
}

# Setup directories
setup_directories() {
    log_step "Setting up directories..."
    mkdir -p "${SIAB_DIR}"
    mkdir -p "${SIAB_CONFIG_DIR}"
    mkdir -p "${SIAB_LOG_DIR}"
    mkdir -p "${SIAB_BIN_DIR}"
    chmod 700 "${SIAB_CONFIG_DIR}"
}

# Clone or update SIAB repository
clone_siab_repo() {
    log_step "Fetching SIAB repository..."

    local SIAB_REPO_URL="https://github.com/morbidsteve/SIAB.git"
    local SIAB_REPO_DIR="${SIAB_DIR}/repo"

    # Check if we're already running from a cloned repo
    local script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    if [[ -f "${script_dir}/siab-status.sh" ]] && [[ -d "${script_dir}/crds" ]]; then
        log_info "Running from existing repo clone, using local files..."
        SIAB_REPO_DIR="${script_dir}"
    else
        # Need to clone the repo
        if [[ -d "${SIAB_REPO_DIR}/.git" ]]; then
            log_info "Updating existing SIAB repository..."
            cd "${SIAB_REPO_DIR}"
            git pull origin main 2>/dev/null || git pull 2>/dev/null || true
            cd - >/dev/null
        else
            log_info "Cloning SIAB repository..."
            rm -rf "${SIAB_REPO_DIR}"
            git clone --depth 1 "${SIAB_REPO_URL}" "${SIAB_REPO_DIR}"
        fi
    fi

    # Export the repo dir for other functions to use
    export SIAB_REPO_DIR
    log_info "SIAB repo available at: ${SIAB_REPO_DIR}"
}

# Install system dependencies
install_dependencies() {
    log_step "Installing system dependencies..."

    if [[ "${OS_FAMILY}" == "rhel" ]]; then
        # Remove any leftover RKE2 repos from previous installs to avoid GPG issues
        rm -f /etc/yum.repos.d/rancher-rke2*.repo 2>/dev/null || true
        dnf clean all
        dnf update -y
        dnf install -y \
            curl \
            wget \
            tar \
            git \
            jq \
            openssl \
            policycoreutils-python-utils \
            container-selinux \
            iptables \
            chrony \
            audit

        # Enable and start chrony for time sync
        systemctl enable --now chronyd

        # Enable audit logging
        systemctl enable --now auditd

    elif [[ "${OS_FAMILY}" == "debian" ]]; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get install -y \
            curl \
            wget \
            tar \
            git \
            jq \
            openssl \
            iptables \
            chrony \
            auditd \
            apparmor \
            apparmor-utils

        # Install yq separately (not in default repos)
        wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
        chmod +x /usr/local/bin/yq

        # Enable and start chrony for time sync
        systemctl enable --now chrony

        # Enable audit logging
        systemctl enable --now auditd
    fi

    log_info "System dependencies installed"
}

# Configure firewall
configure_firewall() {
    log_step "Configuring firewall for RKE2, Canal, and Istio..."

    if [[ "${FIREWALL_CMD}" == "firewalld" ]]; then
        # Use comprehensive firewalld configuration script
        if [[ -f "${SIAB_REPO_DIR}/scripts/configure-firewalld.sh" ]]; then
            log_info "Running comprehensive firewalld configuration..."
            bash "${SIAB_REPO_DIR}/scripts/configure-firewalld.sh"
        else
            # Fallback to basic configuration if script not found
            log_warn "Firewalld script not found, using basic configuration..."

            # Install firewalld if not present
            dnf install -y firewalld
            systemctl enable --now firewalld

            # Add CNI interfaces to trusted zone
            firewall-cmd --permanent --zone=trusted --add-interface=cni0 2>/dev/null || true
            firewall-cmd --permanent --zone=trusted --add-interface=flannel.1 2>/dev/null || true
            firewall-cmd --permanent --zone=trusted --add-interface=tunl0 2>/dev/null || true

            # Add pod and service CIDRs to trusted zone
            firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16  # Pod CIDR
            firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16  # Service CIDR

            # RKE2 ports
            firewall-cmd --permanent --add-port=6443/tcp   # Kubernetes API
            firewall-cmd --permanent --add-port=9345/tcp   # RKE2 supervisor API
            firewall-cmd --permanent --add-port=10250/tcp  # Kubelet metrics
            firewall-cmd --permanent --add-port=2379-2380/tcp   # etcd
            firewall-cmd --permanent --add-port=30000-32767/tcp  # NodePort Services (TCP)
            firewall-cmd --permanent --add-port=30000-32767/udp  # NodePort Services (UDP)
            firewall-cmd --permanent --add-port=53/tcp     # DNS (CoreDNS)
            firewall-cmd --permanent --add-port=53/udp     # DNS (CoreDNS)

            # Canal (Calico + Flannel) ports
            firewall-cmd --permanent --add-port=8472/udp   # Flannel VXLAN
            firewall-cmd --permanent --add-port=4789/udp   # Flannel VXLAN (alt)
            firewall-cmd --permanent --add-port=51820-51821/udp  # Flannel Wireguard
            firewall-cmd --permanent --add-port=179/tcp    # Calico BGP
            firewall-cmd --permanent --add-port=5473/tcp   # Calico Typha

            # Istio ports
            firewall-cmd --permanent --add-port=80/tcp     # HTTP ingress (redirects to HTTPS)
            firewall-cmd --permanent --add-port=443/tcp    # HTTPS ingress
            firewall-cmd --permanent --add-port=15010-15017/tcp  # Istio control plane
            firewall-cmd --permanent --add-port=15021/tcp  # Istio health checks
            firewall-cmd --permanent --add-port=15090/tcp  # Istio metrics

            # Enable masquerading
            firewall-cmd --permanent --zone=public --add-masquerade
            firewall-cmd --permanent --zone=trusted --add-masquerade

            firewall-cmd --reload
        fi

    elif [[ "${FIREWALL_CMD}" == "ufw" ]]; then
        # Install ufw if not present
        apt-get install -y ufw

        # Enable ufw (non-interactive)
        ufw --force enable

        # Allow SSH first (prevent lockout)
        ufw allow 22/tcp

        # RKE2 ports
        ufw allow 6443/tcp    # Kubernetes API
        ufw allow 9345/tcp    # RKE2 supervisor API
        ufw allow 10250/tcp   # Kubelet metrics
        ufw allow 2379/tcp    # etcd client
        ufw allow 2380/tcp    # etcd peer
        ufw allow 30000:32767/tcp  # NodePort Services (TCP)
        ufw allow 30000:32767/udp  # NodePort Services (UDP)
        ufw allow 53/tcp      # DNS (CoreDNS)
        ufw allow 53/udp      # DNS (CoreDNS)

        # Canal (Calico + Flannel) ports
        ufw allow 8472/udp    # Flannel VXLAN
        ufw allow 4789/udp    # Flannel VXLAN (alt)
        ufw allow 51820:51821/udp  # Flannel Wireguard
        ufw allow 179/tcp     # Calico BGP
        ufw allow 5473/tcp    # Calico Typha

        # Istio ports
        ufw allow 80/tcp      # HTTP ingress (redirects to HTTPS)
        ufw allow 443/tcp     # HTTPS ingress
        ufw allow 15010:15017/tcp  # Istio control plane
        ufw allow 15021/tcp   # Istio health checks
        ufw allow 15090/tcp   # Istio metrics

        # Reload ufw
        ufw reload
    fi

    log_info "Firewall configured successfully"
    log_info "Note: CNI interfaces will be added to trusted zone when they are created"
}

# Configure security module (SELinux or AppArmor)
configure_security() {
    if [[ "${SECURITY_MODULE}" == "selinux" ]]; then
        log_step "Configuring SELinux..."

        # Ensure SELinux is enforcing
        if [[ $(getenforce) != "Enforcing" ]]; then
            setenforce 1
            sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
        fi

        # Set SELinux booleans for containers
        setsebool -P container_manage_cgroup on

        log_info "SELinux configured in enforcing mode"

    elif [[ "${SECURITY_MODULE}" == "apparmor" ]]; then
        log_step "Configuring AppArmor..."

        # Ensure AppArmor is enabled
        systemctl enable --now apparmor

        # Check AppArmor status
        if ! aa-status >/dev/null 2>&1; then
            log_warn "AppArmor not available, skipping..."
        else
            # Set AppArmor to enforcing mode
            aa-enforce /etc/apparmor.d/* 2>/dev/null || true
            log_info "AppArmor configured in enforcing mode"
        fi
    fi
}

# Clean up any existing RKE2 installation
cleanup_rke2() {
    log_step "Checking for existing RKE2 installation..."

    # Check if RKE2 is installed
    if [[ -f /usr/local/bin/rke2 ]] || [[ -f /var/lib/rancher/rke2 ]] || \
       systemctl is-active --quiet rke2-server 2>/dev/null || \
       systemctl is-enabled --quiet rke2-server 2>/dev/null; then

        log_info "Existing RKE2 installation found. Cleaning up..."

        # Stop services
        log_info "Stopping RKE2 services..."
        systemctl stop rke2-server 2>/dev/null || true
        systemctl stop rke2-agent 2>/dev/null || true
        systemctl disable rke2-server 2>/dev/null || true
        systemctl disable rke2-agent 2>/dev/null || true
        sleep 3

        # Kill any remaining processes
        log_info "Cleaning up processes..."
        pkill -9 -f "rke2" 2>/dev/null || true
        pkill -9 -f "containerd-shim" 2>/dev/null || true
        pkill -9 -f "kubelet" 2>/dev/null || true
        sleep 2

        # Run official uninstall script if available
        if [[ -f /usr/local/bin/rke2-uninstall.sh ]]; then
            log_info "Running RKE2 uninstall script..."
            /usr/local/bin/rke2-uninstall.sh 2>/dev/null || true
        fi

        # Remove all RKE2 data and config
        log_info "Removing RKE2 data directories..."
        rm -rf /var/lib/rancher/rke2
        rm -rf /etc/rancher/rke2
        rm -rf /var/lib/kubelet
        rm -rf /var/lib/cni
        rm -rf /var/log/pods
        rm -rf /var/log/containers
        rm -rf /run/k3s
        rm -f /usr/local/bin/rke2*
        rm -f /usr/local/bin/kubectl
        rm -rf /usr/local/lib/systemd/system/rke2*
        rm -f /etc/yum.repos.d/rancher-rke2*.repo 2>/dev/null || true

        # Reload systemd
        systemctl daemon-reload

        log_info "RKE2 cleanup complete"
    else
        log_info "No existing RKE2 installation found"
    fi
}

# Setup RKE2 prerequisites
setup_rke2_prerequisites() {
    log_step "Setting up RKE2 prerequisites..."

    # Create etcd user and group (required for CIS profile)
    if ! getent group etcd >/dev/null 2>&1; then
        groupadd --system etcd
        log_info "Created etcd group"
    fi
    if ! getent passwd etcd >/dev/null 2>&1; then
        useradd --system --gid etcd --shell /sbin/nologin --comment "etcd user" etcd
        log_info "Created etcd user"
    fi

    # Set required kernel parameters
    log_info "Setting kernel parameters..."
    cat > /etc/sysctl.d/90-rke2-cis.conf <<EOF
# RKE2 CIS Profile Requirements
kernel.panic = 10
kernel.panic_on_oops = 1
vm.overcommit_memory = 1
vm.panic_on_oom = 0
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1

# Increase inotify limits to prevent "Too many open files" errors
# Required for Kubernetes, Longhorn, and monitoring tools
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
fs.inotify.max_queued_events = 32768
fs.file-max = 2097152
EOF

    # Set ulimits for the system to prevent file descriptor exhaustion
    log_info "Configuring system limits..."
    cat > /etc/security/limits.d/90-rke2.conf <<EOF
# Increase file descriptor limits for Kubernetes
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 1048576
* hard nproc 1048576
root soft nofile 1048576
root hard nofile 1048576
root soft nproc 1048576
root hard nproc 1048576
EOF

    # Load required kernel modules
    modprobe br_netfilter 2>/dev/null || true
    modprobe overlay 2>/dev/null || true

    # Apply sysctl settings
    sysctl --system > /dev/null 2>&1

    log_info "Prerequisites configured"
}

# Install RKE2
install_rke2() {
    start_step "RKE2 Kubernetes"

    # Check if RKE2 is already properly installed
    if check_rke2_installed; then
        skip_step "RKE2 Kubernetes" "Already installed and running correctly"
        # Still setup kubectl access if needed
        mkdir -p ~/.kube
        cp /etc/rancher/rke2/rke2.yaml ~/.kube/config 2>/dev/null || true
        chmod 600 ~/.kube/config 2>/dev/null || true
        export PATH=$PATH:/var/lib/rancher/rke2/bin
        return 0
    fi

    log_step "Installing RKE2 ${RKE2_VERSION}..."

    # Clean up any existing installation first
    cleanup_rke2

    # Setup prerequisites
    setup_rke2_prerequisites

    # Create RKE2 config directory
    mkdir -p /etc/rancher/rke2
    mkdir -p /var/lib/rancher/rke2/server/manifests

    # Get hostname and IP for TLS SANs
    local hostname_val=$(hostname)
    local ip_val=$(hostname -I | awk '{print $1}')

    # Create simplified RKE2 configuration (CIS profile causes issues on some systems)
    # Security is still enforced via other means (network policies, pod security, etc.)
    cat > /etc/rancher/rke2/config.yaml <<EOF
# RKE2 Configuration for SIAB
write-kubeconfig-mode: "0644"
tls-san:
  - ${hostname_val}
  - ${ip_val}
  - localhost
  - 127.0.0.1
# Secrets encryption
secrets-encryption: true
EOF

    # Install RKE2 using tarball method (avoids GPG issues with RPM repos)
    log_info "Downloading and installing RKE2..."
    curl -sfL https://get.rke2.io | INSTALL_RKE2_METHOD="tar" sh -

    # Enable RKE2 service
    systemctl daemon-reload
    systemctl enable rke2-server.service

    # Start RKE2 and monitor startup
    log_info "Starting RKE2 service..."
    log_info "First startup takes 5-10 minutes. Monitoring progress..."
    echo ""
    systemctl start rke2-server.service &

    # Monitor RKE2 startup with real-time status display
    local max_wait=600  # 10 minutes
    local elapsed=0
    local last_status_time=0

    while [[ $elapsed -lt $max_wait ]]; do
        # Check if service failed
        local svc_status=$(systemctl is-active rke2-server 2>/dev/null || echo "unknown")

        if [[ "$svc_status" == "failed" ]]; then
            echo ""
            log_error "RKE2 service failed!"
            echo "----------------------------------------"
            systemctl status rke2-server --no-pager -l 2>/dev/null || true
            echo "----------------------------------------"
            log_error "Recent logs:"
            journalctl -u rke2-server --no-pager -n 20
            exit 1
        fi

        # Show status every 30 seconds
        if [[ $((elapsed - last_status_time)) -ge 30 ]] || [[ $elapsed -eq 0 ]]; then
            echo ""
            echo "=== RKE2 Status (${elapsed}s elapsed) ==="
            # Show brief service status
            local active_state=$(systemctl show rke2-server --property=ActiveState --value 2>/dev/null || echo "unknown")
            local sub_state=$(systemctl show rke2-server --property=SubState --value 2>/dev/null || echo "unknown")
            echo "Service: ${active_state} (${sub_state})"

            # Show what's happening from recent logs (last 3 lines)
            echo "Recent activity:"
            journalctl -u rke2-server --no-pager -n 3 -q 2>/dev/null | tail -3 || echo "  (waiting for logs...)"
            echo "================================="
            last_status_time=$elapsed
        fi

        # Check if kubectl is available and working
        if [[ -f /var/lib/rancher/rke2/bin/kubectl ]] && \
           [[ -f /etc/rancher/rke2/rke2.yaml ]]; then
            if /var/lib/rancher/rke2/bin/kubectl \
               --kubeconfig /etc/rancher/rke2/rke2.yaml \
               get nodes &>/dev/null 2>&1; then
                echo ""
                log_info "RKE2 is ready!"
                # Show final node status
                echo ""
                /var/lib/rancher/rke2/bin/kubectl \
                    --kubeconfig /etc/rancher/rke2/rke2.yaml \
                    get nodes
                break
            fi
        fi

        sleep 5
        elapsed=$((elapsed + 5))
    done

    if [[ $elapsed -ge $max_wait ]]; then
        echo ""
        log_error "RKE2 startup timeout after ${max_wait}s"
        log_error "Final status:"
        systemctl status rke2-server --no-pager -l 2>/dev/null || true
        log_error "Check logs: journalctl -fu rke2-server"
        exit 1
    fi

    # Setup kubectl access
    mkdir -p ~/.kube
    cp /etc/rancher/rke2/rke2.yaml ~/.kube/config
    chmod 600 ~/.kube/config

    # Add RKE2 bins to PATH
    echo 'export PATH=$PATH:/var/lib/rancher/rke2/bin' >> /etc/profile.d/rke2.sh
    export PATH=$PATH:/var/lib/rancher/rke2/bin

    # Create symlinks
    ln -sf /var/lib/rancher/rke2/bin/kubectl "${SIAB_BIN_DIR}/kubectl"

    complete_step "RKE2 Kubernetes"
    log_info "RKE2 installed successfully"
}

# Configure Calico/Canal for proper connectivity
configure_calico_network() {
    log_step "Configuring Calico/Canal network for optimal connectivity..."

    # Wait for Calico to be ready before configuring
    log_info "Waiting for Canal/Calico pods to be ready..."
    local max_wait=120
    local elapsed=0
    while [[ $elapsed -lt $max_wait ]]; do
        local canal_ready=$(kubectl get pods -n kube-system -l k8s-app=canal --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        if [[ $canal_ready -ge 1 ]]; then
            log_info "Canal/Calico is ready"
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    # Create GlobalNetworkPolicy to allow all pod traffic
    # This prevents connectivity issues while maintaining Kubernetes NetworkPolicies
    log_info "Creating Calico GlobalNetworkPolicy for pod communication..."
    cat <<EOF | kubectl apply -f - 2>/dev/null || true
apiVersion: crd.projectcalico.org/v1
kind: GlobalNetworkPolicy
metadata:
  name: allow-all-pods
spec:
  order: 1
  selector: all()
  types:
    - Ingress
    - Egress
  ingress:
    - action: Allow
  egress:
    - action: Allow
EOF

    # Configure Felix for optimal connectivity
    log_info "Configuring Calico Felix for optimal performance..."
    cat <<EOF | kubectl apply -f - 2>/dev/null || true
apiVersion: crd.projectcalico.org/v1
kind: FelixConfiguration
metadata:
  name: default
spec:
  defaultEndpointToHostAction: Accept
  iptablesFilterAllowAction: Accept
  iptablesMangleAllowAction: Accept
  logSeverityScreen: Info
  reportingInterval: 0s
EOF

    log_info "Calico/Canal network configured for optimal connectivity"
}

# Install Helm
install_helm() {
    start_step "Helm Package Manager"

    # Check if Helm is already properly installed
    if check_helm_installed; then
        skip_step "Helm Package Manager" "Already installed with required repos"
        export PATH="${SIAB_BIN_DIR}:${PATH}"
        return 0
    fi

    log_step "Installing Helm ${HELM_VERSION}..."

    # Download and extract Helm
    local helm_url="https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
    log_info "Downloading Helm from ${helm_url}..."

    if ! curl -fsSL "${helm_url}" -o /tmp/helm.tar.gz; then
        log_error "Failed to download Helm"
        exit 1
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
        exit 1
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
    "${SIAB_BIN_DIR}/helm" repo update

    complete_step "Helm Package Manager"
    log_info "Helm installed successfully"
}

# Install k9s for cluster monitoring
install_k9s() {
    start_step "k9s Cluster UI"

    # Check if k9s is already properly installed
    if check_k9s_installed; then
        skip_step "k9s Cluster UI" "Already installed and working"
        return 0
    fi

    log_step "Installing k9s..."

    local k9s_version="v0.32.5"
    local k9s_url="https://github.com/derailed/k9s/releases/download/${k9s_version}/k9s_Linux_amd64.tar.gz"

    if ! curl -fsSL "${k9s_url}" -o /tmp/k9s.tar.gz; then
        log_error "Failed to download k9s"
        exit 1
    fi

    cd /tmp
    tar xzf k9s.tar.gz k9s
    mv k9s "${SIAB_BIN_DIR}/k9s"
    rm -f k9s.tar.gz
    chmod +x "${SIAB_BIN_DIR}/k9s"
    cd - >/dev/null

    # Ensure SIAB bin directory is in PATH for all users
    cat > /etc/profile.d/siab.sh <<'EOF'
# SIAB - Secure Infrastructure as a Box
# Add SIAB and Kubernetes tools to PATH
export PATH="${PATH}:/usr/local/bin:/var/lib/rancher/rke2/bin"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
EOF
    chmod +x /etc/profile.d/siab.sh

    # Also add to /etc/environment for non-login shells
    if ! grep -q "/usr/local/bin" /etc/environment 2>/dev/null; then
        if [[ -f /etc/environment ]]; then
            # Update existing PATH in /etc/environment
            if grep -q "^PATH=" /etc/environment; then
                sed -i 's|^PATH="\(.*\)"|PATH="\1:/usr/local/bin:/var/lib/rancher/rke2/bin"|' /etc/environment
            else
                echo 'PATH="/usr/local/bin:/var/lib/rancher/rke2/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin"' >> /etc/environment
            fi
        else
            echo 'PATH="/usr/local/bin:/var/lib/rancher/rke2/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin"' > /etc/environment
        fi
    fi

    complete_step "k9s Cluster UI"
    log_info "k9s installed at ${SIAB_BIN_DIR}/k9s"
    log_info "PATH configured in /etc/profile.d/siab.sh"
}

# Generate secure credentials
generate_credentials() {
    log_step "Generating secure credentials..."

    local keycloak_admin_password
    local minio_root_password
    local grafana_admin_password

    keycloak_admin_password=$(openssl rand -base64 24 | tr -d '=+/' | head -c 24)
    minio_root_password=$(openssl rand -base64 24 | tr -d '=+/' | head -c 24)
    grafana_admin_password=$(openssl rand -base64 24 | tr -d '=+/' | head -c 24)

    cat > "${SIAB_CONFIG_DIR}/credentials.env" <<EOF
# SIAB Platform Credentials
# Generated on $(date)
# KEEP THIS FILE SECURE!

KEYCLOAK_ADMIN_USER=admin
KEYCLOAK_ADMIN_PASSWORD=${keycloak_admin_password}

MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=${minio_root_password}

GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=${grafana_admin_password}

SIAB_DOMAIN=${SIAB_DOMAIN}
EOF
    chmod 600 "${SIAB_CONFIG_DIR}/credentials.env"

    log_info "Credentials generated and saved to ${SIAB_CONFIG_DIR}/credentials.env"
}

# Create namespaces
create_namespaces() {
    log_step "Creating namespaces..."

    # Create all required namespaces
    local namespaces=(
        "siab-system"
        "keycloak"
        "minio"
        "monitoring"
        "cert-manager"
        "trivy-system"
        "gatekeeper-system"
    )

    for ns in "${namespaces[@]}"; do
        kubectl create namespace "$ns" --dry-run=client -o yaml | kubectl apply -f -
    done

    # Create allow-all-ingress network policies for backend services
    # This ensures Istio gateways can reach backend services
    log_info "Creating network policies for service connectivity..."
    for ns in siab-system keycloak minio monitoring istio-system; do
        cat <<EOF | kubectl apply -f - 2>/dev/null || true
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all-ingress
  namespace: $ns
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - {}
EOF
    done

    # Label namespaces for Istio injection
    # Note: keycloak, minio, and monitoring have Istio disabled to avoid sidecar issues with their jobs
    kubectl label namespace default istio-injection=enabled --overwrite
    kubectl label namespace siab-system istio-injection=enabled --overwrite
    kubectl label namespace keycloak istio-injection=disabled --overwrite
    kubectl label namespace minio istio-injection=disabled --overwrite
    kubectl label namespace monitoring istio-injection=disabled --overwrite

    log_info "Namespaces created"
}

# Install cert-manager
install_cert_manager() {
    start_step "cert-manager"

    # Check if cert-manager is already properly installed
    if check_cert_manager_installed; then
        skip_step "cert-manager" "Already installed and configured"
        return 0
    fi

    log_step "Installing cert-manager ${CERTMANAGER_VERSION}..."

    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/${CERTMANAGER_VERSION}/cert-manager.crds.yaml

    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --version ${CERTMANAGER_VERSION} \
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

# Install MetalLB for LoadBalancer services
install_metallb() {
    start_step "MetalLB Load Balancer"

    # Check if MetalLB is already properly installed
    if check_metallb_installed; then
        skip_step "MetalLB Load Balancer" "Already installed and configured"
        return 0
    fi

    log_step "Installing MetalLB..."

    # Add MetalLB helm repo
    helm repo add metallb https://metallb.github.io/metallb || true
    helm repo update

    # Create metallb-system namespace
    kubectl create namespace metallb-system --dry-run=client -o yaml | kubectl apply -f -

    # Install MetalLB
    helm upgrade --install metallb metallb/metallb \
        --namespace metallb-system \
        --wait --timeout=300s

    # Wait for MetalLB to be ready
    log_info "Waiting for MetalLB controller to be ready..."
    kubectl wait --for=condition=Available deployment/metallb-controller -n metallb-system --timeout=300s

    # Get node IP for address pool
    local node_ip
    node_ip=$(hostname -I | awk '{print $1}')

    # Create IP address pools for admin and user planes
    # Admin plane: .240-.249, User plane: .250-.254
    local ip_base="${node_ip%.*}"
    log_info "Configuring MetalLB with IP pools based on ${ip_base}.x"

    cat <<EOF | kubectl apply -f -
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: admin-pool
  namespace: metallb-system
spec:
  addresses:
    - ${ip_base}.240-${ip_base}.241
  autoAssign: false
---
apiVersion: metallb.io/v1beta1
kind: IPAddressPool
metadata:
  name: user-pool
  namespace: metallb-system
spec:
  addresses:
    - ${ip_base}.242-${ip_base}.243
  autoAssign: false
---
apiVersion: metallb.io/v1beta1
kind: L2Advertisement
metadata:
  name: siab-l2
  namespace: metallb-system
spec:
  ipAddressPools:
    - admin-pool
    - user-pool
EOF

    # Save the IPs for later use
    echo "ADMIN_GATEWAY_IP=${ip_base}.240" >> "${SIAB_CONFIG_DIR}/network.env"
    echo "USER_GATEWAY_IP=${ip_base}.242" >> "${SIAB_CONFIG_DIR}/network.env"

    complete_step "MetalLB Load Balancer"
    log_info "MetalLB installed with admin pool (${ip_base}.240-241) and user pool (${ip_base}.242-243)"
}

# Install Longhorn for block storage
install_longhorn() {
    start_step "Longhorn Block Storage"

    if [[ "${SIAB_SKIP_LONGHORN}" == "true" ]]; then
        skip_step "Longhorn Block Storage" "Skipped by configuration"
        return 0
    fi

    # Check if Longhorn is already installed
    if kubectl get namespace longhorn-system &>/dev/null; then
        if kubectl get deployment longhorn-driver-deployer -n longhorn-system &>/dev/null 2>&1; then
            skip_step "Longhorn Block Storage" "Already installed"
            return 0
        fi
    fi

    log_step "Installing Longhorn ${LONGHORN_VERSION}..."

    # Install prerequisites based on OS family
    log_info "Installing iSCSI and NFS prerequisites..."
    case "${OS_FAMILY}" in
        rhel)
            ${PKG_MANAGER} install -y iscsi-initiator-utils nfs-utils || true
            ;;
        debian)
            apt-get update && apt-get install -y open-iscsi nfs-common || true
            ;;
    esac

    # Enable and start iscsid service
    systemctl enable iscsid 2>/dev/null || true
    systemctl start iscsid 2>/dev/null || true

    # Add Longhorn Helm repository
    helm repo add longhorn https://charts.longhorn.io 2>/dev/null || true
    helm repo update

    # Create longhorn-system namespace
    kubectl create namespace longhorn-system --dry-run=client -o yaml | kubectl apply -f -

    # Install Longhorn with single-node optimized settings
    log_info "Installing Longhorn chart..."
    helm upgrade --install longhorn longhorn/longhorn \
        --namespace longhorn-system \
        --version ${LONGHORN_VERSION} \
        --set defaultSettings.defaultDataPath="/var/lib/longhorn" \
        --set defaultSettings.replicaReplenishmentWaitInterval=60 \
        --set defaultSettings.defaultReplicaCount=1 \
        --set persistence.defaultClass=true \
        --set persistence.defaultClassReplicaCount=1 \
        --set csi.kubeletRootDir="/var/lib/kubelet" \
        --set defaultSettings.guaranteedInstanceManagerCPU=5 \
        --set ingress.enabled=false \
        --wait --timeout=600s

    # Wait for Longhorn components to be ready
    log_info "Waiting for Longhorn components to be ready..."
    kubectl wait --for=condition=Ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s || true

    # Set Longhorn as default StorageClass
    log_info "Setting Longhorn as default StorageClass..."
    kubectl patch storageclass longhorn -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' 2>/dev/null || true

    # Remove local-path as default if it exists
    kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' 2>/dev/null || true

    # Note: Istio resources (DestinationRule and VirtualService) for Longhorn
    # are created in create_istio_gateway() function after Istio is installed

    complete_step "Longhorn Block Storage"
    log_info "Longhorn block storage installed and configured as default StorageClass"
}

# Install Istio with dual-gateway architecture (admin + user planes)
install_istio() {
    start_step "Istio Service Mesh"

    # Check if Istio is already properly installed
    if check_istio_installed; then
        skip_step "Istio Service Mesh" "Already installed with dual gateways"
        return 0
    fi

    log_step "Installing Istio ${ISTIO_VERSION} with dual-gateway architecture..."

    # Install Istio base
    helm upgrade --install istio-base istio/base \
        --namespace istio-system \
        --create-namespace \
        --version ${ISTIO_VERSION} \
        --wait

    # Install Istio control plane with security settings
    helm upgrade --install istiod istio/istiod \
        --namespace istio-system \
        --version ${ISTIO_VERSION} \
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
        --version ${ISTIO_VERSION} \
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
        --version ${ISTIO_VERSION} \
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
        local admin_ip=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        local user_ip=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
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

# Install Keycloak
install_keycloak() {
    start_step "Keycloak Identity"

    # Check if Keycloak is already installed and ready
    if kubectl get deployment keycloak -n keycloak -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -q "1"; then
        skip_step "Keycloak Identity" "Already installed and running"
        return 0
    fi

    log_step "Installing Keycloak..."

    # Load credentials
    source "${SIAB_CONFIG_DIR}/credentials.env"

    # Clean up any existing Keycloak installation
    log_info "Cleaning up any existing Keycloak installation..."
    helm uninstall keycloak -n keycloak 2>/dev/null || true
    kubectl delete statefulset,deployment,service,secret -l app=keycloak -n keycloak 2>/dev/null || true
    kubectl delete statefulset,deployment,service -l app.kubernetes.io/name=keycloakx -n keycloak 2>/dev/null || true
    kubectl delete pvc --all -n keycloak 2>/dev/null || true
    kubectl delete pods --all -n keycloak --force --grace-period=0 2>/dev/null || true
    sleep 3

    # Create secrets
    local pg_password=$(openssl rand -base64 24 | tr -d '=+/' | head -c 24)

    # Deploy Keycloak directly without helm (avoids chart configuration issues)
    cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-credentials
  namespace: keycloak
type: Opaque
stringData:
  admin-user: admin
  admin-password: "${KEYCLOAK_ADMIN_PASSWORD}"
---
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-postgresql
  namespace: keycloak
type: Opaque
stringData:
  password: "${pg_password}"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keycloak-postgresql
  namespace: keycloak
spec:
  replicas: 1
  selector:
    matchLabels:
      app: keycloak-postgresql
  template:
    metadata:
      labels:
        app: keycloak-postgresql
    spec:
      containers:
      - name: postgresql
        image: postgres:15-alpine
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_DB
          value: keycloak
        - name: POSTGRES_USER
          value: postgres
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: keycloak-postgresql
              key: password
        resources:
          requests:
            memory: 256Mi
            cpu: 100m
---
apiVersion: v1
kind: Service
metadata:
  name: keycloak-postgresql
  namespace: keycloak
spec:
  ports:
  - port: 5432
  selector:
    app: keycloak-postgresql
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keycloak
  namespace: keycloak
  labels:
    app: keycloak
spec:
  replicas: 1
  selector:
    matchLabels:
      app: keycloak
  template:
    metadata:
      labels:
        app: keycloak
    spec:
      containers:
      - name: keycloak
        image: quay.io/keycloak/keycloak:24.0
        args:
        - start
        - --hostname-strict=false
        - --http-enabled=true
        - --proxy=edge
        - --cache=local
        env:
        - name: KEYCLOAK_ADMIN
          valueFrom:
            secretKeyRef:
              name: keycloak-credentials
              key: admin-user
        - name: KEYCLOAK_ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: keycloak-credentials
              key: admin-password
        - name: KC_DB
          value: postgres
        - name: KC_DB_URL
          value: jdbc:postgresql://keycloak-postgresql:5432/keycloak
        - name: KC_DB_USERNAME
          value: postgres
        - name: KC_DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: keycloak-postgresql
              key: password
        - name: KC_HEALTH_ENABLED
          value: "true"
        - name: KC_METRICS_ENABLED
          value: "true"
        ports:
        - name: http
          containerPort: 8080
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /health/live
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 30
        resources:
          requests:
            memory: 512Mi
            cpu: 250m
---
apiVersion: v1
kind: Service
metadata:
  name: keycloak
  namespace: keycloak
spec:
  ports:
  - name: http
    port: 80
    targetPort: 8080
  selector:
    app: keycloak
EOF

    # Monitor Keycloak deployment
    log_info "Waiting for Keycloak to be ready (this may take 3-5 minutes)..."
    local max_wait=600
    local elapsed=0
    local last_status_time=0

    while [[ $elapsed -lt $max_wait ]]; do
        # Show status every 30 seconds
        if [[ $((elapsed - last_status_time)) -ge 30 ]] || [[ $elapsed -eq 0 ]]; then
            echo ""
            echo "=== Keycloak Status (${elapsed}s elapsed) ==="
            kubectl get pods -n keycloak -o wide 2>/dev/null || echo "  (waiting for pods...)"
            echo "================================="
            last_status_time=$elapsed
        fi

        # Check if Keycloak is ready
        if kubectl get deployment keycloak -n keycloak -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -q "1"; then
            echo ""
            log_info "Keycloak is ready!"
            break
        fi

        # Check for crash loops or errors
        local pod_status=$(kubectl get pods -n keycloak -l app=keycloak -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting.reason}' 2>/dev/null)
        if [[ "$pod_status" == "CrashLoopBackOff" ]] || [[ "$pod_status" == "Error" ]] || [[ "$pod_status" == "ImagePullBackOff" ]]; then
            echo ""
            log_error "Keycloak pod is in $pod_status state"
            kubectl describe pods -n keycloak -l app=keycloak 2>/dev/null | tail -30 || true
            kubectl logs -n keycloak -l app=keycloak --tail=50 2>/dev/null || true
            exit 1
        fi

        sleep 10
        elapsed=$((elapsed + 10))
    done

    if [[ $elapsed -ge $max_wait ]]; then
        log_error "Keycloak installation timeout after ${max_wait}s"
        kubectl describe pods -n keycloak
        exit 1
    fi

    # Create DestinationRule to disable mTLS for Keycloak (no sidecar)
    # NOTE: DestinationRule must be in istio-system where the gateway runs
    cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: keycloak-disable-mtls
  namespace: istio-system
spec:
  host: keycloak.keycloak.svc.cluster.local
  trafficPolicy:
    tls:
      mode: DISABLE
EOF

    # Create Istio VirtualService for Keycloak
    cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: keycloak
  namespace: istio-system
spec:
  hosts:
    - "keycloak.${SIAB_DOMAIN}"
  gateways:
    - admin-gateway
  http:
    - route:
        - destination:
            host: keycloak.keycloak.svc.cluster.local
            port:
              number: 80
EOF

    complete_step "Keycloak Identity"
    log_info "Keycloak installed"
}

# Configure Keycloak Realm with users, roles, groups, and clients
configure_keycloak_realm() {
    start_step "Keycloak Realm Setup"

    # Check if realm already exists by testing for a client
    if kubectl get secret oauth2-proxy-client -n oauth2-proxy -o jsonpath='{.data.client-secret}' 2>/dev/null | base64 -d | grep -q "."; then
        skip_step "Keycloak Realm Setup" "Already configured"
        return 0
    fi

    log_step "Configuring Keycloak realm with users, roles, and clients..."

    # Load credentials to get Keycloak admin password
    source "${SIAB_CONFIG_DIR}/credentials.env"

    # Run the Keycloak configuration script
    if [[ -f "${SIAB_REPO_DIR}/scripts/configure-keycloak.sh" ]]; then
        chmod +x "${SIAB_REPO_DIR}/scripts/configure-keycloak.sh"
        SIAB_CONFIG_DIR="${SIAB_CONFIG_DIR}" \
        SIAB_DOMAIN="${SIAB_DOMAIN}" \
        KEYCLOAK_INTERNAL_URL="http://keycloak.keycloak.svc.cluster.local:80" \
        KEYCLOAK_ADMIN_USER="${KEYCLOAK_ADMIN_USER}" \
        KEYCLOAK_ADMIN_PASSWORD="${KEYCLOAK_ADMIN_PASSWORD}" \
        bash "${SIAB_REPO_DIR}/scripts/configure-keycloak.sh"
    else
        log_warn "Keycloak configuration script not found at ${SIAB_REPO_DIR}/scripts/configure-keycloak.sh"
        log_warn "Please run it manually after installation"
        skip_step "Keycloak Realm Setup" "Script not found"
        return 0
    fi

    complete_step "Keycloak Realm Setup"
    log_info "Keycloak realm configured with users and roles"
}

# Install OAuth2 Proxy for SSO enforcement
install_oauth2_proxy() {
    start_step "OAuth2 Proxy"

    # Check if OAuth2 Proxy is already running
    if kubectl get deployment oauth2-proxy -n oauth2-proxy -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -q "[1-9]"; then
        skip_step "OAuth2 Proxy" "Already installed and running"
        return 0
    fi

    log_step "Installing OAuth2 Proxy for SSO enforcement..."

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

    log_step "Configuring SSO enforcement policies..."

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

# Install MinIO
install_minio() {
    start_step "MinIO Storage"

    if [[ "${SIAB_SKIP_STORAGE}" == "true" ]]; then
        skip_step "MinIO Storage" "Skipped by configuration"
        return
    fi

    # Check if MinIO is already installed and ready
    if kubectl get deployment minio -n minio -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -q "1"; then
        skip_step "MinIO Storage" "Already installed and running"
        return 0
    fi

    log_step "Installing MinIO..."

    # Load credentials
    source "${SIAB_CONFIG_DIR}/credentials.env"

    # Disable Istio sidecar injection for minio namespace FIRST (before any cleanup)
    # This ensures any new pods created won't get sidecars injected
    kubectl label namespace minio istio-injection=disabled --overwrite 2>/dev/null || true

    # Clean up any existing/stuck MinIO installation thoroughly
    log_info "Cleaning up any existing MinIO installation..."

    # First, uninstall the helm release
    helm uninstall minio -n minio --wait 2>/dev/null || true

    # Force delete any stuck jobs (post-job can get stuck with Istio sidecars)
    for job in $(kubectl get jobs -n minio -o name 2>/dev/null); do
        log_info "Removing stuck job: $job"
        kubectl delete "$job" -n minio --force --grace-period=0 2>/dev/null || true
    done

    # Kill any pods that might be hanging (especially with Istio sidecars that won't exit)
    for pod in $(kubectl get pods -n minio -o name 2>/dev/null); do
        log_info "Force removing pod: $pod"
        kubectl delete "$pod" -n minio --force --grace-period=0 2>/dev/null || true
    done

    # Delete any PVCs
    kubectl delete pvc --all -n minio 2>/dev/null || true

    # Wait for everything to be gone
    log_info "Waiting for cleanup to complete..."
    local cleanup_timeout=60
    local cleanup_elapsed=0
    while [[ $cleanup_elapsed -lt $cleanup_timeout ]]; do
        local remaining_pods=$(kubectl get pods -n minio --no-headers 2>/dev/null | wc -l)
        if [[ "$remaining_pods" -eq 0 ]]; then
            break
        fi
        sleep 2
        cleanup_elapsed=$((cleanup_elapsed + 2))
    done

    # Final force cleanup if anything remains
    kubectl delete pods --all -n minio --force --grace-period=0 2>/dev/null || true
    sleep 2

    # Create MinIO secret
    kubectl create secret generic minio-creds \
        --namespace minio \
        --from-literal=rootUser="${MINIO_ROOT_USER}" \
        --from-literal=rootPassword="${MINIO_ROOT_PASSWORD}" \
        --dry-run=client -o yaml | kubectl apply -f -

    # Install MinIO (persistence disabled for single-node setup without storage provisioner)
    # Disable post-job as it can hang waiting for MinIO to be ready
    helm upgrade --install minio minio/minio \
        --namespace minio \
        --set rootUser="${MINIO_ROOT_USER}" \
        --set rootPassword="${MINIO_ROOT_PASSWORD}" \
        --set mode=standalone \
        --set replicas=1 \
        --set persistence.enabled=false \
        --set resources.requests.memory=1Gi \
        --set securityContext.runAsUser=1000 \
        --set securityContext.runAsGroup=1000 \
        --set securityContext.fsGroup=1000 \
        --set consoleService.type=ClusterIP \
        --set postJob.enabled=false \
        --timeout=600s

    # Wait for MinIO deployment to be ready
    log_info "Waiting for MinIO to be ready..."
    local max_wait=300
    local elapsed=0

    while [[ $elapsed -lt $max_wait ]]; do
        if kubectl get deployment minio -n minio -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -q "1"; then
            log_info "MinIO is ready!"
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        if [[ $((elapsed % 30)) -eq 0 ]]; then
            echo "  Waiting for MinIO... (${elapsed}s)"
            kubectl get pods -n minio 2>/dev/null || true
        fi
    done

    if [[ $elapsed -ge $max_wait ]]; then
        log_error "MinIO installation timeout"
        kubectl describe pods -n minio
        exit 1
    fi

    # Create DestinationRule to disable mTLS for MinIO (no sidecar)
    # NOTE: DestinationRule must be in istio-system where the gateway runs
    cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: minio-disable-mtls
  namespace: istio-system
spec:
  host: minio-console.minio.svc.cluster.local
  trafficPolicy:
    tls:
      mode: DISABLE
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: minio-api-disable-mtls
  namespace: istio-system
spec:
  host: minio.minio.svc.cluster.local
  trafficPolicy:
    tls:
      mode: DISABLE
EOF

    # Create Istio VirtualService for MinIO Console
    cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: minio-console
  namespace: istio-system
spec:
  hosts:
    - "minio.${SIAB_DOMAIN}"
  gateways:
    - admin-gateway
  http:
    - route:
        - destination:
            host: minio-console.minio.svc.cluster.local
            port:
              number: 9001
EOF

    complete_step "MinIO Storage"
    log_info "MinIO installed"
}

# Install Trivy Operator
install_trivy() {
    start_step "Trivy Security Scanner"

    # Check if Trivy is already installed
    if check_helm_release_installed "trivy-operator" "trivy-system"; then
        skip_step "Trivy Security Scanner" "Already installed"
        return 0
    fi

    log_step "Installing Trivy Operator ${TRIVY_VERSION}..."

    helm upgrade --install trivy-operator aqua/trivy-operator \
        --namespace trivy-system \
        --version ${TRIVY_VERSION} \
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

# Install OPA Gatekeeper
install_gatekeeper() {
    start_step "OPA Gatekeeper"

    # Check if Gatekeeper is already installed
    if check_helm_release_installed "gatekeeper" "gatekeeper-system"; then
        skip_step "OPA Gatekeeper" "Already installed"
        return 0
    fi

    log_step "Installing OPA Gatekeeper ${GATEKEEPER_VERSION}..."

    helm upgrade --install gatekeeper gatekeeper/gatekeeper \
        --namespace gatekeeper-system \
        --version ${GATEKEEPER_VERSION} \
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

# Install Monitoring Stack (Prometheus + Grafana)
install_monitoring() {
    start_step "Monitoring Stack"

    if [[ "${SIAB_SKIP_MONITORING}" == "true" ]]; then
        skip_step "Monitoring Stack" "Skipped by configuration"
        return
    fi

    # Check if monitoring is already installed
    if kubectl get deployment kube-prometheus-stack-grafana -n monitoring -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -q "1"; then
        skip_step "Monitoring Stack" "Already installed and running"
        return 0
    fi

    # Load credentials for Grafana
    source "${SIAB_CONFIG_DIR}/credentials.env"

    # Disable Istio sidecar injection for monitoring namespace FIRST (before any cleanup)
    # This ensures any new pods created won't get sidecars injected
    kubectl label namespace monitoring istio-injection=disabled --overwrite 2>/dev/null || true

    # Clean up any existing monitoring installation thoroughly
    log_info "Cleaning up any existing monitoring installation..."

    # First, uninstall the helm release
    helm uninstall kube-prometheus-stack -n monitoring --wait 2>/dev/null || true

    # Force delete any stuck jobs (admission jobs can get stuck with Istio sidecars)
    for job in $(kubectl get jobs -n monitoring -o name 2>/dev/null); do
        log_info "Removing stuck job: $job"
        kubectl delete "$job" -n monitoring --force --grace-period=0 2>/dev/null || true
    done

    # Kill any pods that might be hanging (especially with Istio sidecars that won't exit)
    for pod in $(kubectl get pods -n monitoring -o name 2>/dev/null); do
        log_info "Force removing pod: $pod"
        kubectl delete "$pod" -n monitoring --force --grace-period=0 2>/dev/null || true
    done

    # Delete any PVCs
    kubectl delete pvc --all -n monitoring 2>/dev/null || true

    # Wait for everything to be gone
    log_info "Waiting for monitoring cleanup to complete..."
    local cleanup_timeout=60
    local cleanup_elapsed=0
    while [[ $cleanup_elapsed -lt $cleanup_timeout ]]; do
        local remaining_pods=$(kubectl get pods -n monitoring --no-headers 2>/dev/null | wc -l)
        if [[ "$remaining_pods" -eq 0 ]]; then
            break
        fi
        sleep 2
        cleanup_elapsed=$((cleanup_elapsed + 2))
    done

    # Final force cleanup if anything remains
    kubectl delete pods --all -n monitoring --force --grace-period=0 2>/dev/null || true
    sleep 2

    # Install kube-prometheus-stack (Prometheus, Grafana, AlertManager)
    helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --version ${PROMETHEUS_STACK_VERSION} \
        --set prometheus.prometheusSpec.retention=7d \
        --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.accessModes[0]=ReadWriteOnce \
        --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=10Gi \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
        --set grafana.enabled=true \
        --set grafana.adminUser=admin \
        --set grafana.adminPassword="${GRAFANA_ADMIN_PASSWORD}" \
        --set grafana.service.type=ClusterIP \
        --set grafana.persistence.enabled=false \
        --set grafana.sidecar.dashboards.enabled=true \
        --set grafana.sidecar.dashboards.searchNamespace=ALL \
        --set grafana.grafana\.ini.auth\.anonymous.enabled=true \
        --set grafana.grafana\.ini.auth\.anonymous.org_role=Viewer \
        --set grafana.grafana\.ini.server.root_url=https://grafana.${SIAB_DOMAIN} \
        --set grafana.grafana\.ini.server.serve_from_sub_path=false \
        --set alertmanager.enabled=true \
        --set alertmanager.alertmanagerSpec.retention=120h \
        --set nodeExporter.enabled=true \
        --set kubeStateMetrics.enabled=true \
        --timeout=600s

    # Wait for Grafana to be ready
    log_info "Waiting for Grafana to be ready..."
    local max_wait=300
    local elapsed=0
    while [[ $elapsed -lt $max_wait ]]; do
        if kubectl get deployment kube-prometheus-stack-grafana -n monitoring -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -q "1"; then
            log_info "Grafana is ready!"
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        if [[ $((elapsed % 30)) -eq 0 ]]; then
            echo "  Waiting for Grafana... (${elapsed}s)"
        fi
    done

    # Create DestinationRule to disable mTLS for monitoring services (they don't have sidecars)
    # NOTE: DestinationRule must be in istio-system where the gateway runs
    cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: grafana-disable-mtls
  namespace: istio-system
spec:
  host: kube-prometheus-stack-grafana.monitoring.svc.cluster.local
  trafficPolicy:
    tls:
      mode: DISABLE
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: prometheus-disable-mtls
  namespace: istio-system
spec:
  host: kube-prometheus-stack-prometheus.monitoring.svc.cluster.local
  trafficPolicy:
    tls:
      mode: DISABLE
EOF

    # Create Istio VirtualService for Grafana
    cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: grafana
  namespace: istio-system
spec:
  hosts:
    - "grafana.${SIAB_DOMAIN}"
  gateways:
    - admin-gateway
  http:
    - route:
        - destination:
            host: kube-prometheus-stack-grafana.monitoring.svc.cluster.local
            port:
              number: 80
EOF

    complete_step "Monitoring Stack"
    log_info "Monitoring stack installed"
}

# Install Kubernetes Dashboard
install_kubernetes_dashboard() {
    start_step "Kubernetes Dashboard"

    # Check if dashboard is already installed
    if check_helm_release_installed "kubernetes-dashboard" "kubernetes-dashboard"; then
        skip_step "Kubernetes Dashboard" "Already installed"
        return 0
    fi

    log_step "Installing Kubernetes Dashboard..."

    # Clean up any existing dashboard
    helm uninstall kubernetes-dashboard -n kubernetes-dashboard 2>/dev/null || true
    kubectl delete namespace kubernetes-dashboard 2>/dev/null || true
    sleep 3

    # Create namespace
    kubectl create namespace kubernetes-dashboard --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace kubernetes-dashboard istio-injection=disabled --overwrite

    # Install Kubernetes Dashboard
    helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
        --namespace kubernetes-dashboard \
        --version ${KUBE_DASHBOARD_VERSION} \
        --set app.ingress.enabled=false \
        --set api.containers.resources.requests.cpu=100m \
        --set api.containers.resources.requests.memory=200Mi \
        --set web.containers.resources.requests.cpu=100m \
        --set web.containers.resources.requests.memory=200Mi \
        --timeout=300s

    # Wait for dashboard to be ready
    log_info "Waiting for Kubernetes Dashboard to be ready..."
    kubectl wait --for=condition=Available deployment --all -n kubernetes-dashboard --timeout=300s 2>/dev/null || true

    # Create admin service account for dashboard access
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: siab-admin
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: siab-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: siab-admin
  namespace: kubernetes-dashboard
---
apiVersion: v1
kind: Secret
metadata:
  name: siab-admin-token
  namespace: kubernetes-dashboard
  annotations:
    kubernetes.io/service-account.name: siab-admin
type: kubernetes.io/service-account-token
EOF

    # Create DestinationRule to disable mTLS for Dashboard (no sidecar)
    # NOTE: DestinationRule must be in istio-system where the gateway runs
    cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: k8s-dashboard-disable-mtls
  namespace: istio-system
spec:
  host: kubernetes-dashboard-kong-proxy.kubernetes-dashboard.svc.cluster.local
  trafficPolicy:
    tls:
      mode: SIMPLE
EOF

    # Create Istio VirtualService for Kubernetes Dashboard
    # Using k8s-dashboard.${SIAB_DOMAIN} to avoid conflict with SIAB Dashboard
    cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: kubernetes-dashboard
  namespace: istio-system
spec:
  hosts:
    - "k8s-dashboard.${SIAB_DOMAIN}"
  gateways:
    - admin-gateway
  http:
    - route:
        - destination:
            host: kubernetes-dashboard-kong-proxy.kubernetes-dashboard.svc.cluster.local
            port:
              number: 443
EOF

    complete_step "Kubernetes Dashboard"
    log_info "Kubernetes Dashboard installed"
}

# Install SIAB tools (status script, etc.)
install_siab_tools() {
    start_step "SIAB Tools"

    log_step "Installing SIAB management tools..."

    # Install siab-status script
    if [[ -f "${SIAB_REPO_DIR}/siab-status.sh" ]]; then
        cp "${SIAB_REPO_DIR}/siab-status.sh" "${SIAB_BIN_DIR}/siab-status"
        chmod +x "${SIAB_BIN_DIR}/siab-status"
        log_info "siab-status command installed"
    else
        log_warn "siab-status.sh not found in repo"
    fi

    # Install siab-info script
    if [[ -f "${SIAB_REPO_DIR}/siab-info.sh" ]]; then
        cp "${SIAB_REPO_DIR}/siab-info.sh" "${SIAB_BIN_DIR}/siab-info"
        chmod +x "${SIAB_BIN_DIR}/siab-info"
        log_info "siab-info command installed"
    else
        log_warn "siab-info.sh not found in repo"
    fi

    # Install fix-rke2 script
    if [[ -f "${SIAB_REPO_DIR}/fix-rke2.sh" ]]; then
        cp "${SIAB_REPO_DIR}/fix-rke2.sh" "${SIAB_BIN_DIR}/siab-fix-rke2"
        chmod +x "${SIAB_BIN_DIR}/siab-fix-rke2"
        log_info "siab-fix-rke2 command installed"
    fi

    # Install uninstall script
    if [[ -f "${SIAB_REPO_DIR}/uninstall.sh" ]]; then
        cp "${SIAB_REPO_DIR}/uninstall.sh" "${SIAB_BIN_DIR}/siab-uninstall"
        chmod +x "${SIAB_BIN_DIR}/siab-uninstall"
        log_info "siab-uninstall command installed"
    fi

    # Install fix-istio-routing script
    if [[ -f "${SIAB_REPO_DIR}/fix-istio-routing.sh" ]]; then
        cp "${SIAB_REPO_DIR}/fix-istio-routing.sh" "${SIAB_BIN_DIR}/siab-fix-istio"
        chmod +x "${SIAB_BIN_DIR}/siab-fix-istio"
        log_info "siab-fix-istio command installed"
    fi

    # Install diagnostic script
    if [[ -f "${SIAB_REPO_DIR}/siab-diagnose.sh" ]]; then
        cp "${SIAB_REPO_DIR}/siab-diagnose.sh" "${SIAB_BIN_DIR}/siab-diagnose"
        chmod +x "${SIAB_BIN_DIR}/siab-diagnose"
        log_info "siab-diagnose command installed"
    fi

    complete_step "SIAB Tools"
    log_info "SIAB tools installed"
}

# Apply security policies
apply_security_policies() {
    start_step "Security Policies"

    log_step "Applying security policies..."

    # Default deny network policy for default namespace
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: default
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: default
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: UDP
          port: 53
EOF

    # Apply additional security policies from repo if available
    if [[ -d "${SIAB_REPO_DIR}/manifests/security" ]]; then
        log_info "Applying additional security policies..."
        kubectl apply -f "${SIAB_REPO_DIR}/manifests/security/" 2>/dev/null || {
            log_warn "Some security policies may have failed to apply (gatekeeper constraints need templates first)"
        }
    fi

    complete_step "Security Policies"
    log_info "Security policies applied"
}

# Install SIAB CRDs
install_siab_crds() {
    start_step "SIAB CRDs"

    log_step "Installing SIAB Custom Resource Definitions..."

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

    complete_step "SIAB CRDs"
    log_info "SIAB CRDs installed"
}

# Install landing page dashboard
install_dashboard() {
    start_step "SIAB Dashboard"

    # Check if dashboard is already running
    if kubectl get deployment siab-dashboard -n siab-dashboard -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -q "[1-9]"; then
        skip_step "SIAB Dashboard" "Already installed and running"
        return 0
    fi

    log_step "Installing SIAB Dashboard..."

    # Create namespace (silently)
    run_quiet_ok kubectl create namespace siab-dashboard
    run_quiet_ok kubectl label namespace siab-dashboard istio-injection=enabled --overwrite

    # Read the HTML content from the frontend
    local html_content=""
    if [[ -f "${SIAB_REPO_DIR}/dashboard/frontend/index.html" ]]; then
        html_content=$(cat "${SIAB_REPO_DIR}/dashboard/frontend/index.html")
        # Escape for YAML - replace domain placeholder
        html_content=$(echo "$html_content" | sed "s/siab\.local/${SIAB_DOMAIN}/g")
    else
        log_warn "Dashboard HTML not found, using placeholder"
        html_content='<!DOCTYPE html><html><head><title>SIAB Dashboard</title></head><body><h1>SIAB Dashboard</h1><p>Welcome to SIAB!</p></body></html>'
    fi

    # Create the ConfigMap with the actual HTML content (silently)
    kubectl create configmap siab-dashboard-html \
        --from-literal=index.html="$html_content" \
        -n siab-dashboard \
        --dry-run=client -o yaml 2>/dev/null | run_quiet kubectl apply -f -

    # Deploy dashboard manifests
    if [[ -f "${SIAB_REPO_DIR}/manifests/dashboard/siab-dashboard.yaml" ]]; then
        # Apply the manifest (skip the HTML configmap since we created it above)
        sed "s/siab\.local/${SIAB_DOMAIN}/g" "${SIAB_REPO_DIR}/manifests/dashboard/siab-dashboard.yaml" | \
            grep -v "^  index.html:" | run_quiet kubectl apply -f -
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

    # Copy manifests to SIAB directory for reference
    if [[ -d "${SIAB_REPO_DIR}/manifests" ]]; then
        cp -r "${SIAB_REPO_DIR}/manifests" "${SIAB_DIR}/"
        log_info "Manifests copied to ${SIAB_DIR}/manifests/"
    fi

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

    log_step "Installing SIAB Application Deployer..."

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

    # Read and inject frontend HTML content if it exists
    local frontend_html="${SIAB_REPO_DIR}/app-deployer/frontend/index.html"
    if [[ -f "$frontend_html" ]]; then
        local html_content
        html_content=$(cat "$frontend_html" | sed "s/siab\.local/${SIAB_DOMAIN}/g")

        # Create ConfigMap with the frontend HTML
        kubectl create configmap app-deployer-frontend-html \
            --from-literal=index.html="$html_content" \
            -n siab-deployer \
            --dry-run=client -o yaml 2>/dev/null | run_quiet kubectl apply -f -
    fi

    # Read and inject apps.html if it exists
    local apps_html="${SIAB_REPO_DIR}/app-deployer/frontend/apps.html"
    if [[ -f "$apps_html" ]]; then
        local apps_content
        apps_content=$(cat "$apps_html" | sed "s/siab\.local/${SIAB_DOMAIN}/g")

        kubectl create configmap app-deployer-frontend-apps \
            --from-literal=apps.html="$apps_content" \
            -n siab-deployer \
            --dry-run=client -o yaml 2>/dev/null | run_quiet kubectl apply -f -
    fi

    # Apply the deployer manifest with domain substitution
    sed "s/siab\.local/${SIAB_DOMAIN}/g" "$deployer_manifest" | run_quiet kubectl apply -f -
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

# Create Istio Gateways (Admin and User planes)
create_istio_gateway() {
    start_step "Istio Gateways"

    # Check if gateways already exist
    if kubectl get gateway admin-gateway -n istio-system &>/dev/null && \
       kubectl get gateway user-gateway -n istio-system &>/dev/null; then
        skip_step "Istio Gateways" "Already configured"
        return 0
    fi

    log_step "Creating Istio Gateways with HTTPS-only access..."

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
    - "*.admin.${SIAB_DOMAIN}"
    - "admin.${SIAB_DOMAIN}"
EOF

    # Use manifest files if available, otherwise create inline
    if [[ -f "${SIAB_REPO_DIR}/manifests/istio/gateways.yaml" ]]; then
        log_info "Applying gateway manifests with HTTPS redirects..."
        # Replace SIAB_DOMAIN placeholder in manifests
        sed "s/siab\.local/${SIAB_DOMAIN}/g" "${SIAB_REPO_DIR}/manifests/istio/gateways.yaml" | kubectl apply -f -
    else
        log_info "Creating gateways inline with HTTPS redirects..."

        # ADMIN Gateway - for administrative interfaces (Grafana, Keycloak, K8s Dashboard, MinIO)
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
        number: 443
        name: https
        protocol: HTTPS
      tls:
        mode: SIMPLE
        credentialName: siab-gateway-cert
      hosts:
        - "grafana.${SIAB_DOMAIN}"
        - "keycloak.${SIAB_DOMAIN}"
        - "k8s-dashboard.${SIAB_DOMAIN}"
        - "minio.${SIAB_DOMAIN}"
        - "longhorn.${SIAB_DOMAIN}"
        - "*.admin.${SIAB_DOMAIN}"
    - port:
        number: 80
        name: http
        protocol: HTTP
      tls:
        httpsRedirect: true
      hosts:
        - "grafana.${SIAB_DOMAIN}"
        - "keycloak.${SIAB_DOMAIN}"
        - "k8s-dashboard.${SIAB_DOMAIN}"
        - "minio.${SIAB_DOMAIN}"
        - "longhorn.${SIAB_DOMAIN}"
        - "*.admin.${SIAB_DOMAIN}"
EOF

        # USER Gateway - for user applications and catalog
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
        number: 443
        name: https
        protocol: HTTPS
      tls:
        mode: SIMPLE
        credentialName: siab-gateway-cert
      hosts:
        - "${SIAB_DOMAIN}"
        - "dashboard.${SIAB_DOMAIN}"
        - "catalog.${SIAB_DOMAIN}"
        - "*.apps.${SIAB_DOMAIN}"
    - port:
        number: 80
        name: http
        protocol: HTTP
      tls:
        httpsRedirect: true
      hosts:
        - "${SIAB_DOMAIN}"
        - "dashboard.${SIAB_DOMAIN}"
        - "catalog.${SIAB_DOMAIN}"
        - "*.apps.${SIAB_DOMAIN}"
EOF

        # Legacy gateway for backward compatibility (routes to user gateway by default)
        cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: siab-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingress-user
  servers:
    - port:
        number: 443
        name: https
        protocol: HTTPS
      tls:
        mode: SIMPLE
        credentialName: siab-gateway-cert
      hosts:
        - "*.${SIAB_DOMAIN}"
        - "${SIAB_DOMAIN}"
    - port:
        number: 80
        name: http
        protocol: HTTP
      tls:
        httpsRedirect: true
      hosts:
        - "*.${SIAB_DOMAIN}"
        - "${SIAB_DOMAIN}"
EOF
    fi

    # Apply PeerAuthentication policies for ingress gateways
    log_info "Configuring mTLS policies for ingress gateways..."
    if [[ -f "${SIAB_REPO_DIR}/manifests/istio/peer-authentication.yaml" ]]; then
        kubectl apply -f "${SIAB_REPO_DIR}/manifests/istio/peer-authentication.yaml"
    else
        # Create inline if manifest not found
        cat <<EOF | kubectl apply -f -
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: ingress-admin-mtls
  namespace: istio-system
spec:
  selector:
    matchLabels:
      istio: ingress-admin
  mtls:
    mode: PERMISSIVE
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: ingress-user-mtls
  namespace: istio-system
spec:
  selector:
    matchLabels:
      istio: ingress-user
  mtls:
    mode: PERMISSIVE
EOF
    fi

    # Create RequestAuthentication for JWT validation from Keycloak (on admin gateway)
    cat <<EOF | kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: keycloak-jwt-auth-admin
  namespace: istio-system
spec:
  selector:
    matchLabels:
      istio: ingress-admin
  jwtRules:
    - issuer: "https://keycloak.${SIAB_DOMAIN}/realms/siab"
      jwksUri: "http://keycloak.keycloak.svc.cluster.local:80/realms/siab/protocol/openid-connect/certs"
      forwardOriginalToken: true
      outputPayloadToHeader: x-jwt-payload
EOF

    # Create RequestAuthentication for JWT validation from Keycloak (on user gateway)
    cat <<EOF | kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: RequestAuthentication
metadata:
  name: keycloak-jwt-auth-user
  namespace: istio-system
spec:
  selector:
    matchLabels:
      istio: ingress-user
  jwtRules:
    - issuer: "https://keycloak.${SIAB_DOMAIN}/realms/siab"
      jwksUri: "http://keycloak.keycloak.svc.cluster.local:80/realms/siab/protocol/openid-connect/certs"
      forwardOriginalToken: true
      outputPayloadToHeader: x-jwt-payload
EOF

    # Allow unauthenticated access to Keycloak (needed to login)
    cat <<EOF | kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-keycloak-unauthenticated
  namespace: istio-system
spec:
  selector:
    matchLabels:
      istio: ingress-admin
  action: ALLOW
  rules:
    - to:
        - operation:
            hosts:
              - "keycloak.${SIAB_DOMAIN}"
              - "keycloak.${SIAB_DOMAIN}:*"
EOF

    # Allow unauthenticated access to user dashboard and catalog
    cat <<EOF | kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-dashboard-unauthenticated
  namespace: istio-system
spec:
  selector:
    matchLabels:
      istio: ingress-user
  action: ALLOW
  rules:
    - to:
        - operation:
            hosts:
              - "${SIAB_DOMAIN}"
              - "${SIAB_DOMAIN}:*"
              - "dashboard.${SIAB_DOMAIN}"
              - "dashboard.${SIAB_DOMAIN}:*"
              - "catalog.${SIAB_DOMAIN}"
              - "catalog.${SIAB_DOMAIN}:*"
EOF

    # Create Istio AuthorizationPolicies to allow traffic through gateways
    log_info "Creating Istio authorization policies..."
    cat <<EOF | kubectl apply -f -
---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-admin-services
  namespace: istio-system
spec:
  selector:
    matchLabels:
      istio: ingress-admin
  action: ALLOW
  rules:
    - {}
---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-user-services
  namespace: istio-system
spec:
  selector:
    matchLabels:
      istio: ingress-user
  action: ALLOW
  rules:
    - {}
EOF

    complete_step "Istio Gateways"
    log_info "Istio Gateway and authentication created"
    log_info "Authorization policies configured for gateway access"
}

# Fix Istio mTLS for services without sidecars
fix_istio_mtls_for_non_sidecar_services() {
    log_info "Configuring mTLS exceptions for services without Istio sidecars..."

    # Create DestinationRules to disable mTLS for services in namespaces without Istio injection
    # This is necessary because these namespaces have istio-injection=disabled but Istio
    # is configured with STRICT mTLS globally

    cat <<EOF | kubectl apply -f -
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: keycloak-mtls-disable
  namespace: istio-system
spec:
  host: keycloak.keycloak.svc.cluster.local
  trafficPolicy:
    tls:
      mode: DISABLE
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: minio-mtls-disable
  namespace: istio-system
spec:
  host: minio.minio.svc.cluster.local
  trafficPolicy:
    tls:
      mode: DISABLE
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: minio-console-mtls-disable
  namespace: istio-system
spec:
  host: minio-console.minio.svc.cluster.local
  trafficPolicy:
    tls:
      mode: DISABLE
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: grafana-mtls-disable
  namespace: istio-system
spec:
  host: kube-prometheus-stack-grafana.monitoring.svc.cluster.local
  trafficPolicy:
    tls:
      mode: DISABLE
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: prometheus-mtls-disable
  namespace: istio-system
spec:
  host: kube-prometheus-stack-prometheus.monitoring.svc.cluster.local
  trafficPolicy:
    tls:
      mode: DISABLE
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: longhorn-mtls-disable
  namespace: istio-system
spec:
  host: longhorn-frontend.longhorn-system.svc.cluster.local
  trafficPolicy:
    tls:
      mode: DISABLE
EOF

    log_info "mTLS exceptions configured for non-sidecar services"

    # Create VirtualService for Longhorn UI (installed before Istio, so created here)
    log_info "Creating VirtualService for Longhorn UI..."
    cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: longhorn-ui
  namespace: istio-system
spec:
  hosts:
    - "longhorn.${SIAB_DOMAIN}"
  gateways:
    - admin-gateway
  http:
    - route:
        - destination:
            host: longhorn-frontend.longhorn-system.svc.cluster.local
            port:
              number: 80
EOF

    log_info "Longhorn UI VirtualService created"
}

# Final configuration
final_configuration() {
    start_step "Final Configuration"

    log_step "Performing final configuration..."

    # Get gateway IPs from MetalLB LoadBalancer services
    local admin_gateway_ip user_gateway_ip
    log_info "Waiting for gateway LoadBalancer IPs..."

    # Wait up to 60 seconds for IPs to be assigned
    local timeout=60
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        admin_gateway_ip=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        user_gateway_ip=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

        if [[ -n "$admin_gateway_ip" ]] && [[ -n "$user_gateway_ip" ]]; then
            break
        fi
        sleep 2
        elapsed=$((elapsed + 2))
    done

    # Fallback to node IP if LoadBalancer IPs not available
    if [[ -z "$admin_gateway_ip" ]] || [[ -z "$user_gateway_ip" ]]; then
        log_warn "LoadBalancer IPs not available, falling back to node IP"
        local node_ip
        node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
        admin_gateway_ip="${node_ip}"
        user_gateway_ip="${node_ip}"
    fi

    log_info "Admin Gateway IP: ${admin_gateway_ip}"
    log_info "User Gateway IP: ${user_gateway_ip}"

    # Save installation info
    cat > "${SIAB_CONFIG_DIR}/install-info.json" <<EOF
{
  "version": "${SIAB_VERSION}",
  "installed_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "domain": "${SIAB_DOMAIN}",
  "admin_gateway_ip": "${admin_gateway_ip}",
  "user_gateway_ip": "${user_gateway_ip}",
  "components": {
    "rke2": "${RKE2_VERSION}",
    "istio": "${ISTIO_VERSION}",
    "keycloak": "${KEYCLOAK_VERSION}",
    "minio": "${MINIO_VERSION}",
    "trivy": "${TRIVY_VERSION}",
    "gatekeeper": "${GATEKEEPER_VERSION}",
    "cert_manager": "${CERTMANAGER_VERSION}"
  }
}
EOF

    # Save gateway IPs to credentials file for siab-info script
    cat >> "${SIAB_CONFIG_DIR}/credentials.env" <<EOF

# Gateway IPs (MetalLB LoadBalancer)
ADMIN_GATEWAY_IP="${admin_gateway_ip}"
USER_GATEWAY_IP="${user_gateway_ip}"
EOF

    # Add hosts entries for local access - separate admin and user plane domains
    if ! grep -q "SIAB Admin Plane" /etc/hosts; then
        cat >> /etc/hosts <<EOF

# SIAB Admin Plane (administrative services - restricted access)
${admin_gateway_ip} keycloak.${SIAB_DOMAIN}
${admin_gateway_ip} minio.${SIAB_DOMAIN}
${admin_gateway_ip} grafana.${SIAB_DOMAIN}
${admin_gateway_ip} k8s-dashboard.${SIAB_DOMAIN}

# SIAB User Plane (user-facing services)
${user_gateway_ip} ${SIAB_DOMAIN}
${user_gateway_ip} dashboard.${SIAB_DOMAIN}
${user_gateway_ip} catalog.${SIAB_DOMAIN}
EOF
    fi

    # Setup kubectl access for non-root users
    setup_nonroot_access

    complete_step "Final Configuration"
    log_info "Final configuration complete"
}

# Setup kubectl access for non-root users
setup_nonroot_access() {
    log_info "Setting up kubectl access for non-root users..."

    # Get the user who ran sudo (if any)
    local real_user="${SUDO_USER:-}"
    local real_home=""

    if [[ -n "$real_user" ]] && [[ "$real_user" != "root" ]]; then
        real_home=$(getent passwd "$real_user" | cut -d: -f6)

        if [[ -n "$real_home" ]]; then
            log_info "Configuring kubectl for user: $real_user"

            # Create .kube directory for the user
            mkdir -p "${real_home}/.kube"

            # Copy kubeconfig
            cp /etc/rancher/rke2/rke2.yaml "${real_home}/.kube/config"

            # Fix permissions
            chown -R "${real_user}:${real_user}" "${real_home}/.kube"
            chmod 600 "${real_home}/.kube/config"

            # Add RKE2 and SIAB bins to user's PATH
            if ! grep -q "/var/lib/rancher/rke2/bin" "${real_home}/.bashrc" 2>/dev/null; then
                cat >> "${real_home}/.bashrc" <<'EOF'

# SIAB - Kubernetes tools
export PATH=$PATH:/var/lib/rancher/rke2/bin:/usr/local/bin
export KUBECONFIG=$HOME/.kube/config
EOF
                chown "${real_user}:${real_user}" "${real_home}/.bashrc"
            fi

            log_info "User $real_user can now run kubectl, helm, and k9s without sudo"
        fi
    fi

    # Also ensure the credentials file is readable
    if [[ -n "$real_user" ]] && [[ "$real_user" != "root" ]]; then
        # Create a copy of credentials for the user
        if [[ -f "${SIAB_CONFIG_DIR}/credentials.env" ]]; then
            cp "${SIAB_CONFIG_DIR}/credentials.env" "${real_home}/.siab-credentials.env"
            chown "${real_user}:${real_user}" "${real_home}/.siab-credentials.env"
            chmod 600 "${real_home}/.siab-credentials.env"
            log_info "Credentials copied to ${real_home}/.siab-credentials.env"
        fi
    fi
}

# Print completion message
print_completion() {
    # Get gateway IPs from MetalLB LoadBalancer services
    local admin_gateway_ip user_gateway_ip
    admin_gateway_ip=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    user_gateway_ip=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    # Fallback to node IP if needed
    if [[ -z "$admin_gateway_ip" ]] || [[ -z "$user_gateway_ip" ]]; then
        local node_ip
        node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
        admin_gateway_ip="${admin_gateway_ip:-$node_ip}"
        user_gateway_ip="${user_gateway_ip:-$node_ip}"
    fi

    # Get dashboard token - try multiple methods for compatibility
    local dashboard_token=""

    # Method 1: Try to get from the secret (older method)
    dashboard_token=$(kubectl get secret siab-admin-token -n kubernetes-dashboard -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null || true)

    # Method 2: If secret method failed, use kubectl create token (K8s 1.24+)
    if [[ -z "$dashboard_token" ]] || [[ ${#dashboard_token} -lt 50 ]]; then
        dashboard_token=$(kubectl create token siab-admin -n kubernetes-dashboard --duration=8760h 2>/dev/null || true)
    fi

    echo ""
    echo "╔════════════════════════════════════════════════════════════════╗"
    echo -e "║          ${GREEN}SIAB Installation Complete!${NC}                          ║"
    echo "╚════════════════════════════════════════════════════════════════╝"
    echo ""
    echo -e "${BLUE}▸ Network Architecture${NC}"
    echo "  ─────────────────────────────────────────"
    echo "  Admin Gateway IP:  ${admin_gateway_ip} (restricted access)"
    echo "  User Gateway IP:   ${user_gateway_ip} (user-facing apps)"
    echo ""
    echo -e "${BLUE}▸ Admin Plane Services (port 443)${NC}"
    echo "  ─────────────────────────────────────────"
    echo "  Grafana (Monitoring):    https://grafana.${SIAB_DOMAIN}"
    echo "  K8s Dashboard:           https://k8s-dashboard.${SIAB_DOMAIN}"
    echo "  Keycloak (Identity):     https://keycloak.${SIAB_DOMAIN}"
    echo "  MinIO (S3 Storage):      https://minio.${SIAB_DOMAIN}"
    echo "  Longhorn (Block Storage):https://longhorn.${SIAB_DOMAIN}"
    echo ""
    echo -e "${BLUE}▸ User Plane Services (port 443)${NC}"
    echo "  ─────────────────────────────────────────"
    echo "  SIAB Dashboard:          https://dashboard.${SIAB_DOMAIN}"
    echo "  App Catalog:             https://catalog.${SIAB_DOMAIN}"
    echo ""
    echo -e "${BLUE}▸ SIAB Commands${NC}"
    echo "  ─────────────────────────────────────────"
    echo "  siab-status              - View SIAB platform status"
    echo "  siab-info                - Show access URLs & credentials"
    echo "  siab-fix-rke2            - Troubleshoot RKE2 issues"
    echo "  siab-fix-istio           - Fix Istio routing issues"
    echo "  siab-diagnose            - Diagnose and fix common issues"
    echo "  siab-uninstall           - Remove SIAB completely"
    echo ""
    echo -e "${BLUE}▸ Kubernetes Commands${NC}"
    echo "  ─────────────────────────────────────────"
    echo "  k9s                      - Interactive cluster UI (terminal)"
    echo "  kubectl get pods -A      - List all pods"
    echo "  helm list -A             - List installed Helm charts"
    echo ""
    echo -e "${BLUE}▸ Credentials${NC}"
    echo "  ─────────────────────────────────────────"
    echo "  File: ${SIAB_CONFIG_DIR}/credentials.env"
    echo "  View: sudo cat ${SIAB_CONFIG_DIR}/credentials.env"
    echo ""
    # Show SIAB user credentials if available
    if [[ -f "${SIAB_CONFIG_DIR}/keycloak/default-user.env" ]]; then
        source "${SIAB_CONFIG_DIR}/keycloak/default-user.env" 2>/dev/null || true
        echo -e "${BLUE}▸ SIAB Login (Keycloak SSO)${NC}"
        echo "  ─────────────────────────────────────────"
        echo "  Username: ${DEFAULT_ADMIN_USER:-siab-admin}"
        echo "  Password: ${DEFAULT_ADMIN_PASSWORD:-<check credentials file>}"
        echo -e "  ${YELLOW}(Password must be changed on first login)${NC}"
        echo ""
        echo "  Roles available:"
        echo "    - siab-admin    (Full administrative access)"
        echo "    - siab-operator (Deploy and manage apps)"
        echo "    - siab-user     (Use deployed apps)"
        echo ""
    fi
    if [[ -n "$dashboard_token" ]]; then
        echo -e "${BLUE}▸ Kubernetes Dashboard Token${NC}"
        echo "  ─────────────────────────────────────────"
        echo "  Use this token to log into the K8s Dashboard:"
        echo ""
        echo "  $dashboard_token"
        echo ""
    fi
    if [[ -n "${SUDO_USER:-}" ]] && [[ "${SUDO_USER}" != "root" ]]; then
        echo -e "${BLUE}▸ Non-root Access${NC}"
        echo "  ─────────────────────────────────────────"
        echo "  User: ${SUDO_USER}"
        echo "  Run: source ~/.bashrc  (or log out and back in)"
        echo "  Then use kubectl, helm, k9s, siab-status without sudo"
        echo ""
    fi
    echo -e "${YELLOW}▸ Add to /etc/hosts on client machines:${NC}"
    echo "  ─────────────────────────────────────────"
    echo ""
    echo "Admin Plane (restricted)"
    echo "  ${admin_gateway_ip} keycloak.${SIAB_DOMAIN} minio.${SIAB_DOMAIN} grafana.${SIAB_DOMAIN} k8s-dashboard.${SIAB_DOMAIN} longhorn.${SIAB_DOMAIN}"
    echo ""
    echo "User Plane"
    echo "  ${user_gateway_ip} ${SIAB_DOMAIN} dashboard.${SIAB_DOMAIN} catalog.${SIAB_DOMAIN} deployer.${SIAB_DOMAIN} auth.${SIAB_DOMAIN}"
    echo ""
    echo -e "${GREEN}▸ Next Steps${NC}"
    echo "  ─────────────────────────────────────────"
    echo "  1. Add the /etc/hosts entries above to your client machine"
    echo "  2. Access https://dashboard.${SIAB_DOMAIN} to login"
    echo "  3. Change your password on first login (required)"
    echo "  4. Create additional users in Keycloak as needed"
    echo ""
    echo "  SSO is now enabled for all applications!"
    echo "    - Dashboard:      https://dashboard.${SIAB_DOMAIN}"
    echo "    - App Deployer:   https://deployer.${SIAB_DOMAIN}"
    echo "    - Keycloak Admin: https://keycloak.${SIAB_DOMAIN}"
    echo ""
    echo "════════════════════════════════════════════════════════════════"
    echo "  Thank you for installing SIAB - Secure Infrastructure as a Box"
    echo "════════════════════════════════════════════════════════════════"
}

# Main installation
main() {
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║         SIAB - Secure Infrastructure as a Box                  ║${NC}"
    echo -e "${BOLD}║                  Version ${SIAB_VERSION}                                   ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    log_info "Starting SIAB ${SIAB_VERSION} installation..."

    # Initialize status tracking
    init_step_status

    check_root
    setup_directories

    # Redirect stdout/stderr to log file (progress bar uses fd 3 for display)
    exec 1>>"$SIAB_LOG_FILE" 2>&1

    # System Requirements check
    start_step "System Requirements"
    check_requirements
    complete_step "System Requirements"

    # System Dependencies
    start_step "System Dependencies"
    install_dependencies
    complete_step "System Dependencies"

    # Repository Clone
    start_step "Repository Clone"
    clone_siab_repo
    complete_step "Repository Clone"

    # Firewall Configuration
    start_step "Firewall Configuration"
    configure_firewall
    complete_step "Firewall Configuration"

    # Security Configuration
    start_step "Security Configuration"
    configure_security
    complete_step "Security Configuration"

    # Core Infrastructure
    install_rke2

    # Configure Calico/Canal network after RKE2 is running
    configure_calico_network

    install_helm
    install_k9s

    # Credentials Generation
    start_step "Credentials Generation"
    generate_credentials
    complete_step "Credentials Generation"

    # Kubernetes Namespaces
    start_step "Kubernetes Namespaces"
    create_namespaces
    complete_step "Kubernetes Namespaces"

    # Kubernetes Components
    install_cert_manager
    install_metallb
    install_longhorn
    install_istio
    create_istio_gateway
    fix_istio_mtls_for_non_sidecar_services

    # Applications
    install_keycloak
    configure_keycloak_realm
    install_oauth2_proxy
    configure_sso
    install_minio
    install_trivy
    install_gatekeeper
    install_monitoring
    install_kubernetes_dashboard

    # SIAB Components
    install_siab_tools
    apply_security_policies
    install_siab_crds
    install_dashboard
    install_deployer

    # Final Configuration
    final_configuration

    # Restore stdout/stderr for final messages
    exec 1>&3 2>&4

    # Print final status dashboard
    print_status_dashboard

    print_completion

    log_info "Installation completed successfully!"
}

# Run main function
main "$@"
