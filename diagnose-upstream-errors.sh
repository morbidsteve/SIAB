#!/bin/bash
# SIAB Upstream Connection Error Diagnostic Tool
# Diagnoses and fixes "upstream connect error or disconnect/reset before headers"

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

AUTO_FIX=false
VERBOSE=false

# Parse arguments
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
            cat <<EOF
SIAB Upstream Connection Error Diagnostic Tool

Diagnoses and fixes "upstream connect error or disconnect/reset before headers"
errors when accessing services through Istio gateways.

Usage: $0 [OPTIONS]

Options:
  --fix      Automatically create missing DestinationRules
  -v         Verbose output
  -h         Show this help

What this script checks:
  1. VirtualService → Backend Service mapping
  2. Backend service existence
  3. Backend pod health
  4. DestinationRule existence for each backend
  5. mTLS configuration
  6. Namespace labels

Common fix:
  The most common cause is missing DestinationRules for backend services.
  Use --fix to automatically create them.

Examples:
  # Diagnose issues
  $0

  # Diagnose and automatically fix
  $0 --fix

  # Verbose output
  $0 -v --fix

EOF
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

ISSUES_FOUND=0
ISSUES_FIXED=0

# Main diagnostic function
diagnose_virtualservice() {
    local vs_namespace="$1"
    local vs_name="$2"

    log_info "Analyzing VirtualService: $vs_name (namespace: $vs_namespace)"

    # Get VirtualService details
    local vs_yaml=$(kubectl get virtualservice "$vs_name" -n "$vs_namespace" -o yaml 2>/dev/null)

    if [[ -z "$vs_yaml" ]]; then
        log_fail "VirtualService not found"
        return
    fi

    # Extract hosts
    local hosts=$(echo "$vs_yaml" | grep -A 10 "^spec:" | grep -A 5 "hosts:" | grep "- " | sed 's/.*- //' | tr -d '"')

    log_verbose "Hosts: $(echo $hosts | tr '\n' ', ')"

    # Extract destination hosts
    local dest_hosts=$(echo "$vs_yaml" | grep -E "^\s+host:" | awk '{print $2}' | tr -d '"' | sort -u)

    for dest_host in $dest_hosts; do
        log_verbose "Checking destination: $dest_host"

        # Parse destination host (format: service.namespace.svc.cluster.local)
        local service_name=$(echo "$dest_host" | cut -d. -f1)
        local service_namespace=$(echo "$dest_host" | cut -d. -f2)

        # If namespace not in FQDN, assume istio-system or same as VS
        if [[ "$service_namespace" == "svc" ]] || [[ -z "$service_namespace" ]]; then
            service_namespace="$vs_namespace"
        fi

        log_verbose "  Service: $service_name, Namespace: $service_namespace"

        # Check if service exists
        if kubectl get svc "$service_name" -n "$service_namespace" &>/dev/null; then
            log_ok "  Service $service_name exists in namespace $service_namespace"

            # Check if pods are running
            local selector=$(kubectl get svc "$service_name" -n "$service_namespace" -o jsonpath='{.spec.selector}' 2>/dev/null)

            if [[ -n "$selector" ]]; then
                # Convert selector to label query
                local label_query=$(echo "$selector" | jq -r 'to_entries | map("\(.key)=\(.value)") | join(",")')  2>/dev/null || ""

                if [[ -n "$label_query" ]]; then
                    local pod_count=$(kubectl get pods -n "$service_namespace" -l "$label_query" --no-headers 2>/dev/null | wc -l)
                    local ready_count=$(kubectl get pods -n "$service_namespace" -l "$label_query" --no-headers 2>/dev/null | grep "Running" | wc -l)

                    if [[ "$ready_count" -gt 0 ]]; then
                        log_ok "  Pods are running: $ready_count/$pod_count"
                    else
                        log_fail "  No pods are running for service $service_name"
                        ((ISSUES_FOUND++))
                        log_warn "    Fix: Check why pods are not running"
                        log_verbose "    kubectl get pods -n $service_namespace -l $label_query"
                        log_verbose "    kubectl describe pods -n $service_namespace -l $label_query"
                    fi
                fi
            fi

        else
            log_fail "  Service $service_name NOT FOUND in namespace $service_namespace"
            ((ISSUES_FOUND++))
            log_warn "    This is likely why you're getting 503 errors!"
            log_warn "    VirtualService points to: $dest_host"
            log_warn "    But service doesn't exist in namespace: $service_namespace"

            # Try to find the service in other namespaces
            log_verbose "    Searching for $service_name in other namespaces..."
            local other_namespaces=$(kubectl get svc -A --no-headers 2>/dev/null | grep "$service_name" | awk '{print $1}' || echo "")

            if [[ -n "$other_namespaces" ]]; then
                log_warn "    Found $service_name in namespace(s): $other_namespaces"
                log_warn "    Update VirtualService to use correct namespace!"
            fi
            continue
        fi

        # Check for DestinationRule
        log_verbose "  Checking DestinationRule for $service_name..."

        # Look for DestinationRule in both service namespace and istio-system
        local dr_exists=false

        if kubectl get destinationrule "$service_name" -n "$service_namespace" &>/dev/null; then
            dr_exists=true
            log_ok "  DestinationRule exists in namespace $service_namespace"

            # Check if it has mTLS configured
            local has_mtls=$(kubectl get destinationrule "$service_name" -n "$service_namespace" -o yaml | grep -c "mode: ISTIO_MUTUAL" || echo "0")

            if [[ "$has_mtls" -gt 0 ]]; then
                log_ok "  DestinationRule has mTLS configured"
            else
                log_warn "  DestinationRule exists but mTLS not configured"
                ((ISSUES_FOUND++))

                if [[ "$AUTO_FIX" == "true" ]]; then
                    fix_destinationrule_mtls "$service_name" "$service_namespace"
                fi
            fi

        elif kubectl get destinationrule -n istio-system --no-headers 2>/dev/null | grep -q "$service_name"; then
            dr_exists=true
            log_ok "  DestinationRule exists in istio-system"
        else
            log_fail "  DestinationRule NOT FOUND for $service_name"
            ((ISSUES_FOUND++))
            log_warn "    This is likely causing 'upstream connect error'!"
            log_warn "    With mTLS STRICT mode, DestinationRule is required"

            if [[ "$AUTO_FIX" == "true" ]]; then
                create_destinationrule "$service_name" "$service_namespace" "$dest_host"
            else
                log_info "    Run with --fix to automatically create DestinationRule"
            fi
        fi
    done
}

