#!/bin/bash
# SIAB Comprehensive Test Suite
# Tests all components, endpoints, storage, and networking

set -o pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Test results tracking
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNED=0
FAILED_TESTS=()
WARNED_TESTS=()

# Ensure kubectl is available
if ! command -v kubectl &> /dev/null; then
    export PATH=$PATH:/var/lib/rancher/rke2/bin:/usr/local/bin
fi

# Check kubeconfig
if [[ -f /etc/rancher/rke2/rke2.yaml ]] && [[ ! -f ~/.kube/config ]]; then
    export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
fi

# Get configuration
SIAB_DOMAIN="${SIAB_DOMAIN:-siab.local}"
if [[ -f /etc/siab/credentials.env ]]; then
    source /etc/siab/credentials.env 2>/dev/null
fi

# Get gateway IPs
ADMIN_GATEWAY_IP=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
USER_GATEWAY_IP=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)

# Test helper functions
print_header() {
    echo ""
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║  $1${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_test() {
    echo -e "${BLUE}▸ Testing:${NC} $1"
}

pass_test() {
    echo -e "  ${GREEN}✓ PASS${NC} - $1"
    ((TESTS_PASSED++))
}

fail_test() {
    echo -e "  ${RED}✗ FAIL${NC} - $1"
    ((TESTS_FAILED++))
    FAILED_TESTS+=("$1")
}

warn_test() {
    echo -e "  ${YELLOW}⚠ WARN${NC} - $1"
    ((TESTS_WARNED++))
    WARNED_TESTS+=("$1")
}

# Test functions
test_prerequisites() {
    print_header "1. Prerequisites & Environment"

    print_test "kubectl available"
    if command -v kubectl &> /dev/null; then
        pass_test "kubectl found at $(command -v kubectl)"
    else
        fail_test "kubectl not found in PATH"
        return 1
    fi

    print_test "Kubernetes cluster access"
    if kubectl cluster-info &> /dev/null; then
        pass_test "Cluster is accessible"
    else
        fail_test "Cannot access Kubernetes cluster"
        return 1
    fi

    print_test "helm available"
    if command -v helm &> /dev/null; then
        pass_test "helm found at $(command -v helm)"
    else
        warn_test "helm not found (optional but recommended)"
    fi
}

test_core_namespaces() {
    print_header "2. Core Namespaces"

    local namespaces=(
        "kube-system"
        "istio-system"
        "siab-system"
        "metallb-system"
        "cert-manager"
        "keycloak"
        "minio"
        "monitoring"
        "longhorn-system"
        "trivy-system"
        "gatekeeper-system"
    )

    for ns in "${namespaces[@]}"; do
        print_test "Namespace: $ns"
        if kubectl get namespace "$ns" &> /dev/null; then
            pass_test "Namespace $ns exists"
        else
            fail_test "Namespace $ns not found"
        fi
    done
}

test_metallb_loadbalancer() {
    print_header "3. MetalLB Load Balancer"

    print_test "MetalLB controller deployment"
    if kubectl get deployment -n metallb-system controller &> /dev/null; then
        local replicas=$(kubectl get deployment -n metallb-system controller -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
        if [[ "$replicas" -ge 1 ]]; then
            pass_test "MetalLB controller is running ($replicas replicas)"
        else
            fail_test "MetalLB controller not ready"
        fi
    else
        fail_test "MetalLB controller not found"
    fi

    print_test "MetalLB speaker daemonset"
    if kubectl get daemonset -n metallb-system speaker &> /dev/null; then
        local ready=$(kubectl get daemonset -n metallb-system speaker -o jsonpath='{.status.numberReady}' 2>/dev/null)
        local desired=$(kubectl get daemonset -n metallb-system speaker -o jsonpath='{.status.desiredNumberScheduled}' 2>/dev/null)
        if [[ "$ready" -eq "$desired" ]] && [[ "$ready" -gt 0 ]]; then
            pass_test "MetalLB speaker running on $ready/$desired nodes"
        else
            fail_test "MetalLB speaker not ready ($ready/$desired)"
        fi
    else
        fail_test "MetalLB speaker not found"
    fi

    print_test "IP address pools configured"
    local pools=$(kubectl get ipaddresspool -n metallb-system --no-headers 2>/dev/null | wc -l)
    if [[ "$pools" -ge 2 ]]; then
        pass_test "Found $pools IP address pools"
        kubectl get ipaddresspool -n metallb-system -o custom-columns=NAME:.metadata.name,ADDRESSES:.spec.addresses --no-headers 2>/dev/null | while read -r line; do
            echo "    $line"
        done
    else
        fail_test "Expected 2 IP pools, found $pools"
    fi

    print_test "L2 advertisement configured"
    if kubectl get l2advertisement -n metallb-system &> /dev/null; then
        pass_test "L2 advertisement configured"
    else
        fail_test "L2 advertisement not found"
    fi
}

test_istio_gateways() {
    print_header "4. Istio Service Mesh & Gateways"

    print_test "Istio control plane (istiod)"
    if kubectl get deployment -n istio-system istiod &> /dev/null; then
        local replicas=$(kubectl get deployment -n istio-system istiod -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
        if [[ "$replicas" -ge 1 ]]; then
            pass_test "istiod running ($replicas replicas)"
        else
            fail_test "istiod not ready"
        fi
    else
        fail_test "istiod not found"
    fi

    print_test "Admin ingress gateway deployment"
    if kubectl get deployment -n istio-system istio-ingress-admin &> /dev/null; then
        local replicas=$(kubectl get deployment -n istio-system istio-ingress-admin -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
        if [[ "$replicas" -ge 1 ]]; then
            pass_test "Admin gateway running ($replicas replicas)"
        else
            fail_test "Admin gateway not ready"
        fi
    else
        fail_test "Admin gateway deployment not found"
    fi

    print_test "User ingress gateway deployment"
    if kubectl get deployment -n istio-system istio-ingress-user &> /dev/null; then
        local replicas=$(kubectl get deployment -n istio-system istio-ingress-user -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
        if [[ "$replicas" -ge 1 ]]; then
            pass_test "User gateway running ($replicas replicas)"
        else
            fail_test "User gateway not ready"
        fi
    else
        fail_test "User gateway deployment not found"
    fi

    print_test "Admin gateway LoadBalancer IP"
    if [[ -n "$ADMIN_GATEWAY_IP" ]]; then
        pass_test "Admin gateway IP: $ADMIN_GATEWAY_IP"
    else
        fail_test "Admin gateway has no external IP assigned"
    fi

    print_test "User gateway LoadBalancer IP"
    if [[ -n "$USER_GATEWAY_IP" ]]; then
        pass_test "User gateway IP: $USER_GATEWAY_IP"
    else
        fail_test "User gateway has no external IP assigned"
    fi

    print_test "Gateway resources"
    local gateways=$(kubectl get gateway -n istio-system --no-headers 2>/dev/null | wc -l)
    if [[ "$gateways" -ge 2 ]]; then
        pass_test "Found $gateways Istio Gateway resources"
        kubectl get gateway -n istio-system -o custom-columns=NAME:.metadata.name,HOSTS:.spec.hosts --no-headers 2>/dev/null | while read -r line; do
            echo "    $line"
        done
    else
        fail_test "Expected 2 gateways (admin, user), found $gateways"
    fi

    print_test "VirtualServices configured"
    local vs_count=$(kubectl get virtualservice -A --no-headers 2>/dev/null | wc -l)
    if [[ "$vs_count" -gt 0 ]]; then
        pass_test "Found $vs_count VirtualService resources"
    else
        warn_test "No VirtualServices found"
    fi
}

test_storage_systems() {
    print_header "5. Storage Systems"

    # MinIO
    print_test "MinIO deployment"
    if kubectl get deployment -n minio minio &> /dev/null; then
        local replicas=$(kubectl get deployment -n minio minio -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
        if [[ "$replicas" -ge 1 ]]; then
            pass_test "MinIO running ($replicas replicas)"
        else
            fail_test "MinIO not ready"
        fi
    else
        fail_test "MinIO deployment not found"
    fi

    print_test "MinIO console service"
    if kubectl get svc -n minio minio-console &> /dev/null; then
        pass_test "MinIO console service exists"
    else
        warn_test "MinIO console service not found"
    fi

    # Longhorn
    print_test "Longhorn manager deployment"
    if kubectl get deployment -n longhorn-system longhorn-driver-deployer &> /dev/null; then
        pass_test "Longhorn driver deployer found"
    else
        warn_test "Longhorn driver deployer not found"
    fi

    print_test "Longhorn storage class"
    if kubectl get storageclass longhorn &> /dev/null; then
        local is_default=$(kubectl get storageclass longhorn -o jsonpath='{.metadata.annotations.storageclass\.kubernetes\.io/is-default-class}' 2>/dev/null)
        if [[ "$is_default" == "true" ]]; then
            pass_test "Longhorn is the default StorageClass"
        else
            pass_test "Longhorn StorageClass exists (not default)"
        fi
    else
        warn_test "Longhorn StorageClass not found"
    fi

    # Test PVC creation
    print_test "Storage provisioning (test PVC)"
    cat <<EOF | kubectl apply -f - &> /dev/null
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: siab-test-pvc
  namespace: default
spec:
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 1Gi
EOF
    sleep 3
    local pvc_status=$(kubectl get pvc -n default siab-test-pvc -o jsonpath='{.status.phase}' 2>/dev/null)
    if [[ "$pvc_status" == "Bound" ]]; then
        pass_test "Test PVC successfully bound"
        kubectl delete pvc -n default siab-test-pvc &> /dev/null
    else
        warn_test "Test PVC status: $pvc_status (expected: Bound)"
        kubectl delete pvc -n default siab-test-pvc &> /dev/null
    fi
}

test_security_components() {
    print_header "6. Security Components"

    print_test "Trivy Operator"
    if kubectl get deployment -n trivy-system trivy-operator &> /dev/null; then
        local replicas=$(kubectl get deployment -n trivy-system trivy-operator -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
        if [[ "$replicas" -ge 1 ]]; then
            pass_test "Trivy Operator running ($replicas replicas)"
        else
            fail_test "Trivy Operator not ready"
        fi
    else
        warn_test "Trivy Operator not found"
    fi

    print_test "OPA Gatekeeper"
    if kubectl get deployment -n gatekeeper-system gatekeeper-controller-manager &> /dev/null; then
        local replicas=$(kubectl get deployment -n gatekeeper-system gatekeeper-controller-manager -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
        if [[ "$replicas" -ge 1 ]]; then
            pass_test "Gatekeeper running ($replicas replicas)"
        else
            fail_test "Gatekeeper not ready"
        fi
    else
        warn_test "Gatekeeper not found"
    fi

    print_test "Cert-Manager"
    if kubectl get deployment -n cert-manager cert-manager &> /dev/null; then
        local replicas=$(kubectl get deployment -n cert-manager cert-manager -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
        if [[ "$replicas" -ge 1 ]]; then
            pass_test "cert-manager running ($replicas replicas)"
        else
            fail_test "cert-manager not ready"
        fi
    else
        fail_test "cert-manager not found"
    fi

    print_test "TLS certificates"
    local certs=$(kubectl get certificate -A --no-headers 2>/dev/null | wc -l)
    if [[ "$certs" -gt 0 ]]; then
        pass_test "Found $certs TLS certificate(s)"
        local ready_certs=$(kubectl get certificate -A --no-headers 2>/dev/null | grep -c "True" || true)
        if [[ "$ready_certs" -eq "$certs" ]]; then
            pass_test "All certificates are ready ($ready_certs/$certs)"
        else
            warn_test "Some certificates not ready ($ready_certs/$certs)"
        fi
    else
        warn_test "No TLS certificates found"
    fi
}

test_authentication() {
    print_header "7. Authentication (Keycloak)"

    print_test "Keycloak deployment"
    if kubectl get deployment -n keycloak keycloak &> /dev/null; then
        local replicas=$(kubectl get deployment -n keycloak keycloak -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
        if [[ "$replicas" -ge 1 ]]; then
            pass_test "Keycloak running ($replicas replicas)"
        else
            fail_test "Keycloak not ready"
        fi
    elif kubectl get statefulset -n keycloak keycloak &> /dev/null; then
        local replicas=$(kubectl get statefulset -n keycloak keycloak -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
        if [[ "$replicas" -ge 1 ]]; then
            pass_test "Keycloak running ($replicas replicas)"
        else
            fail_test "Keycloak not ready"
        fi
    else
        fail_test "Keycloak not found"
    fi

    print_test "Keycloak service"
    if kubectl get svc -n keycloak keycloak &> /dev/null; then
        pass_test "Keycloak service exists"
    else
        fail_test "Keycloak service not found"
    fi
}

test_monitoring() {
    print_header "8. Monitoring Stack"

    print_test "Prometheus deployment"
    local prom_pods=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=prometheus --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$prom_pods" -gt 0 ]]; then
        pass_test "Prometheus running ($prom_pods pods)"
    else
        warn_test "Prometheus not found or not running"
    fi

    print_test "Grafana deployment"
    if kubectl get deployment -n monitoring kube-prometheus-stack-grafana &> /dev/null; then
        local replicas=$(kubectl get deployment -n monitoring kube-prometheus-stack-grafana -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
        if [[ "$replicas" -ge 1 ]]; then
            pass_test "Grafana running ($replicas replicas)"
        else
            fail_test "Grafana not ready"
        fi
    else
        warn_test "Grafana deployment not found"
    fi
}

test_dashboard() {
    print_header "9. SIAB Dashboard"

    print_test "Dashboard deployment"
    if kubectl get deployment -n siab-system siab-dashboard &> /dev/null; then
        local replicas=$(kubectl get deployment -n siab-system siab-dashboard -o jsonpath='{.status.availableReplicas}' 2>/dev/null)
        if [[ "$replicas" -ge 1 ]]; then
            pass_test "Dashboard running ($replicas replicas)"
        else
            fail_test "Dashboard not ready"
        fi
    else
        fail_test "Dashboard deployment not found"
    fi

    print_test "Dashboard service"
    if kubectl get svc -n siab-system siab-dashboard &> /dev/null; then
        pass_test "Dashboard service exists"
    else
        fail_test "Dashboard service not found"
    fi

    print_test "Dashboard VirtualService"
    if kubectl get virtualservice -n istio-system siab-dashboard &> /dev/null; then
        pass_test "Dashboard VirtualService configured"
    else
        fail_test "Dashboard VirtualService not found"
    fi
}

test_endpoint_connectivity() {
    print_header "10. Endpoint Connectivity Tests"

    if [[ -z "$ADMIN_GATEWAY_IP" ]] || [[ -z "$USER_GATEWAY_IP" ]]; then
        fail_test "Gateway IPs not available, skipping connectivity tests"
        return 1
    fi

    # Test admin endpoints
    local admin_endpoints=(
        "https://${ADMIN_GATEWAY_IP}:443|keycloak.${SIAB_DOMAIN}|Keycloak"
        "https://${ADMIN_GATEWAY_IP}:443|minio.${SIAB_DOMAIN}|MinIO"
        "https://${ADMIN_GATEWAY_IP}:443|grafana.${SIAB_DOMAIN}|Grafana"
        "https://${ADMIN_GATEWAY_IP}:443|k8s-dashboard.${SIAB_DOMAIN}|K8s Dashboard"
        "https://${ADMIN_GATEWAY_IP}:443|longhorn.${SIAB_DOMAIN}|Longhorn"
    )

    echo -e "${BLUE}Admin Gateway Endpoints (${ADMIN_GATEWAY_IP}):${NC}"
    for endpoint in "${admin_endpoints[@]}"; do
        IFS='|' read -r url host name <<< "$endpoint"
        print_test "$name endpoint"
        if timeout 5 curl -skL -H "Host: $host" "$url" -o /dev/null -w "%{http_code}" 2>/dev/null | grep -qE "^(200|301|302|401|403)"; then
            pass_test "$name responding at $host"
        else
            warn_test "$name not responding at $host (may need proper DNS/hosts entry)"
        fi
    done

    # Test user endpoints
    local user_endpoints=(
        "https://${USER_GATEWAY_IP}:443|dashboard.${SIAB_DOMAIN}|Dashboard"
        "https://${USER_GATEWAY_IP}:443|${SIAB_DOMAIN}|Main Site"
        "https://${USER_GATEWAY_IP}:443|catalog.${SIAB_DOMAIN}|Catalog"
    )

    echo ""
    echo -e "${BLUE}User Gateway Endpoints (${USER_GATEWAY_IP}):${NC}"
    for endpoint in "${user_endpoints[@]}"; do
        IFS='|' read -r url host name <<< "$endpoint"
        print_test "$name endpoint"
        if timeout 5 curl -skL -H "Host: $host" "$url" -o /dev/null -w "%{http_code}" 2>/dev/null | grep -qE "^(200|301|302)"; then
            pass_test "$name responding at $host"
        else
            warn_test "$name not responding at $host (may need proper DNS/hosts entry)"
        fi
    done
}

test_network_policies() {
    print_header "11. Network Policies"

    print_test "Network policies configured"
    local netpol_count=$(kubectl get networkpolicy -A --no-headers 2>/dev/null | wc -l)
    if [[ "$netpol_count" -gt 0 ]]; then
        pass_test "Found $netpol_count NetworkPolicy resources"
    else
        warn_test "No NetworkPolicies found"
    fi
}

test_pod_health() {
    print_header "12. Overall Pod Health"

    print_test "Pods in CrashLoopBackOff"
    local crash_pods=$(kubectl get pods -A --field-selector=status.phase!=Succeeded --no-headers 2>/dev/null | grep -c "CrashLoopBackOff" || echo "0")
    if [[ "$crash_pods" -eq 0 ]]; then
        pass_test "No pods in CrashLoopBackOff"
    else
        fail_test "$crash_pods pod(s) in CrashLoopBackOff"
        kubectl get pods -A --field-selector=status.phase!=Succeeded --no-headers 2>/dev/null | grep "CrashLoopBackOff" | while read -r line; do
            echo "    $line"
        done
    fi

    print_test "Pods in Error state"
    local error_pods=$(kubectl get pods -A --field-selector=status.phase=Failed --no-headers 2>/dev/null | wc -l)
    if [[ "$error_pods" -eq 0 ]]; then
        pass_test "No pods in Error state"
    else
        fail_test "$error_pods pod(s) in Error state"
    fi

    print_test "Pods not Running (excluding Completed)"
    local pending_pods=$(kubectl get pods -A --field-selector=status.phase=Pending --no-headers 2>/dev/null | wc -l)
    if [[ "$pending_pods" -eq 0 ]]; then
        pass_test "No pods stuck in Pending state"
    else
        warn_test "$pending_pods pod(s) in Pending state"
        kubectl get pods -A --field-selector=status.phase=Pending --no-headers 2>/dev/null | while read -r line; do
            echo "    $line"
        done
    fi
}

test_dns_resolution() {
    print_header "13. DNS Resolution (Internal)"

    print_test "CoreDNS pods running"
    local coredns_pods=$(kubectl get pods -n kube-system -l k8s-app=kube-dns --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    if [[ "$coredns_pods" -gt 0 ]]; then
        pass_test "CoreDNS running ($coredns_pods pods)"
    else
        fail_test "CoreDNS not running"
    fi

    print_test "Service DNS resolution"
    if kubectl run -n default test-dns-resolution --image=busybox:1.28 --restart=Never --rm -i --command -- nslookup kubernetes.default.svc.cluster.local &> /dev/null; then
        pass_test "DNS resolution working (kubernetes.default.svc.cluster.local)"
    else
        fail_test "DNS resolution failed"
    fi
}

test_rbac_permissions() {
    print_header "14. RBAC & Service Accounts"

    print_test "Required ClusterRoles"
    local cluster_roles=$(kubectl get clusterrole --no-headers 2>/dev/null | wc -l)
    if [[ "$cluster_roles" -gt 10 ]]; then
        pass_test "Found $cluster_roles ClusterRoles"
    else
        warn_test "Only $cluster_roles ClusterRoles found"
    fi

    print_test "Service accounts in siab-system"
    local sa_count=$(kubectl get sa -n siab-system --no-headers 2>/dev/null | wc -l)
    if [[ "$sa_count" -gt 0 ]]; then
        pass_test "Found $sa_count service account(s)"
    else
        warn_test "No custom service accounts in siab-system"
    fi
}

# Main execution
main() {
    clear
    echo -e "${CYAN}"
    cat << "EOF"
╔═══════════════════════════════════════════════════════════════╗
║                                                               ║
║              SIAB Comprehensive Test Suite                   ║
║         Secure Infrastructure as a Box - Validator           ║
║                                                               ║
╚═══════════════════════════════════════════════════════════════╝
EOF
    echo -e "${NC}"

    echo "Starting SIAB validation tests..."
    echo "Gateway IPs: Admin=$ADMIN_GATEWAY_IP, User=$USER_GATEWAY_IP"
    echo "Domain: $SIAB_DOMAIN"
    echo ""

    # Run all tests
    test_prerequisites || exit 1
    test_core_namespaces
    test_metallb_loadbalancer
    test_istio_gateways
    test_storage_systems
    test_security_components
    test_authentication
    test_monitoring
    test_dashboard
    test_endpoint_connectivity
    test_network_policies
    test_pod_health
    test_dns_resolution
    test_rbac_permissions

    # Summary
    print_header "Test Summary"

    local total_tests=$((TESTS_PASSED + TESTS_FAILED + TESTS_WARNED))

    echo -e "${GREEN}Passed:${NC}  $TESTS_PASSED / $total_tests"
    echo -e "${YELLOW}Warnings:${NC} $TESTS_WARNED / $total_tests"
    echo -e "${RED}Failed:${NC}  $TESTS_FAILED / $total_tests"
    echo ""

    if [[ "$TESTS_FAILED" -gt 0 ]]; then
        echo -e "${RED}Failed Tests:${NC}"
        for test in "${FAILED_TESTS[@]}"; do
            echo -e "  ${RED}✗${NC} $test"
        done
        echo ""
    fi

    if [[ "$TESTS_WARNED" -gt 0 ]]; then
        echo -e "${YELLOW}Warnings:${NC}"
        for test in "${WARNED_TESTS[@]}"; do
            echo -e "  ${YELLOW}⚠${NC} $test"
        done
        echo ""
    fi

    # Overall result
    if [[ "$TESTS_FAILED" -eq 0 ]]; then
        echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║           ✓ ALL TESTS PASSED - SIAB IS HEALTHY!              ║${NC}"
        echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "Next steps:"
        echo "  1. Access dashboard: https://dashboard.$SIAB_DOMAIN or https://$USER_GATEWAY_IP"
        echo "  2. Configure /etc/hosts on remote VMs (see docs/external-vm-access.md)"
        echo "  3. View credentials: sudo cat /etc/siab/credentials.env"
        echo ""
        exit 0
    else
        echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║     ✗ SOME TESTS FAILED - REVIEW ERRORS ABOVE                ║${NC}"
        echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo "Troubleshooting:"
        echo "  1. Run: sudo siab-diagnose"
        echo "  2. Check logs: kubectl logs -n istio-system -l app=istiod"
        echo "  3. View status: sudo siab-status"
        echo "  4. See docs: ./docs/external-vm-access.md"
        echo ""
        exit 1
    fi
}

# Run main function
main "$@"
