#!/bin/bash
# SIAB - Secure Infrastructure as a Box
# Modular Uninstaller Orchestrator
#
# This script completely removes SIAB and all its components,
# returning the system to its pre-installation state.

set -uo pipefail
# Note: Not using -e because we want to continue on errors

# Get script directory for module loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ==============================================================================
# Load Libraries
# ==============================================================================

source "${SCRIPT_DIR}/lib/common/colors.sh"
source "${SCRIPT_DIR}/lib/common/config.sh"
source "${SCRIPT_DIR}/lib/common/logging.sh"
source "${SCRIPT_DIR}/lib/common/os.sh"
source "${SCRIPT_DIR}/lib/common/utils.sh"
source "${SCRIPT_DIR}/lib/kubernetes/kubectl.sh"
source "${SCRIPT_DIR}/lib/kubernetes/helm.sh"
source "${SCRIPT_DIR}/lib/kubernetes/cleanup.sh"

# ==============================================================================
# Load Modules (for uninstall functions)
# ==============================================================================

source "${SCRIPT_DIR}/modules/core/rke2.sh"
source "${SCRIPT_DIR}/modules/core/helm.sh"
source "${SCRIPT_DIR}/modules/core/k9s.sh"
source "${SCRIPT_DIR}/modules/infrastructure/firewall.sh"
source "${SCRIPT_DIR}/modules/infrastructure/cert-manager.sh"
source "${SCRIPT_DIR}/modules/infrastructure/metallb.sh"
source "${SCRIPT_DIR}/modules/infrastructure/longhorn.sh"
source "${SCRIPT_DIR}/modules/infrastructure/istio.sh"
source "${SCRIPT_DIR}/modules/security/keycloak.sh"
source "${SCRIPT_DIR}/modules/security/oauth2-proxy.sh"
source "${SCRIPT_DIR}/modules/security/gatekeeper.sh"
source "${SCRIPT_DIR}/modules/security/trivy.sh"
source "${SCRIPT_DIR}/modules/applications/minio.sh"
source "${SCRIPT_DIR}/modules/applications/monitoring.sh"
source "${SCRIPT_DIR}/modules/applications/dashboard.sh"
source "${SCRIPT_DIR}/modules/applications/siab-apps.sh"
source "${SCRIPT_DIR}/modules/config/credentials.sh"
source "${SCRIPT_DIR}/modules/config/network.sh"

# ==============================================================================
# Variables
# ==============================================================================

readonly BACKUP_DIR="/tmp/siab-backup-$(date +%Y%m%d-%H%M%S)"
CREATE_BACKUP=false

# Store primary interface for SSH safety
PRIMARY_IFACE=""
SSH_IP=""

# ==============================================================================
# Functions
# ==============================================================================

# Detect and preserve SSH connectivity
# This function MUST be called early to prevent SSH disconnection
ensure_ssh_connectivity() {
    log_info_verbose "Ensuring SSH connectivity is preserved..."

    # Try to get SSH connection info
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        SSH_IP=$(echo "$SSH_CONNECTION" | awk '{print $3}')
        PRIMARY_IFACE=$(ip -o addr show 2>/dev/null | grep "$SSH_IP" | awk '{print $2}' | head -1)
        log_info_verbose "Detected SSH on interface: ${PRIMARY_IFACE:-unknown} (IP: ${SSH_IP})"
    fi

    # Fallback: get interface from default route
    if [[ -z "$PRIMARY_IFACE" ]]; then
        PRIMARY_IFACE=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -1)
        log_info_verbose "Using default route interface: ${PRIMARY_IFACE:-unknown}"
    fi

    # Ensure SSH port is allowed through firewall
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --add-port=22/tcp 2>/dev/null || true
        firewall-cmd --add-service=ssh 2>/dev/null || true
        # Make it permanent too
        firewall-cmd --permanent --add-port=22/tcp 2>/dev/null || true
        firewall-cmd --permanent --add-service=ssh 2>/dev/null || true
    fi

    if command -v ufw &>/dev/null; then
        ufw allow 22/tcp 2>/dev/null || true
    fi

    # Add SSH rule to iptables at the top of INPUT chain
    iptables -C INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || \
        iptables -I INPUT 1 -p tcp --dport 22 -j ACCEPT 2>/dev/null || true

    # Also for established connections
    iptables -C INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
        iptables -I INPUT 2 -m state --state ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || true

    log_info_verbose "SSH connectivity safeguards in place"
}

