#!/bin/bash

# Fix admin gateway to include longhorn.siab.local
# This updates the existing gateway configuration

set -e

export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH="/var/lib/rancher/rke2/bin:${PATH}"

echo "============================================"
echo "  Fix Admin Gateway for Longhorn"
echo "============================================"
echo ""

# Get domain from config or use default
SIAB_DOMAIN="${SIAB_DOMAIN:-siab.local}"

echo "Updating admin-gateway to include longhorn.${SIAB_DOMAIN}..."
echo ""

# Apply updated admin gateway configuration
cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: admin-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingress-admin
  servers:
    - port:
        number: 443
        name: https
        protocol: HTTPS
      tls:
        mode: SIMPLE
        credentialName: siab-gateway-cert
      hosts:
        - "grafana.${SIAB_DOMAIN}"
        - "keycloak.${SIAB_DOMAIN}"
        - "k8s-dashboard.${SIAB_DOMAIN}"
        - "minio.${SIAB_DOMAIN}"
        - "longhorn.${SIAB_DOMAIN}"
        - "*.admin.${SIAB_DOMAIN}"
    - port:
        number: 80
        name: http
        protocol: HTTP
      hosts:
        - "grafana.${SIAB_DOMAIN}"
        - "keycloak.${SIAB_DOMAIN}"
        - "k8s-dashboard.${SIAB_DOMAIN}"
        - "minio.${SIAB_DOMAIN}"
        - "longhorn.${SIAB_DOMAIN}"
        - "*.admin.${SIAB_DOMAIN}"
EOF

echo ""
echo "✓ Gateway updated"
echo ""

echo "Verifying gateway configuration:"
kubectl get gateway admin-gateway -n istio-system -o yaml | grep -A 10 "hosts:"
echo ""

echo "Done! Admin gateway now includes longhorn.${SIAB_DOMAIN}"
