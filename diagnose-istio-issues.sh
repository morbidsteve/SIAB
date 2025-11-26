#!/bin/bash

# Comprehensive Istio diagnostics and troubleshooting script
# This script checks all Istio configurations and identifies issues

set -e

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m' # No Color

echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  SIAB - Istio Diagnostics              ${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl not found${NC}"
    exit 1
fi

echo -e "${GREEN}✓ kubectl found${NC}"
echo ""

# Function to check and display status
check_status() {
    local name=$1
    local command=$2

    echo -e "${CYAN}Checking: ${name}${NC}"
    if eval "$command" &> /dev/null; then
        echo -e "${GREEN}✓ ${name}${NC}"
        return 0
    else
        echo -e "${RED}✗ ${name}${NC}"
        return 1
    fi
}

# 1. Check Istio components
echo -e "${YELLOW}[1] Checking Istio Components${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_status "Istio namespace" "kubectl get namespace istio-system"
check_status "Istiod deployment" "kubectl get deployment istiod -n istio-system"
check_status "Admin ingress gateway" "kubectl get deployment istio-ingress-admin -n istio-system"
check_status "User ingress gateway" "kubectl get deployment istio-ingress-user -n istio-system"
echo ""

# 2. Check service pods
echo -e "${YELLOW}[2] Checking Service Pods${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
check_status "Keycloak pods" "kubectl get pods -n keycloak -l app=keycloak --field-selector=status.phase=Running"
check_status "MinIO pods" "kubectl get pods -n minio -l app=minio --field-selector=status.phase=Running"
check_status "Grafana pods" "kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana --field-selector=status.phase=Running"
check_status "Longhorn pods" "kubectl get pods -n longhorn-system -l app=longhorn-ui --field-selector=status.phase=Running"
echo ""

# 3. Check services
echo -e "${YELLOW}[3] Checking Services${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Keycloak service:"
kubectl get svc -n keycloak keycloak 2>/dev/null || echo -e "${RED}  Not found${NC}"

echo "MinIO services:"
kubectl get svc -n minio 2>/dev/null | grep -E "minio|NAME" || echo -e "${RED}  Not found${NC}"

echo "Grafana service:"
kubectl get svc -n monitoring -l app.kubernetes.io/name=grafana 2>/dev/null || echo -e "${RED}  Not found${NC}"

echo "Longhorn service:"
kubectl get svc -n longhorn-system longhorn-frontend 2>/dev/null || echo -e "${RED}  Not found${NC}"
echo ""

# 4. Check Gateways
echo -e "${YELLOW}[4] Checking Gateways${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl get gateway -n istio-system 2>/dev/null || echo -e "${RED}No gateways found${NC}"
echo ""

# 5. Check VirtualServices
echo -e "${YELLOW}[5] Checking VirtualServices${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl get virtualservice -n istio-system 2>/dev/null || echo -e "${RED}No virtual services found${NC}"
echo ""

# 6. Check DestinationRules
echo -e "${YELLOW}[6] Checking DestinationRules${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
DEST_RULES=$(kubectl get destinationrules -n istio-system 2>/dev/null | grep -c mtls-disable || echo "0")
if [ "$DEST_RULES" -eq 0 ]; then
    echo -e "${RED}✗ No mTLS DestinationRules found${NC}"
    echo -e "${YELLOW}  This is likely causing the upstream connection errors!${NC}"
else
    echo -e "${GREEN}✓ Found $DEST_RULES mTLS DestinationRules${NC}"
    kubectl get destinationrules -n istio-system | grep mtls-disable
fi
echo ""

# 7. Check AuthorizationPolicies
echo -e "${YELLOW}[7] Checking AuthorizationPolicies${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl get authorizationpolicies -n istio-system 2>/dev/null || echo -e "${RED}No authorization policies found${NC}"
echo ""

# 8. Check PeerAuthentication (mTLS mode)
echo -e "${YELLOW}[8] Checking PeerAuthentication (mTLS mode)${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl get peerauthentication -n istio-system 2>/dev/null || echo -e "${YELLOW}No peer authentication found${NC}"
echo ""

# 9. Check namespace Istio injection labels
echo -e "${YELLOW}[9] Checking Namespace Istio Injection${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for ns in keycloak minio monitoring longhorn-system; do
    label=$(kubectl get namespace $ns -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null || echo "not-set")
    if [ "$label" = "disabled" ]; then
        echo -e "${CYAN}$ns${NC}: istio-injection=${YELLOW}disabled${NC} (no sidecars)"
    elif [ "$label" = "enabled" ]; then
        echo -e "${CYAN}$ns${NC}: istio-injection=${GREEN}enabled${NC} (has sidecars)"
    else
        echo -e "${CYAN}$ns${NC}: istio-injection=${RED}not-set${NC}"
    fi
done
echo ""

# 10. Get pod IPs to verify connectivity
echo -e "${YELLOW}[10] Service Endpoints${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Keycloak endpoints:"
kubectl get endpoints -n keycloak keycloak 2>/dev/null || echo -e "${RED}  Not found${NC}"

echo "MinIO endpoints:"
kubectl get endpoints -n minio 2>/dev/null | grep -E "minio|NAME" || echo -e "${RED}  Not found${NC}"

echo "Grafana endpoints:"
kubectl get endpoints -n monitoring -l app.kubernetes.io/name=grafana 2>/dev/null || echo -e "${RED}  Not found${NC}"
echo ""

# 11. Check recent ingress logs for errors
echo -e "${YELLOW}[11] Recent Admin Gateway Errors${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl logs -n istio-system -l istio=ingress-admin --tail=20 2>/dev/null | grep -E "503|403|500|RBAC|upstream" | head -10 || echo "No recent errors"
echo ""

# Summary and recommendations
echo ""
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  Summary & Recommendations            ${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""

if [ "$DEST_RULES" -eq 0 ]; then
    echo -e "${RED}⚠ CRITICAL: DestinationRules missing!${NC}"
    echo -e "  ${YELLOW}Run: ./fix-all-istio-issues.sh${NC}"
    echo ""
fi

echo -e "${CYAN}Common Issues:${NC}"
echo -e "  1. ${YELLOW}delayed_connect_error:_113${NC} → Service pod not reachable (check pod status)"
echo -e "  2. ${YELLOW}rbac_access_denied_matched_policy[none]${NC} → AuthorizationPolicy blocking traffic"
echo -e "  3. ${YELLOW}filter_chain_not_found${NC} → Gateway missing host in TLS configuration"
echo -e "  4. ${YELLOW}upstream_reset${NC} → mTLS mismatch (needs DestinationRule)"
echo ""
