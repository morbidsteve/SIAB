#!/bin/bash
# SIAB Access Information
# Shows all URLs, credentials, and access details

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    export PATH=$PATH:/var/lib/rancher/rke2/bin:/usr/local/bin
fi

# Check kubeconfig
if [[ ! -f ~/.kube/config ]] && [[ ! -f /etc/rancher/rke2/rke2.yaml ]]; then
    echo -e "${RED}Error: No kubeconfig found. Run as root or ensure kubectl is configured.${NC}"
    exit 1
fi

if [[ -f /etc/rancher/rke2/rke2.yaml ]] && [[ ! -f ~/.kube/config ]]; then
    export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
fi

# Get domain and gateway IPs from config
SIAB_DOMAIN="siab.local"
ADMIN_GATEWAY_IP=""
USER_GATEWAY_IP=""
if [[ -f /etc/siab/credentials.env ]]; then
    source /etc/siab/credentials.env 2>/dev/null
    SIAB_DOMAIN="${SIAB_DOMAIN:-siab.local}"
fi

# Try to get gateway IPs from LoadBalancer services if not in credentials
if [[ -z "$ADMIN_GATEWAY_IP" ]]; then
    ADMIN_GATEWAY_IP=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
fi
if [[ -z "$USER_GATEWAY_IP" ]]; then
    USER_GATEWAY_IP=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
fi

# Fallback to node IP if LoadBalancer IPs not available
if [[ -z "$ADMIN_GATEWAY_IP" ]] || [[ -z "$USER_GATEWAY_IP" ]]; then
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)
    ADMIN_GATEWAY_IP="${ADMIN_GATEWAY_IP:-$NODE_IP}"
    USER_GATEWAY_IP="${USER_GATEWAY_IP:-$NODE_IP}"
fi

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║              SIAB - Access Information                         ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Network Architecture
echo -e "${BLUE}▸ Network Architecture${NC}"
echo "  ─────────────────────────────────────────────────────────────"
echo ""
echo "  Admin Gateway IP:  ${ADMIN_GATEWAY_IP} (administrative services)"
echo "  User Gateway IP:   ${USER_GATEWAY_IP} (user-facing applications)"
echo ""

# /etc/hosts entry
echo -e "${BLUE}▸ Add to /etc/hosts (on your client machine)${NC}"
echo "  ─────────────────────────────────────────────────────────────"
echo ""
echo -e "  ${GREEN}# Admin Plane (restricted access)${NC}"
echo -e "  ${GREEN}${ADMIN_GATEWAY_IP} keycloak.${SIAB_DOMAIN} minio.${SIAB_DOMAIN} grafana.${SIAB_DOMAIN} longhorn.${SIAB_DOMAIN} k8s-dashboard.${SIAB_DOMAIN}${NC}"
echo ""
echo -e "  ${GREEN}# User Plane${NC}"
echo -e "  ${GREEN}${USER_GATEWAY_IP} ${SIAB_DOMAIN} dashboard.${SIAB_DOMAIN} catalog.${SIAB_DOMAIN} deployer.${SIAB_DOMAIN}${NC}"
echo ""
echo "  Windows: C:\\Windows\\System32\\drivers\\etc\\hosts"
echo "  Linux/Mac: /etc/hosts"
echo ""

# Admin Plane Services
echo -e "${BLUE}▸ Admin Plane Services (port 443) - RESTRICTED${NC}"
echo "  ─────────────────────────────────────────────────────────────"
echo ""
echo "  Keycloak (Identity):     https://keycloak.${SIAB_DOMAIN}"
echo "  MinIO (Storage):         https://minio.${SIAB_DOMAIN}"
echo "  Grafana (Monitoring):    https://grafana.${SIAB_DOMAIN}"
echo "  Longhorn (Block Storage):https://longhorn.${SIAB_DOMAIN}"
echo "  Kubernetes Dashboard:    https://k8s-dashboard.${SIAB_DOMAIN}"
echo ""

# User Plane Services
echo -e "${BLUE}▸ User Plane Services (port 443)${NC}"
echo "  ─────────────────────────────────────────────────────────────"
echo ""
echo "  SIAB Dashboard:          https://dashboard.${SIAB_DOMAIN}"
echo "  App Catalog:             https://catalog.${SIAB_DOMAIN}"
echo "  App Deployer:            https://deployer.${SIAB_DOMAIN}"
echo ""
echo -e "${YELLOW}Note: Accept the self-signed certificate warning in your browser${NC}"
echo ""