# Show warning and get confirmation
show_warning() {
    echo ""
    echo -e "${RED}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}${BOLD}║                    WARNING                                     ║${NC}"
    echo -e "${RED}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}This script will COMPLETELY REMOVE the following:${NC}"
    echo ""
    echo "  - RKE2 Kubernetes cluster and ALL workloads"
    echo "  - Istio service mesh"
    echo "  - All deployed applications and data"
    echo "  - Keycloak (Identity and Access Management)"
    echo "  - MinIO (Object Storage) and all stored data"
    echo "  - Longhorn (Block Storage) and all volumes"
    echo "  - Prometheus, Grafana, and monitoring data"
    echo "  - All certificates and secrets"
    echo "  - Firewall rules added by SIAB"
    echo "  - Installed binaries (kubectl, helm, k9s, istioctl)"
    echo "  - Configuration files and logs"
    echo ""
    echo -e "${RED}${BOLD}THIS ACTION CANNOT BE UNDONE!${NC}"
    echo -e "${YELLOW}All data in MinIO, Longhorn volumes, and databases will be LOST.${NC}"
    echo ""

    # Check if running interactively
    if [ -t 0 ]; then
        read -p "Are you sure you want to continue? Type 'yes' to proceed: " confirmation
        if [[ "${confirmation}" != "yes" ]]; then
            log_info_verbose "Uninstall cancelled."
            exit 0
        fi

        echo ""
        read -p "Do you want to create a backup of configurations before removal? (y/N): " backup_choice
        if [[ "${backup_choice}" =~ ^[Yy]$ ]]; then
            CREATE_BACKUP=true
        fi
    else
        # Non-interactive mode - check for environment variable
        if [[ "${SIAB_UNINSTALL_CONFIRM:-no}" != "yes" ]]; then
            log_error_verbose "Non-interactive mode requires SIAB_UNINSTALL_CONFIRM=yes"
            exit 1
        fi
        CREATE_BACKUP=false
    fi
}

# Create backup of configurations
backup_configs() {
    if [[ "${CREATE_BACKUP}" != "true" ]]; then
        return 0
    fi

    log_step_verbose "Creating configuration backup..."

    mkdir -p "${BACKUP_DIR}"

    # Backup kubectl config
    if [[ -f ~/.kube/config ]]; then
        log_info_verbose "Backing up kubeconfig..."
        cp ~/.kube/config "${BACKUP_DIR}/kubeconfig.yaml" 2>/dev/null || true
    fi

    # Backup RKE2 config
    if [[ -f /etc/rancher/rke2/config.yaml ]]; then
        log_info_verbose "Backing up RKE2 config..."
        mkdir -p "${BACKUP_DIR}/rke2"
        cp /etc/rancher/rke2/config.yaml "${BACKUP_DIR}/rke2/config.yaml" 2>/dev/null || true
    fi

    # Backup SIAB configs
    if [[ -d "${SIAB_CONFIG_DIR}" ]]; then
        log_info_verbose "Backing up SIAB configs..."
        cp -r "${SIAB_CONFIG_DIR}" "${BACKUP_DIR}/siab-config" 2>/dev/null || true
    fi

    log_success_verbose "Backup created at: ${BACKUP_DIR}"
    echo ""
}

# Stop all SIAB services with force deletion
stop_services() {
    log_step_verbose "Stopping SIAB services (with force deletion)..."

    # Export kubeconfig if available
    setup_kubeconfig || true

    # Check if kubectl is available
    if ! command -v kubectl &>/dev/null; then
        log_warning_verbose "kubectl not available, skipping Kubernetes cleanup"
        return 0
    fi

    if ! cluster_accessible; then
        log_warning_verbose "Kubernetes cluster not accessible, skipping Kubernetes cleanup"
        return 0
    fi

    log_info_verbose "Kubernetes cluster is running, removing workloads..."

    # Delete Helm releases first
    delete_all_helm_releases

    # Delete webhook configurations
    delete_webhooks

    # Force delete all SIAB namespaces
    force_delete_siab_namespaces

    # Delete cluster-wide RBAC resources
    delete_cluster_rbac "app-deployer" "siab-admin" "kubernetes-dashboard-admin"

    # Force delete CRDs
    force_delete_crds "istio|cert-manager|gatekeeper|longhorn|trivy|prometheus|alertmanager|servicemonitor|podmonitor|aqua"

    log_info_verbose "Waiting for cleanup to propagate..."
    sleep 5

    log_success_verbose "Kubernetes cleanup complete"
}

