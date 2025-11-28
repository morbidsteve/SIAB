#!/bin/bash
# Diagnose why gateway can't connect to keycloak (error 113)

set -euo pipefail

echo "=== Keycloak Pod Status ==="
kubectl get pods -n keycloak -o wide

echo ""
echo "=== Container Status (should show 2/2 ready) ==="
kubectl get pods -n keycloak -o custom-columns=NAME:.metadata.name,READY:.status.containerStatuses[*].ready,CONTAINERS:.status.containerStatuses[*].name

echo ""
echo "=== Check istio-proxy sidecar logs ==="
KEYCLOAK_POD=$(kubectl get pods -n keycloak -l app=keycloak -o jsonpath='{.items[0].metadata.name}')
echo "Pod: $KEYCLOAK_POD"
echo ""
echo "Last 50 lines of istio-proxy logs:"
kubectl logs -n keycloak "$KEYCLOAK_POD" -c istio-proxy --tail=50 2>&1 | tail -30

echo ""
echo "=== Check NetworkPolicies ==="
kubectl get networkpolicy -n keycloak
echo ""
if kubectl get networkpolicy -n keycloak &>/dev/null; then
    echo "NetworkPolicy details:"
    kubectl describe networkpolicy -n keycloak
fi

echo ""
echo "=== Check if gateway can reach keycloak pod directly ==="
KEYCLOAK_POD_IP=$(kubectl get pod -n keycloak -l app=keycloak -o jsonpath='{.items[0].status.podIP}')
ADMIN_GATEWAY_POD=$(kubectl get pods -n istio-system -l istio=ingress-admin -o jsonpath='{.items[0].metadata.name}')

echo "Keycloak pod IP: $KEYCLOAK_POD_IP"
echo "Testing from gateway pod: $ADMIN_GATEWAY_POD"
echo ""

# Test connection from gateway to keycloak pod
kubectl exec -n istio-system "$ADMIN_GATEWAY_POD" -- curl -v -s --connect-timeout 5 "http://$KEYCLOAK_POD_IP:8080/" 2>&1 | grep -E "Connected|Connection|Failed|refused|reset" || echo "Connection test completed"

echo ""
echo "=== Check if keycloak pod has proper Istio labels ==="
kubectl get pod -n keycloak -l app=keycloak -o yaml | grep -A 10 "labels:"

echo ""
echo "=== Check keycloak service ==="
kubectl get svc keycloak -n keycloak -o yaml | grep -A 20 "spec:"

echo ""
echo "=== Check endpoints ==="
kubectl get endpoints keycloak -n keycloak

echo ""
echo "=== Test from within cluster ==="
kubectl run test-curl-$$ --rm -i --restart=Never --image=curlimages/curl:latest -- \
  curl -v --connect-timeout 5 http://keycloak.keycloak.svc.cluster.local/ 2>&1 | tail -20

echo ""
echo "=== Recommendations ==="
echo ""
echo "If you see a NetworkPolicy blocking traffic:"
echo "  kubectl delete networkpolicy <policy-name> -n keycloak"
echo ""
echo "If istio-proxy is not ready:"
echo "  kubectl delete pod $KEYCLOAK_POD -n keycloak"
echo ""
echo "If pod is not actually 2/2:"
echo "  Check why the sidecar injection failed"
