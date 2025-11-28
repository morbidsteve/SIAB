#!/bin/bash
# Fix Keycloak by excluding PostgreSQL traffic from Istio interception

set -euo pipefail

echo "=== Fixing Keycloak - Excluding PostgreSQL from Istio ==="

# Find the PostgreSQL port
PG_PORT=$(kubectl get svc keycloak-postgresql -n keycloak -o jsonpath='{.spec.ports[0].port}' 2>/dev/null || echo "5432")

echo "PostgreSQL service port: $PG_PORT"
echo ""

echo "Patching Keycloak deployment to exclude PostgreSQL port from Istio..."

# Patch keycloak deployment to exclude PostgreSQL port from interception
kubectl patch deployment keycloak -n keycloak --type=merge -p "
{
  \"spec\": {
    \"template\": {
      \"metadata\": {
        \"annotations\": {
          \"traffic.sidecar.istio.io/excludeOutboundPorts\": \"$PG_PORT\"
        }
      }
    }
  }
}
"

echo ""
echo "Deployment patched. Waiting for rollout..."
kubectl rollout status deployment keycloak -n keycloak --timeout=120s

echo ""
echo "Checking pod status..."
kubectl get pods -n keycloak

echo ""
echo "Checking latest keycloak pod logs (last 30 lines)..."
sleep 5
LATEST_POD=$(kubectl get pods -n keycloak -l app=keycloak --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
echo "Pod: $LATEST_POD"
kubectl logs -n keycloak "$LATEST_POD" -c keycloak --tail=30 || echo "Pod not ready yet"

echo ""
echo "=== Fix Applied ==="
echo ""
echo "PostgreSQL traffic (port $PG_PORT) is now excluded from Istio interception."
echo "Keycloak will connect directly to PostgreSQL, bypassing the service mesh."
echo ""
echo "Monitor with:"
echo "  kubectl get pods -n keycloak -w"
echo "  kubectl logs -n keycloak -l app=keycloak -f"
