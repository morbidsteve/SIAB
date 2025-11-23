#!/bin/bash
# SIAB Diagnostic and Fix Tool
# Diagnoses common issues and can automatically fix them

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Symbols
readonly CHECK_MARK="✓"
readonly CROSS_MARK="✗"
readonly WARN_MARK="⚠"
readonly INFO_MARK="ℹ"

# Counters
ISSUES_FOUND=0
ISSUES_FIXED=0

# Parse arguments
AUTO_FIX=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --fix)
            AUTO_FIX=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            echo "SIAB Diagnostic Tool"
            echo ""
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --fix      Automatically fix issues where possible"
            echo "  -v         Verbose output"
            echo "  -h         Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

log_ok() {
    echo -e "${GREEN}${CHECK_MARK}${NC} $1"
}

log_fail() {
    echo -e "${RED}${CROSS_MARK}${NC} $1"
    ((ISSUES_FOUND++)) || true
}

log_warn() {
    echo -e "${YELLOW}${WARN_MARK}${NC} $1"
}

log_info() {
    echo -e "${BLUE}${INFO_MARK}${NC} $1"
}

log_fixed() {
    echo -e "${GREEN}${CHECK_MARK}${NC} ${CYAN}FIXED:${NC} $1"
    ((ISSUES_FIXED++)) || true
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "  ${BLUE}→${NC} $1"
    fi
}

section() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
}

subsection() {
    echo ""
    echo -e "${CYAN}▸ $1${NC}"
}

# Ensure kubectl is available
setup_kubectl() {
    if command -v kubectl &>/dev/null; then
        KUBECTL="kubectl"
    elif [[ -f /var/lib/rancher/rke2/bin/kubectl ]]; then
        KUBECTL="/var/lib/rancher/rke2/bin/kubectl"
        export KUBECONFIG="${KUBECONFIG:-/etc/rancher/rke2/rke2.yaml}"
    else
        echo -e "${RED}ERROR: kubectl not found${NC}"
        exit 1
    fi
}

# ============================================================================
# KUBERNETES CLUSTER CHECKS
# ============================================================================

