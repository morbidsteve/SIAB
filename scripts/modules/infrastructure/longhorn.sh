#!/bin/bash
# SIAB - Longhorn Module
# Block storage installation and configuration

# Requires: logging.sh, config.sh, os.sh, progress/status.sh

# Install Longhorn for block storage
install_longhorn() {
    start_step "Longhorn Block Storage"

    if [[ "${SIAB_SKIP_LONGHORN}" == "true" ]]; then
        skip_step "Longhorn Block Storage" "Skipped by configuration"
        return 0
    fi

    # Check if Longhorn is already installed
    if check_longhorn_installed; then
        skip_step "Longhorn Block Storage" "Already installed"
        return 0
    fi

    log_info "Installing Longhorn ${LONGHORN_VERSION}..."

    # Install prerequisites based on OS family
    log_info "Installing iSCSI and NFS prerequisites..."
    case "${OS_FAMILY}" in
        rhel)
            ${PKG_MANAGER} install -y iscsi-initiator-utils nfs-utils || true
            ;;
        debian)
            apt-get update && apt-get install -y open-iscsi nfs-common || true
            ;;
    esac

    # Enable and start iscsid service
    systemctl enable iscsid 2>/dev/null || true
    systemctl start iscsid 2>/dev/null || true

    # Add Longhorn Helm repository
    helm repo add longhorn https://charts.longhorn.io 2>/dev/null || true
    helm repo update

    # Create longhorn-system namespace
    kubectl create namespace longhorn-system --dry-run=client -o yaml | kubectl apply -f -

    # Install Longhorn with single-node optimized settings
    log_info "Installing Longhorn chart..."
    helm upgrade --install longhorn longhorn/longhorn \
        --namespace longhorn-system \
        --version "${LONGHORN_VERSION}" \
        --set defaultSettings.defaultDataPath="/var/lib/longhorn" \
        --set defaultSettings.replicaReplenishmentWaitInterval=60 \
        --set defaultSettings.defaultReplicaCount=1 \
        --set persistence.defaultClass=true \
        --set persistence.defaultClassReplicaCount=1 \
        --set csi.kubeletRootDir="/var/lib/kubelet" \
        --set defaultSettings.guaranteedInstanceManagerCPU=5 \
        --set ingress.enabled=false \
        --wait --timeout=600s

    # Wait for Longhorn components to be ready
    log_info "Waiting for Longhorn components to be ready..."
    kubectl wait --for=condition=Ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s || true

    # Set Longhorn as default StorageClass
    log_info "Setting Longhorn as default StorageClass..."
    kubectl patch storageclass longhorn -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}' 2>/dev/null || true

    # Remove local-path as default if it exists
    kubectl patch storageclass local-path -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"false"}}}' 2>/dev/null || true

    complete_step "Longhorn Block Storage"
    log_info "Longhorn block storage installed and configured as default StorageClass"
}

# Uninstall Longhorn
uninstall_longhorn() {
    log_info "Uninstalling Longhorn..."

    # Set deleting confirmation flag
    kubectl -n longhorn-system patch -p '{"value": "true"}' --type=merge lhs deleting-confirmation-flag 2>/dev/null || true

    # Uninstall via Helm
    helm uninstall longhorn -n longhorn-system 2>/dev/null || true

    # Delete namespace
    kubectl delete namespace longhorn-system --wait=false 2>/dev/null || true

    # Clean up data directory
    rm -rf /var/lib/longhorn 2>/dev/null || true

    log_info "Longhorn uninstalled"
}