# Remove binaries
remove_binaries() {
    log_step_verbose "Removing SIAB binaries..."

    rm -f "${SIAB_BIN_DIR}/kubectl" 2>/dev/null || true
    rm -f "${SIAB_BIN_DIR}/helm" 2>/dev/null || true
    rm -f "${SIAB_BIN_DIR}/k9s" 2>/dev/null || true
    rm -f "${SIAB_BIN_DIR}/istioctl" 2>/dev/null || true
    rm -f "${SIAB_BIN_DIR}/siab-*" 2>/dev/null || true

    log_success_verbose "Binaries removed"
}

# Verify uninstall
verify_uninstall() {
    log_step_verbose "Verifying uninstall..."

    local issues=0

    # Check for remaining processes
    if pgrep -f "rke2|containerd|kubelet" >/dev/null 2>&1; then
        log_warning_verbose "Some Kubernetes processes may still be running"
        ((issues++))
    fi

    # Check for remaining mounts
    if mount | grep -q "kubelet\|longhorn"; then
        log_warning_verbose "Some Kubernetes mounts may still exist"
        ((issues++))
    fi

    # Check for remaining directories
    if [[ -d /var/lib/rancher/rke2 ]]; then
        log_warning_verbose "RKE2 data directory still exists"
        ((issues++))
    fi

    if [[ $issues -eq 0 ]]; then
        log_success_verbose "Uninstall verification passed"
    else
        log_warning_verbose "Uninstall verification found $issues potential issues"
    fi
}

# Print summary
print_summary() {
    echo ""
    echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║              SIAB Uninstall Complete                           ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [[ "${CREATE_BACKUP}" == "true" ]]; then
        echo -e "${BOLD}Backup saved to:${NC} ${BACKUP_DIR}"
    fi

    echo ""
    echo "The following have been removed:"
    echo "  - RKE2 Kubernetes cluster"
    echo "  - All deployed applications"
    echo "  - Istio service mesh"
    echo "  - SIAB management tools"
    echo "  - Configuration files"
    echo ""
    echo "You may want to:"
    echo "  - Reboot the system to ensure clean state"
    echo "  - Remove any manually added /etc/hosts entries"
    echo ""
}

# ==============================================================================
# Main
# ==============================================================================

main() {
    # Check root privileges
    check_root

    # Detect operating system
    detect_os

    # Initialize logging
    init_logging "uninstall"

    echo ""
    echo -e "${BOLD}${RED}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${RED}║              SIAB - Uninstall                                        ║${NC}"
    echo -e "${BOLD}${RED}╚══════════════════════════════════════════════════════════════════════╝${NC}"

    # CRITICAL: Ensure SSH connectivity is preserved FIRST
    ensure_ssh_connectivity

    # Show warning and get confirmation
    show_warning

    # Create backup if requested
    backup_configs

    # Stop services and clean up Kubernetes resources
    stop_services

    # Re-ensure SSH after K8s cleanup
    ensure_ssh_connectivity

    # Unmount volumes
    unmount_all_volumes

    # Uninstall RKE2 (SSH-safe version)
    uninstall_rke2

    # Re-ensure SSH after RKE2 removal (critical point)
    ensure_ssh_connectivity

    # Remove binaries
    remove_binaries

    # Restore firewall (SSH-safe version)
    restore_firewall

    # Final SSH check after firewall changes
    ensure_ssh_connectivity

    # Remove SIAB files
    remove_siab_files

    # Clean up hosts file
    cleanup_hosts_file

    # Verify uninstall
    verify_uninstall

    # Print summary
    print_summary
}

main "$@"
