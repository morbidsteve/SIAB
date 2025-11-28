#!/bin/bash
# Fix Keycloak service port mapping

set -euo pipefail

echo "=== Current Keycloak Service Configuration ==="
kubectl get svc keycloak -n keycloak -o yaml | grep -A 10 "ports:"

echo ""
echo "=== Checking what port Keycloak container is listening on ==="
KEYCLOAK_POD=$(kubectl get pods -n keycloak -l app=keycloak -o jsonpath='{.items[0].metadata.name}')
echo "Pod: $KEYCLOAK_POD"
echo ""
echo "Checking container ports..."
kubectl get pod "$KEYCLOAK_POD" -n keycloak -o jsonpath='{.spec.containers[?(@.name=="keycloak")].ports}' | jq .

echo ""
echo "=== Fixing Service Port Mapping ==="

# Patch the service to forward port 80 to targetPort 8080
kubectl patch svc keycloak -n keycloak --type=merge -p '
{
  "spec": {
    "ports": [
      {
        "name": "http",
        "port": 80,
        "targetPort": 8080,
        "protocol": "TCP"
      }
    ]
  }
}
'

echo ""
echo "=== Updated Service Configuration ==="
kubectl get svc keycloak -n keycloak -o yaml | grep -A 10 "ports:"

echo ""
echo "=== Testing Service Connection ==="
sleep 2
kubectl run test-curl-$$ --rm -i --restart=Never --image=curlimages/curl:latest -- \
  curl -v --connect-timeout 5 http://keycloak.keycloak.svc.cluster.local/ 2>&1 | tail -20

echo ""
echo "=== Fix Complete! ==="
echo ""
echo "Now try accessing keycloak.siab.local from your browser"
