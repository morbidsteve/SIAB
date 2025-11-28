#!/bin/bash
# SIAB Istio Access Test Script
# Comprehensive testing of all Istio-routed services from multiple perspectives
# Tests both internal cluster access and external client access

set -euo pipefail

# Colors and formatting
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

# Symbols
readonly CHECK_MARK="✓"
readonly CROSS_MARK="✗"
readonly WARN_MARK="⚠"
readonly INFO_MARK="ℹ"
readonly ARROW="→"
readonly BULLET="•"

# Test results counters
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNED=0

# Diagnostic data collection
declare -a FAILED_TESTS=()
declare -a WARNED_TESTS=()
declare -A SERVICE_STATUS=()
declare -A DIAGNOSTIC_INFO=()

# Configuration
TIMEOUT=10
VERBOSE=false
EXTERNAL_TEST=true
INTERNAL_TEST=true
COLLECT_DIAGNOSTICS=true
OUTPUT_FILE=""
SIAB_DOMAIN="${SIAB_DOMAIN:-siab.local}"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --domain)
            SIAB_DOMAIN="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        --internal-only)
            EXTERNAL_TEST=false
            shift
            ;;
        --external-only)
            INTERNAL_TEST=false
            shift
            ;;
        --no-diagnostics)
            COLLECT_DIAGNOSTICS=false
            shift
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            cat <<EOF
SIAB Istio Access Test Script

Tests access to all Istio-routed services from multiple perspectives.

Usage: $0 [OPTIONS]

Options:
  --domain DOMAIN          SIAB domain (default: siab.local)
  --timeout SECONDS        Request timeout in seconds (default: 10)
  -v, --verbose           Verbose output with detailed diagnostics
  --internal-only         Only test internal cluster access
  --external-only         Only test external client access
  --no-diagnostics        Skip diagnostic data collection
  -o, --output FILE       Write detailed report to file
  -h, --help             Show this help

Examples:
  # Run all tests with default settings
  $0

  # Test only external access with verbose output
  $0 --external-only -v

  # Test with custom domain and save report
  $0 --domain mysiab.local -o report.txt

  # Quick internal test without diagnostics
  $0 --internal-only --no-diagnostics

EOF
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Logging functions
log_ok() {
    echo -e "${GREEN}${CHECK_MARK}${NC} $1"
}

log_fail() {
    echo -e "${RED}${CROSS_MARK}${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}${WARN_MARK}${NC} $1"
}

log_info() {
    echo -e "${BLUE}${INFO_MARK}${NC} $1"
}

log_section() {
    echo ""
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${BOLD}  $1${NC}"
    echo -e "${BOLD}═══════════════════════════════════════════════════════════════${NC}"
}

log_subsection() {
    echo ""
    echo -e "${CYAN}${BOLD}▸ $1${NC}"
}

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "  ${DIM}${ARROW}${NC} $1"
    fi
}

log_diagnostic() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "  ${MAGENTA}${BULLET}${NC} ${DIM}$1${NC}"
    fi
}

# Test result tracking
record_test_pass() {
    local name="$1"
    ((TESTS_RUN++))
    ((TESTS_PASSED++))
    SERVICE_STATUS["$name"]="PASS"
}

record_test_fail() {
    local name="$1"
    local reason="$2"
    ((TESTS_RUN++))
    ((TESTS_FAILED++))
    SERVICE_STATUS["$name"]="FAIL"
    FAILED_TESTS+=("$name: $reason")
}

record_test_warn() {
    local name="$1"
    local reason="$2"
    ((TESTS_RUN++))
    ((TESTS_WARNED++))
    SERVICE_STATUS["$name"]="WARN"
    WARNED_TESTS+=("$name: $reason")
}

# Ensure kubectl is available
check_kubectl() {
    if ! command -v kubectl &>/dev/null; then
        log_fail "kubectl not found in PATH"
        echo ""
        echo "This script requires kubectl to be installed and configured."
        echo "Please install kubectl: https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi

    # Test cluster connectivity
    if ! kubectl cluster-info &>/dev/null; then
        log_fail "Cannot connect to Kubernetes cluster"
        echo ""
        echo "kubectl is installed but cannot connect to the cluster."
        echo "Please check your kubeconfig and cluster connectivity."
        exit 1
    fi
}

