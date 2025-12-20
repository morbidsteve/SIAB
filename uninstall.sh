#!/bin/bash
set -euo pipefail

# SIAB - Secure Infrastructure as a Box
# Comprehensive Uninstall Script
#
# This script completely removes SIAB and all its components,
# returning the system to its pre-installation state.

readonly SCRIPT_VERSION="1.0.0"
readonly SIAB_DIR="/opt/siab"
readonly SIAB_CONFIG_DIR="/etc/siab"
readonly SIAB_LOG_DIR="/var/log/siab"
readonly SIAB_BIN_DIR="/usr/local/bin"
readonly BACKUP_DIR="/tmp/siab-backup-$(date +%Y%m%d-%H%M%S)"
UNINSTALL_LOG_TIMESTAMP="$(date '+%Y%m%d-%H%M%S')"
readonly UNINSTALL_LOG="${SIAB_LOG_DIR}/uninstall-${UNINSTALL_LOG_TIMESTAMP}.log"

# Ensure log directory exists
mkdir -p "$SIAB_LOG_DIR" 2>/dev/null || true

# Also create a symlink to the latest log for convenience
ln -sf "uninstall-${UNINSTALL_LOG_TIMESTAMP}.log" "${SIAB_LOG_DIR}/uninstall-latest.log" 2>/dev/null || true

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Logging functions - log to both console and file
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" >> "$UNINSTALL_LOG" 2>/dev/null || true
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $*" >> "$UNINSTALL_LOG" 2>/dev/null || true
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $*" >> "$UNINSTALL_LOG" 2>/dev/null || true
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >> "$UNINSTALL_LOG" 2>/dev/null || true
}

log_step() {
    echo ""
    echo -e "${CYAN}${BOLD}==>${NC} ${BOLD}$*${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STEP] $*" >> "$UNINSTALL_LOG" 2>/dev/null || true
}

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
        OS_FAMILY="rhel"
        PKG_MANAGER="dnf"
        FIREWALL_CMD="firewalld"
        ;;
    ubuntu|xubuntu|kubuntu|lubuntu|debian)
        OS_FAMILY="debian"
        PKG_MANAGER="apt"
        FIREWALL_CMD="ufw"
        ;;
    *)
        log_error "Unsupported operating system: ${OS_ID}"
        exit 1
        ;;
esac

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        echo "Please run: sudo $0"
        exit 1
    fi
}

