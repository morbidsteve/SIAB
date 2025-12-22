#!/bin/bash
# SIAB - Configuration Library
# Centralized version pins, paths, and default configuration

# SIAB Version
readonly SIAB_VERSION="1.0.0"

# Directory paths
readonly SIAB_DIR="/opt/siab"
readonly SIAB_CONFIG_DIR="/etc/siab"
readonly SIAB_LOG_DIR="/var/log/siab"
readonly SIAB_BIN_DIR="/usr/local/bin"
# Allow SIAB_REPO_DIR to be set by install.sh to point to source directory
SIAB_REPO_DIR="${SIAB_REPO_DIR:-${SIAB_DIR}/repo}"

# Ensure SIAB bin directory is in PATH
export PATH="${SIAB_BIN_DIR}:/var/lib/rancher/rke2/bin:${PATH}"

# Component versions (pinned for security)
# These can be overridden via environment variables
readonly RKE2_VERSION="${RKE2_VERSION:-v1.28.4+rke2r1}"
readonly HELM_VERSION="${HELM_VERSION:-v3.13.3}"
readonly ISTIO_VERSION="${ISTIO_VERSION:-1.20.1}"
readonly KEYCLOAK_VERSION="${KEYCLOAK_VERSION:-23.0.3}"
readonly MINIO_VERSION="${MINIO_VERSION:-5.0.15}"
readonly TRIVY_VERSION="${TRIVY_VERSION:-0.18.4}"
readonly GATEKEEPER_VERSION="${GATEKEEPER_VERSION:-3.14.0}"
readonly CERTMANAGER_VERSION="${CERTMANAGER_VERSION:-v1.13.3}"
readonly PROMETHEUS_STACK_VERSION="${PROMETHEUS_STACK_VERSION:-56.6.2}"
readonly KUBE_DASHBOARD_VERSION="${KUBE_DASHBOARD_VERSION:-7.1.0}"
readonly LONGHORN_VERSION="${LONGHORN_VERSION:-1.5.3}"

# Runtime configuration (can be overridden via environment)
SIAB_DOMAIN="${SIAB_DOMAIN:-siab.local}"
SIAB_ADMIN_EMAIL="${SIAB_ADMIN_EMAIL:-admin@${SIAB_DOMAIN}}"
SIAB_SKIP_MONITORING="${SIAB_SKIP_MONITORING:-false}"
SIAB_SKIP_STORAGE="${SIAB_SKIP_STORAGE:-false}"
SIAB_SKIP_LONGHORN="${SIAB_SKIP_LONGHORN:-false}"
SIAB_MINIO_SIZE="${SIAB_MINIO_SIZE:-20Gi}"
SIAB_SINGLE_NODE="${SIAB_SINGLE_NODE:-true}"

# Kubernetes namespaces used by SIAB
readonly SIAB_NAMESPACES=(
    "cert-manager"
    "istio-system"
    "metallb-system"
    "longhorn-system"
    "keycloak"
    "oauth2-proxy"
    "minio"
    "trivy-system"
    "gatekeeper-system"
    "monitoring"
    "kubernetes-dashboard"
    "siab-system"
    "siab-dashboard"
    "siab-deployer"
)

# Helm repositories
declare -A HELM_REPOS=(
    ["jetstack"]="https://charts.jetstack.io"
    ["istio"]="https://istio-release.storage.googleapis.com/charts"
    ["metallb"]="https://metallb.github.io/metallb"
    ["longhorn"]="https://charts.longhorn.io"
    ["bitnami"]="https://charts.bitnami.com/bitnami"
    ["oauth2-proxy"]="https://oauth2-proxy.github.io/manifests"
    ["minio"]="https://charts.min.io/"
    ["aqua"]="https://aquasecurity.github.io/helm-charts/"
    ["gatekeeper"]="https://open-policy-agent.github.io/gatekeeper/charts"
    ["prometheus-community"]="https://prometheus-community.github.io/helm-charts"
    ["kubernetes-dashboard"]="https://kubernetes.github.io/dashboard/"
)

# Export configuration
export SIAB_VERSION SIAB_DIR SIAB_CONFIG_DIR SIAB_LOG_DIR SIAB_BIN_DIR SIAB_REPO_DIR
export SIAB_DOMAIN SIAB_ADMIN_EMAIL
export SIAB_SKIP_MONITORING SIAB_SKIP_STORAGE SIAB_SKIP_LONGHORN
export SIAB_MINIO_SIZE SIAB_SINGLE_NODE