# Direct IP access (port-forward alternative for troubleshooting)
SERVER_IP="${ADMIN_GATEWAY_IP:-localhost}"
echo -e "${BLUE}▸ Direct IP Access (via port-forward - for troubleshooting)${NC}"
echo "  ─────────────────────────────────────────────────────────────"
echo ""
echo "  Run these commands on the server, then access from browser:"
echo ""
echo "  # Grafana - http://${SERVER_IP}:3000"
echo "  kubectl port-forward -n monitoring svc/kube-prometheus-stack-grafana 3000:80 --address 0.0.0.0"
echo ""
echo "  # Keycloak - http://${SERVER_IP}:8080"
echo "  kubectl port-forward -n keycloak svc/keycloak 8080:80 --address 0.0.0.0"
echo ""
echo "  # MinIO Console - http://${SERVER_IP}:9001"
echo "  kubectl port-forward -n minio svc/minio-console 9001:9001 --address 0.0.0.0"
echo ""
echo "  # K8s Dashboard - https://${SERVER_IP}:8443"
echo "  kubectl port-forward -n kubernetes-dashboard svc/kubernetes-dashboard-kong-proxy 8443:443 --address 0.0.0.0"
echo ""

# Credentials
echo -e "${BLUE}▸ Credentials${NC}"
echo "  ─────────────────────────────────────────────────────────────"
echo ""
if [[ -f /etc/siab/credentials.env ]]; then
    if [[ -r /etc/siab/credentials.env ]]; then
        echo "  Grafana:"
        echo "    Username: admin"
        echo "    Password: ${GRAFANA_ADMIN_PASSWORD:-<run as root to see>}"
        echo ""
        echo "  Keycloak:"
        echo "    Username: ${KEYCLOAK_ADMIN_USER:-admin}"
        echo "    Password: ${KEYCLOAK_ADMIN_PASSWORD:-<run as root to see>}"
        echo ""
        echo "  MinIO:"
        echo "    Username: ${MINIO_ROOT_USER:-admin}"
        echo "    Password: ${MINIO_ROOT_PASSWORD:-<run as root to see>}"
        echo ""
    else
        echo "  Run as root to see credentials, or view:"
        echo "  sudo cat /etc/siab/credentials.env"
        echo ""
    fi
else
    echo "  Credentials file not found at /etc/siab/credentials.env"
    echo ""
fi

# Check for user's local credentials copy
if [[ -f ~/.siab-credentials.env ]]; then
    echo "  Your local copy: ~/.siab-credentials.env"
    echo ""
fi

# Kubernetes Dashboard Token
echo -e "${BLUE}▸ Kubernetes Dashboard Token${NC}"
echo "  ─────────────────────────────────────────────────────────────"
echo ""
DASHBOARD_TOKEN=$(kubectl get secret siab-admin-token -n kubernetes-dashboard -o jsonpath='{.data.token}' 2>/dev/null | base64 -d 2>/dev/null)
if [[ -n "$DASHBOARD_TOKEN" ]]; then
    echo "  Use this token to log into the Kubernetes Dashboard:"
    echo ""
    echo "  ${DASHBOARD_TOKEN}"
    echo ""
else
    echo "  Token not available. Run as root or check if dashboard is installed."
    echo ""
fi

# Quick commands
echo -e "${BLUE}▸ SIAB Commands${NC}"
echo "  ─────────────────────────────────────────────────────────────"
echo ""
echo "  siab-status      - View platform health status"
echo "  siab-info        - Show this access information"
echo "  siab-fix-rke2    - Troubleshoot RKE2 issues"
echo "  siab-fix-istio   - Fix Istio routing issues"
echo "  siab-uninstall   - Remove SIAB completely"
echo ""
echo -e "${BLUE}▸ Kubernetes Commands${NC}"
echo "  ─────────────────────────────────────────────────────────────"
echo ""
echo "  k9s              - Interactive cluster UI (terminal)"
echo "  kubectl get pods -A   - List all pods"
echo "  helm list -A     - List installed Helm charts"
echo ""

echo -e "${BLUE}▸ Initial Setup Checklist${NC}"
echo "  ─────────────────────────────────────────────────────────────"
echo ""
echo "  1. Add /etc/hosts entries on client machines (see above)"
echo "  2. Accept self-signed certificate warnings in browser"
echo "  3. Log into Keycloak and create a realm for your apps"
echo "  4. Log into MinIO and create buckets for storage"
echo "  5. Log into Grafana and explore monitoring dashboards"
echo "  6. Deploy apps via catalog: https://catalog.${SIAB_DOMAIN}"
echo ""
echo -e "  ${GREEN}Full guide: docs/GETTING-STARTED.md${NC}"
echo ""

echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
