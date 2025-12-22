#!/bin/bash
# SIAB - MinIO Module
# S3-compatible object storage installation

# Requires: logging.sh, config.sh, progress/status.sh

# Install MinIO
install_minio() {
    start_step "MinIO Storage"

    if [[ "${SIAB_SKIP_STORAGE}" == "true" ]]; then
        skip_step "MinIO Storage" "Skipped by configuration"
        return
    fi

    # Check if MinIO is already installed and ready
    if kubectl get deployment minio -n minio -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -q "1"; then
        skip_step "MinIO Storage" "Already installed and running"
        return 0
    fi

    log_info "Installing MinIO..."

    # Load credentials
    source "${SIAB_CONFIG_DIR}/credentials.env"

    # Create namespace with Istio injection disabled
    kubectl create namespace minio 2>/dev/null || true
    kubectl label namespace minio istio-injection=disabled --overwrite 2>/dev/null || true

    # Clean up any existing MinIO installation
    log_info "Cleaning up any existing MinIO installation..."
    helm uninstall minio -n minio --wait 2>/dev/null || true

    # Force delete any stuck jobs and pods
    for job in $(kubectl get jobs -n minio -o name 2>/dev/null); do
        kubectl delete "$job" -n minio --force --grace-period=0 2>/dev/null || true
    done
    for pod in $(kubectl get pods -n minio -o name 2>/dev/null); do
        kubectl delete "$pod" -n minio --force --grace-period=0 2>/dev/null || true
    done
    kubectl delete pvc --all -n minio 2>/dev/null || true
    sleep 5

    # Create MinIO secret
    kubectl create secret generic minio-creds \
        --namespace minio \
        --from-literal=rootUser="${MINIO_ROOT_USER}" \
        --from-literal=rootPassword="${MINIO_ROOT_PASSWORD}" \
        --dry-run=client -o yaml | kubectl apply -f -

    # Install MinIO
    helm upgrade --install minio minio/minio \
        --namespace minio \
        --set rootUser="${MINIO_ROOT_USER}" \
        --set rootPassword="${MINIO_ROOT_PASSWORD}" \
        --set mode=standalone \
        --set replicas=1 \
        --set persistence.enabled=false \
        --set resources.requests.memory=1Gi \
        --set securityContext.runAsUser=1000 \
        --set securityContext.runAsGroup=1000 \
        --set securityContext.fsGroup=1000 \
        --set consoleService.type=ClusterIP \
        --set postJob.enabled=false \
        --timeout=600s

    # Wait for MinIO to be ready
    log_info "Waiting for MinIO to be ready..."
    local max_wait=300
    local elapsed=0
    while [[ $elapsed -lt $max_wait ]]; do
        if kubectl get deployment minio -n minio -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -q "1"; then
            log_info "MinIO is ready!"
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    if [[ $elapsed -ge $max_wait ]]; then
        log_error "MinIO installation timeout"
        fail_step "MinIO Storage" "Timeout"
        return 1
    fi

    # Create Istio DestinationRule to disable mTLS for MinIO (no sidecar)
    cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: minio-disable-mtls
  namespace: istio-system
spec:
  host: minio-console.minio.svc.cluster.local
  trafficPolicy:
    tls:
      mode: DISABLE
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: minio-api-disable-mtls
  namespace: istio-system
spec:
  host: minio.minio.svc.cluster.local
  trafficPolicy:
    tls:
      mode: DISABLE
EOF

    # Create Istio VirtualService for MinIO Console
    cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: minio-console
  namespace: istio-system
spec:
  hosts:
    - "minio.${SIAB_DOMAIN}"
  gateways:
    - admin-gateway
  http:
    - route:
        - destination:
            host: minio-console.minio.svc.cluster.local
            port:
              number: 9001
EOF

    complete_step "MinIO Storage"
    log_info "MinIO installed"
}

# Uninstall MinIO
uninstall_minio() {
    log_info "Uninstalling MinIO..."

    helm uninstall minio -n minio 2>/dev/null || true
    kubectl delete pvc --all -n minio 2>/dev/null || true
    kubectl delete namespace minio --wait=false 2>/dev/null || true

    log_info "MinIO uninstalled"
}
