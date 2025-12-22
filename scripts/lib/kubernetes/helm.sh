#!/bin/bash
# SIAB - Helm Helper Library
# Helm operations helpers for install and uninstall scripts

# Requires: logging.sh, config.sh to be sourced first

# Check if a Helm release is installed and ready
# Usage: check_helm_release namespace release_name
check_helm_release() {
    local namespace="$1"
    local release_name="$2"

    if ! helm status "$release_name" -n "$namespace" &>/dev/null; then
        return 1
    fi

    # Check if all pods are running
    local pods_running
    pods_running=$(kubectl get pods -n "$namespace" -l "app.kubernetes.io/instance=$release_name" --no-headers 2>/dev/null | grep -c "Running" || echo "0")

    if [[ "$pods_running" -gt 0 ]]; then
        return 0
    fi

    return 1
}

# Add a Helm repository if not already added
# Usage: add_helm_repo name url
add_helm_repo() {
    local name="$1"
    local url="$2"

    if ! helm repo list 2>/dev/null | grep -q "^$name"; then
        log_info "Adding Helm repository: $name"
        helm repo add "$name" "$url" 2>>"${SIAB_LOG_FILE:-/dev/null}" || {
            log_warn "Failed to add Helm repo $name"
            return 1
        }
    else
        log_info "Helm repository $name already exists"
    fi
}

# Add all SIAB required Helm repositories
add_all_helm_repos() {
    log_info "Adding all required Helm repositories..."

    add_helm_repo "jetstack" "https://charts.jetstack.io"
    add_helm_repo "istio" "https://istio-release.storage.googleapis.com/charts"
    add_helm_repo "metallb" "https://metallb.github.io/metallb"
    add_helm_repo "longhorn" "https://charts.longhorn.io"
    add_helm_repo "bitnami" "https://charts.bitnami.com/bitnami"
    add_helm_repo "oauth2-proxy" "https://oauth2-proxy.github.io/manifests"
    add_helm_repo "minio" "https://charts.min.io/"
    add_helm_repo "aqua" "https://aquasecurity.github.io/helm-charts/"
    add_helm_repo "gatekeeper" "https://open-policy-agent.github.io/gatekeeper/charts"
    add_helm_repo "prometheus-community" "https://prometheus-community.github.io/helm-charts"
    add_helm_repo "kubernetes-dashboard" "https://kubernetes.github.io/dashboard/"

    log_info "Updating Helm repositories..."
    helm repo update 2>>"${SIAB_LOG_FILE:-/dev/null}" || true
}

# Update Helm repositories
update_helm_repos() {
    log_info "Updating Helm repositories..."
    helm repo update 2>>"${SIAB_LOG_FILE:-/dev/null}" || {
        log_warn "Failed to update some Helm repositories"
    }
}

# Install or upgrade a Helm release
# Usage: helm_install_upgrade namespace release_name chart [extra_args...]
helm_install_upgrade() {
    local namespace="$1"
    local release_name="$2"
    local chart="$3"
    shift 3
    local extra_args=("$@")

    log_info "Installing/upgrading Helm release: $release_name in $namespace"

    helm upgrade --install "$release_name" "$chart" \
        --namespace "$namespace" \
        --create-namespace \
        "${extra_args[@]}" 2>>"${SIAB_LOG_FILE:-/dev/null}" || {
        log_error "Failed to install Helm release $release_name"
        return 1
    }

    log_info "Helm release $release_name installed/upgraded successfully"
}

# Uninstall a Helm release safely
# Usage: helm_uninstall namespace release_name [--no-hooks]
helm_uninstall() {
    local namespace="$1"
    local release_name="$2"
    local no_hooks="${3:-}"

    if ! helm status "$release_name" -n "$namespace" &>/dev/null; then
        log_info "Helm release $release_name not found in $namespace, skipping"
        return 0
    fi

    log_info "Uninstalling Helm release: $release_name from $namespace"

    local args=("--namespace" "$namespace")
    if [[ "$no_hooks" == "--no-hooks" ]]; then
        args+=("--no-hooks")
    fi

    run_with_timeout 60 helm uninstall "$release_name" "${args[@]}" 2>>"${SIAB_LOG_FILE:-/dev/null}" || {
        log_warn "Helm uninstall for $release_name may have timed out or failed"
        return 1
    }

    log_info "Helm release $release_name uninstalled"
}

# List all Helm releases
list_helm_releases() {
    helm list --all-namespaces 2>/dev/null
}

# Get Helm release status
get_helm_release_status() {
    local namespace="$1"
    local release_name="$2"

    helm status "$release_name" -n "$namespace" -o json 2>/dev/null | jq -r '.info.status' || echo "not-found"
}

# Check if Helm is installed
helm_installed() {
    command -v helm &>/dev/null
}
