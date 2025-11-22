#!/bin/bash
set -euo pipefail

# SIAB RKE2 Fix Script v2
# Fixes common RKE2 startup issues with better diagnostics

readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Check root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

echo "=============================================="
echo "       SIAB RKE2 Fix Script v2"
echo "=============================================="
echo ""

# Step 1: Full cleanup
log_step "Step 1/8: Stopping all RKE2 services..."
systemctl stop rke2-server 2>/dev/null || true
systemctl stop rke2-agent 2>/dev/null || true
sleep 3

log_step "Step 2/8: Killing remaining processes..."
pkill -9 -f "rke2" 2>/dev/null || true
pkill -9 -f "containerd-shim" 2>/dev/null || true
sleep 2

# Step 3: Full RKE2 uninstall and cleanup
log_step "Step 3/8: Cleaning up RKE2 installation..."
if [[ -f /usr/local/bin/rke2-uninstall.sh ]]; then
    /usr/local/bin/rke2-uninstall.sh 2>/dev/null || true
fi

# Remove all RKE2 data
rm -rf /var/lib/rancher/rke2
rm -rf /etc/rancher/rke2
rm -rf /var/lib/kubelet
rm -rf /var/lib/cni
rm -rf /var/log/pods
rm -rf /var/log/containers
rm -f /etc/yum.repos.d/rancher-rke2*.repo 2>/dev/null || true

# Step 4: Prerequisites
log_step "Step 4/8: Setting up prerequisites..."

# Create etcd user/group
if ! getent group etcd >/dev/null 2>&1; then
    groupadd --system etcd
fi
if ! getent passwd etcd >/dev/null 2>&1; then
    useradd --system --gid etcd --shell /sbin/nologin --comment "etcd user" etcd
fi

# Kernel parameters
cat > /etc/sysctl.d/90-rke2.conf <<EOF
kernel.panic = 10
kernel.panic_on_oops = 1
vm.overcommit_memory = 1
vm.panic_on_oom = 0
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

modprobe br_netfilter 2>/dev/null || true
modprobe overlay 2>/dev/null || true
sysctl --system > /dev/null 2>&1

log_info "Prerequisites configured"

# Step 5: Create directories
log_step "Step 5/8: Creating directories..."
mkdir -p /etc/rancher/rke2
mkdir -p /var/lib/rancher/rke2/server/manifests

# Step 6: Create SIMPLE config (no CIS for now - we'll add it later)
log_step "Step 6/8: Creating RKE2 configuration..."
cat > /etc/rancher/rke2/config.yaml <<EOF
# RKE2 Configuration - Basic Setup
write-kubeconfig-mode: "0644"
tls-san:
  - $(hostname)
  - $(hostname -I | awk '{print $1}')
# Note: CIS profile disabled for initial setup
# Can be enabled later with: profile: "cis-1.23"
EOF

log_info "Config created at /etc/rancher/rke2/config.yaml"

# Step 7: Install RKE2
log_step "Step 7/8: Installing RKE2..."
curl -sfL https://get.rke2.io | INSTALL_RKE2_METHOD="tar" sh -

# Step 8: Start with monitoring
log_step "Step 8/8: Starting RKE2 service..."
systemctl daemon-reload
systemctl enable rke2-server

# Start in background and monitor
systemctl start rke2-server &

echo ""
echo "=============================================="
echo "  Monitoring RKE2 Startup (Ctrl+C to exit)"
echo "=============================================="
echo ""
echo "RKE2 is starting. First startup takes 5-10 minutes."
echo "Watching for status changes..."
echo ""

# Monitor function
monitor_rke2() {
    local dots=0
    local max_wait=600  # 10 minutes
    local elapsed=0
    local last_status=""

    while [[ $elapsed -lt $max_wait ]]; do
        # Check service status
        local status=$(systemctl is-active rke2-server 2>/dev/null || echo "unknown")

        if [[ "$status" == "failed" ]]; then
            echo ""
            log_error "RKE2 service failed!"
            echo ""
            echo "Last few log lines:"
            journalctl -u rke2-server --no-pager -n 20
            echo ""
            log_error "Check full logs with: journalctl -xeu rke2-server"
            return 1
        fi

        # Try kubectl
        if [[ -f /var/lib/rancher/rke2/bin/kubectl ]] && \
           [[ -f /etc/rancher/rke2/rke2.yaml ]]; then
            if /var/lib/rancher/rke2/bin/kubectl \
               --kubeconfig /etc/rancher/rke2/rke2.yaml \
               get nodes &>/dev/null 2>&1; then
                echo ""
                echo ""
                log_info "=========================================="
                log_info "  RKE2 IS READY!"
                log_info "=========================================="
                echo ""

                # Show nodes
                /var/lib/rancher/rke2/bin/kubectl \
                    --kubeconfig /etc/rancher/rke2/rke2.yaml \
                    get nodes

                # Setup kubectl
                mkdir -p /root/.kube
                cp /etc/rancher/rke2/rke2.yaml /root/.kube/config
                chmod 600 /root/.kube/config

                # Add to path
                echo 'export PATH=$PATH:/var/lib/rancher/rke2/bin' >> /root/.bashrc
                echo 'export KUBECONFIG=/etc/rancher/rke2/rke2.yaml' >> /root/.bashrc

                echo ""
                log_info "kubectl configured for root user"
                log_info "Run: source ~/.bashrc"
                log_info "Then: kubectl get nodes"
                echo ""
                log_info "To continue SIAB installation, run: ./install.sh"
                return 0
            fi
        fi

        # Show progress
        printf "."
        dots=$((dots + 1))
        if [[ $((dots % 60)) -eq 0 ]]; then
            echo " (${elapsed}s)"
        fi

        sleep 5
        elapsed=$((elapsed + 5))
    done

    echo ""
    log_warn "Timeout after ${max_wait}s. RKE2 may still be starting."
    log_warn "Check: systemctl status rke2-server"
    log_warn "Logs: journalctl -fu rke2-server"
    return 1
}

monitor_rke2
