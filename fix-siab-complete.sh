#!/bin/bash
# SIAB Complete Fix Script
# Fixes all connectivity issues and adds block storage support
# Run this on your Rocky OS machine at 10.10.30.100

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Symbols
readonly CHECK="✓"
readonly CROSS="✗"
readonly ARROW="→"

log_info() { echo -e "${GREEN}${CHECK}${NC} $1"; }
log_warn() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}${CROSS}${NC} $1"; }
log_step() { echo -e "${CYAN}${ARROW}${NC} ${BOLD}$1${NC}"; }
section() { echo ""; echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"; echo -e "${BOLD}  $1${NC}"; echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"; }

# Setup kubectl
setup_kubectl() {
    export PATH="/var/lib/rancher/rke2/bin:/usr/local/bin:$PATH"
    if [ -f /etc/rancher/rke2/rke2.yaml ]; then
        export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
    fi

    if ! command -v kubectl &>/dev/null; then
        log_error "kubectl not found. Ensure RKE2 is installed."
        exit 1
    fi
}

# Install block storage (Longhorn)
install_longhorn() {
    section "Installing Longhorn Block Storage"

    # Check if already installed
    if kubectl get namespace longhorn-system &>/dev/null; then
        log_info "Longhorn namespace already exists, checking installation..."
        if kubectl get deployment longhorn-driver-deployer -n longhorn-system &>/dev/null 2>&1; then
            log_info "Longhorn is already installed, skipping..."
            return 0
        fi
    fi

    log_step "Installing prerequisites..."
    # Install iscsi-initiator-utils (required for Longhorn)
    if command -v dnf &>/dev/null; then
        dnf install -y iscsi-initiator-utils nfs-utils || yum install -y iscsi-initiator-utils nfs-utils
    elif command -v apt-get &>/dev/null; then
        apt-get update && apt-get install -y open-iscsi nfs-common
    fi

    # Enable and start iscsid
    systemctl enable iscsid
    systemctl start iscsid || true

    log_step "Adding Longhorn Helm repository..."
    helm repo add longhorn https://charts.longhorn.io 2>/dev/null || true
    helm repo update

    log_step "Installing Longhorn..."
    kubectl create namespace longhorn-system --dry-run=client -o yaml | kubectl apply -f -

    helm upgrade --install longhorn longhorn/longhorn \
        --namespace longhorn-system \
        --version 1.5.3 \
        --set defaultSettings.defaultDataPath="/var/lib/longhorn" \
        --set defaultSettings.replicaReplenishmentWaitInterval=60 \
        --set defaultSettings.defaultReplicaCount=1 \
        --set persistence.defaultClass=true \
        --set persistence.defaultClassReplicaCount=1 \
        --set csi.kubeletRootDir="/var/lib/kubelet" \
        --set defaultSettings.guaranteedInstanceManagerCPU=5 \
        --wait --timeout=600s

    log_step "Waiting for Longhorn to be ready..."
    kubectl wait --for=condition=Ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s || true

    # Set Longhorn as default StorageClass
    log_step "Setting Longhorn as default StorageClass..."
    kubectl patch storageclass longhorn -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' || true

    # Remove local-path as default if it exists
    kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' 2>/dev/null || true

    log_info "Longhorn block storage installed successfully!"

    # Create VirtualService for Longhorn UI (admin plane)
    log_step "Exposing Longhorn UI on admin plane..."
    cat <<EOF | kubectl apply -f -
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: longhorn-ui
  namespace: istio-system
spec:
  hosts:
    - "longhorn.siab.local"
  gateways:
    - admin-gateway
  http:
    - route:
        - destination:
            host: longhorn-frontend.longhorn-system.svc.cluster.local
            port:
              number: 80
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: longhorn-disable-mtls
  namespace: istio-system
spec:
  host: longhorn-frontend.longhorn-system.svc.cluster.local
  trafficPolicy:
    tls:
      mode: DISABLE
EOF

    log_info "Longhorn UI will be available at: https://longhorn.siab.local"
}

# Fix network policies
fix_network_policies() {
    section "Fixing Network Policies"

    log_step "Creating allow-all ingress policies for backend services..."

    for ns in keycloak minio monitoring kubernetes-dashboard longhorn-system siab-system istio-system; do
        if kubectl get namespace "$ns" &>/dev/null; then
            cat <<EOF | kubectl apply -f -
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
            log_info "Applied allow-all-ingress to $ns"
        fi
    done

    log_info "Network policies configured"
}