# Collect diagnostic information
collect_istio_diagnostics() {
    if [[ "$COLLECT_DIAGNOSTICS" != "true" ]]; then
        return
    fi

    log_subsection "Collecting Istio Diagnostics"

    # Istio version
    if command -v istioctl &>/dev/null; then
        DIAGNOSTIC_INFO["istio_version"]=$(istioctl version --short 2>/dev/null || echo "unknown")
        log_verbose "Istio version: ${DIAGNOSTIC_INFO[istio_version]}"
    else
        DIAGNOSTIC_INFO["istio_version"]="istioctl not available"
        log_verbose "istioctl not found"
    fi

    # Control plane status
    log_diagnostic "Checking Istio control plane..."
    local istiod_ready=$(kubectl get deploy istiod -n istio-system -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
    local istiod_desired=$(kubectl get deploy istiod -n istio-system -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "0")
    DIAGNOSTIC_INFO["istiod_status"]="$istiod_ready/$istiod_desired ready"
    log_verbose "Istiod: ${DIAGNOSTIC_INFO[istiod_status]}"

    # Gateway pods status
    log_diagnostic "Checking gateway pods..."
    local admin_gw_pods=$(kubectl get pods -n istio-system -l istio=ingress-admin --no-headers 2>/dev/null | wc -l)
    local admin_gw_ready=$(kubectl get pods -n istio-system -l istio=ingress-admin --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    DIAGNOSTIC_INFO["admin_gateway_pods"]="$admin_gw_ready/$admin_gw_pods ready"

    local user_gw_pods=$(kubectl get pods -n istio-system -l istio=ingress-user --no-headers 2>/dev/null | wc -l)
    local user_gw_ready=$(kubectl get pods -n istio-system -l istio=ingress-user --no-headers 2>/dev/null | grep -c "Running" || echo "0")
    DIAGNOSTIC_INFO["user_gateway_pods"]="$user_gw_ready/$user_gw_pods ready"

    log_verbose "Admin Gateway: ${DIAGNOSTIC_INFO[admin_gateway_pods]}"
    log_verbose "User Gateway: ${DIAGNOSTIC_INFO[user_gateway_pods]}"

    # Gateway services
    log_diagnostic "Checking gateway services..."
    DIAGNOSTIC_INFO["admin_gateway_ip"]=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [[ -z "${DIAGNOSTIC_INFO[admin_gateway_ip]}" ]]; then
        DIAGNOSTIC_INFO["admin_gateway_ip"]=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "none")
    fi

    DIAGNOSTIC_INFO["user_gateway_ip"]=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [[ -z "${DIAGNOSTIC_INFO[user_gateway_ip]}" ]]; then
        DIAGNOSTIC_INFO["user_gateway_ip"]=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.spec.clusterIP}' 2>/dev/null || echo "none")
    fi

    log_verbose "Admin Gateway IP: ${DIAGNOSTIC_INFO[admin_gateway_ip]}"
    log_verbose "User Gateway IP: ${DIAGNOSTIC_INFO[user_gateway_ip]}"

    # Gateway NodePorts (if applicable)
    local admin_http_nodeport=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null || echo "")
    local admin_https_nodeport=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}' 2>/dev/null || echo "")
    local user_http_nodeport=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.spec.ports[?(@.name=="http")].nodePort}' 2>/dev/null || echo "")
    local user_https_nodeport=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}' 2>/dev/null || echo "")

    DIAGNOSTIC_INFO["admin_http_nodeport"]="$admin_http_nodeport"
    DIAGNOSTIC_INFO["admin_https_nodeport"]="$admin_https_nodeport"
    DIAGNOSTIC_INFO["user_http_nodeport"]="$user_http_nodeport"
    DIAGNOSTIC_INFO["user_https_nodeport"]="$user_https_nodeport"

    if [[ -n "$admin_http_nodeport" ]]; then
        log_verbose "Admin Gateway NodePort (HTTP): $admin_http_nodeport"
    fi
    if [[ -n "$user_http_nodeport" ]]; then
        log_verbose "User Gateway NodePort (HTTP): $user_http_nodeport"
    fi

    # VirtualServices count
    local vs_count=$(kubectl get virtualservice -A --no-headers 2>/dev/null | wc -l)
    DIAGNOSTIC_INFO["virtualservices_count"]="$vs_count"
    log_verbose "VirtualServices configured: $vs_count"

    # Gateways count
    local gw_count=$(kubectl get gateway -A --no-headers 2>/dev/null | wc -l)
    DIAGNOSTIC_INFO["gateways_count"]="$gw_count"
    log_verbose "Gateways configured: $gw_count"

    # DestinationRules count
    local dr_count=$(kubectl get destinationrule -A --no-headers 2>/dev/null | wc -l)
    DIAGNOSTIC_INFO["destinationrules_count"]="$dr_count"
    log_verbose "DestinationRules configured: $dr_count"

    # Check mTLS mode
    log_diagnostic "Checking mTLS configuration..."
    local mtls_mode=$(kubectl get peerauthentication -n istio-system default -o jsonpath='{.spec.mtls.mode}' 2>/dev/null || echo "not configured")
    DIAGNOSTIC_INFO["mtls_mode"]="$mtls_mode"
    log_verbose "mTLS mode: $mtls_mode"
}

