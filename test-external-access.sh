#!/bin/bash
# SIAB External Client Access Test
# Run this script from a CLIENT machine (not the K8s host)
# Tests access to Istio-routed services from outside the cluster

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

# Configuration
K8S_HOST=""
ADMIN_NODEPORT=""
USER_NODEPORT=""
ADMIN_IP=""
USER_IP=""
SIAB_DOMAIN="siab.local"
TIMEOUT=10
VERBOSE=false
TEST_HTTPS=false

# Test results
TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
declare -a FAILED_TESTS=()

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --k8s-host)
            K8S_HOST="$2"
            shift 2
            ;;
        --admin-nodeport)
            ADMIN_NODEPORT="$2"
            shift 2
            ;;
        --user-nodeport)
            USER_NODEPORT="$2"
            shift 2
            ;;
        --admin-ip)
            ADMIN_IP="$2"
            shift 2
            ;;
        --user-ip)
            USER_IP="$2"
            shift 2
            ;;
        --domain)
            SIAB_DOMAIN="$2"
            shift 2
            ;;
        --timeout)
            TIMEOUT="$2"
            shift 2
            ;;
        --https)
            TEST_HTTPS=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            cat <<EOF
SIAB External Client Access Test

Run this from a CLIENT machine to test access to SIAB services.

Usage: $0 --k8s-host <HOST> [OPTIONS]

Required:
  --k8s-host HOST          K8s node IP or hostname

Gateway Access (provide at least one):
  --admin-nodeport PORT    Admin gateway NodePort (default: auto-detect)
  --user-nodeport PORT     User gateway NodePort (default: auto-detect)
  --admin-ip IP           Admin gateway LoadBalancer IP
  --user-ip IP            User gateway LoadBalancer IP

Optional:
  --domain DOMAIN         SIAB domain (default: siab.local)
  --timeout SECONDS       Request timeout (default: 10)
  --https                 Test HTTPS instead of HTTP
  -v, --verbose          Verbose output
  -h, --help             Show this help

Examples:
  # Test using NodePort (most common)
  $0 --k8s-host 192.168.1.100 --admin-nodeport 31367 --user-nodeport 30435

  # Auto-detect NodePorts via SSH
  $0 --k8s-host 192.168.1.100

  # Test using LoadBalancer IPs
  $0 --k8s-host 192.168.1.100 --admin-ip 10.10.30.240 --user-ip 10.10.30.242

  # Test HTTPS with verbose output
  $0 --k8s-host 192.168.1.100 --https -v

Prerequisites:
  - curl must be installed on this machine
  - Network connectivity to K8s host
  - /etc/hosts entries for *.siab.local (or DNS configured)

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

log_verbose() {
    if [[ "$VERBOSE" == "true" ]]; then
        echo -e "  ${CYAN}→${NC} $1"
    fi
}

# Check prerequisites
check_prerequisites() {
    if ! command -v curl &>/dev/null; then
        log_fail "curl not found - please install curl"
        exit 1
    fi

    if [[ -z "$K8S_HOST" ]]; then
        log_fail "K8s host not specified - use --k8s-host"
        echo "Example: $0 --k8s-host 192.168.1.100"
        exit 1
    fi

    log_ok "Prerequisites check passed"
}