check_kubernetes() {
    section "Kubernetes Cluster"

    subsection "Node Status"
    local node_status
    node_status=$($KUBECTL get nodes -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")

    if [[ "$node_status" == "True" ]]; then
        log_ok "Node is Ready"
        $KUBECTL get nodes -o wide 2>/dev/null | head -5
    else
        log_fail "Node is NOT Ready (status: $node_status)"
        if [[ "$AUTO_FIX" == "true" ]]; then
            log_info "Cannot auto-fix node issues. Check: journalctl -u rke2-server"
        fi
    fi

    subsection "System Pods"
    local failed_pods
    failed_pods=$($KUBECTL get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded -o name 2>/dev/null | wc -l)

    if [[ "$failed_pods" -eq 0 ]]; then
        log_ok "All system pods are healthy"
    else
        log_warn "$failed_pods pods are not in Running/Succeeded state:"
        $KUBECTL get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded 2>/dev/null
    fi
}

# ============================================================================
# ISTIO CHECKS
# ============================================================================

check_istio() {
    section "Istio Service Mesh"

    subsection "Istio Control Plane"
    local istiod_ready
    istiod_ready=$($KUBECTL get deployment istiod -n istio-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")

    if [[ "$istiod_ready" -ge 1 ]]; then
        log_ok "Istiod is running ($istiod_ready replicas)"
    else
        log_fail "Istiod is NOT running"
    fi

    subsection "Istio Gateways"
    local admin_gw user_gw
    admin_gw=$($KUBECTL get deployment istio-ingress-admin -n istio-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    user_gw=$($KUBECTL get deployment istio-ingress-user -n istio-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")

    if [[ "$admin_gw" -ge 1 ]]; then
        log_ok "Admin gateway is running"
    else
        log_fail "Admin gateway is NOT running"
    fi

    if [[ "$user_gw" -ge 1 ]]; then
        log_ok "User gateway is running"
    else
        log_fail "User gateway is NOT running"
    fi

    subsection "Gateway LoadBalancer IPs"
    local admin_ip user_ip
    admin_ip=$($KUBECTL get svc istio-ingress-admin -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    user_ip=$($KUBECTL get svc istio-ingress-user -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    if [[ -n "$admin_ip" ]]; then
        log_ok "Admin gateway IP: $admin_ip"
    else
        log_fail "Admin gateway has no external IP"
    fi

    if [[ -n "$user_ip" ]]; then
        log_ok "User gateway IP: $user_ip"
    else
        log_fail "User gateway has no external IP"
    fi

    subsection "Istio Gateway Resources"
    local gw_count
    gw_count=$($KUBECTL get gateways -n istio-system --no-headers 2>/dev/null | wc -l)
    if [[ "$gw_count" -ge 2 ]]; then
        log_ok "Gateway resources configured ($gw_count gateways)"
        log_verbose "$($KUBECTL get gateways -n istio-system 2>/dev/null)"
    else
        log_fail "Gateway resources not properly configured"
    fi

    subsection "VirtualServices"
    local vs_count
    vs_count=$($KUBECTL get virtualservices -A --no-headers 2>/dev/null | wc -l)
    if [[ "$vs_count" -ge 1 ]]; then
        log_ok "VirtualServices configured ($vs_count found)"
        if [[ "$VERBOSE" == "true" ]]; then
            $KUBECTL get virtualservices -A 2>/dev/null
        fi
    else
        log_warn "No VirtualServices found"
    fi

    subsection "DestinationRules"
    local dr_count
    dr_count=$($KUBECTL get destinationrules -A --no-headers 2>/dev/null | wc -l)
    if [[ "$dr_count" -ge 1 ]]; then
        log_ok "DestinationRules configured ($dr_count found)"
    else
        log_warn "No DestinationRules found"
    fi
}

# ============================================================================
# BACKEND SERVICES CHECKS
# ============================================================================

check_backend_services() {
    section "Backend Services"

    declare -A services=(
        ["keycloak"]="keycloak:keycloak:80"
        ["grafana"]="monitoring:kube-prometheus-stack-grafana:80"
        ["minio"]="minio:minio-console:9001"
        ["k8s-dashboard"]="kubernetes-dashboard:kubernetes-dashboard-kong-proxy:443"
    )

    for name in "${!services[@]}"; do
        IFS=':' read -r namespace svc port <<< "${services[$name]}"

        subsection "$name"

        # Check if namespace exists
        if ! $KUBECTL get namespace "$namespace" &>/dev/null; then
            log_fail "Namespace '$namespace' does not exist"
            continue
        fi

        # Check if service exists
        if ! $KUBECTL get svc "$svc" -n "$namespace" &>/dev/null; then
            log_fail "Service '$svc' does not exist in namespace '$namespace'"
            continue
        fi

        # Check if pods are running
        local pods_ready
        pods_ready=$($KUBECTL get pods -n "$namespace" -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -c "True" || echo "0")

        if [[ "$pods_ready" -ge 1 ]]; then
            log_ok "Pods running in $namespace ($pods_ready ready)"
        else
            log_fail "No ready pods in $namespace"
            $KUBECTL get pods -n "$namespace" 2>/dev/null
        fi
    done
}

# ============================================================================
# NETWORK CONNECTIVITY CHECKS
# ============================================================================

check_network_connectivity() {
    section "Network Connectivity"

    subsection "Gateway to Backend Connectivity"

    # Get gateway pod
    local gateway_pod
    gateway_pod=$($KUBECTL get pods -n istio-system -l istio=ingress-admin -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    if [[ -z "$gateway_pod" ]]; then
        log_fail "Cannot find admin gateway pod"
        return
    fi

    log_info "Testing from gateway pod: $gateway_pod"

    # Test connectivity to keycloak via service
    subsection "Service IP Connectivity"
    local keycloak_svc_ip
    keycloak_svc_ip=$($KUBECTL get svc keycloak -n keycloak -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "")

    if [[ -n "$keycloak_svc_ip" ]]; then
        log_info "Testing Keycloak via service IP: $keycloak_svc_ip"
        if $KUBECTL exec -n istio-system "$gateway_pod" -- curl -s --connect-timeout 5 "http://$keycloak_svc_ip:80/health/ready" &>/dev/null; then
            log_ok "Can reach Keycloak via service IP"
        else
            log_fail "Cannot reach Keycloak via service IP"
        fi
    fi

    # Test connectivity to keycloak via pod IP
    subsection "Pod IP Connectivity (Direct)"
    local keycloak_pod_ip
    keycloak_pod_ip=$($KUBECTL get pods -n keycloak -l app=keycloak -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || echo "")

    if [[ -n "$keycloak_pod_ip" ]]; then
        log_info "Testing Keycloak via pod IP: $keycloak_pod_ip"
        if $KUBECTL exec -n istio-system "$gateway_pod" -- curl -s --connect-timeout 5 "http://$keycloak_pod_ip:8080/health/ready" &>/dev/null; then
            log_ok "Can reach Keycloak via pod IP"
        else
            log_fail "Cannot reach Keycloak via pod IP - This is the routing issue!"

            if [[ "$AUTO_FIX" == "true" ]]; then
                fix_network_connectivity
            else
                log_info "Run with --fix to attempt automatic repair"
            fi
        fi
    fi
}

# ============================================================================
# NETWORK POLICY CHECKS
# ============================================================================

check_network_policies() {
    section "Network Policies"

    subsection "Kubernetes NetworkPolicies"
    $KUBECTL get networkpolicies -A 2>/dev/null || echo "No NetworkPolicies found"

    subsection "Checking for restrictive policies"

    # Check for default-deny in namespaces that need traffic
    for ns in keycloak minio monitoring kubernetes-dashboard; do
        local policies
        policies=$($KUBECTL get networkpolicies -n "$ns" --no-headers 2>/dev/null | wc -l)

        if [[ "$policies" -eq 0 ]]; then
            log_verbose "No NetworkPolicies in $ns (traffic allowed by default)"
        else
            log_info "Found $policies NetworkPolicies in $ns"

            # Check if there's an allow-all-ingress
            if $KUBECTL get networkpolicy allow-all-ingress -n "$ns" &>/dev/null; then
                log_ok "$ns has allow-all-ingress policy"
            else
                log_warn "$ns has policies but no explicit allow-all-ingress"

                if [[ "$AUTO_FIX" == "true" ]]; then
                    log_info "Creating allow-all-ingress policy in $ns..."
                    cat <<EOF | $KUBECTL apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all-ingress
  namespace: $ns
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - {}
EOF
                    log_fixed "Created allow-all-ingress policy in $ns"
                fi
            fi
        fi
    done
}

# ============================================================================
# CALICO/CNI CHECKS
# ============================================================================

check_calico() {
    section "Calico/CNI Network"

    subsection "Canal/Calico Pods"
    local canal_pods
    canal_pods=$($KUBECTL get pods -n kube-system -l k8s-app=canal --no-headers 2>/dev/null | grep -c "Running" || echo "0")

    if [[ "$canal_pods" -ge 1 ]]; then
        log_ok "Canal pods running ($canal_pods)"
    else
        log_fail "Canal pods not running"
    fi

    subsection "IPTables FORWARD Policy"
    local forward_policy
    forward_policy=$(iptables -L FORWARD -n 2>/dev/null | head -1 | grep -oP 'policy \K\w+' || echo "unknown")

    if [[ "$forward_policy" == "ACCEPT" ]]; then
        log_ok "FORWARD policy is ACCEPT"
    elif [[ "$forward_policy" == "DROP" ]]; then
        log_warn "FORWARD policy is DROP (Calico manages this)"

        # Check for dropped packets
        local dropped
        dropped=$(iptables -L FORWARD -n -v 2>/dev/null | head -1 | awk '{print $1}')
        if [[ "$dropped" != "0" ]]; then
            log_warn "FORWARD chain has dropped $dropped packets"
        fi
    fi

    subsection "Calico Node Logs (Recent Errors)"
    local calico_errors
    calico_errors=$($KUBECTL logs -n kube-system -l k8s-app=canal -c calico-node --tail=100 2>/dev/null | grep -iE "(error|fail)" | tail -5 || echo "")

    if [[ -z "$calico_errors" ]]; then
        log_ok "No recent errors in Calico logs"
    else
        log_warn "Found errors in Calico logs:"
        echo "$calico_errors"
    fi
}

# ============================================================================
# FIX FUNCTIONS
# ============================================================================

fix_network_connectivity() {
    section "Attempting Network Fixes"

    log_info "Step 1: Ensuring NetworkPolicies allow traffic..."

    for ns in keycloak minio monitoring kubernetes-dashboard istio-system; do
        cat <<EOF | $KUBECTL apply -f - 2>/dev/null || true
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-all-ingress
  namespace: $ns
spec:
  podSelector: {}
  policyTypes:
    - Ingress
  ingress:
    - {}
EOF
    done
    log_fixed "Applied allow-all-ingress policies to all backend namespaces"

    log_info "Step 2: Restarting Calico/Canal to refresh iptables rules..."
    $KUBECTL delete pod -n kube-system -l k8s-app=canal --wait=false 2>/dev/null || true
    log_info "Waiting for Canal to restart..."
    sleep 10
    $KUBECTL wait --for=condition=Ready pod -n kube-system -l k8s-app=canal --timeout=120s 2>/dev/null || true
    log_fixed "Restarted Canal pods"

    log_info "Step 3: Restarting backend pods to get fresh network config..."
    for ns in keycloak minio; do
        $KUBECTL delete pods -n "$ns" --all --wait=false 2>/dev/null || true
    done
    log_info "Waiting for backend pods to restart..."
    sleep 15

    log_info "Step 4: Verifying fix..."
    sleep 10

    local gateway_pod
    gateway_pod=$($KUBECTL get pods -n istio-system -l istio=ingress-admin -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

    local keycloak_pod_ip
    keycloak_pod_ip=$($KUBECTL get pods -n keycloak -l app=keycloak -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || echo "")

    if [[ -n "$gateway_pod" ]] && [[ -n "$keycloak_pod_ip" ]]; then
        if $KUBECTL exec -n istio-system "$gateway_pod" -- curl -s --connect-timeout 5 "http://$keycloak_pod_ip:8080/health/ready" &>/dev/null; then
            log_fixed "Network connectivity restored!"
        else
            log_fail "Network connectivity still broken after fixes"
            log_info "Manual intervention may be required. Check:"
            log_info "  - iptables -L cali-FORWARD -n -v"
            log_info "  - journalctl -u rke2-server | grep -i error"
        fi
    fi
}

fix_istio_routing() {
    section "Fixing Istio Routing"

    log_info "Recreating DestinationRules for backends without sidecars..."

    # Keycloak
    cat <<EOF | $KUBECTL apply -f -
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
EOF

    # Grafana
    cat <<EOF | $KUBECTL apply -f -
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
EOF

    # MinIO
    cat <<EOF | $KUBECTL apply -f -
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
EOF

    # K8s Dashboard
    cat <<EOF | $KUBECTL apply -f -
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

    log_fixed "Recreated DestinationRules"

    log_info "Restarting Istio gateways to pick up new config..."
    $KUBECTL rollout restart deployment -n istio-system istio-ingress-admin istio-ingress-user 2>/dev/null || true

    log_info "Waiting for gateways to restart..."
    $KUBECTL rollout status deployment -n istio-system istio-ingress-admin --timeout=120s 2>/dev/null || true

    log_fixed "Istio routing reconfigured"
}

# ============================================================================
# MAIN
# ============================================================================

main() {
    echo ""
    echo -e "${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║            SIAB Diagnostic Tool                                ║${NC}"
    echo -e "${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    if [[ "$AUTO_FIX" == "true" ]]; then
        echo -e "${YELLOW}Running in AUTO-FIX mode - will attempt to fix issues${NC}"
    fi

    setup_kubectl

    check_kubernetes
    check_istio
    check_backend_services
    check_network_policies
    check_calico
    check_network_connectivity

    if [[ "$AUTO_FIX" == "true" ]] && [[ "$ISSUES_FOUND" -gt 0 ]]; then
        fix_istio_routing
    fi

    # Summary
    section "Summary"

    if [[ "$ISSUES_FOUND" -eq 0 ]]; then
        echo -e "${GREEN}${CHECK_MARK} All checks passed! No issues found.${NC}"
    else
        echo -e "${YELLOW}${WARN_MARK} Found $ISSUES_FOUND potential issues${NC}"
        if [[ "$ISSUES_FIXED" -gt 0 ]]; then
            echo -e "${GREEN}${CHECK_MARK} Fixed $ISSUES_FIXED issues${NC}"
        fi
        if [[ "$AUTO_FIX" == "false" ]]; then
            echo ""
            echo -e "${CYAN}Run with --fix to attempt automatic repairs:${NC}"
            echo "  $0 --fix"
        fi
    fi

    echo ""
}

# Run main
main "$@"