# Show warning and get confirmation
show_warning() {
    echo ""
    echo -e "${RED}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${RED}${BOLD}║                    ⚠️  WARNING  ⚠️                             ║${NC}"
    echo -e "${RED}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${YELLOW}This script will COMPLETELY REMOVE the following:${NC}"
    echo ""
    echo "  • RKE2 Kubernetes cluster and ALL workloads"
    echo "  • Istio service mesh"
    echo "  • All deployed applications and data"
    echo "  • Keycloak (Identity and Access Management)"
    echo "  • MinIO (Object Storage) and all stored data"
    echo "  • Longhorn (Block Storage) and all volumes"
    echo "  • Prometheus, Grafana, and monitoring data"
    echo "  • All certificates and secrets"
    echo "  • Firewall rules added by SIAB"
    echo "  • Installed binaries (kubectl, helm, k9s, istioctl)"
    echo "  • Configuration files and logs"
    echo ""
    echo -e "${RED}${BOLD}THIS ACTION CANNOT BE UNDONE!${NC}"
    echo -e "${YELLOW}All data in MinIO, Longhorn volumes, and databases will be LOST.${NC}"
    echo ""

    # Check if running interactively
    if [ -t 0 ]; then
        read -p "Are you sure you want to continue? Type 'yes' to proceed: " confirmation
        if [[ "${confirmation}" != "yes" ]]; then
            log_info "Uninstall cancelled."
            exit 0
        fi

        echo ""
        read -p "Do you want to create a backup of configurations before removal? (y/N): " backup_choice
        if [[ "${backup_choice}" =~ ^[Yy]$ ]]; then
            CREATE_BACKUP=true
        else
            CREATE_BACKUP=false
        fi
    else
        # Non-interactive mode - check for environment variable
        if [[ "${SIAB_UNINSTALL_CONFIRM:-no}" != "yes" ]]; then
            log_error "Non-interactive mode requires SIAB_UNINSTALL_CONFIRM=yes"
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

    log_step "Creating configuration backup..."

    mkdir -p "${BACKUP_DIR}"

    # Backup kubectl config
    if [[ -f ~/.kube/config ]]; then
        log_info "Backing up kubeconfig..."
        cp ~/.kube/config "${BACKUP_DIR}/kubeconfig.yaml"
    fi

    # Backup RKE2 config
    if [[ -f /etc/rancher/rke2/config.yaml ]]; then
        log_info "Backing up RKE2 config..."
        mkdir -p "${BACKUP_DIR}/rke2"
        cp /etc/rancher/rke2/config.yaml "${BACKUP_DIR}/rke2/config.yaml"
    fi

    # Backup SIAB configs
    if [[ -d "${SIAB_CONFIG_DIR}" ]]; then
        log_info "Backing up SIAB configs..."
        cp -r "${SIAB_CONFIG_DIR}" "${BACKUP_DIR}/siab-config"
    fi

    # Export all Kubernetes resources as YAML (if kubectl is available)
    if command -v kubectl &>/dev/null && kubectl cluster-info &>/dev/null; then
        log_info "Exporting Kubernetes resources..."
        mkdir -p "${BACKUP_DIR}/k8s-resources"

        # Export all namespaces
        kubectl get namespaces -o yaml > "${BACKUP_DIR}/k8s-resources/namespaces.yaml" 2>/dev/null || true

        # Export resources from important namespaces
        for ns in istio-system keycloak minio longhorn-system monitoring siab-deployer siab-dashboard siab-system oauth2-proxy kubernetes-dashboard cert-manager metallb-system gatekeeper-system trivy-system; do
            if kubectl get namespace "${ns}" &>/dev/null; then
                log_info "Exporting namespace: ${ns}"
                mkdir -p "${BACKUP_DIR}/k8s-resources/${ns}"
                kubectl get all -n "${ns}" -o yaml > "${BACKUP_DIR}/k8s-resources/${ns}/all.yaml" 2>/dev/null || true
                kubectl get configmaps,secrets -n "${ns}" -o yaml > "${BACKUP_DIR}/k8s-resources/${ns}/configs.yaml" 2>/dev/null || true
            fi
        done
    fi

    # Create backup summary
    cat > "${BACKUP_DIR}/README.txt" <<EOF
SIAB Configuration Backup
Created: $(date)
System: ${OS_NAME} ${OS_VERSION_ID}

This directory contains backups created before SIAB uninstallation.

Contents:
- kubeconfig.yaml: Kubernetes cluster access configuration
- rke2/: RKE2 configuration files
- siab-config/: SIAB-specific configuration files
- k8s-resources/: Exported Kubernetes resources (YAML manifests)

To restore these configurations, you would need to:
1. Reinstall SIAB using install.sh
2. Apply the backed-up Kubernetes resources using kubectl apply
3. Restore any custom configurations

Note: This backup does NOT include persistent data from volumes.
EOF

    log_success "Backup created at: ${BACKUP_DIR}"
    echo ""
}

