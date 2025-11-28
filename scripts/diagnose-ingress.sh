#!/bin/bash
# SIAB Ingress Diagnostic Script
# This script checks for nginx-ingress and validates Istio configuration

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

echo -e "${BOLD}SIAB Ingress Diagnostic Tool${NC}"
echo "=================================="
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl not found. Please ensure kubectl is in your PATH.${NC}"
    exit 1
fi

echo -e "${BLUE}Checking for ingress controllers...${NC}"
echo ""

# Function to check for nginx-ingress
check_nginx_ingress() {
    echo -e "${BOLD}1. Checking for nginx-ingress-controller...${NC}"

    local nginx_found=false

    # Check for nginx-ingress deployments
    if kubectl get deployment -A -o json | jq -r '.items[] | select(.metadata.name | contains("nginx") or contains("ingress")) | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null | grep -i nginx; then
        echo -e "${YELLOW}  ⚠ Found nginx-ingress deployments:${NC}"
        kubectl get deployment -A -o wide | grep -E "nginx.*ingress|ingress.*nginx"
        nginx_found=true
    fi

    # Check for nginx-ingress daemonsets
    if kubectl get daemonset -A -o json | jq -r '.items[] | select(.metadata.name | contains("nginx") or contains("ingress")) | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null | grep -i nginx; then
        echo -e "${YELLOW}  ⚠ Found nginx-ingress daemonsets:${NC}"
        kubectl get daemonset -A -o wide | grep -E "nginx.*ingress|ingress.*nginx"
        nginx_found=true
    fi

    # Check for nginx-ingress services
    if kubectl get svc -A -o json | jq -r '.items[] | select(.metadata.name | contains("nginx") or contains("ingress")) | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null | grep -i nginx; then
        echo -e "${YELLOW}  ⚠ Found nginx-ingress services:${NC}"
        kubectl get svc -A -o wide | grep -E "nginx.*ingress|ingress.*nginx"
        nginx_found=true
    fi

    # Check for IngressClass
    if kubectl get ingressclass 2>/dev/null | grep -i nginx; then
        echo -e "${YELLOW}  ⚠ Found nginx IngressClass:${NC}"
        kubectl get ingressclass | grep -i nginx
        nginx_found=true
    fi

    # Check for Ingress resources using nginx
    if kubectl get ingress -A -o json 2>/dev/null | jq -r '.items[] | select(.spec.ingressClassName == "nginx" or (.metadata.annotations["kubernetes.io/ingress.class"] // "") == "nginx") | "\(.metadata.namespace)/\(.metadata.name)"' | grep .; then
        echo -e "${YELLOW}  ⚠ Found Ingress resources using nginx class:${NC}"
        kubectl get ingress -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,CLASS:.spec.ingressClassName,HOSTS:.spec.rules[*].host
        nginx_found=true
    fi

    # Check for helm releases
    if command -v helm &> /dev/null; then
        if helm list -A -o json 2>/dev/null | jq -r '.[] | select(.name | contains("nginx") or contains("ingress")) | "\(.namespace)/\(.name)"' | grep -i nginx; then
            echo -e "${YELLOW}  ⚠ Found nginx-ingress helm releases:${NC}"
            helm list -A | grep -i nginx
            nginx_found=true
        fi
    fi

    if [ "$nginx_found" = false ]; then
        echo -e "${GREEN}  ✓ No nginx-ingress found${NC}"
    else
        echo -e "${RED}  ✗ nginx-ingress is installed!${NC}"
        echo -e "${YELLOW}  → This may conflict with Istio ingress${NC}"
    fi

    echo ""
    return $([ "$nginx_found" = true ] && echo 1 || echo 0)
}

