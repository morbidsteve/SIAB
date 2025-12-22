#!/bin/bash
# SIAB - Kubectl Helper Library
# Kubernetes operations helpers for install and uninstall scripts

# Requires: logging.sh, utils.sh to be sourced first

# Wait for all pods in a namespace to be ready
# Usage: wait_for_pods namespace [timeout_seconds]
wait_for_pods() {
    local namespace="$1"
    local timeout="${2:-300}"

    log_info "Waiting for pods in $namespace to be ready..."
    kubectl wait --for=condition=Ready pod --all -n "$namespace" --timeout="${timeout}s" 2>/dev/null || {
        log_warn "Some pods in $namespace may not be ready after ${timeout}s"
        return 1
    }
}

# Wait for specific deployment to be available
# Usage: wait_for_deployment namespace deployment_name [timeout_seconds]
wait_for_deployment() {
    local namespace="$1"
    local deployment="$2"
    local timeout="${3:-300}"

    log_info "Waiting for deployment $deployment in $namespace..."
    kubectl wait --for=condition=Available deployment/"$deployment" -n "$namespace" --timeout="${timeout}s" 2>/dev/null || {
        log_warn "Deployment $deployment in $namespace not available after ${timeout}s"
        return 1
    }
}

# Wait for all deployments in a namespace to be available
# Usage: wait_for_all_deployments namespace [timeout_seconds]
wait_for_all_deployments() {
    local namespace="$1"
    local timeout="${2:-300}"

    log_info "Waiting for all deployments in $namespace to be available..."
    kubectl wait --for=condition=Available deployment --all -n "$namespace" --timeout="${timeout}s" 2>/dev/null || {
        log_warn "Some deployments in $namespace may not be available after ${timeout}s"
        return 1
    }
}

# Wait for a StatefulSet to be ready
# Usage: wait_for_statefulset namespace statefulset_name [timeout_seconds]
wait_for_statefulset() {
    local namespace="$1"
    local statefulset="$2"
    local timeout="${3:-300}"
    local interval=5
    local elapsed=0

    log_info "Waiting for StatefulSet $statefulset in $namespace..."

    while [[ $elapsed -lt $timeout ]]; do
        local ready
        ready=$(kubectl get statefulset "$statefulset" -n "$namespace" -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        local desired
        desired=$(kubectl get statefulset "$statefulset" -n "$namespace" -o jsonpath='{.spec.replicas}' 2>/dev/null || echo "1")

        if [[ "$ready" -ge "$desired" && "$ready" -gt 0 ]]; then
            log_info "StatefulSet $statefulset is ready ($ready/$desired replicas)"
            return 0
        fi

        sleep $interval
        ((elapsed += interval))
    done

    log_warn "StatefulSet $statefulset not ready after ${timeout}s"
    return 1
}

# Wait for pods with a specific label to be running
# Usage: wait_for_labeled_pods namespace label [timeout_seconds]
wait_for_labeled_pods() {
    local namespace="$1"
    local label="$2"
    local timeout="${3:-300}"

    log_info "Waiting for pods with label $label in $namespace..."
    kubectl wait --for=condition=Ready pod -l "$label" -n "$namespace" --timeout="${timeout}s" 2>/dev/null || {
        log_warn "Pods with label $label in $namespace not ready after ${timeout}s"
        return 1
    }
}

# Create namespace if it doesn't exist
# Usage: ensure_namespace namespace [labels]
ensure_namespace() {
    local namespace="$1"
    local labels="${2:-}"

    if ! kubectl get namespace "$namespace" &>/dev/null; then
        log_info "Creating namespace: $namespace"
        kubectl create namespace "$namespace"

        if [[ -n "$labels" ]]; then
            kubectl label namespace "$namespace" $labels --overwrite
        fi
    else
        log_info "Namespace $namespace already exists"
    fi
}

# Apply manifests from stdin or file with retry
# Usage: apply_manifest [file_path] or echo "yaml" | apply_manifest
apply_manifest() {
    local file="${1:-}"
    local max_attempts=3
    local attempt=1

    while [[ $attempt -le $max_attempts ]]; do
        if [[ -n "$file" ]]; then
            if kubectl apply -f "$file" 2>>"${SIAB_LOG_FILE:-/dev/null}"; then
                return 0
            fi
        else
            if kubectl apply -f - 2>>"${SIAB_LOG_FILE:-/dev/null}"; then
                return 0
            fi
        fi

        log_warn "Apply attempt $attempt/$max_attempts failed, retrying..."
        sleep $((attempt * 2))
        ((attempt++))
    done

    log_error "Failed to apply manifest after $max_attempts attempts"
    return 1
}

# Get the status of a namespace
# Usage: get_namespace_status namespace
get_namespace_status() {
    local namespace="$1"
    kubectl get namespace "$namespace" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound"
}

# Check if namespace exists
# Usage: namespace_exists namespace
namespace_exists() {
    kubectl get namespace "$1" &>/dev/null
}

# Get pod count by status in a namespace
# Usage: get_pod_count_by_status namespace status
get_pod_count_by_status() {
    local namespace="$1"
    local status="$2"
    kubectl get pods -n "$namespace" --no-headers 2>/dev/null | grep -c "$status" || echo "0"
}

# Get cluster nodes status
get_nodes_ready() {
    kubectl get nodes -o jsonpath='{.items[*].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null | grep -c "True" || echo "0"
}

# Setup kubeconfig for RKE2
setup_kubeconfig() {
    if [[ -f /etc/rancher/rke2/rke2.yaml ]]; then
        export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
        export PATH="/var/lib/rancher/rke2/bin:${PATH}"
        return 0
    fi
    return 1
}

# Check if cluster is accessible
cluster_accessible() {
    kubectl cluster-info &>/dev/null 2>&1
}