# Test internal cluster access (from within the cluster)
test_internal_access() {
    log_subsection "Testing Internal Cluster Access"

    # Test dashboard service directly
    log_diagnostic "Testing siab-dashboard service..."
    if kubectl get svc siab-dashboard -n siab-system &>/dev/null; then
        local dashboard_ip=$(kubectl get svc siab-dashboard -n siab-system -o jsonpath='{.spec.clusterIP}')
        log_verbose "Dashboard ClusterIP: $dashboard_ip"

        # Try to access the service using a test pod
        local test_result=$(kubectl run test-curl-$$ --rm -i --restart=Never --image=curlimages/curl:latest -- \
            curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 \
            "http://siab-dashboard.siab-system.svc.cluster.local/health" 2>/dev/null || echo "000")

        if [[ "$test_result" == "200" ]]; then
            log_ok "Dashboard service accessible internally (HTTP $test_result)"
            record_test_pass "internal_dashboard_service"
        else
            log_fail "Dashboard service not accessible internally (HTTP $test_result)"
            record_test_fail "internal_dashboard_service" "HTTP $test_result"
        fi
    else
        log_fail "Dashboard service not found in siab-system namespace"
        record_test_fail "internal_dashboard_service" "Service not found"
    fi

    # Test catalog service
    log_diagnostic "Testing catalog service..."
    if kubectl get svc catalog-frontend -n siab-catalog &>/dev/null; then
        local catalog_ip=$(kubectl get svc catalog-frontend -n siab-catalog -o jsonpath='{.spec.clusterIP}')
        log_verbose "Catalog ClusterIP: $catalog_ip"

        local test_result=$(kubectl run test-curl-$$ --rm -i --restart=Never --image=curlimages/curl:latest -- \
            curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 \
            "http://catalog-frontend.siab-catalog.svc.cluster.local/" 2>/dev/null || echo "000")

        if [[ "$test_result" == "200" || "$test_result" == "301" || "$test_result" == "302" ]]; then
            log_ok "Catalog service accessible internally (HTTP $test_result)"
            record_test_pass "internal_catalog_service"
        else
            log_fail "Catalog service not accessible internally (HTTP $test_result)"
            record_test_fail "internal_catalog_service" "HTTP $test_result"
        fi
    else
        log_warn "Catalog service not found (may not be deployed yet)"
        record_test_warn "internal_catalog_service" "Service not found"
    fi

    # Test gateway services
    log_diagnostic "Testing gateway services..."

    # Admin gateway
    if kubectl get svc istio-ingress-admin -n istio-system &>/dev/null; then
        local admin_gw_ip=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.spec.clusterIP}')
        log_verbose "Admin Gateway ClusterIP: $admin_gw_ip"

        local test_result=$(kubectl run test-curl-$$ --rm -i --restart=Never --image=curlimages/curl:latest -- \
            curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 \
            "http://$admin_gw_ip" 2>/dev/null || echo "000")

        # Gateway itself will return various codes, we just want connectivity
        if [[ "$test_result" != "000" ]]; then
            log_ok "Admin gateway service reachable (HTTP $test_result)"
            record_test_pass "internal_admin_gateway"
        else
            log_fail "Admin gateway service not reachable"
            record_test_fail "internal_admin_gateway" "Connection failed"
        fi
    else
        log_fail "Admin gateway service not found"
        record_test_fail "internal_admin_gateway" "Service not found"
    fi

    # User gateway
    if kubectl get svc istio-ingress-user -n istio-system &>/dev/null; then
        local user_gw_ip=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.spec.clusterIP}')
        log_verbose "User Gateway ClusterIP: $user_gw_ip"

        local test_result=$(kubectl run test-curl-$$ --rm -i --restart=Never --image=curlimages/curl:latest -- \
            curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 \
            "http://$user_gw_ip" 2>/dev/null || echo "000")

        if [[ "$test_result" != "000" ]]; then
            log_ok "User gateway service reachable (HTTP $test_result)"
            record_test_pass "internal_user_gateway"
        else
            log_fail "User gateway service not reachable"
            record_test_fail "internal_user_gateway" "Connection failed"
        fi
    else
        log_fail "User gateway service not found"
        record_test_fail "internal_user_gateway" "Service not found"
    fi
}

