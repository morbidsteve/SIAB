#!/bin/bash
#
# Test HTTPS configuration and HTTP to HTTPS redirects
#

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}ℹ${NC} $1"
}

log_success() {
    echo -e "${GREEN}✓${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

log_error() {
    echo -e "${RED}✗${NC} $1"
}

echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  SIAB HTTPS Configuration Test                                ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""

# Get LoadBalancer IPs
ADMIN_IP=$(kubectl get svc -n istio-system istio-ingress-admin -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
USER_IP=$(kubectl get svc -n istio-system istio-ingress-user -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

if [ -z "$ADMIN_IP" ]; then
    log_error "Could not get admin ingress IP"
    exit 1
fi

if [ -z "$USER_IP" ]; then
    log_error "Could not get user ingress IP"
    exit 1
fi

log_info "Admin Gateway: $ADMIN_IP"
log_info "User Gateway: $USER_IP"
echo ""

# Test function
test_http_redirect() {
    local host=$1
    local ip=$2
    local expected_location=$3

    log_info "Testing HTTP redirect for $host..."

    response=$(curl -s -I -H "Host: $host" http://$ip 2>&1 | head -20)

    if echo "$response" | grep -q "HTTP/1.1 301\|HTTP/1.1 308"; then
        if echo "$response" | grep -q "location: https://$host"; then
            log_success "$host: HTTP redirects to HTTPS ✓"
            return 0
        else
            log_warning "$host: Redirect found but location doesn't match"
            echo "$response" | grep "location:"
            return 1
        fi
    else
        log_error "$host: No HTTP redirect found"
        echo "$response" | head -5
        return 1
    fi
}

# Admin Services
echo "Testing Admin Gateway Services:"
echo "──────────────────────────────────────────────────────────────"

test_http_redirect "keycloak.siab.local" "$ADMIN_IP" "https://keycloak.siab.local/"
test_http_redirect "minio.siab.local" "$ADMIN_IP" "https://minio.siab.local/"
test_http_redirect "grafana.siab.local" "$ADMIN_IP" "https://grafana.siab.local/"
test_http_redirect "k8s-dashboard.siab.local" "$ADMIN_IP" "https://k8s-dashboard.siab.local/"
test_http_redirect "longhorn.siab.local" "$ADMIN_IP" "https://longhorn.siab.local/"

echo ""
echo "Testing User Gateway Services:"
echo "──────────────────────────────────────────────────────────────"

test_http_redirect "siab.local" "$USER_IP" "https://siab.local/"
test_http_redirect "dashboard.siab.local" "$USER_IP" "https://dashboard.siab.local/"
test_http_redirect "catalog.siab.local" "$USER_IP" "https://catalog.siab.local/"

echo ""
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║  Test Complete                                                 ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo ""
log_info "All HTTP requests should be redirected to HTTPS"
log_info "To access services, use: https://<service-name>.siab.local"
echo ""
log_warning "Note: You may see certificate warnings because SIAB uses self-signed certificates"
log_info "For production, configure Let's Encrypt or use commercial certificates"
echo ""