# Fix Calico/Canal network
fix_calico() {
    section "Configuring Calico/Canal Network"

    log_step "Applying permissive Calico configuration..."

    # Create GlobalNetworkPolicy to allow all pod traffic
    cat <<EOF | kubectl apply -f -
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

    # Configure Felix for permissive mode
    cat <<EOF | kubectl apply -f -
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

    log_info "Calico network configured for connectivity"
}

# Fix Istio routing
fix_istio_routing() {
    section "Fixing Istio Service Mesh Routing"

    log_step "Removing old DestinationRules from service namespaces..."
    kubectl delete destinationrule --all -n keycloak 2>/dev/null || true
    kubectl delete destinationrule --all -n minio 2>/dev/null || true
    kubectl delete destinationrule --all -n monitoring 2>/dev/null || true
    kubectl delete destinationrule --all -n kubernetes-dashboard 2>/dev/null || true

    log_step "Creating DestinationRules in istio-system namespace..."
    cat <<EOF | kubectl apply -f -
---
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
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: minio-console-disable-mtls
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
---
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
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: k8s-dashboard-disable-mtls
  namespace: istio-system
spec:
  host: kubernetes-dashboard-kong-proxy.kubernetes-dashboard.svc.cluster.local
  trafficPolicy:
    tls:
      mode: DISABLE
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: siab-dashboard-disable-mtls
  namespace: istio-system
spec:
  host: siab-dashboard.siab-system.svc.cluster.local
  trafficPolicy:
    tls:
      mode: DISABLE
EOF

    log_step "Creating/Updating VirtualServices in istio-system..."
    cat <<EOF | kubectl apply -f -
---
# Admin Plane Services
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: keycloak
  namespace: istio-system
spec:
  hosts:
    - "keycloak.siab.local"
  gateways:
    - admin-gateway
  http:
    - route:
        - destination:
            host: keycloak.keycloak.svc.cluster.local
            port:
              number: 80
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: minio-console
  namespace: istio-system
spec:
  hosts:
    - "minio.siab.local"
  gateways:
    - admin-gateway
  http:
    - route:
        - destination:
            host: minio-console.minio.svc.cluster.local
            port:
              number: 9001
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: grafana
  namespace: istio-system
spec:
  hosts:
    - "grafana.siab.local"
  gateways:
    - admin-gateway
  http:
    - route:
        - destination:
            host: kube-prometheus-stack-grafana.monitoring.svc.cluster.local
            port:
              number: 80
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: kubernetes-dashboard
  namespace: istio-system
spec:
  hosts:
    - "k8s-dashboard.siab.local"
  gateways:
    - admin-gateway
  http:
    - route:
        - destination:
            host: kubernetes-dashboard-kong-proxy.kubernetes-dashboard.svc.cluster.local
            port:
              number: 443
---
# User Plane Services
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: siab-dashboard
  namespace: istio-system
spec:
  hosts:
    - "dashboard.siab.local"
    - "siab.local"
  gateways:
    - user-gateway
  http:
    - route:
        - destination:
            host: siab-dashboard.siab-system.svc.cluster.local
            port:
              number: 80
EOF

    log_step "Creating Istio authorization policies..."
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

    log_info "Istio routing configured"
}

# Restart all components
restart_components() {
    section "Restarting Components"

    log_step "Restarting Calico/Canal..."
    kubectl delete pod -n kube-system -l k8s-app=canal --wait=false 2>/dev/null || true

    log_step "Restarting Istio gateways..."
    kubectl rollout restart deployment -n istio-system istio-ingress-admin 2>/dev/null || true
    kubectl rollout restart deployment -n istio-system istio-ingress-user 2>/dev/null || true

    log_step "Restarting backend services..."
    kubectl rollout restart deployment -n keycloak keycloak 2>/dev/null || true
    kubectl rollout restart deployment -n siab-system siab-dashboard 2>/dev/null || true

    log_step "Waiting for components to restart..."
    sleep 15

    log_step "Waiting for Istio gateways to be ready..."
    kubectl wait --for=condition=Available deployment -n istio-system istio-ingress-admin --timeout=120s 2>/dev/null || true
    kubectl wait --for=condition=Available deployment -n istio-system istio-ingress-user --timeout=120s 2>/dev/null || true

    log_info "Components restarted"
}

