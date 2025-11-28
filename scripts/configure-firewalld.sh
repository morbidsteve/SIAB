#!/bin/bash
#
# Configure firewalld for RKE2 with Canal (Calico+Flannel) and Istio
#
# This script properly configures firewalld to work with:
# - RKE2 Kubernetes distribution
# - Canal CNI (Calico + Flannel)
# - Istio service mesh
# - MetalLB load balancer
#
# Based on RKE2 documentation and known issues:
# https://docs.rke2.io/known_issues

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Firewalld Configuration for RKE2 + Istio                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    log_error "This script must be run as root (use sudo)"
    exit 1
fi

# Detect the network interface for CNI
CNI_INTERFACE="cni0"
FLANNEL_INTERFACE="flannel.1"
CALICO_INTERFACE="tunl0"

log_info "Configuring firewalld for RKE2..."

# Enable and start firewalld
systemctl enable firewalld
systemctl start firewalld

# Add CNI interfaces to trusted zone
# This is critical - CNI interfaces must be trusted for pod-to-pod communication
log_info "Adding CNI interfaces to trusted zone..."
firewall-cmd --permanent --zone=trusted --add-interface=${CNI_INTERFACE} 2>/dev/null || log_warning "${CNI_INTERFACE} not found (may not exist yet)"
firewall-cmd --permanent --zone=trusted --add-interface=${FLANNEL_INTERFACE} 2>/dev/null || log_warning "${FLANNEL_INTERFACE} not found (may not exist yet)"
firewall-cmd --permanent --zone=trusted --add-interface=${CALICO_INTERFACE} 2>/dev/null || log_warning "${CALICO_INTERFACE} not found (may not exist yet)"

# Add Calico/Canal pod CIDR to trusted sources
log_info "Adding pod CIDR to trusted sources..."
POD_CIDR="10.42.0.0/16"
firewall-cmd --permanent --zone=trusted --add-source=${POD_CIDR}

# Add service CIDR to trusted sources
log_info "Adding service CIDR to trusted sources..."
SERVICE_CIDR="10.43.0.0/16"
firewall-cmd --permanent --zone=trusted --add-source=${SERVICE_CIDR}

# RKE2 Required Ports
log_info "Opening RKE2 ports..."

# Kubernetes API Server
firewall-cmd --permanent --add-port=6443/tcp
log_success "Opened 6443/tcp (Kubernetes API)"

# RKE2 Supervisor API
firewall-cmd --permanent --add-port=9345/tcp
log_success "Opened 9345/tcp (RKE2 Supervisor)"

# Kubelet
firewall-cmd --permanent --add-port=10250/tcp
log_success "Opened 10250/tcp (Kubelet)"

# etcd
firewall-cmd --permanent --add-port=2379-2380/tcp
log_success "Opened 2379-2380/tcp (etcd)"

# NodePort Services
firewall-cmd --permanent --add-port=30000-32767/tcp
log_success "Opened 30000-32767/tcp (NodePort range)"

# Canal/Flannel VXLAN
firewall-cmd --permanent --add-port=8472/udp
firewall-cmd --permanent --add-port=4789/udp
log_success "Opened 8472/udp, 4789/udp (Flannel VXLAN)"

# Flannel Wireguard (if used)
firewall-cmd --permanent --add-port=51820-51821/udp
log_success "Opened 51820-51821/udp (Flannel Wireguard)"

# Calico BGP
firewall-cmd --permanent --add-port=179/tcp
log_success "Opened 179/tcp (Calico BGP)"

# Calico Typha (if used)
firewall-cmd --permanent --add-port=5473/tcp
log_success "Opened 5473/tcp (Calico Typha)"

# Istio Required Ports
log_info "Opening Istio ports..."

# Istio ingress gateways
firewall-cmd --permanent --add-port=80/tcp
firewall-cmd --permanent --add-port=443/tcp
log_success "Opened 80/tcp, 443/tcp (Istio Ingress)"

# Istio control plane
firewall-cmd --permanent --add-port=15010/tcp
firewall-cmd --permanent --add-port=15012/tcp
firewall-cmd --permanent --add-port=15014/tcp
firewall-cmd --permanent --add-port=15017/tcp
log_success "Opened 15010-15017/tcp (Istio Control Plane)"

# Istio health and metrics
firewall-cmd --permanent --add-port=15021/tcp
firewall-cmd --permanent --add-port=15090/tcp
log_success "Opened 15021/tcp, 15090/tcp (Istio Health/Metrics)"

# Allow masquerading for pod network
log_info "Enabling masquerading..."
firewall-cmd --permanent --zone=public --add-masquerade
firewall-cmd --permanent --zone=trusted --add-masquerade

# Reload firewalld to apply changes
log_info "Reloading firewalld..."
firewall-cmd --reload

# Display configuration
echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Firewalld Configuration Summary                               ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

log_info "Trusted interfaces:"
firewall-cmd --zone=trusted --list-interfaces || echo "  None configured"

echo ""
log_info "Trusted sources:"
firewall-cmd --zone=trusted --list-sources || echo "  None configured"

echo ""
log_info "Open ports (public zone):"
firewall-cmd --zone=public --list-ports

echo ""
log_success "Firewalld configuration complete!"
log_warning "Note: CNI interfaces (cni0, flannel.1, tunl0) will be added to trusted zone automatically when they are created."
echo ""
