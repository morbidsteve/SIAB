#!/bin/bash
set -euo pipefail

# SIAB Uninstaller
# WARNING: This will remove all SIAB components and data

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

# Confirmation prompt
echo ""
echo "======================================"
echo -e "${RED}WARNING: DESTRUCTIVE OPERATION${NC}"
echo "======================================"
echo ""
echo "This will completely remove SIAB and all associated data:"
echo "  - All deployed applications"
echo "  - All data in MinIO"
echo "  - All Keycloak users and realms"
echo "  - RKE2 Kubernetes cluster"
echo "  - All persistent data"
echo ""
read -p "Are you sure you want to continue? (type 'yes' to confirm): " -r
echo ""

if [[ ! $REPLY == "yes" ]]; then
    log_info "Uninstallation cancelled"
    exit 0
fi

log_warn "Starting SIAB uninstallation..."

# Stop RKE2
log_info "Stopping RKE2..."
systemctl stop rke2-server.service || true
systemctl disable rke2-server.service || true

# Uninstall RKE2
log_info "Removing RKE2..."
/usr/local/bin/rke2-uninstall.sh 2>/dev/null || true

# Remove directories
log_info "Removing SIAB directories..."
rm -rf /opt/siab
rm -rf /etc/siab
rm -rf /var/log/siab
rm -rf /var/lib/rancher/rke2
rm -rf /etc/rancher/rke2
rm -rf ~/.kube

# Remove binaries
log_info "Removing binaries..."
rm -f /usr/local/bin/kubectl
rm -f /usr/local/bin/helm
rm -f /usr/local/bin/rke2*

# Clean up PATH
sed -i '/rke2/d' /etc/profile.d/rke2.sh 2>/dev/null || true
rm -f /etc/profile.d/rke2.sh

# Remove firewall rules
log_info "Removing firewall rules..."
firewall-cmd --permanent --remove-port=6443/tcp || true
firewall-cmd --permanent --remove-port=9345/tcp || true
firewall-cmd --permanent --remove-port=10250/tcp || true
firewall-cmd --permanent --remove-port=2379/tcp || true
firewall-cmd --permanent --remove-port=2380/tcp || true
firewall-cmd --permanent --remove-port=30000-32767/tcp || true
firewall-cmd --permanent --remove-port=15021/tcp || true
firewall-cmd --permanent --remove-port=443/tcp || true
firewall-cmd --permanent --remove-port=80/tcp || true
firewall-cmd --permanent --remove-port=8472/udp || true
firewall-cmd --permanent --remove-port=4789/udp || true
firewall-cmd --reload || true

# Remove hosts entries
log_info "Removing hosts entries..."
sed -i '/# SIAB Platform/,+6d' /etc/hosts

# Clean up container remnants
log_info "Cleaning up containers..."
if command -v crictl &> /dev/null; then
    crictl rm -f $(crictl ps -aq) 2>/dev/null || true
    crictl rmi -a 2>/dev/null || true
fi

# Remove CNI configuration
log_info "Removing CNI configuration..."
rm -rf /etc/cni
rm -rf /opt/cni
rm -rf /var/lib/cni

# Clean iptables rules
log_info "Cleaning iptables rules..."
iptables -F
iptables -t nat -F
iptables -t mangle -F
iptables -X

# Remove network interfaces
log_info "Removing network interfaces..."
ip link delete cni0 2>/dev/null || true
ip link delete flannel.1 2>/dev/null || true

# Clean up mounts
log_info "Unmounting volumes..."
umount $(mount | grep '/var/lib/kubelet' | awk '{print $3}') 2>/dev/null || true
umount $(mount | grep '/run/k3s' | awk '{print $3}') 2>/dev/null || true

log_info "SIAB uninstallation complete"
echo ""
echo "The following were preserved (if they exist):"
echo "  - System packages (you may want to remove them manually)"
echo "  - SELinux configuration (remains in enforcing mode)"
echo ""
echo "To reinstall SIAB, run:"
echo "  ./install.sh"
echo ""