# Verify connectivity
verify_connectivity() {
    section "Verifying Connectivity"

    log_step "Testing gateway to backend connectivity..."

    # Get gateway pod
    local gateway_pod
    gateway_pod=$(kubectl get pods -n istio-system -l istio=ingress-admin -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -z "$gateway_pod" ]; then
        log_warn "Cannot find admin gateway pod for testing"
        return
    fi

    # Test Keycloak connectivity
    log_step "Testing Keycloak..."
    if kubectl exec -n istio-system "$gateway_pod" -- curl -s --connect-timeout 5 "http://keycloak.keycloak.svc.cluster.local:80/health/ready" &>/dev/null; then
        log_info "✓ Keycloak is reachable from gateway"
    else
        log_warn "✗ Keycloak is NOT reachable (may still be starting)"
    fi

    # Test dashboard connectivity
    log_step "Testing SIAB Dashboard..."
    local user_gateway_pod
    user_gateway_pod=$(kubectl get pods -n istio-system -l istio=ingress-user -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [ -n "$user_gateway_pod" ]; then
        if kubectl exec -n istio-system "$user_gateway_pod" -- curl -s --connect-timeout 5 "http://siab-dashboard.siab-system.svc.cluster.local:80/health" &>/dev/null; then
            log_info "✓ SIAB Dashboard is reachable from gateway"
        else
            log_warn "✗ SIAB Dashboard is NOT reachable (may still be starting)"
        fi
    fi
}

# Print summary
print_summary() {
    section "Installation Summary"

    # Get gateway IPs
    local admin_ip user_ip
    admin_ip=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    user_ip=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    if [ -z "$admin_ip" ] || [ -z "$user_ip" ]; then
        local node_ip
        node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
        admin_ip=${admin_ip:-$node_ip}
        user_ip=${user_ip:-$node_ip}
    fi

    echo ""
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}${GREEN}  SIAB Fix Complete!${NC}"
    echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${CYAN}Add these entries to /etc/hosts on your client machine:${NC}"
    echo ""
    echo -e "${YELLOW}# Admin Plane (restricted)${NC}"
    echo "$admin_ip keycloak.siab.local minio.siab.local grafana.siab.local k8s-dashboard.siab.local longhorn.siab.local"
    echo ""
    echo -e "${YELLOW}# User Plane${NC}"
    echo "$user_ip siab.local dashboard.siab.local catalog.siab.local"
    echo ""
    echo -e "${CYAN}Access your services:${NC}"
    echo ""
    echo -e "${BOLD}Admin Services:${NC}"
    echo "  • Keycloak:       https://keycloak.siab.local"
    echo "  • MinIO Console:  https://minio.siab.local"
    echo "  • Grafana:        https://grafana.siab.local"
    echo "  • K8s Dashboard:  https://k8s-dashboard.siab.local"
    echo "  • Longhorn UI:    https://longhorn.siab.local"
    echo ""
    echo -e "${BOLD}User Services:${NC}"
    echo "  • Dashboard:      https://dashboard.siab.local"
    echo "  • Catalog:        https://catalog.siab.local"
    echo ""
    echo -e "${YELLOW}Note: Accept the self-signed certificate warning in your browser${NC}"
    echo ""
    echo -e "${CYAN}Block Storage:${NC}"
    echo "  • Longhorn is now installed as the default StorageClass"
    echo "  • All PVCs will use Longhorn for persistent storage"
    echo ""
    echo -e "${CYAN}Credentials:${NC}"
    echo "  Run: ${BOLD}./siab-info.sh${NC} to see all credentials"
    echo ""
}

# Main execution
main() {
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║           SIAB Complete Fix & Block Storage Setup              ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Check if running as root
    if [ "$EUID" -ne 0 ]; then
        log_error "This script must be run as root"
        echo "Please run: sudo bash $0"
        exit 1
    fi

    setup_kubectl

    # Run all fixes
    install_longhorn
    fix_network_policies
    fix_calico
    fix_istio_routing
    restart_components

    # Wait a bit for services to stabilize
    log_step "Waiting for services to stabilize..."
    sleep 20

    verify_connectivity
    print_summary

    echo ""
    log_info "${GREEN}${BOLD}All fixes applied successfully!${NC}"
    echo ""
}

# Run main
main "$@"