# Test VirtualService routing through gateways
test_virtualservice_routing() {
    log_subsection "Testing VirtualService Routing"

    # Get gateway IPs/endpoints
    local user_gw_ip="${DIAGNOSTIC_INFO[user_gateway_ip]:-}"
    local admin_gw_ip="${DIAGNOSTIC_INFO[admin_gateway_ip]:-}"

    if [[ -z "$user_gw_ip" ]] || [[ "$user_gw_ip" == "none" ]]; then
        log_warn "User gateway IP not available, skipping VirtualService routing tests"
        return
    fi

    # Define services to test through user gateway
    declare -A user_services=(
        ["dashboard"]="dashboard.$SIAB_DOMAIN"
        ["catalog"]="catalog.$SIAB_DOMAIN"
        ["siab_root"]="$SIAB_DOMAIN"
    )

    for service_name in "${!user_services[@]}"; do
        local hostname="${user_services[$service_name]}"
        log_diagnostic "Testing VirtualService for $hostname..."

        # Test via gateway with Host header
        local test_result=$(kubectl run test-curl-$$ --rm -i --restart=Never --image=curlimages/curl:latest -- \
            curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$TIMEOUT" \
            -H "Host: $hostname" \
            "http://$user_gw_ip/" 2>/dev/null || echo "000")

        log_verbose "$hostname → HTTP $test_result"

        if [[ "$test_result" == "200" ]]; then
            log_ok "VirtualService routing for $hostname working (HTTP $test_result)"
            record_test_pass "vs_$service_name"
        elif [[ "$test_result" == "301" || "$test_result" == "302" ]]; then
            log_ok "VirtualService routing for $hostname responding with redirect (HTTP $test_result)"
            record_test_pass "vs_$service_name"
        elif [[ "$test_result" == "404" ]]; then
            log_warn "VirtualService for $hostname returns 404 (service may not be deployed)"
            record_test_warn "vs_$service_name" "HTTP 404 - service not deployed?"
        elif [[ "$test_result" == "503" ]]; then
            log_fail "VirtualService for $hostname returns 503 (upstream unavailable)"
            record_test_fail "vs_$service_name" "HTTP 503 - upstream unavailable"
            DIAGNOSTIC_INFO["vs_${service_name}_error"]="503: Check if backend pods are running and ready"
        else
            log_fail "VirtualService routing for $hostname failed (HTTP $test_result)"
            record_test_fail "vs_$service_name" "HTTP $test_result"
        fi
    done

    # Test admin gateway services if admin IP is available
    if [[ -n "$admin_gw_ip" ]] && [[ "$admin_gw_ip" != "none" ]]; then
        declare -A admin_services=(
            ["grafana"]="grafana.$SIAB_DOMAIN"
            ["keycloak"]="keycloak.$SIAB_DOMAIN"
        )

        for service_name in "${!admin_services[@]}"; do
            local hostname="${admin_services[$service_name]}"
            log_diagnostic "Testing VirtualService for $hostname..."

            local test_result=$(kubectl run test-curl-$$ --rm -i --restart=Never --image=curlimages/curl:latest -- \
                curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$TIMEOUT" \
                -H "Host: $hostname" \
                "http://$admin_gw_ip/" 2>/dev/null || echo "000")

            log_verbose "$hostname → HTTP $test_result"

            if [[ "$test_result" == "200" || "$test_result" == "301" || "$test_result" == "302" ]]; then
                log_ok "VirtualService routing for $hostname working (HTTP $test_result)"
                record_test_pass "vs_admin_$service_name"
            elif [[ "$test_result" == "404" ]]; then
                log_warn "VirtualService for $hostname returns 404 (service may not be deployed)"
                record_test_warn "vs_admin_$service_name" "HTTP 404 - service not deployed?"
            else
                log_fail "VirtualService routing for $hostname failed (HTTP $test_result)"
                record_test_fail "vs_admin_$service_name" "HTTP $test_result"
            fi
        done
    fi
}

# Test external access (from client perspective)
test_external_access() {
    log_subsection "Testing External Client Access"

    # Get node IP for NodePort access
    local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "")

    if [[ -z "$node_ip" ]]; then
        log_warn "Cannot determine node IP, skipping external NodePort tests"
        return
    fi

    log_verbose "Node IP: $node_ip"

    # Test user gateway NodePort access
    local user_http_nodeport="${DIAGNOSTIC_INFO[user_http_nodeport]:-}"

    if [[ -n "$user_http_nodeport" ]]; then
        log_diagnostic "Testing external access via NodePort $user_http_nodeport..."

        # Test dashboard
        local test_result=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$TIMEOUT" \
            -H "Host: dashboard.$SIAB_DOMAIN" \
            "http://$node_ip:$user_http_nodeport/" 2>/dev/null || echo "000")

        log_verbose "External dashboard access → HTTP $test_result"

        if [[ "$test_result" == "200" || "$test_result" == "301" || "$test_result" == "302" ]]; then
            log_ok "Dashboard accessible externally via NodePort (HTTP $test_result)"
            record_test_pass "external_dashboard_nodeport"
        elif [[ "$test_result" == "404" ]]; then
            log_warn "Dashboard returns 404 via NodePort (check VirtualService configuration)"
            record_test_warn "external_dashboard_nodeport" "HTTP 404"
        else
            log_fail "Dashboard not accessible externally via NodePort (HTTP $test_result)"
            record_test_fail "external_dashboard_nodeport" "HTTP $test_result"
        fi

        # Test catalog
        test_result=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$TIMEOUT" \
            -H "Host: catalog.$SIAB_DOMAIN" \
            "http://$node_ip:$user_http_nodeport/" 2>/dev/null || echo "000")

        log_verbose "External catalog access → HTTP $test_result"

        if [[ "$test_result" == "200" || "$test_result" == "301" || "$test_result" == "302" ]]; then
            log_ok "Catalog accessible externally via NodePort (HTTP $test_result)"
            record_test_pass "external_catalog_nodeport"
        elif [[ "$test_result" == "404" ]]; then
            log_warn "Catalog returns 404 via NodePort"
            record_test_warn "external_catalog_nodeport" "HTTP 404"
        else
            log_fail "Catalog not accessible externally via NodePort (HTTP $test_result)"
            record_test_fail "external_catalog_nodeport" "HTTP $test_result"
        fi
    else
        log_warn "User gateway NodePort not configured, skipping NodePort tests"
    fi

    # Test LoadBalancer IP access if available
    local user_lb_ip="${DIAGNOSTIC_INFO[user_gateway_ip]:-}"

    # Check if it's actually a LoadBalancer IP (not ClusterIP)
    local user_gw_type=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.spec.type}' 2>/dev/null || echo "")

    if [[ "$user_gw_type" == "LoadBalancer" ]] && [[ -n "$user_lb_ip" ]] && [[ "$user_lb_ip" != "none" ]]; then
        log_diagnostic "Testing external access via LoadBalancer IP $user_lb_ip..."

        local test_result=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout "$TIMEOUT" \
            -H "Host: dashboard.$SIAB_DOMAIN" \
            "http://$user_lb_ip/" 2>/dev/null || echo "000")

        if [[ "$test_result" == "200" || "$test_result" == "301" || "$test_result" == "302" ]]; then
            log_ok "Services accessible via LoadBalancer IP (HTTP $test_result)"
            record_test_pass "external_loadbalancer"
        else
            log_fail "Services not accessible via LoadBalancer IP (HTTP $test_result)"
            record_test_fail "external_loadbalancer" "HTTP $test_result"
        fi
    else
        log_verbose "LoadBalancer not configured (using NodePort mode)"
    fi
}

