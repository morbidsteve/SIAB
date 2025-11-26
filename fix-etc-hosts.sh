#!/bin/bash

# Fix /etc/hosts entries for SIAB services
# This removes conflicting entries and sets up correct gateway IPs

set -e

export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH="/var/lib/rancher/rke2/bin:${PATH}"

echo "============================================"
echo "  Fix /etc/hosts for SIAB Services"
echo "============================================"
echo ""

# Get gateway IPs
ADMIN_IP=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
USER_IP=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

if [ -z "$ADMIN_IP" ] || [ -z "$USER_IP" ]; then
    echo "ERROR: Could not get gateway IPs"
    echo "Admin IP: $ADMIN_IP"
    echo "User IP: $USER_IP"
    exit 1
fi

echo "Gateway IPs:"
echo "  Admin: $ADMIN_IP"
echo "  User: $USER_IP"
echo ""

# Backup current /etc/hosts
cp /etc/hosts /etc/hosts.backup.$(date +%Y%m%d-%H%M%S)
echo "✓ Backed up /etc/hosts"

# Remove all siab.local entries
sed -i '/siab\.local/d' /etc/hosts
echo "✓ Removed old siab.local entries"

# Add correct entries
cat >> /etc/hosts <<EOF

# SIAB - Admin Plane ($(date))
$ADMIN_IP keycloak.siab.local minio.siab.local grafana.siab.local k8s-dashboard.siab.local longhorn.siab.local

# SIAB - User Plane ($(date))
$USER_IP siab.local dashboard.siab.local catalog.siab.local
EOF

echo "✓ Added correct entries"
echo ""

echo "New /etc/hosts entries:"
grep siab.local /etc/hosts
echo ""

echo "============================================"
echo "  Testing Connections"
echo "============================================"
echo ""

echo "Testing keycloak.siab.local (should resolve to $ADMIN_IP):"
getent hosts keycloak.siab.local || echo "DNS lookup failed"
echo ""

echo "Testing siab.local (should resolve to $USER_IP):"
getent hosts siab.local || echo "DNS lookup failed"
echo ""

echo "Done! /etc/hosts has been fixed."
echo ""
echo "Old /etc/hosts backed up to: /etc/hosts.backup.*"
echo ""
