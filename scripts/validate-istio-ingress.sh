#!/bin/bash
# SIAB Istio Ingress Validation Script
# This script validates that Istio ingress is properly configured and accessible

set -euo pipefail

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly BOLD='\033[1m'
readonly NC='\033[0m' # No Color

echo -e "${BOLD}SIAB Istio Ingress Validation${NC}"
echo "=================================="
echo ""

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo -e "${RED}✗ kubectl not found. Please ensure kubectl is in your PATH.${NC}"
    exit 1
fi

validation_passed=true

# 1. Validate Istio Control Plane
echo -e "${BOLD}1. Validating Istio Control Plane${NC}"
echo ""

if ! kubectl get namespace istio-system &> /dev/null; then
    echo -e "${RED}✗ istio-system namespace not found${NC}"
    echo -e "${YELLOW}  Istio is not installed. Run: ./install.sh${NC}"
    validation_passed=false
else
    echo -e "${GREEN}✓ istio-system namespace exists${NC}"

    # Check istiod
    if kubectl get deployment istiod -n istio-system &> /dev/null; then
        ready=$(kubectl get deployment istiod -n istio-system -o jsonpath='{.status.readyReplicas}')
        desired=$(kubectl get deployment istiod -n istio-system -o jsonpath='{.status.replicas}')

        if [ "$ready" = "$desired" ] && [ "$ready" -gt 0 ]; then
            echo -e "${GREEN}✓ istiod is healthy: $ready/$desired pods ready${NC}"

            # Check istiod version
            version=$(kubectl get deployment istiod -n istio-system -o jsonpath='{.spec.template.spec.containers[0].image}' | cut -d: -f2)
            echo -e "${BLUE}  Version: $version${NC}"
        else
            echo -e "${RED}✗ istiod is not healthy: $ready/$desired pods ready${NC}"
            validation_passed=false
        fi
    else
        echo -e "${RED}✗ istiod deployment not found${NC}"
        validation_passed=false
    fi
fi

echo ""

# 2. Validate Ingress Gateways
echo -e "${BOLD}2. Validating Istio Ingress Gateways${NC}"
echo ""

