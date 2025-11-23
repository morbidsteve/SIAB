#!/bin/bash
# SIAB Istio Routing Fix Script
# Fixes the upstream connect errors by:
# 1. Moving DestinationRules to istio-system namespace
# 2. Configuring dual ingress gateways (admin and user) with MetalLB
# 3. Updating VirtualServices with FQDN hosts and correct gateways

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    export PATH=$PATH:/var/lib/rancher/rke2/bin:/usr/local/bin
fi

if [[ ! -f ~/.kube/config ]] && [[ ! -f /etc/rancher/rke2/rke2.yaml ]]; then
    log_error "No kubeconfig found. Run as root."
    exit 1
fi

if [[ -f /etc/rancher/rke2/rke2.yaml ]] && [[ ! -f ~/.kube/config ]]; then
    export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
fi

SIAB_DOMAIN="${SIAB_DOMAIN:-siab.local}"

log_step "Fixing Istio routing configuration for dual-gateway architecture..."

# Step 1: Delete old DestinationRules from wrong namespaces
log_info "Removing old DestinationRules from service namespaces..."
kubectl delete destinationrule keycloak-disable-mtls -n keycloak 2>/dev/null || true
kubectl delete destinationrule minio-disable-mtls -n minio 2>/dev/null || true
kubectl delete destinationrule grafana-disable-mtls -n monitoring 2>/dev/null || true
kubectl delete destinationrule dashboard-disable-mtls -n kubernetes-dashboard 2>/dev/null || true

# Step 2: Delete old VirtualServices from service namespaces
log_info "Removing old VirtualServices from service namespaces..."
kubectl delete virtualservice keycloak -n keycloak 2>/dev/null || true
kubectl delete virtualservice minio-console -n minio 2>/dev/null || true
kubectl delete virtualservice grafana -n monitoring 2>/dev/null || true
kubectl delete virtualservice kubernetes-dashboard -n kubernetes-dashboard 2>/dev/null || true

# Step 3: Create DestinationRules in istio-system namespace
log_info "Creating DestinationRules in istio-system namespace..."
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
EOF

# Step 4: Create VirtualServices in istio-system namespace with correct gateways
log_info "Creating VirtualServices in istio-system namespace..."
cat <<EOF | kubectl apply -f -
---
# Admin Plane VirtualServices (use admin-gateway)
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
---
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
---
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
---
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
---
# User Plane VirtualServices (use user-gateway)
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: siab-dashboard
  namespace: istio-system
spec:
  hosts:
    - "dashboard.${SIAB_DOMAIN}"
    - "${SIAB_DOMAIN}"
  gateways:
    - user-gateway
  http:
    - match:
        - uri:
            prefix: /
      route:
        - destination:
            host: siab-dashboard.siab-system.svc.cluster.local
            port:
              number: 80
EOF

# Step 5: Create dual Istio gateways (admin and user)
log_info "Creating admin and user gateways..."
cat <<EOF | kubectl apply -f -
---
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
        number: 80
        name: http
        protocol: HTTP
      hosts:
        - "*.${SIAB_DOMAIN}"
      tls:
        httpsRedirect: true
    - port:
        number: 443
        name: https
        protocol: HTTPS
      hosts:
        - "*.${SIAB_DOMAIN}"
      tls:
        mode: SIMPLE
        credentialName: siab-gateway-cert
---
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
        number: 80
        name: http
        protocol: HTTP
      hosts:
        - "*.${SIAB_DOMAIN}"
        - "${SIAB_DOMAIN}"
      tls:
        httpsRedirect: true
    - port:
        number: 443
        name: https
        protocol: HTTPS
      hosts:
        - "*.${SIAB_DOMAIN}"
        - "${SIAB_DOMAIN}"
      tls:
        mode: SIMPLE
        credentialName: siab-gateway-cert
EOF

# Step 6: Get LoadBalancer IPs and update /etc/hosts
log_info "Getting gateway LoadBalancer IPs..."

