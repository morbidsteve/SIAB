#!/bin/bash
# Deep dive diagnostic for keycloak issue

set -euo pipefail

echo "=== Keycloak Service Details ==="
kubectl get svc keycloak -n keycloak -o yaml

echo ""
echo "=== Keycloak Pods Status ==="
kubectl get pods -n keycloak -o wide

echo ""
echo "=== Keycloak Pod Details ==="
kubectl describe pods -n keycloak | grep -A 20 "^Name:\|Containers:\|Ready:\|Status:\|Conditions:"

echo ""
echo "=== Keycloak VirtualService ==="
kubectl get virtualservice keycloak -n istio-system -o yaml

echo ""
echo "=== Keycloak DestinationRule ==="
kubectl get destinationrule -A -o yaml | grep -A 30 "name: keycloak" || echo "Using different name"
kubectl get destinationrule -A | grep keycloak

echo ""
echo "=== Check if keycloak pods have Istio sidecar ==="
kubectl get pods -n keycloak -o jsonpath='{.items[*].spec.containers[*].name}' | tr ' ' '\n'

echo ""
echo "=== Keycloak service endpoints ==="
kubectl get endpoints keycloak -n keycloak

echo ""
echo "=== Test from within cluster ==="
kubectl run test-curl-$$ --rm -i --restart=Never --image=curlimages/curl:latest -- \
  curl -v -s --connect-timeout 5 \
  http://keycloak.keycloak.svc.cluster.local:8080/ 2>&1 | tail -30

echo ""
echo "=== Check gateway logs for errors ==="
kubectl logs -n istio-system -l istio=ingress-admin --tail=50 | grep -i "keycloak\|upstream\|error" || echo "No recent keycloak errors in logs"

echo ""
echo "=== Check NetworkPolicies blocking traffic ==="
kubectl get networkpolicy -n keycloak
kubectl get networkpolicy -n istio-system

echo ""
echo "=== Check what port keycloak is listening on ==="
kubectl exec -n keycloak $(kubectl get pods -n keycloak -o jsonpath='{.items[0].metadata.name}') -c keycloak -- netstat -tlnp 2>/dev/null || \
kubectl exec -n keycloak $(kubectl get pods -n keycloak -o jsonpath='{.items[0].metadata.name}') -c keycloak -- ss -tlnp 2>/dev/null || \
echo "Cannot check ports (netstat/ss not available in container)"
