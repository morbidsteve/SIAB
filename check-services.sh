#!/bin/bash

# Quick diagnostic script for checking service status
# Run with: sudo ./check-services.sh

set -e

export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH="/var/lib/rancher/rke2/bin:${PATH}"

echo "============================================"
echo "  Service Status Check"
echo "============================================"
echo ""

echo "[1] Keycloak Pods"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl get pods -n keycloak -o wide
echo ""

echo "[2] Keycloak Service"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl get svc -n keycloak keycloak
echo ""

echo "[3] Keycloak Endpoints"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl get endpoints -n keycloak keycloak
echo ""

echo "[4] MinIO Pods"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl get pods -n minio -o wide
echo ""

echo "[5] MinIO Services"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl get svc -n minio
echo ""

echo "[6] Grafana Pods"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl get pods -n monitoring -l app.kubernetes.io/name=grafana -o wide
echo ""

echo "[7] Grafana Service"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl get svc -n monitoring -l app.kubernetes.io/name=grafana
echo ""

echo "[8] Longhorn Pods"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl get pods -n longhorn-system -l app=longhorn-ui -o wide
echo ""

echo "[9] Longhorn Service"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl get svc -n longhorn-system longhorn-frontend
echo ""

echo "[10] VirtualServices"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl get virtualservice -n istio-system
echo ""

echo "[11] Gateway Configuration"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
kubectl get gateway -n istio-system admin-gateway -o yaml | grep -A 20 "hosts:"
echo ""

echo "[12] Test connectivity from gateway to Keycloak"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
KEYCLOAK_POD_IP=$(kubectl get pod -n keycloak -l app=keycloak -o jsonpath='{.items[0].status.podIP}')
if [ -n "$KEYCLOAK_POD_IP" ]; then
    echo "Keycloak pod IP: $KEYCLOAK_POD_IP"
    echo "Testing connectivity from admin gateway:"
    kubectl exec -n istio-system deployment/istio-ingress-admin -- wget -q -O- --timeout=5 "http://${KEYCLOAK_POD_IP}:8080" 2>&1 | head -20 || echo "Connection failed"
else
    echo "No Keycloak pod found"
fi
echo ""

echo "[13] Check if Keycloak service has endpoints"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
ENDPOINTS=$(kubectl get endpoints -n keycloak keycloak -o jsonpath='{.subsets[*].addresses[*].ip}')
if [ -z "$ENDPOINTS" ]; then
    echo "ERROR: Keycloak service has NO endpoints!"
    echo "This means the service selector doesn't match any pods"
    echo ""
    echo "Keycloak service selector:"
    kubectl get svc -n keycloak keycloak -o jsonpath='{.spec.selector}'
    echo ""
    echo ""
    echo "Keycloak pod labels:"
    kubectl get pods -n keycloak -o jsonpath='{.items[*].metadata.labels}' | jq .
else
    echo "Keycloak endpoints: $ENDPOINTS"
fi
echo ""

echo "[14] DNS Resolution Test"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Testing from admin gateway pod:"
kubectl exec -n istio-system deployment/istio-ingress-admin -- nslookup keycloak.keycloak.svc.cluster.local 2>&1 || echo "DNS resolution failed"
echo ""

echo "Done!"