# Stop all SIAB services gracefully
stop_services() {
    log_step "Stopping SIAB services..."

    # Export kubeconfig if available
    if [[ -f /etc/rancher/rke2/rke2.yaml ]]; then
        export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
        export PATH=$PATH:/var/lib/rancher/rke2/bin
    fi

    # Check if kubectl is available
    if command -v kubectl &>/dev/null && kubectl cluster-info &>/dev/null; then
        log_info "Kubernetes cluster is running, gracefully removing workloads..."

        # Delete Helm releases (if helm is available)
        if command -v helm &>/dev/null; then
            log_info "Removing Helm releases..."

            # Get all Helm releases across all namespaces
            helm list --all-namespaces --short 2>/dev/null | while read -r release; do
                if [[ -n "${release}" ]]; then
                    log_info "Removing Helm release: ${release}"
                    helm uninstall "${release}" --wait --timeout=5m 2>/dev/null || true
                fi
            done
        fi

        # Delete SIAB-specific namespaces
        log_info "Deleting SIAB namespaces..."
        for ns in siab-deployer siab-dashboard siab-system oauth2-proxy kubernetes-dashboard keycloak minio longhorn-system monitoring istio-system cert-manager metallb-system gatekeeper-system trivy-system siab; do
            if kubectl get namespace "${ns}" &>/dev/null; then
                log_info "Deleting namespace: ${ns}"
                kubectl delete namespace "${ns}" --wait=false 2>/dev/null || true
            fi
        done

        # Delete cluster-wide RBAC resources created by SIAB
        log_info "Deleting SIAB cluster-wide RBAC resources..."
        for resource in app-deployer siab-admin kubernetes-dashboard-admin; do
            kubectl delete clusterrolebinding "${resource}" 2>/dev/null || true
            kubectl delete clusterrole "${resource}" 2>/dev/null || true
        done

        # Delete any remaining Istio CRDs
        log_info "Cleaning up Istio CRDs..."
        kubectl get crd -o name 2>/dev/null | grep -E "istio|cert-manager|gatekeeper|longhorn|trivy" | xargs -r kubectl delete 2>/dev/null || true

        # Wait a moment for graceful shutdown
        log_info "Waiting for graceful shutdown (30 seconds)..."
        sleep 30
    else
        log_warning "Kubernetes cluster not accessible, skipping graceful shutdown"
    fi
}

