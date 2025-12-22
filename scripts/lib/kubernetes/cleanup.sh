#!/bin/bash
# SIAB - Kubernetes Cleanup Library
# Force deletion and cleanup functions for uninstall script

# Requires: logging.sh, utils.sh to be sourced first

# Force remove finalizers from a resource
# Usage: remove_finalizers resource_type resource_name [namespace]
remove_finalizers() {
    local resource_type="$1"
    local resource_name="$2"
    local namespace="${3:-}"

    if [[ -n "$namespace" ]]; then
        kubectl patch "$resource_type" "$resource_name" -n "$namespace" \
            --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
    else
        kubectl patch "$resource_type" "$resource_name" \
            --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
    fi
}

# Force delete all resources in a namespace
# Usage: force_delete_namespace_resources namespace
force_delete_namespace_resources() {
    local ns="$1"
    log_info "Force deleting resources in namespace: $ns"

    # Get all resource types in the namespace and remove finalizers
    for resource_type in $(kubectl api-resources --verbs=list --namespaced -o name 2>/dev/null); do
        kubectl get "$resource_type" -n "$ns" -o name 2>/dev/null | while read -r item; do
            kubectl patch "$item" -n "$ns" --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
            kubectl delete "$item" -n "$ns" --force --grace-period=0 2>/dev/null || true
        done
    done
}

# Force delete a namespace by removing all finalizers
# Usage: force_delete_namespace namespace
force_delete_namespace() {
    local ns="$1"

    if ! kubectl get namespace "$ns" &>/dev/null; then
        return 0
    fi

    log_info "Force deleting namespace: $ns"

    # First try normal delete with short timeout
    run_with_timeout 10 kubectl delete namespace "$ns" --wait=false

    # Check if namespace is stuck in Terminating
    local phase
    phase=$(kubectl get namespace "$ns" -o jsonpath='{.status.phase}' 2>/dev/null || echo "NotFound")

    if [[ "$phase" == "Terminating" ]]; then
        log_info "Namespace $ns stuck in Terminating, forcing deletion..."

        # Remove finalizers from all resources in the namespace
        force_delete_namespace_resources "$ns"

        # Remove namespace finalizers
        kubectl get namespace "$ns" -o json 2>/dev/null | \
            jq '.spec.finalizers = []' | \
            kubectl replace --raw "/api/v1/namespaces/$ns/finalize" -f - 2>/dev/null || true
    fi
}

# Force delete CRDs by removing finalizers first
# Usage: force_delete_crds pattern
force_delete_crds() {
    local pattern="$1"
    log_info "Force deleting CRDs matching: $pattern"

    kubectl get crd -o name 2>/dev/null | grep -E "$pattern" | while read -r crd; do
        local crd_name="${crd#customresourcedefinition.apiextensions.k8s.io/}"
        log_info "Deleting CRD: $crd_name"

        # First, delete all instances of this CRD with finalizers removed
        local api_resource
        api_resource=$(kubectl get crd "$crd_name" -o jsonpath='{.spec.names.plural}' 2>/dev/null || echo "")
        local api_group
        api_group=$(kubectl get crd "$crd_name" -o jsonpath='{.spec.group}' 2>/dev/null || echo "")

        if [[ -n "$api_resource" ]]; then
            # Remove finalizers from all instances
            kubectl get "$api_resource.$api_group" -A -o name 2>/dev/null | while read -r instance; do
                local ns
                ns=$(echo "$instance" | cut -d/ -f1)
                local name
                name=$(echo "$instance" | cut -d/ -f2)
                kubectl patch "$api_resource.$api_group" "$name" ${ns:+-n "$ns"} \
                    --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true
            done

            # Delete all instances
            kubectl delete "$api_resource.$api_group" -A --all --force --grace-period=0 2>/dev/null || true
        fi

        # Remove finalizers from the CRD itself
        kubectl patch crd "$crd_name" --type=merge -p '{"metadata":{"finalizers":[]}}' 2>/dev/null || true

        # Delete the CRD with timeout
        run_with_timeout 10 kubectl delete crd "$crd_name" --force --grace-period=0
    done
}