# Admin Gateway
echo -e "${BLUE}Admin Gateway (for administrative interfaces):${NC}"
if kubectl get deployment istio-ingress-admin -n istio-system &> /dev/null; then
    admin_ready=$(kubectl get deployment istio-ingress-admin -n istio-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    admin_desired=$(kubectl get deployment istio-ingress-admin -n istio-system -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")

    if [ "$admin_ready" = "$admin_desired" ] && [ "$admin_ready" -gt 0 ]; then
        echo -e "${GREEN}  ✓ Deployment: $admin_ready/$admin_desired pods ready${NC}"
    else
        echo -e "${RED}  ✗ Deployment: $admin_ready/$admin_desired pods ready${NC}"
        validation_passed=false
    fi

    # Check service
    if kubectl get svc istio-ingress-admin -n istio-system &> /dev/null; then
        svc_type=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.spec.type}')
        echo -e "${GREEN}  ✓ Service type: $svc_type${NC}"

        if [ "$svc_type" = "LoadBalancer" ]; then
            lb_ip=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            if [ -n "$lb_ip" ]; then
                echo -e "${GREEN}  ✓ LoadBalancer IP: $lb_ip${NC}"
            else
                echo -e "${YELLOW}  ⚠ LoadBalancer IP not assigned yet${NC}"
            fi
        elif [ "$svc_type" = "NodePort" ]; then
            http_port=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
            https_port=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
            echo -e "${BLUE}  NodePorts: HTTP=$http_port, HTTPS=$https_port${NC}"
        fi
    else
        echo -e "${RED}  ✗ Service not found${NC}"
        validation_passed=false
    fi
else
    echo -e "${RED}  ✗ Admin gateway not found${NC}"
    validation_passed=false
fi

echo ""

# User Gateway
echo -e "${BLUE}User Gateway (for user applications):${NC}"
if kubectl get deployment istio-ingress-user -n istio-system &> /dev/null; then
    user_ready=$(kubectl get deployment istio-ingress-user -n istio-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    user_desired=$(kubectl get deployment istio-ingress-user -n istio-system -o jsonpath='{.status.replicas}' 2>/dev/null || echo "0")

    if [ "$user_ready" = "$user_desired" ] && [ "$user_ready" -gt 0 ]; then
        echo -e "${GREEN}  ✓ Deployment: $user_ready/$user_desired pods ready${NC}"
    else
        echo -e "${RED}  ✗ Deployment: $user_ready/$user_desired pods ready${NC}"
        validation_passed=false
    fi

    # Check service
    if kubectl get svc istio-ingress-user -n istio-system &> /dev/null; then
        svc_type=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.spec.type}')
        echo -e "${GREEN}  ✓ Service type: $svc_type${NC}"

        if [ "$svc_type" = "LoadBalancer" ]; then
            lb_ip=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
            if [ -n "$lb_ip" ]; then
                echo -e "${GREEN}  ✓ LoadBalancer IP: $lb_ip${NC}"
            else
                echo -e "${YELLOW}  ⚠ LoadBalancer IP not assigned yet${NC}"
            fi
        elif [ "$svc_type" = "NodePort" ]; then
            http_port=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
            https_port=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
            echo -e "${BLUE}  NodePorts: HTTP=$http_port, HTTPS=$https_port${NC}"
        fi
    else
        echo -e "${RED}  ✗ Service not found${NC}"
        validation_passed=false
    fi
else
    echo -e "${RED}  ✗ User gateway not found${NC}"
    validation_passed=false
fi

echo ""

# 3. Validate Gateway Resources
echo -e "${BOLD}3. Validating Istio Gateway Resources${NC}"
echo ""

gateway_count=$(kubectl get gateway -n istio-system 2>/dev/null --no-headers | wc -l)

if [ "$gateway_count" -gt 0 ]; then
    echo -e "${GREEN}✓ Found $gateway_count Gateway resource(s):${NC}"
    echo ""

    while IFS= read -r gateway; do
        if [ -n "$gateway" ]; then
            name=$(echo "$gateway" | awk '{print $1}')
            echo -e "${BLUE}  Gateway: $name${NC}"

            # Get hosts
            hosts=$(kubectl get gateway "$name" -n istio-system -o jsonpath='{.spec.servers[*].hosts[*]}' 2>/dev/null)
            echo -e "${GREEN}    Hosts: $hosts${NC}"

            # Get selector
            selector=$(kubectl get gateway "$name" -n istio-system -o jsonpath='{.spec.selector}' 2>/dev/null)
            echo -e "${GREEN}    Selector: $selector${NC}"
            echo ""
        fi
    done < <(kubectl get gateway -n istio-system --no-headers 2>/dev/null)
else
    echo -e "${RED}✗ No Gateway resources found${NC}"
    echo -e "${YELLOW}  Gateways define how traffic enters the mesh.${NC}"
    validation_passed=false
fi

echo ""

# 4. Validate VirtualServices
echo -e "${BOLD}4. Validating VirtualServices${NC}"
echo ""

vs_count=$(kubectl get virtualservice -A 2>/dev/null --no-headers | wc -l)

if [ "$vs_count" -gt 0 ]; then
    echo -e "${GREEN}✓ Found $vs_count VirtualService(s):${NC}"
    echo ""

    kubectl get virtualservice -A -o custom-columns=\
NAMESPACE:.metadata.namespace,\
NAME:.metadata.name,\
GATEWAYS:.spec.gateways[*],\
HOSTS:.spec.hosts[*] 2>/dev/null | head -20

    if [ "$vs_count" -gt 20 ]; then
        echo -e "${BLUE}  ... and $((vs_count - 20)) more${NC}"
    fi
else
    echo -e "${YELLOW}⚠ No VirtualServices found${NC}"
    echo -e "${YELLOW}  VirtualServices route traffic to your applications.${NC}"
fi

echo ""

# 5. Check for mTLS configuration
echo -e "${BOLD}5. Validating mTLS Configuration${NC}"
echo ""

if kubectl get peerauthentication default -n istio-system &> /dev/null; then
    mtls_mode=$(kubectl get peerauthentication default -n istio-system -o jsonpath='{.spec.mtls.mode}' 2>/dev/null)
    echo -e "${GREEN}✓ Default mTLS mode: $mtls_mode${NC}"

    if [ "$mtls_mode" = "STRICT" ]; then
        echo -e "${GREEN}  All service-to-service communication is encrypted${NC}"
    fi
else
    echo -e "${YELLOW}⚠ Default PeerAuthentication not found${NC}"
    echo -e "${YELLOW}  mTLS may not be enforced cluster-wide${NC}"
fi

echo ""

# 6. Check DestinationRules
echo -e "${BOLD}6. Validating DestinationRules${NC}"
echo ""

dr_count=$(kubectl get destinationrule -A 2>/dev/null --no-headers | wc -l)

if [ "$dr_count" -gt 0 ]; then
    echo -e "${GREEN}✓ Found $dr_count DestinationRule(s)${NC}"

    # Check for important DestinationRules
    important_drs=("istio-system" "siab-system")
    for ns in "${important_drs[@]}"; do
        if kubectl get destinationrule -n "$ns" &> /dev/null 2>&1; then
            ns_dr_count=$(kubectl get destinationrule -n "$ns" --no-headers 2>/dev/null | wc -l)
            if [ "$ns_dr_count" -gt 0 ]; then
                echo -e "${GREEN}  ✓ $ns: $ns_dr_count DestinationRule(s)${NC}"
            fi
        fi
    done
else
    echo -e "${YELLOW}⚠ No DestinationRules found${NC}"
    echo -e "${YELLOW}  DestinationRules configure traffic policies${NC}"
fi

echo ""

# 7. Test connectivity to gateways
echo -e "${BOLD}7. Testing Gateway Connectivity${NC}"
echo ""

# Get gateway IPs/ports
admin_svc_type=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.spec.type}' 2>/dev/null || echo "")
user_svc_type=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.spec.type}' 2>/dev/null || echo "")