# Check backend pod health
check_backend_health() {
    log_subsection "Checking Backend Service Health"

    # Dashboard pods
    log_diagnostic "Checking dashboard pods..."
    local dashboard_pods=$(kubectl get pods -n siab-system -l app=siab-dashboard --no-headers 2>/dev/null || echo "")

    if [[ -n "$dashboard_pods" ]]; then
        local running_count=$(echo "$dashboard_pods" | grep -c "Running" || echo "0")
        local total_count=$(echo "$dashboard_pods" | wc -l)

        log_verbose "Dashboard pods: $running_count/$total_count running"

        if [[ "$running_count" -gt 0 ]]; then
            log_ok "Dashboard pods are running ($running_count/$total_count)"
            record_test_pass "backend_dashboard_pods"
        else
            log_fail "No dashboard pods are running"
            record_test_fail "backend_dashboard_pods" "No running pods"

            # Collect pod details
            if [[ "$VERBOSE" == "true" ]]; then
                log_diagnostic "Dashboard pod details:"
                kubectl get pods -n siab-system -l app=siab-dashboard | while read -r line; do
                    log_diagnostic "  $line"
                done
            fi
        fi
    else
        log_warn "No dashboard pods found (may not be deployed yet)"
        record_test_warn "backend_dashboard_pods" "No pods found"
    fi

    # Catalog pods
    log_diagnostic "Checking catalog pods..."
    local catalog_pods=$(kubectl get pods -n siab-catalog --no-headers 2>/dev/null || echo "")

    if [[ -n "$catalog_pods" ]]; then
        local running_count=$(echo "$catalog_pods" | grep -c "Running" || echo "0")
        local total_count=$(echo "$catalog_pods" | wc -l)

        log_verbose "Catalog pods: $running_count/$total_count running"

        if [[ "$running_count" -gt 0 ]]; then
            log_ok "Catalog pods are running ($running_count/$total_count)"
            record_test_pass "backend_catalog_pods"
        else
            log_warn "No catalog pods are running"
            record_test_warn "backend_catalog_pods" "No running pods"
        fi
    else
        log_verbose "Catalog not deployed"
    fi
}

