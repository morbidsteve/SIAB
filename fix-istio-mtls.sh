#!/bin/bash

# Fix Istio mTLS errors for services without sidecars
# This script applies DestinationRules to disable mTLS for services in namespaces
# without Istio injection (keycloak, minio, monitoring, longhorn-system)

set -e

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

echo -e "${BLUE}========================================${NC}"
echo -e "${BLUE}  SIAB - Fix Istio mTLS Configuration  ${NC}"
echo -e "${BLUE}========================================${NC}"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl not found${NC}"
    echo "Please ensure kubectl is installed and in your PATH"
    exit 1
fi

# Check if we can connect to the cluster
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
    echo "Please ensure your kubeconfig is properly configured"
    exit 1
fi

echo -e "${YELLOW}Applying DestinationRules to disable mTLS for non-sidecar services...${NC}"
echo ""

# Apply DestinationRules
cat <<EOF | kubectl apply -f -
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: keycloak-mtls-disable
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
  name: minio-mtls-disable
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
  name: minio-console-mtls-disable
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
  name: grafana-mtls-disable
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
  name: prometheus-mtls-disable
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
  name: longhorn-mtls-disable
  namespace: istio-system
spec:
  host: longhorn-frontend.longhorn-system.svc.cluster.local
  trafficPolicy:
    tls:
      mode: DISABLE
EOF

echo ""
echo -e "${GREEN}✓ DestinationRules applied successfully${NC}"
echo ""
echo -e "${YELLOW}What was fixed:${NC}"
echo "  • Keycloak (keycloak.siab.local)"
echo "  • MinIO and MinIO Console (minio.siab.local)"
echo "  • Grafana (grafana.siab.local)"
echo "  • Prometheus"
echo "  • Longhorn (longhorn.siab.local)"
echo ""
echo -e "${YELLOW}These services now bypass Istio mTLS and should be accessible.${NC}"
echo ""
echo -e "${BLUE}Verifying DestinationRules...${NC}"
kubectl get destinationrules -n istio-system | grep mtls-disable
echo ""
echo -e "${GREEN}✓ Fix applied successfully!${NC}"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "  1. Wait 10-30 seconds for Istio to apply the configuration"
echo "  2. Try accessing your services again (e.g., https://keycloak.siab.local)"
echo "  3. Check Istio ingress logs: kubectl logs -n istio-system -l istio=ingress-admin --tail=50"
echo ""
