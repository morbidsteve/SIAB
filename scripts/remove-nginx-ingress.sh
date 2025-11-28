#!/bin/bash
# SIAB nginx-ingress Removal Script
# This script safely removes nginx-ingress and ensures all traffic routes through Istio

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

# Dry run mode
DRY_RUN="${DRY_RUN:-false}"

echo -e "${BOLD}SIAB nginx-ingress Removal Tool${NC}"
echo "=================================="
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl not found. Please ensure kubectl is in your PATH.${NC}"
    exit 1
fi

# Confirm with user unless auto-confirmed
if [ "$DRY_RUN" = "false" ] && [ "${AUTO_CONFIRM:-false}" != "true" ]; then
    echo -e "${YELLOW}This script will remove nginx-ingress from your cluster.${NC}"
    echo -e "${YELLOW}SIAB uses Istio exclusively for ingress traffic.${NC}"
    echo ""
    echo -e "${BOLD}What will be removed:${NC}"
    echo "  - nginx-ingress-controller deployments/daemonsets"
    echo "  - nginx-ingress services"
    echo "  - nginx IngressClass resources"
    echo "  - nginx-ingress helm releases (if any)"
    echo ""
    echo -e "${BOLD}What will NOT be affected:${NC}"
    echo "  - Istio service mesh and gateways"
    echo "  - Your application deployments"
    echo "  - Kubernetes Ingress resources (they will be orphaned)"
    echo ""
    read -p "Do you want to continue? (yes/no): " -r
    if [[ ! $REPLY =~ ^[Yy][Ee][Ss]$ ]]; then
        echo "Aborted."
        exit 0
    fi
    echo ""
fi

# Dry run message
if [ "$DRY_RUN" = "true" ]; then
    echo -e "${BLUE}Running in DRY RUN mode - no changes will be made${NC}"
    echo ""
fi

# Function to execute or simulate command
run_cmd() {
    local cmd="$1"
    local description="$2"

    echo -e "${BLUE}$description${NC}"

    if [ "$DRY_RUN" = "true" ]; then
        echo -e "${YELLOW}[DRY RUN] Would execute: $cmd${NC}"
    else
        if eval "$cmd" 2>&1; then
            echo -e "${GREEN}✓ Done${NC}"
        else
            echo -e "${YELLOW}⚠ Command failed (may not exist)${NC}"
        fi
    fi
    echo ""
}

# Track what was found
found_something=false

echo -e "${BOLD}Searching for nginx-ingress components...${NC}"
echo ""

# 1. Remove helm releases
if command -v helm &> /dev/null; then
    echo -e "${BOLD}1. Checking for helm releases...${NC}"

    # Common nginx-ingress helm release names
    for release_name in nginx-ingress ingress-nginx nginx; do
        for ns in $(kubectl get namespaces -o jsonpath='{.items[*].metadata.name}'); do
            if helm list -n "$ns" -o json 2>/dev/null | jq -e ".[] | select(.name == \"$release_name\")" > /dev/null 2>&1; then
                echo -e "${YELLOW}Found helm release: $release_name in namespace $ns${NC}"
                run_cmd "helm uninstall $release_name -n $ns" "  Uninstalling helm release $release_name from $ns..."
                found_something=true
            fi
        done
    done

    if [ "$found_something" = false ]; then
        echo -e "${GREEN}✓ No nginx-ingress helm releases found${NC}"
    fi
    echo ""
else
    echo -e "${YELLOW}⚠ helm not found, skipping helm release check${NC}"
    echo ""
fi

# 2. Remove nginx-ingress deployments
echo -e "${BOLD}2. Removing nginx-ingress deployments...${NC}"
found_deployments=false

while IFS= read -r line; do
    if [ -n "$line" ]; then
        namespace=$(echo "$line" | awk '{print $1}')
        deployment=$(echo "$line" | awk '{print $2}')
        echo -e "${YELLOW}Found deployment: $deployment in namespace $namespace${NC}"
        run_cmd "kubectl delete deployment $deployment -n $namespace" "  Deleting deployment $deployment from $namespace..."
        found_deployments=true
        found_something=true
    fi