# Analyze VirtualService configurations
analyze_virtualservices() {
    log_subsection "Analyzing VirtualService Configurations"

    local vs_list=$(kubectl get virtualservice -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name,GATEWAYS:.spec.gateways[*],HOSTS:.spec.hosts[*] --no-headers 2>/dev/null || echo "")

    if [[ -z "$vs_list" ]]; then
        log_fail "No VirtualServices found in the cluster"
        record_test_fail "config_virtualservices" "No VirtualServices configured"
        return
    fi

    local vs_count=$(echo "$vs_list" | wc -l)
    log_ok "Found $vs_count VirtualService(s)"

    if [[ "$VERBOSE" == "true" ]]; then
        echo "$vs_list" | while read -r line; do
            log_diagnostic "$line"
        done
    fi

    # Check for essential VirtualServices
    if echo "$vs_list" | grep -q "dashboard"; then
        log_ok "Dashboard VirtualService exists"
        record_test_pass "config_vs_dashboard"
    else
        log_fail "Dashboard VirtualService not found"
        record_test_fail "config_vs_dashboard" "VirtualService missing"
    fi

    if echo "$vs_list" | grep -q "catalog"; then
        log_ok "Catalog VirtualService exists"
        record_test_pass "config_vs_catalog"
    else
        log_warn "Catalog VirtualService not found"
        record_test_warn "config_vs_catalog" "VirtualService missing"
    fi
}

# Check for common configuration issues
check_common_issues() {
    log_subsection "Checking for Common Configuration Issues"

    # Check for DestinationRules
    log_diagnostic "Checking DestinationRules..."
    local dr_count=$(kubectl get destinationrule -A --no-headers 2>/dev/null | wc -l)

    if [[ "$dr_count" -gt 0 ]]; then
        log_ok "DestinationRules configured ($dr_count found)"

        # Check for mTLS in DestinationRules
        local mtls_rules=$(kubectl get destinationrule -A -o yaml 2>/dev/null | grep -c "mode: ISTIO_MUTUAL" || echo "0")
        if [[ "$mtls_rules" -gt 0 ]]; then
            log_verbose "mTLS enabled in $mtls_rules DestinationRule(s)"
        fi
    else
        log_warn "No DestinationRules found - this may cause mTLS issues"
        record_test_warn "config_destinationrules" "No DestinationRules configured"
    fi

    # Check for PeerAuthentication
    log_diagnostic "Checking PeerAuthentication..."
    if kubectl get peerauthentication -n istio-system default &>/dev/null; then
        log_ok "Default PeerAuthentication policy exists"
        record_test_pass "config_peerauthentication"
    else
        log_warn "Default PeerAuthentication policy not found"
        record_test_warn "config_peerauthentication" "Policy not configured"
    fi

    # Check for NetworkPolicies that might block traffic
    log_diagnostic "Checking NetworkPolicies..."
    local netpol_count=$(kubectl get networkpolicy -A --no-headers 2>/dev/null | wc -l)
    if [[ "$netpol_count" -gt 0 ]]; then
        log_verbose "NetworkPolicies configured: $netpol_count"
        DIAGNOSTIC_INFO["networkpolicies_count"]="$netpol_count"
    fi

    # Check istio-injection labels
    log_diagnostic "Checking namespace injection labels..."
    local siab_system_injection=$(kubectl get namespace siab-system -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null || echo "")
    local siab_catalog_injection=$(kubectl get namespace siab-catalog -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null || echo "")

    if [[ "$siab_system_injection" == "enabled" ]]; then
        log_ok "siab-system namespace has Istio injection enabled"
    else
        log_warn "siab-system namespace does not have Istio injection enabled"
        DIAGNOSTIC_INFO["siab_system_injection"]="disabled"
    fi

    if [[ "$siab_catalog_injection" == "enabled" ]]; then
        log_ok "siab-catalog namespace has Istio injection enabled"
    else
        log_verbose "siab-catalog namespace injection: ${siab_catalog_injection:-disabled}"
    fi
}