# Delete all Helm releases quickly
# Usage: delete_all_helm_releases
delete_all_helm_releases() {
    if ! command -v helm &>/dev/null; then
        return 0
    fi

    log_info "Removing all Helm releases..."

    # Get all releases and delete them with short timeout
    helm list --all-namespaces -q 2>/dev/null | while read -r release; do
        if [[ -n "$release" ]]; then
            local ns
            ns=$(helm list --all-namespaces 2>/dev/null | grep "^$release" | awk '{print $2}')
            log_info "Removing Helm release: $release (namespace: $ns)"
            run_with_timeout 30 helm uninstall "$release" -n "$ns" --no-hooks 2>/dev/null || true
        fi
    done
}

# Remove webhook configurations that might block deletions
# Usage: delete_webhooks
delete_webhooks() {
    log_info "Removing webhook configurations..."
    kubectl delete validatingwebhookconfiguration --all 2>/dev/null || true
    kubectl delete mutatingwebhookconfiguration --all 2>/dev/null || true
}

# Delete cluster-wide RBAC resources
# Usage: delete_cluster_rbac resource_names...
delete_cluster_rbac() {
    local resources=("$@")

    log_info "Deleting cluster-wide RBAC resources..."
    for resource in "${resources[@]}"; do
        kubectl delete clusterrolebinding "$resource" 2>/dev/null || true
        kubectl delete clusterrole "$resource" 2>/dev/null || true
    done
}

# Unmount all Kubernetes and Longhorn volumes
# Usage: unmount_all_volumes
unmount_all_volumes() {
    log_info "Unmounting Kubernetes and Longhorn volumes..."

    # IMPORTANT: Do NOT use 'fuser -km' on /var/lib/kubelet as it can kill critical processes
    # Instead, just stop the containerd-shim processes which hold the mounts
    log_info "Stopping containerd shim processes..."
    pkill -9 -f "containerd-shim" 2>/dev/null || true
    sleep 2

    # Unmount all Longhorn CSI volumes
    log_info "Unmounting Longhorn CSI volumes..."
    mount | grep "driver.longhorn.io" | awk '{print $3}' | while read -r mnt; do
        umount -f "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null || true
    done

    # Unmount all kubelet volume mounts
    log_info "Unmounting kubelet volumes..."
    mount | grep "/var/lib/kubelet" | awk '{print $3}' | sort -r | while read -r mnt; do
        umount -f "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null || true
    done

    # Unmount all pod volumes
    log_info "Unmounting pod volumes..."
    mount | grep "/var/lib/rancher/rke2/agent/kubelet/pods" | awk '{print $3}' | sort -r | while read -r mnt; do
        umount -f "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null || true
    done

    # Unmount any tmpfs mounts for secrets/configmaps
    log_info "Unmounting tmpfs secret/configmap volumes..."
    mount | grep -E "tmpfs.*kubelet" | awk '{print $3}' | sort -r | while read -r mnt; do
        umount -f "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null || true
    done

    # Unmount Longhorn block devices
    log_info "Unmounting Longhorn block devices..."
    mount | grep "/dev/longhorn" | awk '{print $3}' | while read -r mnt; do
        umount -f "$mnt" 2>/dev/null || umount -l "$mnt" 2>/dev/null || true
    done

    # Detach any remaining Longhorn devices
    log_info "Detaching Longhorn block devices..."
    ls /dev/longhorn/* 2>/dev/null | while read -r dev; do
        dmsetup remove "$dev" 2>/dev/null || true
    done

    # Remove Longhorn device mapper entries
    dmsetup ls 2>/dev/null | grep -i longhorn | awk '{print $1}' | while read -r dm; do
        dmsetup remove "$dm" 2>/dev/null || true
    done

    # Final check - force unmount anything still mounted
    log_info "Final cleanup of any remaining mounts..."
    for pattern in "/var/lib/kubelet" "/var/lib/rancher" "longhorn"; do
        mount | grep "$pattern" | awk '{print $3}' | sort -r | while read -r mnt; do
            umount -l "$mnt" 2>/dev/null || true
        done
    done

    sleep 2
    log_info "Volume unmounting complete"
}

# Force delete SIAB namespaces
# Usage: force_delete_siab_namespaces
force_delete_siab_namespaces() {
    local namespaces=(
        "siab-deployer"
        "siab-dashboard"
        "siab-system"
        "oauth2-proxy"
        "kubernetes-dashboard"
        "keycloak"
        "minio"
        "longhorn-system"
        "monitoring"
        "istio-system"
        "cert-manager"
        "metallb-system"
        "gatekeeper-system"
        "trivy-system"
    )

    log_info "Force deleting SIAB namespaces..."
    for ns in "${namespaces[@]}"; do
        force_delete_namespace "$ns"
    done
}
