#!/bin/bash
# SIAB Istio Routing Fix Script
# Fixes the upstream connect errors by:
# 1. Moving DestinationRules to istio-system namespace
# 2. Configuring ingress gateway with hostPort for standard 80/443 ports
# 3. Updating VirtualServices with FQDN hosts

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

log_step "Fixing Istio routing configuration..."

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

# Step 4: Create VirtualServices in istio-system namespace
log_info "Creating VirtualServices in istio-system namespace..."
cat <<EOF | kubectl apply -f -
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: keycloak
  namespace: istio-system
spec:
  hosts:
    - "keycloak.${SIAB_DOMAIN}"
  gateways:
    - siab-gateway
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
    - siab-gateway
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
    - siab-gateway
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
    - siab-gateway
  http:
    - route:
        - destination:
            host: kubernetes-dashboard-kong-proxy.kubernetes-dashboard.svc.cluster.local
            port:
              number: 443
---
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
    - siab-gateway
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

# Step 5: Patch ingress gateway to use hostPort for standard ports
log_info "Patching Istio ingress gateway for standard ports (80/443)..."

# Update the service to ClusterIP (we'll use hostPort instead of NodePort)
kubectl patch svc istio-ingress -n istio-system --type='json' -p='[
  {"op": "replace", "path": "/spec/type", "value": "ClusterIP"}
]' 2>/dev/null || true

# Patch the deployment to use hostPort
kubectl patch deployment istio-ingress -n istio-system --type='json' -p='[
  {"op": "replace", "path": "/spec/template/spec/containers/0/ports", "value": [
    {"containerPort": 80, "hostPort": 80, "protocol": "TCP", "name": "http"},
    {"containerPort": 443, "hostPort": 443, "protocol": "TCP", "name": "https"},
    {"containerPort": 15090, "protocol": "TCP", "name": "http-envoy-prom"}
  ]}
]'

# Wait for rollout
log_info "Waiting for ingress gateway rollout..."
kubectl rollout status deployment/istio-ingress -n istio-system --timeout=120s

# Step 6: Update /etc/hosts if needed
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
if ! grep -q "k8s-dashboard.${SIAB_DOMAIN}" /etc/hosts; then
    log_info "Adding k8s-dashboard to /etc/hosts..."
    echo "${NODE_IP} k8s-dashboard.${SIAB_DOMAIN}" >> /etc/hosts
fi
if ! grep -q "catalog.${SIAB_DOMAIN}" /etc/hosts; then
    log_info "Adding catalog to /etc/hosts..."
    echo "${NODE_IP} catalog.${SIAB_DOMAIN}" >> /etc/hosts
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
echo "Ingress Gateway pods:"
kubectl get pods -n istio-system -l istio=ingress

log_info "Fix complete!"
echo ""
echo "=================================="
echo "Your /etc/hosts should include:"
echo "${NODE_IP} ${SIAB_DOMAIN} grafana.${SIAB_DOMAIN} dashboard.${SIAB_DOMAIN} keycloak.${SIAB_DOMAIN} minio.${SIAB_DOMAIN} k8s-dashboard.${SIAB_DOMAIN} catalog.${SIAB_DOMAIN}"
echo ""
echo "Access your services at:"
echo "  https://dashboard.${SIAB_DOMAIN}"
echo "  https://grafana.${SIAB_DOMAIN}"
echo "  https://keycloak.${SIAB_DOMAIN}"
echo "  https://minio.${SIAB_DOMAIN}"
echo "  https://k8s-dashboard.${SIAB_DOMAIN}"
echo ""
echo "Note: Accept the self-signed certificate warning in your browser"
echo "=================================="