# Print detailed diagnostic summary
print_diagnostic_summary() {
    log_section "Diagnostic Summary"

    echo -e "${BOLD}Istio Components:${NC}"
    echo -e "  Istio Version: ${DIAGNOSTIC_INFO[istio_version]:-unknown}"
    echo -e "  Istiod Status: ${DIAGNOSTIC_INFO[istiod_status]:-unknown}"
    echo -e "  Admin Gateway: ${DIAGNOSTIC_INFO[admin_gateway_pods]:-unknown} pods, IP: ${DIAGNOSTIC_INFO[admin_gateway_ip]:-none}"
    echo -e "  User Gateway:  ${DIAGNOSTIC_INFO[user_gateway_pods]:-unknown} pods, IP: ${DIAGNOSTIC_INFO[user_gateway_ip]:-none}"

    if [[ -n "${DIAGNOSTIC_INFO[user_http_nodeport]}" ]]; then
        echo -e "  User NodePort: ${DIAGNOSTIC_INFO[user_http_nodeport]} (HTTP)"
    fi

    echo ""
    echo -e "${BOLD}Configuration:${NC}"
    echo -e "  VirtualServices: ${DIAGNOSTIC_INFO[virtualservices_count]:-0}"
    echo -e "  Gateways: ${DIAGNOSTIC_INFO[gateways_count]:-0}"
    echo -e "  DestinationRules: ${DIAGNOSTIC_INFO[destinationrules_count]:-0}"
    echo -e "  mTLS Mode: ${DIAGNOSTIC_INFO[mtls_mode]:-unknown}"

    if [[ -n "${DIAGNOSTIC_INFO[networkpolicies_count]}" ]]; then
        echo -e "  NetworkPolicies: ${DIAGNOSTIC_INFO[networkpolicies_count]}"
    fi
}

