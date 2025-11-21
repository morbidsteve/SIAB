#!/bin/bash
set -euo pipefail

# SIAB RKE2 Fix Script
# Fixes common RKE2 startup issues

readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

log_info "Starting RKE2 fix process..."

# Step 1: Stop RKE2
log_info "Stopping RKE2 service..."
systemctl stop rke2-server 2>/dev/null || true
sleep 5

# Kill any remaining processes
log_info "Cleaning up any remaining processes..."
pkill -9 -f "rke2" 2>/dev/null || true
pkill -9 -f "containerd" 2>/dev/null || true
pkill -9 -f "kubelet" 2>/dev/null || true
sleep 2

# Step 2: Ensure etcd user/group exists
log_info "Ensuring etcd user and group exist..."
if ! getent group etcd >/dev/null 2>&1; then
    groupadd --system etcd
    log_info "Created etcd group"
fi
if ! getent passwd etcd >/dev/null 2>&1; then
    useradd --system --gid etcd --shell /sbin/nologin --comment "etcd user" etcd
    log_info "Created etcd user"
fi

# Step 3: Set kernel parameters
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
EOF

# Load bridge module first
modprobe br_netfilter 2>/dev/null || true
sysctl --system > /dev/null 2>&1

# Step 4: Clean up old RKE2 data
log_info "Cleaning up old RKE2 data..."
rm -rf /var/lib/rancher/rke2/server/db/
rm -rf /var/lib/rancher/rke2/agent/containerd/
rm -rf /var/lib/rancher/rke2/agent/pod-manifests/
rm -f /var/lib/rancher/rke2/server/token
rm -f /var/lib/rancher/rke2/server/node-token

# Step 5: Fix directory permissions
log_info "Setting up directories with correct permissions..."
mkdir -p /var/lib/rancher/rke2/server/db/etcd
mkdir -p /var/lib/rancher/rke2/agent
mkdir -p /etc/rancher/rke2

chown -R root:root /var/lib/rancher/rke2
chmod 700 /var/lib/rancher/rke2/server/db
chmod 700 /var/lib/rancher/rke2/server/db/etcd

# Step 6: Handle SELinux
if command -v getenforce &>/dev/null; then
    SELINUX_STATUS=$(getenforce)
    if [[ "$SELINUX_STATUS" == "Enforcing" ]]; then
        log_info "SELinux is enforcing, setting contexts..."
        # Set SELinux contexts
        restorecon -Rv /var/lib/rancher 2>/dev/null || true
        restorecon -Rv /etc/rancher 2>/dev/null || true

        # Set SELinux boolean for containers
        setsebool -P container_manage_cgroup on 2>/dev/null || true
    fi
fi

# Step 7: Check/create RKE2 config
log_info "Checking RKE2 configuration..."
if [[ ! -f /etc/rancher/rke2/config.yaml ]]; then
    log_warn "RKE2 config not found, creating minimal config..."
    cat > /etc/rancher/rke2/config.yaml <<EOF
write-kubeconfig-mode: "0600"
profile: "cis-1.23"
selinux: true
secrets-encryption: true
EOF
fi

# Step 8: Start RKE2
log_info "Starting RKE2 service..."
systemctl daemon-reload
systemctl start rke2-server

# Step 9: Wait and monitor
log_info "Waiting for RKE2 to initialize (this may take 5-10 minutes)..."
echo ""
echo "Monitoring startup - Press Ctrl+C to stop monitoring (RKE2 will continue in background)"
echo "=========================================================================="

# Monitor for up to 10 minutes
TIMEOUT=600
ELAPSED=0
INTERVAL=10

while [[ $ELAPSED -lt $TIMEOUT ]]; do
    # Check if service failed
    if ! systemctl is-active --quiet rke2-server; then
        STATUS=$(systemctl is-active rke2-server)
        if [[ "$STATUS" == "failed" ]]; then
            log_error "RKE2 service failed!"
            log_error "Check logs with: journalctl -xeu rke2-server"
            exit 1
        fi
    fi

    # Try to check if kubectl works
    if /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes &>/dev/null; then
        echo ""
        log_info "RKE2 is ready!"
        /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes

        # Set up kubectl for easy access
        mkdir -p ~/.kube
        cp /etc/rancher/rke2/rke2.yaml ~/.kube/config
        chmod 600 ~/.kube/config

        echo ""
        log_info "kubectl configured. You can now use: kubectl get nodes"
        exit 0
    fi

    # Show progress
    echo -n "."
    sleep $INTERVAL
    ELAPSED=$((ELAPSED + INTERVAL))
done

log_warn "Timeout reached. RKE2 may still be starting."
log_warn "Check status with: systemctl status rke2-server"
log_warn "Check logs with: journalctl -fu rke2-server"