# Function to check Istio configuration
check_istio() {
    echo -e "${BOLD}2. Checking Istio configuration...${NC}"

    local istio_ok=true

    # Check Istio namespace
    if ! kubectl get namespace istio-system &> /dev/null; then
        echo -e "${RED}  ✗ istio-system namespace not found${NC}"
        istio_ok=false
    else
        echo -e "${GREEN}  ✓ istio-system namespace exists${NC}"
    fi

    # Check istiod
    if kubectl get deployment istiod -n istio-system &> /dev/null; then
        local ready=$(kubectl get deployment istiod -n istio-system -o jsonpath='{.status.readyReplicas}')
        local desired=$(kubectl get deployment istiod -n istio-system -o jsonpath='{.status.replicas}')
        if [ "$ready" = "$desired" ] && [ "$ready" -gt 0 ]; then
            echo -e "${GREEN}  ✓ istiod is running ($ready/$desired pods ready)${NC}"
        else
            echo -e "${YELLOW}  ⚠ istiod not fully ready ($ready/$desired pods)${NC}"
            istio_ok=false
        fi
    else
        echo -e "${RED}  ✗ istiod deployment not found${NC}"
        istio_ok=false
    fi

    # Check ingress gateways
    echo ""
    echo -e "${BOLD}  Istio Ingress Gateways:${NC}"

    # Check admin gateway
    if kubectl get deployment istio-ingress-admin -n istio-system &> /dev/null; then
        local admin_ready=$(kubectl get deployment istio-ingress-admin -n istio-system -o jsonpath='{.status.readyReplicas}')
        local admin_ip=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        echo -e "${GREEN}    ✓ Admin gateway: $admin_ready pods ready${NC}"
        if [ -n "$admin_ip" ]; then
            echo -e "${GREEN}      LoadBalancer IP: $admin_ip${NC}"
        fi
    else
        echo -e "${YELLOW}    ⚠ Admin gateway not found${NC}"
    fi

    # Check user gateway
    if kubectl get deployment istio-ingress-user -n istio-system &> /dev/null; then
        local user_ready=$(kubectl get deployment istio-ingress-user -n istio-system -o jsonpath='{.status.readyReplicas}')
        local user_ip=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
        echo -e "${GREEN}    ✓ User gateway: $user_ready pods ready${NC}"
        if [ -n "$user_ip" ]; then
            echo -e "${GREEN}      LoadBalancer IP: $user_ip${NC}"
        fi
    else
        echo -e "${YELLOW}    ⚠ User gateway not found${NC}"
    fi

    echo ""

    # Check Gateway resources
    local gateway_count=$(kubectl get gateway -n istio-system 2>/dev/null | grep -v NAME | wc -l)
    if [ "$gateway_count" -gt 0 ]; then
        echo -e "${GREEN}  ✓ Found $gateway_count Istio Gateway(s):${NC}"
        kubectl get gateway -n istio-system -o custom-columns=NAME:.metadata.name,HOSTS:.spec.servers[*].hosts
    else
        echo -e "${YELLOW}  ⚠ No Istio Gateways found${NC}"
        istio_ok=false
    fi

    echo ""

    # Check VirtualServices
    local vs_count=$(kubectl get virtualservice -A 2>/dev/null | grep -v NAMESPACE | wc -l)
    if [ "$vs_count" -gt 0 ]; then
        echo -e "${GREEN}  ✓ Found $vs_count VirtualService(s)${NC}"
    else
        echo -e "${YELLOW}  ⚠ No VirtualServices found${NC}"
    fi

    echo ""
    return $([ "$istio_ok" = true ] && echo 0 || echo 1)
}

# Function to check traffic routing
check_traffic_routing() {
    echo -e "${BOLD}3. Checking traffic routing configuration...${NC}"

    # Check for conflicting Ingress resources
    local ingress_count=$(kubectl get ingress -A 2>/dev/null | grep -v NAMESPACE | wc -l)
    if [ "$ingress_count" -gt 0 ]; then
        echo -e "${YELLOW}  ⚠ Found $ingress_count Kubernetes Ingress resource(s):${NC}"
        kubectl get ingress -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,CLASS:.spec.ingressClassName,HOSTS:.spec.rules[*].host
        echo -e "${YELLOW}  → Consider migrating these to Istio VirtualServices${NC}"
    else
        echo -e "${GREEN}  ✓ No Kubernetes Ingress resources (using Istio only)${NC}"
    fi

    echo ""
}

# Function to provide recommendations
provide_recommendations() {
    echo ""
    echo -e "${BOLD}Recommendations:${NC}"
    echo "=================================="

    if [ "$nginx_detected" = true ]; then
        echo -e "${YELLOW}1. Remove nginx-ingress controller${NC}"
        echo "   SIAB uses Istio for all ingress traffic."
        echo "   Run: ./scripts/remove-nginx-ingress.sh"
        echo ""
        echo -e "${YELLOW}2. Migrate any Ingress resources to Istio VirtualServices${NC}"
        echo "   See: docs/istio-migration.md"
        echo ""
    fi

    if [ "$istio_healthy" = false ]; then
        echo -e "${YELLOW}3. Fix Istio installation${NC}"
        echo "   Istio is not fully operational."
        echo "   Run: ./install.sh (it will skip already-installed components)"
        echo ""
    fi

    if [ "$nginx_detected" = false ] && [ "$istio_healthy" = true ]; then
        echo -e "${GREEN}✓ Your ingress configuration looks good!${NC}"
        echo "  All traffic is properly routed through Istio."
        echo ""
        echo "  Access points:"
        echo "  - Admin gateway: kubectl get svc istio-ingress-admin -n istio-system"
        echo "  - User gateway: kubectl get svc istio-ingress-user -n istio-system"
    fi
}

# Main execution
nginx_detected=false
istio_healthy=true

if check_nginx_ingress; then
    nginx_detected=true
fi

if ! check_istio; then
    istio_healthy=false
fi

check_traffic_routing

provide_recommendations

echo ""
echo -e "${BOLD}Diagnostic complete!${NC}"

# Exit with error code if issues found
if [ "$nginx_detected" = true ] || [ "$istio_healthy" = false ]; then
    exit 1
fi

exit 0
