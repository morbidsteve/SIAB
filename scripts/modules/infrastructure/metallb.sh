#!/bin/bash
# SIAB - MetalLB Module
# LoadBalancer implementation installation

# Requires: logging.sh, config.sh, progress/status.sh, checks/preflight.sh

# Install MetalLB for LoadBalancer services
install_metallb() {
    start_step "MetalLB Load Balancer"

    # Check if MetalLB is already properly installed
    if check_metallb_installed; then
        skip_step "MetalLB Load Balancer" "Already installed and configured"
        return 0
    fi

    log_info "Installing MetalLB..."

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
    # Admin plane: .240-.241, User plane: .242-.243
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
    mkdir -p "${SIAB_CONFIG_DIR}"
    echo "ADMIN_GATEWAY_IP=${ip_base}.240" >> "${SIAB_CONFIG_DIR}/network.env"
    echo "USER_GATEWAY_IP=${ip_base}.242" >> "${SIAB_CONFIG_DIR}/network.env"

    complete_step "MetalLB Load Balancer"
    log_info "MetalLB installed with admin pool (${ip_base}.240-241) and user pool (${ip_base}.242-243)"
}

# Uninstall MetalLB
uninstall_metallb() {
    log_info "Uninstalling MetalLB..."

    helm uninstall metallb -n metallb-system 2>/dev/null || true
    kubectl delete namespace metallb-system --wait=false 2>/dev/null || true

    log_info "MetalLB uninstalled"
}
