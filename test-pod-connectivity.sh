#!/bin/bash

# Test pod connectivity and health
# This checks if pods are running and reachable

set -e

export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH="/var/lib/rancher/rke2/bin:${PATH}"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  Pod Connectivity Test                 ${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""

# Test Keycloak
echo -e "${YELLOW}[1] Keycloak${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Pod status:"
kubectl get pods -n keycloak -o wide

POD_NAME=$(kubectl get pods -n keycloak -l app=keycloak -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$POD_NAME" ]; then
    echo ""
    echo "Pod details:"
    kubectl describe pod -n keycloak "$POD_NAME" | grep -A 5 "Status:\|IP:\|Port:\|Ready:"
    echo ""
    echo "Testing port 8080 from within pod:"
    kubectl exec -n keycloak "$POD_NAME" -- sh -c "nc -zv localhost 8080 2>&1 || echo 'Port test failed'"
    echo ""
    echo "Testing HTTP from within pod:"
    kubectl exec -n keycloak "$POD_NAME" -- sh -c "curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:8080/ 2>&1 || echo 'HTTP test failed'"
    echo ""
    echo "Recent logs:"
    kubectl logs -n keycloak "$POD_NAME" --tail=10 2>&1 | head -20
else
    echo -e "${RED}No Keycloak pod found${NC}"
fi
echo ""

# Test MinIO
echo -e "${YELLOW}[2] MinIO${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Pod status:"
kubectl get pods -n minio -o wide

POD_NAME=$(kubectl get pods -n minio -l app=minio -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$POD_NAME" ]; then
    echo ""
    echo "Pod details:"
    kubectl describe pod -n minio "$POD_NAME" | grep -A 5 "Status:\|IP:\|Port:\|Ready:"
    echo ""
    echo "Testing ports from within pod:"
    kubectl exec -n minio "$POD_NAME" -- sh -c "nc -zv localhost 9000 2>&1 && nc -zv localhost 9001 2>&1 || echo 'Port test failed'"
else
    echo -e "${RED}No MinIO pod found${NC}"
fi
echo ""

# Test Grafana
echo -e "${YELLOW}[3] Grafana${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Pod status:"
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o wide

POD_NAME=$(kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
if [ -n "$POD_NAME" ]; then
    echo ""
    echo "Pod details:"
    kubectl describe pod -n monitoring "$POD_NAME" | grep -A 5 "Status:\|IP:\|Port:\|Ready:"
    echo ""
    echo "Testing port 3000 from within pod:"
    kubectl exec -n monitoring "$POD_NAME" -- sh -c "nc -zv localhost 3000 2>&1 || curl -s -o /dev/null -w 'HTTP %{http_code}\n' http://localhost:3000/ 2>&1"
else
    echo -e "${RED}No Grafana pod found${NC}"
fi
echo ""

# Test connectivity FROM gateway TO pods
echo -e "${YELLOW}[4] Gateway to Pod Connectivity${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

KEYCLOAK_IP=$(kubectl get pod -n keycloak -l app=keycloak -o jsonpath='{.items[0].status.podIP}' 2>/dev/null || echo "")
if [ -n "$KEYCLOAK_IP" ]; then
    echo "Testing gateway -> Keycloak ($KEYCLOAK_IP:8080):"
    kubectl exec -n istio-system deployment/istio-ingress-admin -- sh -c "nc -zv $KEYCLOAK_IP 8080 2>&1 || echo 'Connection failed'"
    echo ""

    echo "Trying to curl Keycloak from gateway:"
    kubectl exec -n istio-system deployment/istio-ingress-admin -- sh -c "curl -v -m 5 http://$KEYCLOAK_IP:8080/ 2>&1" | head -20 || echo "Curl failed"
fi
echo ""

# Check network policies
echo -e "${YELLOW}[5] Network Policies${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Network policies in keycloak namespace:"
kubectl get networkpolicies -n keycloak 2>&1 || echo "No network policies"
echo ""

echo "Network policies in istio-system namespace:"
kubectl get networkpolicies -n istio-system 2>&1 || echo "No network policies"
echo ""

# Check if pods have the right labels
echo -e "${YELLOW}[6] Service Selectors vs Pod Labels${NC}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Keycloak service selector:"
kubectl get svc -n keycloak keycloak -o jsonpath='{.spec.selector}' | jq .
echo ""
echo "Keycloak pod labels:"
kubectl get pods -n keycloak -l app=keycloak -o jsonpath='{.items[0].metadata.labels}' | jq .
echo ""

echo -e "${BLUE}════════════════════════════════════════${NC}"
echo -e "${BLUE}  Summary${NC}"
echo -e "${BLUE}════════════════════════════════════════${NC}"
echo ""
echo "If you see 'Connection refused' - Pod is not listening on that port"
echo "If you see 'No route to host' - Network issue (CNI, firewall, network policy)"
echo "If you see 'Connection timed out' - Pod is unreachable (network/firewall)"
echo ""