# Create DestinationRule
create_destinationrule() {
    local service_name="$1"
    local service_namespace="$2"
    local host="$3"

    log_info "Creating DestinationRule for $service_name in namespace $service_namespace..."

    cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: $service_name
  namespace: $service_namespace
spec:
  host: $host
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
EOF

    if [[ $? -eq 0 ]]; then
        log_ok "DestinationRule created successfully"
        ((ISSUES_FIXED++))
    else
        log_fail "Failed to create DestinationRule"
    fi
}

# Fix existing DestinationRule to add mTLS
fix_destinationrule_mtls() {
    local service_name="$1"
    local service_namespace="$2"

    log_info "Adding mTLS to existing DestinationRule..."

    kubectl patch destinationrule "$service_name" -n "$service_namespace" --type=merge -p '
{
  "spec": {
    "trafficPolicy": {
      "tls": {
        "mode": "ISTIO_MUTUAL"
      }
    }
  }
}'

    if [[ $? -eq 0 ]]; then
        log_ok "DestinationRule updated with mTLS"
        ((ISSUES_FIXED++))
    else
        log_fail "Failed to update DestinationRule"
    fi
}

# Check namespace injection
check_namespace_injection() {
    log_section "Checking Namespace Istio Injection"

    # Get all namespaces with services
    local namespaces=$(kubectl get svc -A --no-headers | awk '{print $1}' | sort -u | grep -v "kube-system\|kube-public\|kube-node-lease")

    for ns in $namespaces; do
        local injection=$(kubectl get namespace "$ns" -o jsonpath='{.metadata.labels.istio-injection}' 2>/dev/null || echo "")

        if [[ "$injection" == "enabled" ]]; then
            log_ok "Namespace $ns: Istio injection enabled"
        else
            local has_istio_pods=$(kubectl get pods -n "$ns" -o jsonpath='{.items[*].spec.containers[*].name}' 2>/dev/null | grep -c "istio-proxy" || echo "0")

            if [[ "$has_istio_pods" -gt 0 ]]; then
                log_ok "Namespace $ns: Has Istio sidecars (manual injection)"
            else
                log_warn "Namespace $ns: No Istio injection (label: ${injection:-not set})"

                # Check if there are actual application pods
                local pod_count=$(kubectl get pods -n "$ns" --no-headers 2>/dev/null | wc -l)
                if [[ "$pod_count" -gt 0 ]]; then
                    ((ISSUES_FOUND++))
                    if [[ "$AUTO_FIX" == "true" ]]; then
                        log_info "Enabling Istio injection for namespace $ns..."
                        kubectl label namespace "$ns" istio-injection=enabled --overwrite
                        log_warn "  You may need to restart pods: kubectl rollout restart deploy -n $ns"
                    fi
                fi
            fi
        fi
    done
}

