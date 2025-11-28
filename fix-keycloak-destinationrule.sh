#!/bin/bash
# Fix keycloak DestinationRule - enable mTLS for sidecar

set -euo pipefail

echo "=== Fixing Keycloak DestinationRule ==="

echo "Deleting old DestinationRules with mTLS disabled..."

# Delete the old incorrect DestinationRules
kubectl delete destinationrule keycloak-disable-mtls -n istio-system 2>/dev/null || echo "  keycloak-disable-mtls not found"
kubectl delete destinationrule keycloak-mtls-disable -n istio-system 2>/dev/null || echo "  keycloak-mtls-disable not found"

echo ""
echo "Creating new DestinationRule with mTLS enabled..."

# Create correct DestinationRule with ISTIO_MUTUAL
kubectl apply -f - <<EOF
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: keycloak
  namespace: keycloak
spec:
  host: keycloak.keycloak.svc.cluster.local
  trafficPolicy:
    tls:
      mode: ISTIO_MUTUAL
EOF

echo ""
echo "Verifying DestinationRule..."
kubectl get destinationrule -A | grep keycloak

echo ""
echo "=== Fix Complete! ==="
echo ""
echo "Now test accessing keycloak.siab.local from your browser"
echo ""
echo "Monitor gateway logs:"
echo "  kubectl logs -n istio-system -l istio=ingress-admin --tail=20 -f"
