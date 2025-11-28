#!/bin/bash
# Fix Keycloak Istio sidecar startup ordering issue

set -euo pipefail

echo "=== Fixing Keycloak deployment for Istio ==="

# Check if deployment exists
if ! kubectl get deployment keycloak -n keycloak &>/dev/null; then
    echo "ERROR: keycloak deployment not found"
    exit 1
fi

echo "Adding Istio sidecar configuration to keycloak deployment..."

# Patch the deployment to hold application until proxy starts
kubectl patch deployment keycloak -n keycloak --type=merge -p '
{
  "spec": {
    "template": {
      "metadata": {
        "annotations": {
          "proxy.istio.io/config": "{\"holdApplicationUntilProxyStarts\": true}"
        }
      }
    }
  }
}
'

echo ""
echo "Checking if PostgreSQL needs the same fix..."

if kubectl get deployment keycloak-postgresql -n keycloak &>/dev/null; then
    kubectl patch deployment keycloak-postgresql -n keycloak --type=merge -p '
    {
      "spec": {
        "template": {
          "metadata": {
            "annotations": {
              "proxy.istio.io/config": "{\"holdApplicationUntilProxyStarts\": true}"
            }
          }
        }
      }
    }
    '
    echo "PostgreSQL deployment patched"
fi

echo ""
echo "Creating DestinationRule for PostgreSQL..."

kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: keycloak-postgresql
  namespace: keycloak
spec:
  host: keycloak-postgresql.keycloak.svc.cluster.local
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
EOF

echo ""
echo "Waiting for deployments to update..."
sleep 5

echo ""
echo "Checking pod status..."
kubectl get pods -n keycloak

echo ""
echo "=== Fix applied! ==="
echo ""
echo "Monitor the pods with:"
echo "  kubectl get pods -n keycloak -w"
echo ""
echo "Check logs with:"
echo "  kubectl logs -n keycloak -l app=keycloak -f"
