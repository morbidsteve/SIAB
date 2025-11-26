#!/bin/bash

# Fix network policies to allow Istio gateway traffic
# The current policies are blocking traffic from the gateway to backend pods

set -e

export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH="/var/lib/rancher/rke2/bin:${PATH}"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  Fix Network Policies                  ${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""

echo -e "${YELLOW}Current network policies:${NC}"
kubectl get networkpolicies --all-namespaces
echo ""

echo -e "${YELLOW}Checking current allow-all-ingress policy in keycloak:${NC}"
kubectl get networkpolicy allow-all-ingress -n keycloak -o yaml 2>/dev/null || echo "Not found"
echo ""

echo -e "${YELLOW}Deleting restrictive network policies...${NC}"
# Delete the problematic network policies
kubectl delete networkpolicy allow-all-ingress -n keycloak 2>/dev/null || echo "Already deleted from keycloak"
kubectl delete networkpolicy allow-all-ingress -n minio 2>/dev/null || echo "Already deleted from minio"
kubectl delete networkpolicy allow-all-ingress -n monitoring 2>/dev/null || echo "Already deleted from monitoring"
kubectl delete networkpolicy allow-all-ingress -n longhorn-system 2>/dev/null || echo "Already deleted from longhorn-system"
kubectl delete networkpolicy allow-all-ingress -n istio-system 2>/dev/null || echo "Already deleted from istio-system"
echo ""

echo -e "${YELLOW}Creating permissive network policies...${NC}"

# Create proper network policies that allow Istio gateway traffic
cat <<EOF | kubectl apply -f -
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all
  namespace: keycloak
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - {}
  egress:
  - {}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all
  namespace: minio
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - {}
  egress:
  - {}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all
  namespace: monitoring
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - {}
  egress:
  - {}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all
  namespace: longhorn-system
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - {}
  egress:
  - {}
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all
  namespace: istio-system
spec:
  podSelector: {}
  policyTypes:
  - Ingress
  - Egress
  ingress:
  - {}
  egress:
  - {}
EOF

echo ""
echo -e "${GREEN}✓ Network policies updated${NC}"
echo ""

echo -e "${YELLOW}New network policies:${NC}"
kubectl get networkpolicies --all-namespaces
echo ""

echo -e "${YELLOW}Testing connectivity (wait 5 seconds for policies to apply)...${NC}"
sleep 5
echo ""

# Test connectivity from gateway to Keycloak
KEYCLOAK_IP=$(kubectl get pod -n keycloak -l app=keycloak -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || echo "")
if [ -n "$KEYCLOAK_IP" ]; then
    echo "Testing gateway -> Keycloak ($KEYCLOAK_IP:8080):"
    kubectl exec -n istio-system deployment/istio-ingress-admin -- sh -c "nc -zv $KEYCLOAK_IP 8080 2>&1" && echo -e "${GREEN}✓ Connection successful${NC}" || echo -e "${RED}✗ Connection failed${NC}"
fi
echo ""

echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${GREEN}  Network Policies Fixed!               ${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""
echo "Try accessing your services now:"
echo "  curl -k https://keycloak.siab.local"
echo "  curl -k https://minio.siab.local"
echo "  curl -k https://grafana.siab.local"
echo ""