done < <(kubectl get deployment -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name --no-headers 2>/dev/null | grep -iE "nginx.*ingress|ingress.*nginx" || true)

if [ "$found_deployments" = false ]; then
    echo -e "${GREEN}✓ No nginx-ingress deployments found${NC}"
fi
echo ""

# 3. Remove nginx-ingress daemonsets
echo -e "${BOLD}3. Removing nginx-ingress daemonsets...${NC}"
found_daemonsets=false

while IFS= read -r line; do
    if [ -n "$line" ]; then
        namespace=$(echo "$line" | awk '{print $1}')
        daemonset=$(echo "$line" | awk '{print $2}')
        echo -e "${YELLOW}Found daemonset: $daemonset in namespace $namespace${NC}"
        run_cmd "kubectl delete daemonset $daemonset -n $namespace" "  Deleting daemonset $daemonset from $namespace..."
        found_daemonsets=true
        found_something=true
    fi
done < <(kubectl get daemonset -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name --no-headers 2>/dev/null | grep -iE "nginx.*ingress|ingress.*nginx" || true)

if [ "$found_daemonsets" = false ]; then
    echo -e "${GREEN}✓ No nginx-ingress daemonsets found${NC}"
fi
echo ""

# 4. Remove nginx-ingress services
echo -e "${BOLD}4. Removing nginx-ingress services...${NC}"
found_services=false

while IFS= read -r line; do
    if [ -n "$line" ]; then
        namespace=$(echo "$line" | awk '{print $1}')
        service=$(echo "$line" | awk '{print $2}')
        echo -e "${YELLOW}Found service: $service in namespace $namespace${NC}"
        run_cmd "kubectl delete service $service -n $namespace" "  Deleting service $service from $namespace..."
        found_services=true
        found_something=true
    fi
done < <(kubectl get service -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name --no-headers 2>/dev/null | grep -iE "nginx.*ingress|ingress.*nginx" || true)

if [ "$found_services" = false ]; then
    echo -e "${GREEN}✓ No nginx-ingress services found${NC}"
fi
echo ""

# 5. Remove nginx IngressClass
echo -e "${BOLD}5. Removing nginx IngressClass resources...${NC}"
found_ingressclass=false

while IFS= read -r line; do
    if [ -n "$line" ]; then
        echo -e "${YELLOW}Found IngressClass: $line${NC}"
        run_cmd "kubectl delete ingressclass $line" "  Deleting IngressClass $line..."
        found_ingressclass=true
        found_something=true
    fi
done < <(kubectl get ingressclass -o custom-columns=NAME:.metadata.name --no-headers 2>/dev/null | grep -i nginx || true)

if [ "$found_ingressclass" = false ]; then
    echo -e "${GREEN}✓ No nginx IngressClass found${NC}"
fi
echo ""

# 6. Check for orphaned Ingress resources
echo -e "${BOLD}6. Checking for Ingress resources using nginx...${NC}"
orphaned_ingress=false

while IFS= read -r line; do
    if [ -n "$line" ]; then
        echo -e "${YELLOW}Found Ingress resource using nginx: $line${NC}"
        orphaned_ingress=true
    fi
done < <(kubectl get ingress -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,CLASS:.spec.ingressClassName --no-headers 2>/dev/null | grep -i nginx || true)

if [ "$orphaned_ingress" = true ]; then
    echo -e "${YELLOW}⚠ Warning: Some Ingress resources are configured to use nginx${NC}"
    echo -e "${YELLOW}  These resources will not work after nginx-ingress is removed.${NC}"
    echo -e "${YELLOW}  You should migrate them to Istio VirtualServices.${NC}"
    echo -e "${YELLOW}  See: docs/istio-migration.md${NC}"
else
    echo -e "${GREEN}✓ No Ingress resources using nginx${NC}"
fi
echo ""

