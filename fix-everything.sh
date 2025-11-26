#!/bin/bash

# Master fix script - Fixes all known Istio and routing issues
# Run with: sudo ./fix-everything.sh

set -e

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH="/var/lib/rancher/rke2/bin:${PATH}"

echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  SIAB - Master Fix Script              ${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""

# Step 1: Fix /etc/hosts
echo -e "${YELLOW}[1/4] Fixing /etc/hosts${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
./fix-etc-hosts.sh
echo -e "${GREEN}✓ /etc/hosts fixed${NC}"
echo ""

# Step 2: Apply all Istio fixes (mTLS, RBAC, PeerAuth)
echo -e "${YELLOW}[2/4] Applying Istio mTLS and RBAC fixes${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
./fix-all-istio-issues.sh | grep -E "✓|applied|configured" || true
echo -e "${GREEN}✓ Istio fixes applied${NC}"
echo ""

# Step 3: Fix Gateway for Longhorn
echo -e "${YELLOW}[3/4] Updating Gateway for Longhorn${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
./fix-gateway-longhorn.sh | grep -E "✓|updated" || true
echo -e "${GREEN}✓ Gateway updated${NC}"
echo ""

# Step 4: Restart ingress gateway pods to pick up changes
echo -e "${YELLOW}[4/4] Restarting Istio ingress gateways${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl rollout restart deployment istio-ingress-admin -n istio-system
kubectl rollout restart deployment istio-ingress-user -n istio-system

echo "Waiting for gateways to restart..."
kubectl rollout status deployment istio-ingress-admin -n istio-system --timeout=60s
kubectl rollout status deployment istio-ingress-user -n istio-system --timeout=60s
echo -e "${GREEN}✓ Gateways restarted${NC}"
echo ""

# Wait for Istio to propagate changes
echo -e "${YELLOW}Waiting 15 seconds for Istio to propagate changes...${NC}"
sleep 15
echo ""

# Verification
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  Verification                          ${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""

echo -e "${CYAN}[1] /etc/hosts${NC}"
grep siab.local /etc/hosts | head -5
echo ""

echo -e "${CYAN}[2] DestinationRules${NC}"
kubectl get destinationrules -n istio-system | grep mtls-disable | wc -l | xargs echo "Found"
echo ""

echo -e "${CYAN}[3] Gateway Hosts${NC}"
kubectl get gateway admin-gateway -n istio-system -o jsonpath='{.spec.servers[0].hosts}' | jq .
echo ""

echo -e "${CYAN}[4] Admin Gateway Status${NC}"
kubectl get deployment istio-ingress-admin -n istio-system
echo ""

# Final test
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  Testing Services                      ${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""

ADMIN_IP=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
echo "Admin Gateway IP: $ADMIN_IP"
echo ""

echo "Testing keycloak.siab.local:"
curl -s -k -m 5 -o /dev/null -w "HTTP Status: %{http_code}\n" https://keycloak.siab.local/ 2>&1 || echo "Connection failed"
echo ""

echo "Testing minio.siab.local:"
curl -s -k -m 5 -o /dev/null -w "HTTP Status: %{http_code}\n" https://minio.siab.local/ 2>&1 || echo "Connection failed"
echo ""

echo "Testing grafana.siab.local:"
curl -s -k -m 5 -o /dev/null -w "HTTP Status: %{http_code}\n" https://grafana.siab.local/ 2>&1 || echo "Connection failed"
echo ""

echo "Testing longhorn.siab.local:"
curl -s -k -m 5 -o /dev/null -w "HTTP Status: %{http_code}\n" https://longhorn.siab.local/ 2>&1 || echo "Connection failed"
echo ""

echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${GREEN}  All Fixes Applied!                    ${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""
echo -e "${YELLOW}Next Steps:${NC}"
echo "  1. Check the HTTP status codes above (should be 200, 302, or 401, not 503/404)"
echo "  2. Test in browser: https://keycloak.siab.local"
echo "  3. If still failing, check pod status: kubectl get pods -n keycloak"
echo "  4. View logs: kubectl logs -n istio-system -l istio=ingress-admin --tail=20"
echo ""