# Print test results summary
print_test_summary() {
    log_section "Test Results Summary"

    echo -e "${BOLD}Tests Run:${NC} $TESTS_RUN"
    echo -e "${GREEN}${BOLD}Passed:${NC} $TESTS_PASSED"
    echo -e "${YELLOW}${BOLD}Warnings:${NC} $TESTS_WARNED"
    echo -e "${RED}${BOLD}Failed:${NC} $TESTS_FAILED"

    if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
        echo ""
        echo -e "${RED}${BOLD}Failed Tests:${NC}"
        for failure in "${FAILED_TESTS[@]}"; do
            echo -e "  ${RED}${CROSS_MARK}${NC} $failure"
        done
    fi

    if [[ ${#WARNED_TESTS[@]} -gt 0 ]]; then
        echo ""
        echo -e "${YELLOW}${BOLD}Warnings:${NC}"
        for warning in "${WARNED_TESTS[@]}"; do
            echo -e "  ${YELLOW}${WARN_MARK}${NC} $warning"
        done
    fi
}

# Print recommendations
print_recommendations() {
    if [[ $TESTS_FAILED -eq 0 ]]; then
        return
    fi

    log_section "Recommendations"

    # Analyze failures and provide specific recommendations
    local has_vs_failures=false
    local has_backend_failures=false
    local has_gateway_failures=false

    for test_name in "${!SERVICE_STATUS[@]}"; do
        if [[ "${SERVICE_STATUS[$test_name]}" == "FAIL" ]]; then
            if [[ "$test_name" == vs_* ]]; then
                has_vs_failures=true
            elif [[ "$test_name" == backend_* ]]; then
                has_backend_failures=true
            elif [[ "$test_name" == *gateway* ]]; then
                has_gateway_failures=true
            fi
        fi
    done

    if [[ "$has_backend_failures" == "true" ]]; then
        echo -e "${YELLOW}${WARN_MARK}${NC} ${BOLD}Backend pods are not running${NC}"
        echo -e "  ${ARROW} Check pod status: ${CYAN}kubectl get pods -n siab-system${NC}"
        echo -e "  ${ARROW} Check pod logs: ${CYAN}kubectl logs -n siab-system -l app=siab-dashboard${NC}"
        echo -e "  ${ARROW} Describe pods: ${CYAN}kubectl describe pods -n siab-system -l app=siab-dashboard${NC}"
        echo ""
    fi

    if [[ "$has_gateway_failures" == "true" ]]; then
        echo -e "${YELLOW}${WARN_MARK}${NC} ${BOLD}Gateway connectivity issues${NC}"
        echo -e "  ${ARROW} Check gateway pods: ${CYAN}kubectl get pods -n istio-system -l istio=ingress-user${NC}"
        echo -e "  ${ARROW} Check gateway logs: ${CYAN}kubectl logs -n istio-system -l istio=ingress-user${NC}"
        echo -e "  ${ARROW} Verify gateway service: ${CYAN}kubectl get svc -n istio-system istio-ingress-user${NC}"
        echo ""
    fi

    if [[ "$has_vs_failures" == "true" ]]; then
        echo -e "${YELLOW}${WARN_MARK}${NC} ${BOLD}VirtualService routing failures${NC}"
        echo -e "  ${ARROW} Check VirtualServices: ${CYAN}kubectl get virtualservice -A${NC}"
        echo -e "  ${ARROW} Validate configuration: ${CYAN}istioctl analyze${NC}"
        echo -e "  ${ARROW} Check DestinationRules: ${CYAN}kubectl get destinationrule -A${NC}"
        echo -e "  ${ARROW} Run mTLS fix: ${CYAN}./fix-istio-mtls.sh${NC}"
        echo ""
    fi

    # Check for specific error patterns
    for key in "${!DIAGNOSTIC_INFO[@]}"; do
        if [[ "$key" == *"_error" ]]; then
            echo -e "${YELLOW}${WARN_MARK}${NC} ${DIAGNOSTIC_INFO[$key]}"
        fi
    done

    echo -e "${BOLD}General troubleshooting steps:${NC}"
    echo -e "  1. Run SIAB diagnostics: ${CYAN}./siab-diagnose.sh${NC}"
    echo -e "  2. Check Istio configuration: ${CYAN}istioctl analyze${NC}"
    echo -e "  3. Review recent events: ${CYAN}kubectl get events -A --sort-by='.lastTimestamp'${NC}"
    echo -e "  4. Check Istio proxy status: ${CYAN}istioctl proxy-status${NC}"
}

# Save report to file
save_report() {
    if [[ -z "$OUTPUT_FILE" ]]; then
        return
    fi

    log_info "Saving detailed report to $OUTPUT_FILE"

    {
        echo "SIAB Istio Access Test Report"
        echo "Generated: $(date)"
        echo "Domain: $SIAB_DOMAIN"
        echo ""
        echo "=========================================="
        echo "DIAGNOSTIC SUMMARY"
        echo "=========================================="
        echo ""
        for key in "${!DIAGNOSTIC_INFO[@]}"; do
            echo "$key: ${DIAGNOSTIC_INFO[$key]}"
        done
        echo ""
        echo "=========================================="
        echo "TEST RESULTS"
        echo "=========================================="
        echo ""
        echo "Total Tests: $TESTS_RUN"
        echo "Passed: $TESTS_PASSED"
        echo "Warnings: $TESTS_WARNED"
        echo "Failed: $TESTS_FAILED"
        echo ""

        if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
            echo "Failed Tests:"
            for failure in "${FAILED_TESTS[@]}"; do
                echo "  - $failure"
            done
            echo ""
        fi

        if [[ ${#WARNED_TESTS[@]} -gt 0 ]]; then
            echo "Warnings:"
            for warning in "${WARNED_TESTS[@]}"; do
                echo "  - $warning"
            done
            echo ""
        fi

        echo "=========================================="
        echo "DETAILED SERVICE STATUS"
        echo "=========================================="
        echo ""
        for service in "${!SERVICE_STATUS[@]}"; do
            echo "$service: ${SERVICE_STATUS[$service]}"
        done
    } > "$OUTPUT_FILE"

    log_ok "Report saved to $OUTPUT_FILE"
}

# Main execution
main() {
    log_section "SIAB Istio Access Test Suite"
    echo -e "Domain: ${BOLD}$SIAB_DOMAIN${NC}"
    echo -e "Timeout: ${BOLD}${TIMEOUT}s${NC}"
    echo -e "Tests: ${BOLD}Internal=$([ "$INTERNAL_TEST" == "true" ] && echo "✓" || echo "✗") External=$([ "$EXTERNAL_TEST" == "true" ] && echo "✓" || echo "✗")${NC}"

    # Prerequisites
    check_kubectl

    # Collect diagnostics
    collect_istio_diagnostics

    # Configuration analysis
    analyze_virtualservices
    check_common_issues

    # Backend health checks
    check_backend_health

    # Run tests
    if [[ "$INTERNAL_TEST" == "true" ]]; then
        test_internal_access
        test_virtualservice_routing
    fi

    if [[ "$EXTERNAL_TEST" == "true" ]]; then
        test_external_access
    fi

    # Print results
    echo ""
    print_diagnostic_summary
    echo ""
    print_test_summary
    echo ""
    print_recommendations

    # Save report if requested
    save_report

    # Exit with appropriate code
    echo ""
    if [[ $TESTS_FAILED -eq 0 ]]; then
        log_section "✓ All Tests Passed"
        exit 0
    else
        log_section "✗ Some Tests Failed"
        exit 1
    fi
}

# Run main
main