# Unmount all Kubernetes and Longhorn volumes
unmount_volumes() {
    log_step "Unmounting Kubernetes and Longhorn volumes..."

    # Kill any processes using kubelet directories
    log_info "Stopping processes using kubelet mounts..."
    fuser -km /var/lib/kubelet 2>/dev/null || true

    # Kill any containerd/rke2 processes that might hold mounts
    log_info "Stopping containerd shim processes..."
    pkill -9 -f "containerd-shim" 2>/dev/null || true
    sleep 2

    # Unmount all Longhorn CSI volumes
    log_info "Unmounting Longhorn CSI volumes..."
    mount | grep "driver.longhorn.io" | awk '{print $3}' | while read -r mnt; do
        log_info "Unmounting: $mnt"
        umount -f "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null || true
    done

    # Unmount all kubelet volume mounts
    log_info "Unmounting kubelet volumes..."
    mount | grep "/var/lib/kubelet" | awk '{print $3}' | sort -r | while read -r mnt; do
        log_info "Unmounting: $mnt"
        umount -f "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null || true
    done

    # Unmount all pod volumes
    log_info "Unmounting pod volumes..."
    mount | grep "/var/lib/rancher/rke2/agent/kubelet/pods" | awk '{print $3}' | sort -r | while read -r mnt; do
        log_info "Unmounting: $mnt"
        umount -f "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null || true
    done

    # Unmount any tmpfs mounts for secrets/configmaps
    log_info "Unmounting tmpfs secret/configmap volumes..."
    mount | grep -E "tmpfs.*kubelet" | awk '{print $3}' | sort -r | while read -r mnt; do
        umount -f "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null || true
    done

    # Unmount Longhorn block devices
    log_info "Unmounting Longhorn block devices..."
    mount | grep "/dev/longhorn" | awk '{print $3}' | while read -r mnt; do
        log_info "Unmounting: $mnt"
        umount -f "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null || true
    done

    # Detach any remaining Longhorn devices
    log_info "Detaching Longhorn block devices..."
    ls /dev/longhorn/* 2>/dev/null | while read -r dev; do
        log_info "Detaching: $dev"
        dmsetup remove "$dev" 2>/dev/null || true
    done

    # Remove Longhorn device mapper entries
    dmsetup ls 2>/dev/null | grep -i longhorn | awk '{print $1}' | while read -r dm; do
        log_info "Removing device mapper: $dm"
        dmsetup remove "$dm" 2>/dev/null || true
    done

    # Final check - force unmount anything still mounted
    log_info "Final cleanup of any remaining mounts..."
    for pattern in "/var/lib/kubelet" "/var/lib/rancher" "longhorn"; do
        mount | grep "$pattern" | awk '{print $3}' | sort -r | while read -r mnt; do
            log_warning "Force lazy unmount: $mnt"
            umount -l "$mnt" 2>/dev/null || true
        done
    done

    # Wait for unmounts to complete
    sleep 3
    log_success "Volume unmounting complete"
}

# Uninstall RKE2
uninstall_rke2() {
    log_step "Uninstalling RKE2 Kubernetes..."

    # First unmount all volumes
    unmount_volumes

    # Run the RKE2 killall script first if available
    if [[ -f /usr/local/bin/rke2-killall.sh ]]; then
        log_info "Running RKE2 killall script..."
        /usr/local/bin/rke2-killall.sh || log_warning "RKE2 killall script encountered errors (continuing)"
        sleep 5
    elif [[ -f /usr/bin/rke2-killall.sh ]]; then
        log_info "Running RKE2 killall script..."
        /usr/bin/rke2-killall.sh || log_warning "RKE2 killall script encountered errors (continuing)"
        sleep 5
    fi

    # Check if RKE2 uninstall script exists
    if [[ -f /usr/local/bin/rke2-uninstall.sh ]]; then
        log_info "Running RKE2 uninstall script..."
        /usr/local/bin/rke2-uninstall.sh || log_warning "RKE2 uninstall script encountered errors (continuing)"
    elif [[ -f /usr/bin/rke2-uninstall.sh ]]; then
        log_info "Running RKE2 uninstall script..."
        /usr/bin/rke2-uninstall.sh || log_warning "RKE2 uninstall script encountered errors (continuing)"
    else
        log_warning "RKE2 uninstall script not found, performing manual cleanup..."

        # Stop RKE2 services
        log_info "Stopping RKE2 services..."
        systemctl stop rke2-server 2>/dev/null || true
        systemctl stop rke2-agent 2>/dev/null || true
        systemctl disable rke2-server 2>/dev/null || true
        systemctl disable rke2-agent 2>/dev/null || true

        # Kill any remaining RKE2/containerd processes
        log_info "Killing remaining RKE2 processes..."
        pkill -9 -f "rke2" 2>/dev/null || true
        pkill -9 -f "containerd" 2>/dev/null || true
        pkill -9 -f "kubelet" 2>/dev/null || true
        sleep 3

        # Unmount again after killing processes
        unmount_volumes
    fi

    # Remove RKE2 directories (with retry logic)
    log_info "Removing RKE2 directories..."
    for dir in /etc/rancher/rke2 /var/lib/rancher/rke2 /etc/rancher/node /var/lib/kubelet; do
        if [[ -d "$dir" ]]; then
            log_info "Removing: $dir"
            rm -rf "$dir" 2>/dev/null || {
                log_warning "First removal attempt failed for $dir, retrying with force..."
                # Try to unmount anything still mounted in this directory
                mount | grep "$dir" | awk '{print $3}' | sort -r | xargs -r -I{} umount -l {} 2>/dev/null || true
                sleep 1
                rm -rf "$dir" 2>/dev/null || log_warning "Could not remove $dir - may need reboot"
            }
        fi
    done

    # Additional cleanup for CNI and container runtime
    log_info "Cleaning up CNI and container networking..."
    rm -rf /etc/cni
    rm -rf /opt/cni
    rm -rf /var/lib/cni
    rm -rf /var/log/pods
    rm -rf /var/log/containers
    rm -rf /run/k3s
    rm -rf /run/flannel
    rm -rf /run/containerd
    rm -rf /var/lib/containerd

    # Clean up Longhorn data
    log_info "Cleaning up Longhorn data..."
    rm -rf /var/lib/longhorn
    rm -rf /dev/longhorn

    # Clean up iptables rules created by RKE2
    if command -v iptables &>/dev/null; then
        log_info "Flushing iptables rules..."
        iptables -t nat -F 2>/dev/null || true
        iptables -t mangle -F 2>/dev/null || true
        iptables -F 2>/dev/null || true
        iptables -X 2>/dev/null || true
    fi

    log_success "RKE2 uninstalled"
}

# Remove SIAB directories and files
remove_siab_files() {
    log_step "Removing SIAB files and directories..."

    # Remove SIAB directories
    log_info "Removing SIAB directories..."
    rm -rf "${SIAB_DIR}"
    rm -rf "${SIAB_CONFIG_DIR}"
    rm -rf "${SIAB_LOG_DIR}"

    # Remove kubectl config
    log_info "Removing kubectl configuration..."
    rm -rf ~/.kube

    # Remove any remaining rancher directories
    log_info "Removing remaining Rancher directories..."
    rm -rf /etc/rancher
    rm -rf /var/lib/rancher

    log_success "SIAB files removed"
}

# Remove installed binaries
remove_binaries() {
    log_step "Removing installed binaries..."

    # List of binaries to remove
    local binaries=(
        "kubectl"
        "helm"
        "k9s"
        "istioctl"
        "rke2"
        "rke2-killall.sh"
        "rke2-uninstall.sh"
    )

    for binary in "${binaries[@]}"; do
        if [[ -f "${SIAB_BIN_DIR}/${binary}" ]]; then
            log_info "Removing ${binary}..."
            rm -f "${SIAB_BIN_DIR}/${binary}"
        fi
    done

    # Remove from /var/lib/rancher/rke2/bin if exists
    if [[ -d /var/lib/rancher/rke2/bin ]]; then
        rm -rf /var/lib/rancher/rke2/bin
    fi

    log_success "Binaries removed"
}

# Restore firewall to original state
restore_firewall() {
    log_step "Restoring firewall configuration..."

    if [[ "${FIREWALL_CMD}" == "firewalld" ]]; then
        if systemctl is-active firewalld &>/dev/null; then
            log_info "Removing SIAB firewall rules from firewalld..."

            # Remove CNI interfaces from trusted zone
            firewall-cmd --permanent --zone=trusted --remove-interface=cni0 2>/dev/null || true
            firewall-cmd --permanent --zone=trusted --remove-interface=flannel.1 2>/dev/null || true
            firewall-cmd --permanent --zone=trusted --remove-interface=tunl0 2>/dev/null || true

            # Remove pod and service CIDRs from trusted sources
            firewall-cmd --permanent --zone=trusted --remove-source=10.42.0.0/16 2>/dev/null || true
            firewall-cmd --permanent --zone=trusted --remove-source=10.43.0.0/16 2>/dev/null || true

            # Remove ports added by SIAB
            local ports=(
                "6443/tcp"   # Kubernetes API
                "9345/tcp"   # RKE2 supervisor
                "10250/tcp"  # Kubelet
                "2379/tcp"   # etcd client
                "2380/tcp"   # etcd peer
                "8472/udp"   # Flannel VXLAN
                "4789/udp"   # Flannel VXLAN
                "9099/tcp"   # Calico
                "179/tcp"    # Calico BGP
                "5473/tcp"   # Calico Typha
                "443/tcp"    # HTTPS
                "80/tcp"     # HTTP
                "15017/tcp"  # Istio
                "15021/tcp"  # Istio
            )

            for port in "${ports[@]}"; do
                firewall-cmd --permanent --remove-port="${port}" 2>/dev/null || true
            done

            # Reload firewalld
            log_info "Reloading firewalld..."
            firewall-cmd --reload

            log_success "Firewall rules restored"
        else
            log_warning "Firewalld is not active, skipping firewall cleanup"
        fi
    elif [[ "${FIREWALL_CMD}" == "ufw" ]]; then
        if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
            log_info "Removing SIAB firewall rules from ufw..."

            # Remove ports added by SIAB
            ufw delete allow 6443/tcp 2>/dev/null || true
            ufw delete allow 80/tcp 2>/dev/null || true
            ufw delete allow 443/tcp 2>/dev/null || true
            ufw delete allow 2379:2380/tcp 2>/dev/null || true
            ufw delete allow 8472/udp 2>/dev/null || true
            ufw delete allow 4789/udp 2>/dev/null || true

            log_success "Firewall rules restored"
        else
            log_warning "UFW is not active, skipping firewall cleanup"
        fi
    fi
}

# Clean up system modifications
cleanup_system() {
    log_step "Cleaning up system modifications..."

    # Remove network interfaces created by CNI
    log_info "Removing CNI network interfaces..."
    for iface in cni0 flannel.1 tunl0 vxlan.calico; do
        if ip link show "${iface}" &>/dev/null; then
            log_info "Removing interface: ${iface}"
            ip link delete "${iface}" 2>/dev/null || true
        fi
    done

    # Remove kernel modules loaded by Calico/Flannel
    log_info "Removing kernel modules..."
    for mod in ipip ip_tunnel; do
        if lsmod | grep -q "^${mod}"; then
            rmmod "${mod}" 2>/dev/null || true
        fi
    done

    # Remove SELinux module (RHEL family only)
    if [[ "${OS_FAMILY}" == "rhel" ]] && command -v semodule &>/dev/null; then
        log_info "Removing RKE2 SELinux module..."
        semodule -r rke2 2>/dev/null || true
    fi

    log_success "System cleanup completed"
}

# Verify uninstall
verify_uninstall() {
    log_step "Verifying uninstall..."

    local issues=0

    # Check for remaining processes
    if pgrep -f "rke2|k3s|containerd" &>/dev/null; then
        log_warning "Some RKE2/containerd processes are still running"
        issues=$((issues + 1))
    fi

    # Check for remaining directories
    local dirs=("${SIAB_DIR}" "${SIAB_CONFIG_DIR}" "/etc/rancher" "/var/lib/rancher")
    for dir in "${dirs[@]}"; do
        if [[ -d "${dir}" ]]; then
            log_warning "Directory still exists: ${dir}"
            issues=$((issues + 1))
        fi
    done

    # Check for remaining binaries
    local bins=("kubectl" "helm" "k9s" "rke2")
    for bin in "${bins[@]}"; do
        if command -v "${bin}" &>/dev/null; then
            local bin_path=$(which "${bin}")
            if [[ "${bin_path}" == "${SIAB_BIN_DIR}"* ]] || [[ "${bin_path}" == "/var/lib/rancher"* ]]; then
                log_warning "Binary still exists: ${bin_path}"
                issues=$((issues + 1))
            fi
        fi
    done

    if [[ ${issues} -eq 0 ]]; then
        log_success "Uninstall verification passed - system is clean"
        return 0
    else
        log_warning "Uninstall verification found ${issues} issue(s)"
        log_warning "Some components may require manual cleanup or a system reboot"
        return 1
    fi
}

# Print summary
print_summary() {
    echo ""
    echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║              SIAB Uninstall Complete                           ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "The following components have been removed:"
    echo ""
    echo "  ✓ RKE2 Kubernetes cluster"
    echo "  ✓ Istio service mesh"
    echo "  ✓ All applications and workloads"
    echo "  ✓ Storage systems (Longhorn, MinIO)"
    echo "  ✓ Monitoring stack (Prometheus, Grafana)"
    echo "  ✓ Security components (Trivy, Gatekeeper)"
    echo "  ✓ IAM (Keycloak)"
    echo "  ✓ Configuration files"
    echo "  ✓ Installed binaries"
    echo "  ✓ Firewall rules"
    echo ""

    if [[ "${CREATE_BACKUP}" == "true" ]]; then
        echo -e "${CYAN}Configuration backup saved to:${NC}"
        echo "  ${BACKUP_DIR}"
        echo ""
    fi

    echo -e "${YELLOW}Recommended next steps:${NC}"
    echo ""
    echo "  1. Reboot the system to ensure all changes take effect:"
    echo "     ${BOLD}sudo reboot${NC}"
    echo ""
    echo "  2. Verify no lingering processes after reboot:"
    echo "     ${BOLD}ps aux | grep -E 'rke2|containerd|k3s'${NC}"
    echo ""
    echo "  3. Check network interfaces are clean:"
    echo "     ${BOLD}ip link show${NC}"
    echo ""

    if [[ "${CREATE_BACKUP}" == "true" ]]; then
        echo "  4. Review backed-up configurations if needed for reinstall:"
        echo "     ${BOLD}ls -la ${BACKUP_DIR}${NC}"
        echo ""
    fi

    echo -e "${GREEN}Thank you for using SIAB!${NC}"
    echo ""
}

# Main execution
main() {
    echo ""
    echo -e "${BOLD}SIAB Uninstall Script v${SCRIPT_VERSION}${NC}"
    echo ""

    # Pre-flight checks
    check_root
    show_warning

    echo ""
    log_step "Starting SIAB uninstall..."

    # Execute uninstall steps
    backup_configs
    stop_services
    uninstall_rke2
    remove_siab_files
    remove_binaries
    restore_firewall
    cleanup_system
    verify_uninstall

    # Show summary
    print_summary

    log_success "Uninstall completed successfully!"
}

# Run main function
main "$@"