# Auto-detect NodePorts via SSH
auto_detect_nodeports() {
    if [[ -n "$ADMIN_NODEPORT" ]] && [[ -n "$USER_NODEPORT" ]]; then
        log_verbose "Using provided NodePorts"
        return
    fi

    log_info "Attempting to auto-detect NodePorts via SSH..."

    if command -v ssh &>/dev/null; then
        if [[ -z "$ADMIN_NODEPORT" ]]; then
            ADMIN_NODEPORT=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$K8S_HOST" \
                "kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.spec.ports[?(@.name==\"http\")].nodePort}' 2>/dev/null" || echo "")
        fi

        if [[ -z "$USER_NODEPORT" ]]; then
            USER_NODEPORT=$(ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "$K8S_HOST" \
                "kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.spec.ports[?(@.name==\"http\")].nodePort}' 2>/dev/null" || echo "")
        fi
    fi

    if [[ -n "$ADMIN_NODEPORT" ]]; then
        log_ok "Detected Admin NodePort: $ADMIN_NODEPORT"
    else
        log_warn "Could not auto-detect Admin NodePort"
    fi

    if [[ -n "$USER_NODEPORT" ]]; then
        log_ok "Detected User NodePort: $USER_NODEPORT"
    else
        log_warn "Could not auto-detect User NodePort"
    fi
}

# Test a service endpoint
test_endpoint() {
    local name="$1"
    local url="$2"
    local expected_codes="$3"  # Space-separated list of acceptable codes

    ((TESTS_RUN++))

    log_verbose "Testing $name: $url"

    # Make request
    local http_code=""
    local response_headers=""
    local error_message=""

    if [[ "$TEST_HTTPS" == "true" ]]; then
        response=$(curl -k -s -o /dev/null -w "%{http_code}\n%{header_json}" \
            --connect-timeout "$TIMEOUT" \
            --max-time $((TIMEOUT + 5)) \
            "$url" 2>&1) || true
    else
        response=$(curl -s -o /dev/null -w "%{http_code}" \
            --connect-timeout "$TIMEOUT" \
            --max-time $((TIMEOUT + 5)) \
            "$url" 2>&1) || true
    fi

    http_code=$(echo "$response" | head -n1)

    # Check if code is in expected codes
    local is_expected=false
    for code in $expected_codes; do
        if [[ "$http_code" == "$code" ]]; then
            is_expected=true
            break
        fi
    done

    if [[ "$is_expected" == "true" ]]; then
        log_ok "$name: HTTP $http_code"
        ((TESTS_PASSED++))
    else
        log_fail "$name: HTTP $http_code (expected: $expected_codes)"
        ((TESTS_FAILED++))
        FAILED_TESTS+=("$name: HTTP $http_code")

        # If verbose, try to get more details
        if [[ "$VERBOSE" == "true" ]]; then
            local detailed_response=$(curl -v -s -o /dev/null "$url" 2>&1 | tail -20)
            log_verbose "Detailed response:"
            echo "$detailed_response" | while read -r line; do
                log_verbose "  $line"
            done
        fi
    fi
}

# Test admin services
test_admin_services() {
    if [[ -z "$ADMIN_NODEPORT" ]] && [[ -z "$ADMIN_IP" ]]; then
        log_warn "No admin gateway access method configured, skipping admin tests"
        return
    fi

    log_section "Testing Admin Services"

    local base_url=""
    local protocol="http"

    if [[ "$TEST_HTTPS" == "true" ]]; then
        protocol="https"
    fi

    if [[ -n "$ADMIN_IP" ]]; then
        base_url="$protocol://$ADMIN_IP"
        log_info "Using Admin LoadBalancer IP: $ADMIN_IP"
    else
        base_url="$protocol://$K8S_HOST:$ADMIN_NODEPORT"
        log_info "Using Admin NodePort: $ADMIN_NODEPORT"
    fi

    # Define admin services to test
    declare -A admin_services=(
        ["Grafana"]="grafana.$SIAB_DOMAIN"
        ["Keycloak"]="keycloak.$SIAB_DOMAIN"
        ["Kubernetes Dashboard"]="k8s-dashboard.$SIAB_DOMAIN"
        ["Longhorn UI"]="longhorn.$SIAB_DOMAIN"
        ["MinIO Console"]="minio.$SIAB_DOMAIN"
    )

    for service_name in "${!admin_services[@]}"; do
        local hostname="${admin_services[$service_name]}"
        local url="$base_url/"

        log_verbose "Testing $service_name at $hostname"

        # Test with Host header
        local http_code=$(curl -s -o /dev/null -w "%{http_code}" \
            --connect-timeout "$TIMEOUT" \
            -H "Host: $hostname" \
            "$url" 2>/dev/null || echo "000")

        ((TESTS_RUN++))

        if [[ "$http_code" == "200" ]] || [[ "$http_code" == "301" ]] || [[ "$http_code" == "302" ]]; then
            log_ok "$service_name ($hostname): HTTP $http_code"
            ((TESTS_PASSED++))
        elif [[ "$http_code" == "404" ]]; then
            log_warn "$service_name ($hostname): HTTP $http_code - Service may not be deployed"
            ((TESTS_FAILED++))
            FAILED_TESTS+=("$service_name: HTTP $http_code - Not Found")
        elif [[ "$http_code" == "503" ]]; then
            log_fail "$service_name ($hostname): HTTP $http_code - Upstream unavailable"
            ((TESTS_FAILED++))
            FAILED_TESTS+=("$service_name: HTTP $http_code - Upstream unavailable")

            if [[ "$VERBOSE" == "true" ]]; then
                log_verbose "Getting detailed error..."
                curl -v -H "Host: $hostname" "$url" 2>&1 | grep -A 5 "upstream" | while read -r line; do
                    log_verbose "$line"
                done
            fi
        else
            log_fail "$service_name ($hostname): HTTP $http_code"
            ((TESTS_FAILED++))
            FAILED_TESTS+=("$service_name: HTTP $http_code")
        fi
    done
}

# Test user services
test_user_services() {
    if [[ -z "$USER_NODEPORT" ]] && [[ -z "$USER_IP" ]]; then
        log_warn "No user gateway access method configured, skipping user tests"
        return
    fi

    log_section "Testing User Services"

    local base_url=""
    local protocol="http"

    if [[ "$TEST_HTTPS" == "true" ]]; then
        protocol="https"
    fi

    if [[ -n "$USER_IP" ]]; then
        base_url="$protocol://$USER_IP"
        log_info "Using User LoadBalancer IP: $USER_IP"
    else
        base_url="$protocol://$K8S_HOST:$USER_NODEPORT"
        log_info "Using User NodePort: $USER_NODEPORT"
    fi

    # Define user services to test
    declare -A user_services=(
        ["Dashboard"]="dashboard.$SIAB_DOMAIN"
        ["Catalog"]="catalog.$SIAB_DOMAIN"
        ["SIAB Root"]="$SIAB_DOMAIN"
    )

    for service_name in "${!user_services[@]}"; do
        local hostname="${user_services[$service_name]}"
        local url="$base_url/"

        log_verbose "Testing $service_name at $hostname"

        local http_code=$(curl -s -o /dev/null -w "%{http_code}" \
            --connect-timeout "$TIMEOUT" \
            -H "Host: $hostname" \
            "$url" 2>/dev/null || echo "000")

        ((TESTS_RUN++))

        if [[ "$http_code" == "200" ]] || [[ "$http_code" == "301" ]] || [[ "$http_code" == "302" ]]; then
            log_ok "$service_name ($hostname): HTTP $http_code"
            ((TESTS_PASSED++))
        elif [[ "$http_code" == "404" ]]; then
            log_warn "$service_name ($hostname): HTTP $http_code - Service may not be deployed"
            ((TESTS_FAILED++))
            FAILED_TESTS+=("$service_name: HTTP $http_code - Not Found")
        elif [[ "$http_code" == "503" ]]; then
            log_fail "$service_name ($hostname): HTTP $http_code - Upstream unavailable"
            ((TESTS_FAILED++))
            FAILED_TESTS+=("$service_name: HTTP $http_code - Upstream unavailable")
        else
            log_fail "$service_name ($hostname): HTTP $http_code"
            ((TESTS_FAILED++))
            FAILED_TESTS+=("$service_name: HTTP $http_code")
        fi
    done
}

# Test direct gateway connectivity
test_gateway_connectivity() {
    log_section "Testing Gateway Connectivity"

    if [[ -n "$ADMIN_NODEPORT" ]]; then
        log_info "Testing admin gateway at $K8S_HOST:$ADMIN_NODEPORT"

        local http_code=$(curl -s -o /dev/null -w "%{http_code}" \
            --connect-timeout "$TIMEOUT" \
            "http://$K8S_HOST:$ADMIN_NODEPORT/" 2>/dev/null || echo "000")

        ((TESTS_RUN++))

        if [[ "$http_code" != "000" ]]; then
            log_ok "Admin gateway reachable (HTTP $http_code)"
            ((TESTS_PASSED++))
        else
            log_fail "Admin gateway not reachable"
            ((TESTS_FAILED++))
            FAILED_TESTS+=("Admin gateway: Connection failed")
        fi
    fi

    if [[ -n "$USER_NODEPORT" ]]; then
        log_info "Testing user gateway at $K8S_HOST:$USER_NODEPORT"

        local http_code=$(curl -s -o /dev/null -w "%{http_code}" \
            --connect-timeout "$TIMEOUT" \
            "http://$K8S_HOST:$USER_NODEPORT/" 2>/dev/null || echo "000")

        ((TESTS_RUN++))

        if [[ "$http_code" != "000" ]]; then
            log_ok "User gateway reachable (HTTP $http_code)"
            ((TESTS_PASSED++))
        else
            log_fail "User gateway not reachable"
            ((TESTS_FAILED++))
            FAILED_TESTS+=("User gateway: Connection failed")
        fi
    fi
}

# Print test summary
print_summary() {
    log_section "Test Summary"

    echo -e "${BOLD}Tests Run:${NC} $TESTS_RUN"
    echo -e "${GREEN}${BOLD}Passed:${NC} $TESTS_PASSED"
    echo -e "${RED}${BOLD}Failed:${NC} $TESTS_FAILED"

    if [[ ${#FAILED_TESTS[@]} -gt 0 ]]; then
        echo ""
        echo -e "${RED}${BOLD}Failed Tests:${NC}"
        for failure in "${FAILED_TESTS[@]}"; do
            echo -e "  ${RED}${CROSS_MARK}${NC} $failure"
        done
    fi
}

# Print diagnostics
print_diagnostics() {
    if [[ $TESTS_FAILED -eq 0 ]]; then
        return
    fi

    log_section "Diagnostic Information"

    echo -e "${BOLD}Common Issues:${NC}"
    echo ""

    # Check for 503 errors
    local has_503=false
    for test in "${FAILED_TESTS[@]}"; do
        if [[ "$test" == *"503"* ]]; then
            has_503=true
            break
        fi
    done

    if [[ "$has_503" == "true" ]]; then
        echo -e "${YELLOW}${WARN_MARK}${NC} ${BOLD}HTTP 503 - Upstream Unavailable${NC}"
        echo "  This usually means:"
        echo "  1. Backend service doesn't exist"
        echo "  2. Backend pods are not running"
        echo "  3. DestinationRule is missing (mTLS issue)"
        echo "  4. Service namespace mismatch in VirtualService"
        echo ""
        echo "  On the K8s host, run:"
        echo -e "  ${CYAN}kubectl get pods -A | grep <service-name>${NC}"
        echo -e "  ${CYAN}kubectl get svc -A | grep <service-name>${NC}"
        echo -e "  ${CYAN}kubectl get destinationrule -A${NC}"
        echo -e "  ${CYAN}./fix-istio-mtls.sh${NC}"
        echo ""
    fi

    echo -e "${BOLD}Troubleshooting on K8s host:${NC}"
    echo -e "  ${CYAN}./test-istio-access.sh -v${NC}  # Run internal tests"
    echo -e "  ${CYAN}kubectl logs -n istio-system -l istio=ingress-admin${NC}"
    echo -e "  ${CYAN}kubectl logs -n istio-system -l istio=ingress-user${NC}"
    echo -e "  ${CYAN}kubectl get virtualservice -A${NC}"
    echo -e "  ${CYAN}kubectl get destinationrule -A${NC}"
    echo ""

    echo -e "${BOLD}DNS Configuration:${NC}"
    echo "  Ensure /etc/hosts or DNS has entries like:"
    echo -e "  ${CYAN}$K8S_HOST  grafana.$SIAB_DOMAIN keycloak.$SIAB_DOMAIN${NC}"
    echo -e "  ${CYAN}$K8S_HOST  dashboard.$SIAB_DOMAIN catalog.$SIAB_DOMAIN${NC}"
}

# Main execution
main() {
    log_section "SIAB External Client Access Test"

    echo -e "K8s Host: ${BOLD}$K8S_HOST${NC}"
    echo -e "Domain: ${BOLD}$SIAB_DOMAIN${NC}"
    echo -e "Protocol: ${BOLD}$([ "$TEST_HTTPS" == "true" ] && echo "HTTPS" || echo "HTTP")${NC}"

    # Check prerequisites
    check_prerequisites

    # Auto-detect NodePorts if needed
    auto_detect_nodeports

    # Run tests
    test_gateway_connectivity
    test_admin_services
    test_user_services

    # Print results
    echo ""
    print_summary
    echo ""
    print_diagnostics

    # Exit with appropriate code
    if [[ $TESTS_FAILED -eq 0 ]]; then
        echo ""
        log_section "✓ All Tests Passed"
        exit 0
    else
        echo ""
        log_section "✗ Some Tests Failed"
        exit 1
    fi
}

# Run main
main