# Wait for IPs
timeout=60
elapsed=0
while [[ $elapsed -lt $timeout ]]; do
    ADMIN_GATEWAY_IP=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    USER_GATEWAY_IP=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    if [[ -n "$ADMIN_GATEWAY_IP" ]] && [[ -n "$USER_GATEWAY_IP" ]]; then
        break
    fi
    sleep 2
    elapsed=$((elapsed + 2))
done

# Fallback to node IP if LoadBalancer not available
if [[ -z "$ADMIN_GATEWAY_IP" ]] || [[ -z "$USER_GATEWAY_IP" ]]; then
    log_warn "LoadBalancer IPs not available. MetalLB may not be installed."
    log_warn "Run the full install script to install MetalLB for dual-gateway support."
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
    ADMIN_GATEWAY_IP="${NODE_IP}"
    USER_GATEWAY_IP="${NODE_IP}"
fi

log_info "Admin Gateway IP: ${ADMIN_GATEWAY_IP}"
log_info "User Gateway IP: ${USER_GATEWAY_IP}"

# Update /etc/hosts
if ! grep -q "SIAB Admin Plane" /etc/hosts; then
    log_info "Adding gateway entries to /etc/hosts..."
    cat >> /etc/hosts <<EOF

# SIAB Admin Plane (administrative services - restricted access)
${ADMIN_GATEWAY_IP} keycloak.${SIAB_DOMAIN}
${ADMIN_GATEWAY_IP} minio.${SIAB_DOMAIN}
${ADMIN_GATEWAY_IP} grafana.${SIAB_DOMAIN}
${ADMIN_GATEWAY_IP} k8s-dashboard.${SIAB_DOMAIN}

# SIAB User Plane (user-facing services)
${USER_GATEWAY_IP} ${SIAB_DOMAIN}
${USER_GATEWAY_IP} dashboard.${SIAB_DOMAIN}
${USER_GATEWAY_IP} catalog.${SIAB_DOMAIN}
EOF
fi

# Step 7: Verify the configuration
log_step "Verifying configuration..."

echo ""
echo "DestinationRules in istio-system:"
kubectl get destinationrule -n istio-system

echo ""
echo "VirtualServices in istio-system:"
kubectl get virtualservice -n istio-system

echo ""
echo "Gateways in istio-system:"
kubectl get gateway -n istio-system

echo ""
echo "Admin Gateway pods:"
kubectl get pods -n istio-system -l istio=ingress-admin 2>/dev/null || kubectl get pods -n istio-system -l istio=ingress

echo ""
echo "User Gateway pods:"
kubectl get pods -n istio-system -l istio=ingress-user 2>/dev/null || true

echo ""
echo "LoadBalancer Services:"
kubectl get svc -n istio-system | grep -E "istio-ingress|LoadBalancer"

log_info "Fix complete!"
echo ""
echo "=================================="
echo "Add these to /etc/hosts on client machines:"
echo ""
echo "# Admin Plane (restricted access)"
echo "${ADMIN_GATEWAY_IP} keycloak.${SIAB_DOMAIN} minio.${SIAB_DOMAIN} grafana.${SIAB_DOMAIN} k8s-dashboard.${SIAB_DOMAIN}"
echo ""
echo "# User Plane"
echo "${USER_GATEWAY_IP} ${SIAB_DOMAIN} dashboard.${SIAB_DOMAIN} catalog.${SIAB_DOMAIN}"
echo ""
echo "Admin Plane Services (port 443):"
echo "  https://grafana.${SIAB_DOMAIN}"
echo "  https://keycloak.${SIAB_DOMAIN}"
echo "  https://minio.${SIAB_DOMAIN}"
echo "  https://k8s-dashboard.${SIAB_DOMAIN}"
echo ""
echo "User Plane Services (port 443):"
echo "  https://dashboard.${SIAB_DOMAIN}"
echo "  https://catalog.${SIAB_DOMAIN}"
echo ""
echo "Note: Accept the self-signed certificate warning in your browser"
echo "=================================="
