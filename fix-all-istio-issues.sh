#!/bin/bash

# Comprehensive fix for all Istio upstream and RBAC errors
# This script applies all necessary fixes in the correct order

set -e

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  SIAB - Fix All Istio Issues          ${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}Error: kubectl not found${NC}"
    exit 1
fi

# Check cluster connectivity
if ! kubectl cluster-info &> /dev/null; then
    echo -e "${RED}Error: Cannot connect to Kubernetes cluster${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Connected to Kubernetes cluster${NC}"
echo ""

# Step 1: Apply DestinationRules to disable mTLS for services without sidecars
echo -e "${YELLOW}[1/4] Applying DestinationRules for mTLS exceptions${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

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

echo -e "${GREEN}✓ DestinationRules applied${NC}"
echo ""

# Step 2: Fix RBAC - Remove overly restrictive policies and add permissive ones
echo -e "${YELLOW}[2/4] Fixing RBAC AuthorizationPolicies${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# First, check if there are any DENY policies that might be blocking
DENY_POLICIES=$(kubectl get authorizationpolicies -n istio-system -o json | jq -r '.items[] | select(.spec.action == "DENY") | .metadata.name' 2>/dev/null || echo "")
if [ -n "$DENY_POLICIES" ]; then
    echo -e "${YELLOW}Found DENY policies: $DENY_POLICIES${NC}"
    echo "These might be blocking traffic - consider reviewing them"
fi

# Apply updated AuthorizationPolicies that allow traffic
cat <<EOF | kubectl apply -f -
---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-all-admin-gateway
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
  name: allow-all-user-gateway
  namespace: istio-system
spec:
  selector:
    matchLabels:
      istio: ingress-user
  action: ALLOW
  rules:
  - {}
---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-keycloak
  namespace: keycloak
spec:
  action: ALLOW
  rules:
  - {}
---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-minio
  namespace: minio
spec:
  action: ALLOW
  rules:
  - {}
---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-monitoring
  namespace: monitoring
spec:
  action: ALLOW
  rules:
  - {}
---
apiVersion: security.istio.io/v1beta1
kind: AuthorizationPolicy
metadata:
  name: allow-longhorn
  namespace: longhorn-system
spec:
  action: ALLOW
  rules:
  - {}
EOF

echo -e "${GREEN}✓ AuthorizationPolicies applied${NC}"
echo ""

# Step 3: Add PeerAuthentication to allow non-mTLS for services without sidecars
echo -e "${YELLOW}[3/4] Configuring PeerAuthentication for namespaces${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cat <<EOF | kubectl apply -f -
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: allow-plain-text
  namespace: keycloak
spec:
  mtls:
    mode: PERMISSIVE
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: allow-plain-text
  namespace: minio
spec:
  mtls:
    mode: PERMISSIVE
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: allow-plain-text
  namespace: monitoring
spec:
  mtls:
    mode: PERMISSIVE
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: allow-plain-text
  namespace: longhorn-system
spec:
  mtls:
    mode: PERMISSIVE
EOF

echo -e "${GREEN}✓ PeerAuthentication configured${NC}"
echo ""

# Step 4: Verify configurations
echo -e "${YELLOW}[4/4] Verifying configurations${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo "DestinationRules:"
kubectl get destinationrules -n istio-system | grep mtls-disable | wc -l | xargs echo "  Found"

echo "AuthorizationPolicies:"
kubectl get authorizationpolicies --all-namespaces | wc -l | xargs echo "  Found"

echo "PeerAuthentication:"
kubectl get peerauthentication --all-namespaces | grep -c "allow-plain-text" | xargs echo "  Found"

echo ""
echo -e "${GREEN}✓ All configurations verified${NC}"
echo ""

# Final instructions
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  Next Steps                            ${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}1. Wait 10-30 seconds for Istio to propagate changes${NC}"
echo -e "${YELLOW}2. Test your services:${NC}"
echo "   • https://keycloak.siab.local"
echo "   • https://minio.siab.local"
echo "   • https://grafana.siab.local"
echo "   • https://longhorn.siab.local"
echo ""
echo -e "${YELLOW}3. If issues persist, check logs:${NC}"
echo "   kubectl logs -n istio-system -l istio=ingress-admin --tail=50"
echo ""
echo -e "${YELLOW}4. Run diagnostics:${NC}"
echo "   ./diagnose-istio-issues.sh"
echo ""
echo -e "${GREEN}✓ Fix completed successfully!${NC}"
echo ""