# Main execution
main() {
    log_section "SIAB Upstream Connection Error Diagnostic"

    if [[ "$AUTO_FIX" == "true" ]]; then
        log_info "Auto-fix mode enabled"
    fi

    # Check kubectl
    if ! command -v kubectl &>/dev/null; then
        log_fail "kubectl not found"
        exit 1
    fi

    log_section "Analyzing VirtualServices and Backend Services"

    # Get all VirtualServices
    local vs_list=$(kubectl get virtualservice -A -o custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name --no-headers 2>/dev/null)

    if [[ -z "$vs_list" ]]; then
        log_fail "No VirtualServices found"
        exit 1
    fi

    # Process each VirtualService
    while read -r namespace name; do
        diagnose_virtualservice "$namespace" "$name"
        echo ""
    done <<< "$vs_list"

    # Check namespace injection
    check_namespace_injection

    # Check mTLS mode
    log_section "Checking mTLS Configuration"

    local mtls_mode=$(kubectl get peerauthentication -n istio-system default -o jsonpath='{.spec.mtls.mode}' 2>/dev/null || echo "not configured")
    log_info "Global mTLS mode: $mtls_mode"

    if [[ "$mtls_mode" == "STRICT" ]]; then
        log_warn "mTLS is STRICT - all services MUST have DestinationRules"
        log_info "This is the most common cause of 'upstream connect error'"
    fi

    # Summary
    log_section "Summary"

    echo -e "${BOLD}Issues Found:${NC} $ISSUES_FOUND"

    if [[ "$AUTO_FIX" == "true" ]]; then
        echo -e "${BOLD}Issues Fixed:${NC} $ISSUES_FIXED"
    fi

    if [[ $ISSUES_FOUND -gt 0 ]]; then
        echo ""
        log_warn "Issues detected that may cause upstream connect errors"

        if [[ "$AUTO_FIX" != "true" ]]; then
            echo ""
            log_info "Run with --fix to automatically resolve issues:"
            echo -e "  ${CYAN}$0 --fix${NC}"
        else
            echo ""
            log_info "Some issues may require manual intervention"
            log_info "Check pod logs and events for more details"
        fi

        echo ""
        log_info "Additional troubleshooting commands:"
        echo -e "  ${CYAN}kubectl get pods -A | grep -v Running${NC}  # Check unhealthy pods"
        echo -e "  ${CYAN}kubectl logs -n istio-system -l istio=ingress-admin${NC}  # Gateway logs"
        echo -e "  ${CYAN}kubectl get events -A --sort-by='.lastTimestamp'${NC}  # Recent events"

        exit 1
    else
        log_ok "No issues found"
        exit 0
    fi
}

main
