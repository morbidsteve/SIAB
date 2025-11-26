#!/bin/bash

# Check gateway IPs and compare with /etc/hosts

set -e

export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH="/var/lib/rancher/rke2/bin:${PATH}"

echo "============================================"
echo "  Gateway IP Check"
echo "============================================"
echo ""

echo "[1] Istio Gateway Services"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl get svc -n istio-system -l istio
echo ""

echo "[2] Admin Gateway IP"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ADMIN_IP=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Not assigned")
echo "Admin Gateway IP: $ADMIN_IP"
echo ""

echo "[3] User Gateway IP"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
USER_IP=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "Not assigned")
echo "User Gateway IP: $USER_IP"
echo ""

echo "[4] /etc/hosts entries"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
grep -E "keycloak|minio|grafana|longhorn|siab.local" /etc/hosts || echo "No entries found"
echo ""

echo "[5] Expected /etc/hosts entries"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Admin services should point to: $ADMIN_IP"
echo "User services should point to: $USER_IP"
echo ""
echo "Expected entries:"
echo "$ADMIN_IP keycloak.siab.local minio.siab.local grafana.siab.local k8s-dashboard.siab.local longhorn.siab.local"
echo "$USER_IP siab.local dashboard.siab.local catalog.siab.local"
echo ""

echo "[6] Test curl to admin gateway IP"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ "$ADMIN_IP" != "Not assigned" ]; then
    echo "Testing: curl -k -H 'Host: keycloak.siab.local' https://$ADMIN_IP/"
    curl -k -v -H 'Host: keycloak.siab.local' "https://$ADMIN_IP/" 2>&1 | head -30
else
    echo "Admin gateway IP not assigned"
fi
echo ""

echo "Done!"
