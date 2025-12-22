#!/bin/bash
set -uo pipefail
# Note: Not using -e because we want to continue on errors

# SIAB - Secure Infrastructure as a Box
# Comprehensive Uninstall Script with Force Deletion
#
# This script completely removes SIAB and all its components,
# returning the system to its pre-installation state.
# It aggressively handles stuck resources by removing finalizers.

readonly SCRIPT_VERSION="1.1.0"
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
        cp ~/.kube/config "${BACKUP_DIR}/kubeconfig.yaml" 2>/dev/null || true
    fi

    # Backup RKE2 config
    if [[ -f /etc/rancher/rke2/config.yaml ]]; then
        log_info "Backing up RKE2 config..."
        mkdir -p "${BACKUP_DIR}/rke2"
        cp /etc/rancher/rke2/config.yaml "${BACKUP_DIR}/rke2/config.yaml" 2>/dev/null || true
    fi

    # Backup SIAB configs
    if [[ -d "${SIAB_CONFIG_DIR}" ]]; then
        log_info "Backing up SIAB configs..."
        cp -r "${SIAB_CONFIG_DIR}" "${BACKUP_DIR}/siab-config" 2>/dev/null || true
    fi

    log_success "Backup created at: ${BACKUP_DIR}"
    echo ""
}

# Run a command with a timeout
run_with_timeout() {
    local timeout_seconds="$1"
    shift
    timeout "${timeout_seconds}" "$@" 2>/dev/null || true
}

# Force remove finalizers from a resource
remove_finalizers() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="${3:-}"

    if [[ -n "$namespace" ]]; then
        kubectl patch "$resource_type" "$resource_name" -n "$namespace" \
            --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
    else
        kubectl patch "$resource_type" "$resource_name" \
            --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
    fi
}

# Force delete all resources in a namespace
force_delete_namespace_resources() {
    local ns="$1"
    log_info "Force deleting resources in namespace: $ns"

    # Get all resource types in the namespace and remove finalizers
    for resource_type in $(kubectl api-resources --verbs=list --namespaced -o name 2>/dev/null); do
        kubectl get "$resource_type" -n "$ns" -o name 2>/dev/null | while read -r item; do
            kubectl patch "$item" -n "$ns" --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
            kubectl delete "$item" -n "$ns" --force --grace-period=0 2>/dev/null || true
        done
    done
}

