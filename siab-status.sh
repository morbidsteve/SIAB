#!/bin/bash
# SIAB Status Check Script
# Shows the current status of all SIAB components

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

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║              SIAB - Secure Infrastructure Status               ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

# Function to check component status
check_component() {
    local namespace=$1
    local name=$2
    local display_name=$3

    local ready=$(kubectl get deployment,statefulset -n "$namespace" -l "app=$name" -o jsonpath='{.items[*].status.readyReplicas}' 2>/dev/null | awk '{sum=0; for(i=1;i<=NF;i++) sum+=$i; print sum}')
    local desired=$(kubectl get deployment,statefulset -n "$namespace" -l "app=$name" -o jsonpath='{.items[*].status.replicas}' 2>/dev/null | awk '{sum=0; for(i=1;i<=NF;i++) sum+=$i; print sum}')

    if [[ -z "$ready" ]] || [[ "$ready" == "0" ]]; then
        # Try without label selector
        ready=$(kubectl get pods -n "$namespace" --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        desired=$(kubectl get pods -n "$namespace" --no-headers 2>/dev/null | wc -l)
    fi

    if [[ "$ready" -gt 0 ]] && [[ "$ready" -eq "$desired" ]]; then
        echo -e "  ${GREEN}●${NC} $display_name: ${GREEN}Running${NC} ($ready/$desired replicas)"
    elif [[ "$ready" -gt 0 ]]; then
        echo -e "  ${YELLOW}●${NC} $display_name: ${YELLOW}Partial${NC} ($ready/$desired replicas)"
    else
        echo -e "  ${RED}●${NC} $display_name: ${RED}Not Running${NC}"
    fi
}

# Cluster Info
echo -e "${BLUE}▸ Cluster Information${NC}"
echo "  ─────────────────────────────────────────"
node_info=$(kubectl get nodes -o wide --no-headers 2>/dev/null)
if [[ -n "$node_info" ]]; then
    while IFS= read -r line; do
        name=$(echo "$line" | awk '{print $1}')
        status=$(echo "$line" | awk '{print $2}')
        version=$(echo "$line" | awk '{print $5}')
        ip=$(echo "$line" | awk '{print $6}')
        if [[ "$status" == "Ready" ]]; then
            echo -e "  ${GREEN}●${NC} Node: $name ($ip) - $version"
        else
            echo -e "  ${RED}●${NC} Node: $name ($ip) - $status"
        fi
    done <<< "$node_info"
else
    echo -e "  ${RED}●${NC} Unable to get node information"
fi
echo ""

# Core Infrastructure
echo -e "${BLUE}▸ Core Infrastructure${NC}"
echo "  ─────────────────────────────────────────"

# RKE2/Kubernetes
kube_version=$(kubectl version --short 2>/dev/null | grep Server | awk '{print $3}' || kubectl version -o json 2>/dev/null | jq -r '.serverVersion.gitVersion' 2>/dev/null)
if [[ -n "$kube_version" ]]; then
    echo -e "  ${GREEN}●${NC} Kubernetes: ${GREEN}Running${NC} ($kube_version)"
else
    echo -e "  ${RED}●${NC} Kubernetes: ${RED}Not Responding${NC}"
fi

# Istio
istio_pods=$(kubectl get pods -n istio-system --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
istio_total=$(kubectl get pods -n istio-system --no-headers 2>/dev/null | wc -l)
if [[ "$istio_pods" -gt 0 ]]; then
    echo -e "  ${GREEN}●${NC} Istio Service Mesh: ${GREEN}Running${NC} ($istio_pods/$istio_total pods)"
else
    echo -e "  ${RED}●${NC} Istio Service Mesh: ${RED}Not Running${NC}"
fi

# Cert-Manager
cm_pods=$(kubectl get pods -n cert-manager --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [[ "$cm_pods" -gt 0 ]]; then
    echo -e "  ${GREEN}●${NC} Cert-Manager: ${GREEN}Running${NC} ($cm_pods pods)"
else
    echo -e "  ${RED}●${NC} Cert-Manager: ${RED}Not Running${NC}"
fi
echo ""

# Platform Services
echo -e "${BLUE}▸ Platform Services${NC}"
echo "  ─────────────────────────────────────────"

# Keycloak
kc_ready=$(kubectl get deployment keycloak -n keycloak -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
kc_desired=$(kubectl get deployment keycloak -n keycloak -o jsonpath='{.status.replicas}' 2>/dev/null)
if [[ "$kc_ready" -gt 0 ]] && [[ "$kc_ready" == "$kc_desired" ]]; then
    echo -e "  ${GREEN}●${NC} Keycloak (Identity): ${GREEN}Running${NC} ($kc_ready/$kc_desired replicas)"
elif [[ -n "$kc_ready" ]] && [[ "$kc_ready" -gt 0 ]]; then
    echo -e "  ${YELLOW}●${NC} Keycloak (Identity): ${YELLOW}Starting${NC} ($kc_ready/$kc_desired replicas)"
else
    echo -e "  ${RED}●${NC} Keycloak (Identity): ${RED}Not Running${NC}"
fi

# MinIO
minio_ready=$(kubectl get deployment minio -n minio -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
minio_desired=$(kubectl get deployment minio -n minio -o jsonpath='{.status.replicas}' 2>/dev/null)
if [[ "$minio_ready" -gt 0 ]] && [[ "$minio_ready" == "$minio_desired" ]]; then
    echo -e "  ${GREEN}●${NC} MinIO (Storage): ${GREEN}Running${NC} ($minio_ready/$minio_desired replicas)"
elif [[ -n "$minio_ready" ]] && [[ "$minio_ready" -gt 0 ]]; then
    echo -e "  ${YELLOW}●${NC} MinIO (Storage): ${YELLOW}Starting${NC} ($minio_ready/$minio_desired replicas)"
else
    echo -e "  ${RED}●${NC} MinIO (Storage): ${RED}Not Running${NC}"
fi
echo ""

# Security Components
echo -e "${BLUE}▸ Security Components${NC}"
echo "  ─────────────────────────────────────────"

# Trivy
trivy_pods=$(kubectl get pods -n trivy-system --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [[ "$trivy_pods" -gt 0 ]]; then
    echo -e "  ${GREEN}●${NC} Trivy (Vulnerability Scanner): ${GREEN}Running${NC}"
else
    echo -e "  ${RED}●${NC} Trivy (Vulnerability Scanner): ${RED}Not Running${NC}"
fi

# Gatekeeper
gk_pods=$(kubectl get pods -n gatekeeper-system --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
if [[ "$gk_pods" -gt 0 ]]; then
    echo -e "  ${GREEN}●${NC} OPA Gatekeeper (Policy Engine): ${GREEN}Running${NC}"
else
    echo -e "  ${RED}●${NC} OPA Gatekeeper (Policy Engine): ${RED}Not Running${NC}"
fi
echo ""

# Resource Usage
echo -e "${BLUE}▸ Resource Usage${NC}"
echo "  ─────────────────────────────────────────"
node_resources=$(kubectl top nodes 2>/dev/null)
if [[ -n "$node_resources" ]]; then
    echo "$node_resources" | tail -n +2 | while IFS= read -r line; do
        name=$(echo "$line" | awk '{print $1}')
        cpu=$(echo "$line" | awk '{print $2}')
        cpu_pct=$(echo "$line" | awk '{print $3}')
        mem=$(echo "$line" | awk '{print $4}')
        mem_pct=$(echo "$line" | awk '{print $5}')
        echo "  CPU: $cpu ($cpu_pct) | Memory: $mem ($mem_pct)"
    done
else
    echo "  (metrics-server not available - install for resource monitoring)"
fi
echo ""

# Access Information
echo -e "${BLUE}▸ Access Information${NC}"
echo "  ─────────────────────────────────────────"

# Get ingress port
ingress_port=$(kubectl get svc -n istio-system istio-ingress -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}' 2>/dev/null)
node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null)

if [[ -n "$ingress_port" ]] && [[ -n "$node_ip" ]]; then
    domain=$(grep -oP '(?<=SIAB_DOMAIN=)[^\s]+' /etc/siab/credentials.env 2>/dev/null || echo "siab.local")
    echo "  Keycloak:  https://keycloak.${domain}:${ingress_port}"
    echo "  MinIO:     https://minio.${domain}:${ingress_port}"
    echo ""
    echo "  Note: Add entries to /etc/hosts or use IP directly:"
    echo "  https://${node_ip}:${ingress_port}"
fi
echo ""

# Quick Commands
echo -e "${BLUE}▸ Quick Commands${NC}"
echo "  ─────────────────────────────────────────"
echo "  k9s                    - Interactive cluster UI"
echo "  kubectl get pods -A    - List all pods"
echo "  kubectl top pods -A    - Pod resource usage"
echo "  siab-status            - This status page"
echo ""

# Credentials reminder
if [[ -f /etc/siab/credentials.env ]]; then
    echo -e "${YELLOW}▸ Credentials${NC}"
    echo "  ─────────────────────────────────────────"
    echo "  Stored in: /etc/siab/credentials.env"
    echo "  View with: sudo cat /etc/siab/credentials.env"
fi
echo ""
echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