# 7. Remove common nginx-ingress namespaces (if empty)
echo -e "${BOLD}7. Cleaning up nginx-ingress namespaces...${NC}"

for ns in ingress-nginx nginx-ingress; do
    if kubectl get namespace "$ns" &> /dev/null; then
        # Check if namespace has any resources
        resource_count=$(kubectl get all -n "$ns" --no-headers 2>/dev/null | wc -l)

        if [ "$resource_count" -eq 0 ]; then
            echo -e "${YELLOW}Found empty namespace: $ns${NC}"
            run_cmd "kubectl delete namespace $ns" "  Deleting empty namespace $ns..."
            found_something=true
        else
            echo -e "${YELLOW}⚠ Namespace $ns still has resources, skipping deletion${NC}"
            echo -e "${YELLOW}  Check manually: kubectl get all -n $ns${NC}"
        fi
    fi
done
echo ""

# 8. Validate Istio is ready
echo -e "${BOLD}8. Validating Istio configuration...${NC}"

if kubectl get deployment istiod -n istio-system &> /dev/null; then
    istio_ready=$(kubectl get deployment istiod -n istio-system -o jsonpath='{.status.readyReplicas}')
    istio_desired=$(kubectl get deployment istiod -n istio-system -o jsonpath='{.status.replicas}')

    if [ "$istio_ready" = "$istio_desired" ] && [ "$istio_ready" -gt 0 ]; then
        echo -e "${GREEN}✓ Istio control plane is healthy ($istio_ready/$istio_desired)${NC}"
    else
        echo -e "${RED}✗ Istio control plane is not healthy ($istio_ready/$istio_desired)${NC}"
        echo -e "${YELLOW}  Run: kubectl get pods -n istio-system${NC}"
    fi

    # Check gateways
    if kubectl get deployment istio-ingress-admin -n istio-system &> /dev/null; then
        admin_ready=$(kubectl get deployment istio-ingress-admin -n istio-system -o jsonpath='{.status.readyReplicas}')
        echo -e "${GREEN}✓ Istio admin gateway is ready ($admin_ready pods)${NC}"
    fi

    if kubectl get deployment istio-ingress-user -n istio-system &> /dev/null; then
        user_ready=$(kubectl get deployment istio-ingress-user -n istio-system -o jsonpath='{.status.readyReplicas}')
        echo -e "${GREEN}✓ Istio user gateway is ready ($user_ready pods)${NC}"
    fi
else
    echo -e "${RED}✗ Istio is not installed!${NC}"
    echo -e "${YELLOW}  Run: ./install.sh to install SIAB with Istio${NC}"
fi
echo ""

# Summary
echo -e "${BOLD}Summary:${NC}"
echo "=================================="

if [ "$DRY_RUN" = "true" ]; then
    echo -e "${BLUE}This was a dry run. No changes were made.${NC}"
    echo -e "${BLUE}Run without DRY_RUN=true to actually remove nginx-ingress.${NC}"
elif [ "$found_something" = true ]; then
    echo -e "${GREEN}✓ nginx-ingress components have been removed${NC}"
    echo ""
    echo -e "${BOLD}Next steps:${NC}"
    echo "1. Verify Istio gateways are working:"
    echo "   kubectl get svc -n istio-system | grep istio-ingress"
    echo ""
    echo "2. Check that your applications are accessible via Istio:"
    echo "   kubectl get virtualservice -A"
    echo ""
    echo "3. If you had Ingress resources, migrate them to VirtualServices"
    echo "   See: docs/istio-migration.md"
else
    echo -e "${GREEN}✓ No nginx-ingress components found${NC}"
    echo -e "${GREEN}Your cluster is already using Istio exclusively!${NC}"
fi

echo ""
echo -e "${BOLD}For more information:${NC}"
echo "  - Run diagnostics: ./scripts/diagnose-ingress.sh"
echo "  - Check Istio status: kubectl get pods -n istio-system"
echo "  - View gateways: kubectl get gateway -n istio-system"
echo ""
