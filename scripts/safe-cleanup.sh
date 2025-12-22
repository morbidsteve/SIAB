#!/bin/bash
# SIAB Safe Cleanup - Cleans Kubernetes state WITHOUT breaking SSH
# This script ONLY removes K8s workloads, it does NOT touch RKE2 or networking

set -uo pipefail

echo "========================================"
echo "  SIAB Safe Cleanup (SSH-safe)"
echo "========================================"
echo ""
echo "This will clean up Kubernetes workloads but keep RKE2 running."
echo "Your SSH connection will NOT be interrupted."
echo ""

# Setup kubeconfig
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH=/var/lib/rancher/rke2/bin:$PATH

# Check if kubectl works
if ! kubectl get nodes &>/dev/null; then
    echo "Kubernetes not accessible. Nothing to clean."
    exit 0
fi

echo "=== Deleting Helm releases ==="
helm list -A --no-headers 2>/dev/null | while read -r name ns _rest; do
    echo "  Deleting release: $name (ns: $ns)"
    helm uninstall "$name" -n "$ns" --wait=false 2>/dev/null || true
done

echo ""
echo "=== Deleting SIAB namespaces ==="
NAMESPACES=(
    "siab-dashboard"
    "siab-deployer"
    "istio-system"
    "istio-ingress"
    "keycloak"
    "oauth2-proxy"
    "minio"
    "longhorn-system"
    "monitoring"
    "cert-manager"
    "gatekeeper-system"
    "trivy-system"
    "kubernetes-dashboard"
    "metallb-system"
)

for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &>/dev/null; then
        echo "  Deleting namespace: $ns"
        # Remove finalizers first to prevent stuck namespaces
        kubectl get namespace "$ns" -o json 2>/dev/null | \
            jq '.spec.finalizers = []' | \
            kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || true
        kubectl delete namespace "$ns" --force --grace-period=0 2>/dev/null &
    fi
done

echo ""
echo "=== Deleting webhook configurations ==="
kubectl delete validatingwebhookconfigurations --all 2>/dev/null || true
kubectl delete mutatingwebhookconfigurations --all 2>/dev/null || true

echo ""
echo "=== Deleting cluster-wide RBAC ==="
kubectl delete clusterrolebinding -l "app.kubernetes.io/managed-by=siab" 2>/dev/null || true
kubectl delete clusterrole -l "app.kubernetes.io/managed-by=siab" 2>/dev/null || true

echo ""
echo "=== Waiting for namespace cleanup ==="
sleep 10

# Force delete any remaining stuck namespaces
for ns in "${NAMESPACES[@]}"; do
    if kubectl get namespace "$ns" &>/dev/null 2>&1; then
        echo "  Force removing finalizers from: $ns"
        kubectl get namespace "$ns" -o json 2>/dev/null | \
            jq '.spec.finalizers = []' | \
            kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || true
    fi
done

echo ""
echo "=== Current namespace state ==="
kubectl get namespaces

echo ""
echo "=== Current pod state ==="
kubectl get pods -A 2>/dev/null | head -30

echo ""
echo "========================================"
echo "  Safe Cleanup Complete"
echo "========================================"
echo ""
echo "RKE2 is still running - you can now run the install script"
echo "to deploy SIAB fresh on the existing cluster."
echo ""