# Force delete a namespace by removing all finalizers
force_delete_namespace() {
    local ns="$1"

    if ! kubectl get namespace "$ns" &>/dev/null; then
        return 0
    fi

    log_info "Force deleting namespace: $ns"

    # First try normal delete with short timeout
    run_with_timeout 10 kubectl delete namespace "$ns" --wait=false

    # Check if namespace is stuck in Terminating
    local phase
    phase=$(kubectl get namespace "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

    if [[ "$phase" == "Terminating" ]]; then
        log_info "Namespace $ns stuck in Terminating, forcing deletion..."

        # Remove finalizers from all resources in the namespace
        force_delete_namespace_resources "$ns"

        # Remove namespace finalizers
        kubectl get namespace "$ns" -o json 2>/dev/null | \
            jq '.spec.finalizers = []' | \
            kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || true
    fi
}

# Force delete CRDs by removing finalizers first
force_delete_crds() {
    local pattern="$1"
    log_info "Force deleting CRDs matching: $pattern"

    kubectl get crd -o name 2>/dev/null | grep -E "$pattern" | while read -r crd; do
        local crd_name="${crd#customresourcedefinition.apiextensions.k8s.io/}"
        log_info "Deleting CRD: $crd_name"

        # First, delete all instances of this CRD with finalizers removed
        local api_resource
        api_resource=$(kubectl get crd "$crd_name" -o jsonpath='{.spec.names.plural}' 2>/dev/null || echo "")
        local api_group
        api_group=$(kubectl get crd "$crd_name" -o jsonpath='{.spec.group}' 2>/dev/null || echo "")

        if [[ -n "$api_resource" ]]; then
            # Remove finalizers from all instances
            kubectl get "$api_resource.$api_group" -A -o name 2>/dev/null | while read -r instance; do
                local ns
                ns=$(echo "$instance" | cut -d/ -f1)
                local name
                name=$(echo "$instance" | cut -d/ -f2)
                kubectl patch "$api_resource.$api_group" "$name" ${ns:+-n "$ns"} \
                    --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
            done

            # Delete all instances
            kubectl delete "$api_resource.$api_group" -A --all --force --grace-period=0 2>/dev/null || true
        fi

        # Remove finalizers from the CRD itself
        kubectl patch crd "$crd_name" --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true

        # Delete the CRD with timeout
        run_with_timeout 10 kubectl delete crd "$crd_name" --force --grace-period=0
    done
}

# Delete all Helm releases quickly
delete_helm_releases() {
    if ! command -v helm &>/dev/null; then
        return 0
    fi

    log_info "Removing Helm releases..."

    # Get all releases and delete them with short timeout
    helm list --all-namespaces -q 2>/dev/null | while read -r release; do
        if [[ -n "$release" ]]; then
            local ns
            ns=$(helm list --all-namespaces 2>/dev/null | grep "^$release" | awk '{print $2}')
            log_info "Removing Helm release: $release (namespace: $ns)"
            run_with_timeout 30 helm uninstall "$release" -n "$ns" --no-hooks 2>/dev/null || true
        fi
    done
}

# Stop all SIAB services with force deletion
stop_services() {
    log_step "Stopping SIAB services (with force deletion)..."

    # Export kubeconfig if available
    if [[ -f /etc/rancher/rke2/rke2.yaml ]]; then
        export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
        export PATH=$PATH:/var/lib/rancher/rke2/bin
    fi

    # Check if kubectl is available
    if ! command -v kubectl &>/dev/null; then
        log_warning "kubectl not available, skipping Kubernetes cleanup"
        return 0
    fi

    if ! kubectl cluster-info &>/dev/null 2>&1; then
        log_warning "Kubernetes cluster not accessible, skipping Kubernetes cleanup"
        return 0
    fi

    log_info "Kubernetes cluster is running, removing workloads..."

    # Delete Helm releases first (quick, with --no-hooks to avoid hangs)
    delete_helm_releases

    # Delete webhook configurations that might block deletions
    log_info "Removing webhook configurations..."
    kubectl delete validatingwebhookconfiguration --all 2>/dev/null || true
    kubectl delete mutatingwebhookconfiguration --all 2>/dev/null || true

    # Force delete all SIAB namespaces
    log_info "Force deleting SIAB namespaces..."
    local namespaces=(
        "siab-deployer"
        "siab-dashboard"
        "siab-system"
        "oauth2-proxy"
        "kubernetes-dashboard"
        "keycloak"
        "minio"
        "longhorn-system"
        "monitoring"
        "istio-system"
        "cert-manager"
        "metallb-system"
        "gatekeeper-system"
        "trivy-system"
    )

    for ns in "${namespaces[@]}"; do
        force_delete_namespace "$ns"
    done

    # Delete cluster-wide RBAC resources
    log_info "Deleting cluster-wide RBAC resources..."
    for resource in app-deployer siab-admin kubernetes-dashboard-admin; do
        kubectl delete clusterrolebinding "$resource" 2>/dev/null || true
        kubectl delete clusterrole "$resource" 2>/dev/null || true
    done

    # Force delete CRDs (these often get stuck)
    log_info "Force deleting CRDs..."
    force_delete_crds "istio|cert-manager|gatekeeper|longhorn|trivy|prometheus|alertmanager|servicemonitor|podmonitor|aqua"

    # Wait a short moment
    log_info "Waiting for cleanup to propagate..."
    sleep 5

    # Final check for any stuck namespaces
    log_info "Final cleanup of any remaining stuck namespaces..."
    for ns in "${namespaces[@]}"; do
        if kubectl get namespace "$ns" &>/dev/null 2>&1; then
            log_warning "Namespace $ns still exists, forcing final deletion..."
            kubectl get namespace "$ns" -o json 2>/dev/null | \
                jq '.spec.finalizers = []' | \
                kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || true
        fi
    done

    log_success "Kubernetes cleanup complete"
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
        umount -f "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null || true
    done

    # Unmount all kubelet volume mounts
    log_info "Unmounting kubelet volumes..."
    mount | grep "/var/lib/kubelet" | awk '{print $3}' | sort -r | while read -r mnt; do
        umount -f "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null || true
    done

    # Unmount all pod volumes
    log_info "Unmounting pod volumes..."
    mount | grep "/var/lib/rancher/rke2/agent/kubelet/pods" | awk '{print $3}' | sort -r | while read -r mnt; do
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
        umount -f "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null || true
    done

    # Detach any remaining Longhorn devices
    log_info "Detaching Longhorn block devices..."
    ls /dev/longhorn/* 2>/dev/null | while read -r dev; do
        dmsetup remove "$dev" 2>/dev/null || true
    done

    # Remove Longhorn device mapper entries
    dmsetup ls 2>/dev/null | grep -i longhorn | awk '{print $1}' | while read -r dm; do
        dmsetup remove "$dm" 2>/dev/null || true
    done

    # Final check - force unmount anything still mounted
    log_info "Final cleanup of any remaining mounts..."
    for pattern in "/var/lib/kubelet" "/var/lib/rancher" "longhorn"; do
        mount | grep "$pattern" | awk '{print $3}' | sort -r | while read -r mnt; do
            umount -l "$mnt" 2>/dev/null || true
        done
    done

    sleep 2
    log_success "Volume unmounting complete"
}

# Uninstall RKE2
uninstall_rke2() {
    log_step "Uninstalling RKE2 Kubernetes..."

    # First unmount all volumes
    unmount_volumes

    # Always stop and disable RKE2 services first (even before killall)
    log_info "Stopping and disabling RKE2 services..."
    systemctl stop rke2-server 2>/dev/null || true
    systemctl stop rke2-agent 2>/dev/null || true
    systemctl disable rke2-server 2>/dev/null || true
    systemctl disable rke2-agent 2>/dev/null || true

    # Run the RKE2 killall script if available
    if [[ -f /usr/local/bin/rke2-killall.sh ]]; then
        log_info "Running RKE2 killall script..."
        /usr/local/bin/rke2-killall.sh 2>/dev/null || true
        sleep 3
    elif [[ -f /usr/bin/rke2-killall.sh ]]; then
        log_info "Running RKE2 killall script..."
        /usr/bin/rke2-killall.sh 2>/dev/null || true
        sleep 3
    fi

    # Kill any remaining RKE2/containerd processes that killall might have missed
    log_info "Ensuring all RKE2 processes are stopped..."
    pkill -9 -f "rke2" 2>/dev/null || true
    pkill -9 -f "containerd" 2>/dev/null || true
    pkill -9 -f "kubelet" 2>/dev/null || true
    sleep 2

    # Unmount again after killing processes
    unmount_volumes

    # Run the RKE2 uninstall script if available
    if [[ -f /usr/local/bin/rke2-uninstall.sh ]]; then
        log_info "Running RKE2 uninstall script..."
        /usr/local/bin/rke2-uninstall.sh 2>/dev/null || true
    elif [[ -f /usr/bin/rke2-uninstall.sh ]]; then
        log_info "Running RKE2 uninstall script..."
        /usr/bin/rke2-uninstall.sh 2>/dev/null || true
    else
        log_warning "RKE2 uninstall script not found, performing manual cleanup..."
    fi

    # Remove RKE2 systemd service files (in case uninstall script missed them)
    log_info "Removing RKE2 systemd service files..."
    rm -f /usr/local/lib/systemd/system/rke2-server.service 2>/dev/null || true
    rm -f /usr/local/lib/systemd/system/rke2-server.env 2>/dev/null || true
    rm -f /usr/local/lib/systemd/system/rke2-agent.service 2>/dev/null || true
    rm -f /usr/local/lib/systemd/system/rke2-agent.env 2>/dev/null || true
    rm -rf /usr/local/lib/systemd/system/rke2* 2>/dev/null || true
    rm -f /etc/systemd/system/rke2-server.service 2>/dev/null || true
    rm -f /etc/systemd/system/rke2-agent.service 2>/dev/null || true
    systemctl daemon-reload 2>/dev/null || true

    # Remove RKE2 binaries
    log_info "Removing RKE2 binaries..."
    rm -f /usr/local/bin/rke2 2>/dev/null || true
    rm -f /usr/local/bin/rke2-killall.sh 2>/dev/null || true
    rm -f /usr/local/bin/rke2-uninstall.sh 2>/dev/null || true

    # Remove RKE2 YUM/DNF repo files
    log_info "Removing RKE2 repository files..."
    rm -f /etc/yum.repos.d/rancher-rke2*.repo 2>/dev/null || true

    # Remove RKE2 directories (with retry logic)
    log_info "Removing RKE2 directories..."
    for dir in /etc/rancher/rke2 /var/lib/rancher/rke2 /etc/rancher/node /var/lib/kubelet /etc/rancher; do
        if [[ -d "$dir" ]]; then
            log_info "Removing: $dir"
            rm -rf "$dir" 2>/dev/null || {
                mount | grep "$dir" | awk '{print $3}' | sort -r | xargs -r -I{} umount -l {} 2>/dev/null || true
                sleep 1
                rm -rf "$dir" 2>/dev/null || log_warning "Could not remove $dir - may need reboot"
            }
        fi
    done

    # Additional cleanup for CNI and container runtime
    log_info "Cleaning up CNI and container networking..."
    rm -rf /etc/cni 2>/dev/null || true
    rm -rf /opt/cni 2>/dev/null || true
    rm -rf /var/lib/cni 2>/dev/null || true
    rm -rf /var/log/pods 2>/dev/null || true
    rm -rf /var/log/containers 2>/dev/null || true
    rm -rf /run/k3s 2>/dev/null || true
    rm -rf /run/flannel 2>/dev/null || true
    rm -rf /run/containerd 2>/dev/null || true
    rm -rf /var/lib/containerd 2>/dev/null || true

    # Clean up Longhorn data
    log_info "Cleaning up Longhorn data..."
    rm -rf /var/lib/longhorn 2>/dev/null || true
    rm -rf /dev/longhorn 2>/dev/null || true

    # Clean up iptables rules created by RKE2/Kubernetes
    # Note: We use selective removal instead of full flush to preserve SSH connections
    if command -v iptables &>/dev/null; then
        log_info "Cleaning up Kubernetes iptables rules (preserving SSH)..."
        # Remove only KUBE-*, CNI-*, and cali-* chains - preserves system rules including SSH
        iptables-save 2>/dev/null | grep -v KUBE- | grep -v CNI- | grep -v cali- | grep -v flannel | iptables-restore 2>/dev/null || true
        iptables-save -t nat 2>/dev/null | grep -v KUBE- | grep -v CNI- | grep -v cali- | grep -v flannel | iptables-restore -T nat 2>/dev/null || true
        ip6tables-save 2>/dev/null | grep -v KUBE- | grep -v CNI- | grep -v cali- | grep -v flannel | ip6tables-restore 2>/dev/null || true
    fi

    log_success "RKE2 uninstalled"
}

# Remove SIAB directories and files
remove_siab_files() {
    log_step "Removing SIAB files and directories..."

    # Remove SIAB directories
    log_info "Removing SIAB directories..."
    rm -rf "${SIAB_DIR}" 2>/dev/null || true
    rm -rf "${SIAB_CONFIG_DIR}" 2>/dev/null || true
    # Note: Not removing log directory until the end

    # Remove kubectl config
    log_info "Removing kubectl configuration..."
    rm -rf ~/.kube 2>/dev/null || true

    # Remove any remaining rancher directories
    log_info "Removing remaining Rancher directories..."
    rm -rf /etc/rancher 2>/dev/null || true
    rm -rf /var/lib/rancher 2>/dev/null || true

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
        "siab-status"
        "siab-info"
        "siab-fix-rke2"
        "siab-uninstall"
        "siab-diagnose"
    )

    for binary in "${binaries[@]}"; do
        if [[ -f "${SIAB_BIN_DIR}/${binary}" ]]; then
            log_info "Removing ${binary}..."
            rm -f "${SIAB_BIN_DIR}/${binary}" 2>/dev/null || true
        fi
    done

    # Remove from /var/lib/rancher/rke2/bin if exists
    rm -rf /var/lib/rancher/rke2/bin 2>/dev/null || true

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
                "6443/tcp" "9345/tcp" "10250/tcp" "2379/tcp" "2380/tcp"
                "8472/udp" "4789/udp" "9099/tcp" "179/tcp" "5473/tcp"
                "443/tcp" "80/tcp" "15017/tcp" "15021/tcp"
            )

            for port in "${ports[@]}"; do
                firewall-cmd --permanent --remove-port="${port}" 2>/dev/null || true
            done

            firewall-cmd --reload 2>/dev/null || true
            log_success "Firewall rules restored"
        else
            log_warning "Firewalld is not active, skipping firewall cleanup"
        fi
    elif [[ "${FIREWALL_CMD}" == "ufw" ]]; then
        if command -v ufw &>/dev/null && ufw status | grep -q "Status: active"; then
            log_info "Removing SIAB firewall rules from ufw..."
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

    # Remove /etc/hosts entries added by SIAB
    log_info "Cleaning up /etc/hosts entries..."
    if [[ -f /etc/hosts ]]; then
        sed -i '/# SIAB/d' /etc/hosts 2>/dev/null || true
        sed -i '/siab\.local/d' /etc/hosts 2>/dev/null || true
    fi

    # Remove profile.d scripts
    rm -f /etc/profile.d/siab.sh 2>/dev/null || true
    rm -f /etc/profile.d/rke2.sh 2>/dev/null || true

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

    if [[ ${issues} -eq 0 ]]; then
        log_success "Uninstall verification passed - system is clean"
        return 0
    else
        log_warning "Uninstall verification found ${issues} issue(s)"
        log_warning "Some components may require a system reboot to fully remove"
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
    echo "  - RKE2 Kubernetes cluster"
    echo "  - Istio service mesh"
    echo "  - All applications and workloads"
    echo "  - Storage systems (Longhorn, MinIO)"
    echo "  - Monitoring stack (Prometheus, Grafana)"
    echo "  - Security components (Trivy, Gatekeeper)"
    echo "  - IAM (Keycloak)"
    echo "  - Configuration files"
    echo "  - Installed binaries"
    echo "  - Firewall rules"
    echo ""

    if [[ "${CREATE_BACKUP}" == "true" ]]; then
        echo -e "${CYAN}Configuration backup saved to:${NC}"
        echo "  ${BACKUP_DIR}"
        echo ""
    fi

    echo -e "${YELLOW}Recommended next steps:${NC}"
    echo ""
    echo "  1. Verify no lingering processes:"
    echo "     ${BOLD}ps aux | grep -E 'rke2|containerd|k3s'${NC}"
    echo ""
    echo "  2. If any issues persist, a reboot may help clean up remaining state"
    echo ""

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
