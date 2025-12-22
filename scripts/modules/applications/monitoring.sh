#!/bin/bash
# SIAB - Monitoring Module
# Prometheus and Grafana stack installation

# Requires: logging.sh, config.sh, progress/status.sh

# Install Monitoring Stack (Prometheus + Grafana)
install_monitoring() {
    start_step "Monitoring Stack"

    if [[ "${SIAB_SKIP_MONITORING}" == "true" ]]; then
        skip_step "Monitoring Stack" "Skipped by configuration"
        return
    fi

    # Check if monitoring is already installed
    if kubectl get deployment kube-prometheus-stack-grafana -n monitoring -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -q "1"; then
        skip_step "Monitoring Stack" "Already installed and running"
        return 0
    fi

    log_info "Installing Monitoring Stack..."

    # Load credentials for Grafana
    source "${SIAB_CONFIG_DIR}/credentials.env"

    # Create namespace with Istio injection disabled
    kubectl create namespace monitoring 2>/dev/null || true
    kubectl label namespace monitoring istio-injection=disabled --overwrite 2>/dev/null || true

    # Clean up any existing installation
    log_info "Cleaning up any existing monitoring installation..."
    helm uninstall kube-prometheus-stack -n monitoring --wait 2>/dev/null || true

    # Force delete stuck jobs and pods
    for job in $(kubectl get jobs -n monitoring -o name 2>/dev/null); do
        kubectl delete "$job" -n monitoring --force --grace-period=0 2>/dev/null || true
    done
    for pod in $(kubectl get pods -n monitoring -o name 2>/dev/null); do
        kubectl delete "$pod" -n monitoring --force --grace-period=0 2>/dev/null || true
    done
    kubectl delete pvc --all -n monitoring 2>/dev/null || true
    sleep 5

    # Install kube-prometheus-stack
    helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
        --namespace monitoring \
        --version "${PROMETHEUS_STACK_VERSION}" \
        --set grafana.adminPassword="${GRAFANA_ADMIN_PASSWORD}" \
        --set grafana.persistence.enabled=false \
        --set prometheus.prometheusSpec.retention=7d \
        --set prometheus.prometheusSpec.resources.requests.memory=512Mi \
        --set prometheus.prometheusSpec.resources.requests.cpu=200m \
        --set alertmanager.alertmanagerSpec.resources.requests.memory=100Mi \
        --set alertmanager.alertmanagerSpec.resources.requests.cpu=50m \
        --set grafana.resources.requests.memory=256Mi \
        --set grafana.resources.requests.cpu=100m \
        --set prometheus.prometheusSpec.storageSpec.volumeClaimTemplate.spec.resources.requests.storage=10Gi \
        --set prometheus.prometheusSpec.podMonitorSelectorNilUsesHelmValues=false \
        --set prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues=false \
        --set grafana.sidecar.dashboards.enabled=true \
        --set grafana.sidecar.datasources.enabled=true \
        --timeout=600s

    # Wait for Grafana to be ready
    log_info "Waiting for Grafana to be ready..."
    local max_wait=300
    local elapsed=0
    while [[ $elapsed -lt $max_wait ]]; do
        if kubectl get deployment kube-prometheus-stack-grafana -n monitoring -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -q "1"; then
            log_info "Grafana is ready!"
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    # Create Istio VirtualService for Grafana
    cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: grafana-disable-mtls
  namespace: istio-system
spec:
  host: kube-prometheus-stack-grafana.monitoring.svc.cluster.local
  trafficPolicy:
    tls:
      mode: DISABLE
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: grafana
  namespace: istio-system
spec:
  hosts:
    - "grafana.${SIAB_DOMAIN}"
  gateways:
    - admin-gateway
  http:
    - route:
        - destination:
            host: kube-prometheus-stack-grafana.monitoring.svc.cluster.local
            port:
              number: 80
EOF

    complete_step "Monitoring Stack"
    log_info "Monitoring stack installed"
}

# Uninstall Monitoring
uninstall_monitoring() {
    log_info "Uninstalling monitoring stack..."

    helm uninstall kube-prometheus-stack -n monitoring 2>/dev/null || true
    kubectl delete pvc --all -n monitoring 2>/dev/null || true
    kubectl delete namespace monitoring --wait=false 2>/dev/null || true

    log_info "Monitoring stack uninstalled"
}
