#!/bin/bash
# SIAB - Kubernetes Dashboard Module
# Kubernetes Dashboard installation

# Requires: logging.sh, config.sh, progress/status.sh, checks/preflight.sh

# Install Kubernetes Dashboard
install_kubernetes_dashboard() {
    start_step "Kubernetes Dashboard"

    # Check if dashboard is already installed
    if check_helm_release_installed "kubernetes-dashboard" "kubernetes-dashboard"; then
        skip_step "Kubernetes Dashboard" "Already installed"
        return 0
    fi

    log_info "Installing Kubernetes Dashboard..."

    # Clean up any existing dashboard
    helm uninstall kubernetes-dashboard -n kubernetes-dashboard 2>/dev/null || true
    kubectl delete namespace kubernetes-dashboard 2>/dev/null || true
    sleep 3

    # Create namespace
    kubectl create namespace kubernetes-dashboard --dry-run=client -o yaml | kubectl apply -f -
    kubectl label namespace kubernetes-dashboard istio-injection=disabled --overwrite

    # Install Kubernetes Dashboard
    helm upgrade --install kubernetes-dashboard kubernetes-dashboard/kubernetes-dashboard \
        --namespace kubernetes-dashboard \
        --version "${KUBE_DASHBOARD_VERSION}" \
        --set app.ingress.enabled=false \
        --set api.containers.resources.requests.cpu=100m \
        --set api.containers.resources.requests.memory=200Mi \
        --set web.containers.resources.requests.cpu=100m \
        --set web.containers.resources.requests.memory=200Mi \
        --timeout=300s

    # Wait for dashboard to be ready
    log_info "Waiting for Kubernetes Dashboard to be ready..."
    kubectl wait --for=condition=Available deployment --all -n kubernetes-dashboard --timeout=300s 2>/dev/null || true

    # Create admin service account for dashboard access
    cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ServiceAccount
metadata:
  name: siab-admin
  namespace: kubernetes-dashboard
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: siab-admin
roleRef:
  apiGroup: rbac.authorization.k8s.io
  kind: ClusterRole
  name: cluster-admin
subjects:
- kind: ServiceAccount
  name: siab-admin
  namespace: kubernetes-dashboard
---
apiVersion: v1
kind: Secret
metadata:
  name: siab-admin-token
  namespace: kubernetes-dashboard
  annotations:
    kubernetes.io/service-account.name: siab-admin
type: kubernetes.io/service-account-token
EOF

    # Create Istio routing for Dashboard
    cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: k8s-dashboard-disable-mtls
  namespace: istio-system
spec:
  host: kubernetes-dashboard-kong-proxy.kubernetes-dashboard.svc.cluster.local
  trafficPolicy:
    tls:
      mode: SIMPLE
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: kubernetes-dashboard
  namespace: istio-system
spec:
  hosts:
    - "k8s-dashboard.${SIAB_DOMAIN}"
  gateways:
    - admin-gateway
  http:
    - route:
        - destination:
            host: kubernetes-dashboard-kong-proxy.kubernetes-dashboard.svc.cluster.local
            port:
              number: 443
EOF

    complete_step "Kubernetes Dashboard"
    log_info "Kubernetes Dashboard installed"
}

# Uninstall Kubernetes Dashboard
uninstall_kubernetes_dashboard() {
    log_info "Uninstalling Kubernetes Dashboard..."

    helm uninstall kubernetes-dashboard -n kubernetes-dashboard 2>/dev/null || true
    kubectl delete namespace kubernetes-dashboard --wait=false 2>/dev/null || true
    kubectl delete clusterrolebinding siab-admin 2>/dev/null || true

    log_info "Kubernetes Dashboard uninstalled"
}