if [ -n "$admin_svc_type" ]; then
    echo -e "${BLUE}Admin Gateway:${NC}"

    if [ "$admin_svc_type" = "LoadBalancer" ]; then
        admin_ip=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        if [ -n "$admin_ip" ]; then
            echo -e "${GREEN}  Access via: http://$admin_ip or https://$admin_ip${NC}"
        fi
    elif [ "$admin_svc_type" = "NodePort" ]; then
        http_port=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
        https_port=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
        node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
        echo -e "${GREEN}  Access via: http://$node_ip:$http_port or https://$node_ip:$https_port${NC}"
    fi
fi

if [ -n "$user_svc_type" ]; then
    echo -e "${BLUE}User Gateway:${NC}"

    if [ "$user_svc_type" = "LoadBalancer" ]; then
        user_ip=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
        if [ -n "$user_ip" ]; then
            echo -e "${GREEN}  Access via: http://$user_ip or https://$user_ip${NC}"
        fi
    elif [ "$user_svc_type" = "NodePort" ]; then
        http_port=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}')
        https_port=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')
        node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
        echo -e "${GREEN}  Access via: http://$node_ip:$http_port or https://$node_ip:$https_port${NC}"
    fi
fi

echo ""

# Summary
echo -e "${BOLD}Validation Summary${NC}"
echo "=================================="
echo ""

if [ "$validation_passed" = true ]; then
    echo -e "${GREEN}✓ All validations passed!${NC}"
    echo ""
    echo -e "${BOLD}Your Istio ingress is properly configured.${NC}"
    echo ""
    echo "To access services:"
    echo "1. Get gateway addresses:"
    echo "   kubectl get svc -n istio-system | grep istio-ingress"
    echo ""
    echo "2. Configure DNS or /etc/hosts to point hostnames to gateway IPs"
    echo ""
    echo "3. Access your services via the configured hostnames"
    echo ""
    echo "For more information:"
    echo "  kubectl get gateway -n istio-system"
    echo "  kubectl get virtualservice -A"
else
    echo -e "${RED}✗ Some validations failed${NC}"
    echo ""
    echo -e "${YELLOW}Recommended actions:${NC}"
    echo "1. Check Istio installation:"
    echo "   kubectl get pods -n istio-system"
    echo ""
    echo "2. Review logs:"
    echo "   kubectl logs -n istio-system -l app=istiod"
    echo ""
    echo "3. Reinstall if needed:"
    echo "   ./install.sh"
    echo ""
fi

exit $([ "$validation_passed" = true ] && echo 0 || echo 1)
