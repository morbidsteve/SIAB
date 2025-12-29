#!/bin/bash
#
# Docker Registry Module
# Deploys internal Docker registry for SIAB platform
#

# Source required libraries
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/../../lib/common/colors.sh"
source "${SCRIPT_DIR}/../../lib/common/logging.sh"
source "${SCRIPT_DIR}/../../lib/kubernetes/kubectl.sh"

install_docker_registry() {
    log_section "Installing Docker Registry"

    local REGISTRY_NAMESPACE="docker-registry"
    local REGISTRY_DOMAIN="${REGISTRY_DOMAIN:-registry.${SIAB_DOMAIN}}"
    local REGISTRY_STORAGE_SIZE="${REGISTRY_STORAGE_SIZE:-50Gi}"

    # Create namespace
    kubectl create namespace "${REGISTRY_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f - 2>&1 | log_output
    kubectl label namespace "${REGISTRY_NAMESPACE}" istio-injection=enabled --overwrite 2>&1 | log_output

    # Create registry deployment and service
    cat <<EOF | kubectl apply -f - 2>&1 | log_output
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: registry-storage
  namespace: ${REGISTRY_NAMESPACE}
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: longhorn
  resources:
    requests:
      storage: ${REGISTRY_STORAGE_SIZE}
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: registry-config
  namespace: ${REGISTRY_NAMESPACE}
data:
  config.yml: |
    version: 0.1
    log:
      fields:
        service: registry
    storage:
      cache:
        blobdescriptor: inmemory
      filesystem:
        rootdirectory: /var/lib/registry
      delete:
        enabled: true
    http:
      addr: :5000
      headers:
        X-Content-Type-Options: [nosniff]
        Access-Control-Allow-Origin: ['*']
        Access-Control-Allow-Methods: ['HEAD', 'GET', 'OPTIONS', 'DELETE']
        Access-Control-Allow-Headers: ['Authorization', 'Accept', 'Cache-Control']
        Access-Control-Expose-Headers: ['Docker-Content-Digest']
    health:
      storagedriver:
        enabled: true
        interval: 10s
        threshold: 3
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: docker-registry
  namespace: ${REGISTRY_NAMESPACE}
  labels:
    app: docker-registry
spec:
  replicas: 1
  selector:
    matchLabels:
      app: docker-registry
  template:
    metadata:
      labels:
        app: docker-registry
        version: v1
    spec:
      containers:
      - name: registry
        image: registry:2.8
        ports:
        - containerPort: 5000
          name: http
          protocol: TCP
        volumeMounts:
        - name: registry-storage
          mountPath: /var/lib/registry
        - name: registry-config
          mountPath: /etc/docker/registry
        env:
        - name: REGISTRY_HTTP_ADDR
          value: "0.0.0.0:5000"
        - name: REGISTRY_STORAGE_DELETE_ENABLED
          value: "true"
        livenessProbe:
          httpGet:
            path: /
            port: 5000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /
            port: 5000
          initialDelaySeconds: 5
          periodSeconds: 5
        resources:
          requests:
            cpu: 100m
            memory: 128Mi
          limits:
            cpu: 500m
            memory: 512Mi
      volumes:
      - name: registry-storage
        persistentVolumeClaim:
          claimName: registry-storage
      - name: registry-config
        configMap:
          name: registry-config
---
apiVersion: v1
kind: Service
metadata:
  name: docker-registry
  namespace: ${REGISTRY_NAMESPACE}
  labels:
    app: docker-registry
spec:
  type: ClusterIP
  ports:
  - port: 5000
    targetPort: 5000
    protocol: TCP
    name: http
  selector:
    app: docker-registry
---
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: docker-registry
  namespace: ${REGISTRY_NAMESPACE}
spec:
  hosts:
  - "${REGISTRY_DOMAIN}"
  gateways:
  - istio-system/istio-gateway-admin
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: docker-registry.${REGISTRY_NAMESPACE}.svc.cluster.local
        port:
          number: 5000
    timeout: 300s
---
apiVersion: networking.istio.io/v1beta1
kind: DestinationRule
metadata:
  name: docker-registry
  namespace: ${REGISTRY_NAMESPACE}
spec:
  host: docker-registry.${REGISTRY_NAMESPACE}.svc.cluster.local
  trafficPolicy:
    connectionPool:
      tcp:
        maxConnections: 100
      http:
        http1MaxPendingRequests: 100
        http2MaxRequests: 100
        maxRequestsPerConnection: 10
    outlierDetection:
      consecutiveErrors: 5
      interval: 30s
      baseEjectionTime: 30s
---
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: docker-registry
  namespace: ${REGISTRY_NAMESPACE}
spec:
  selector:
    matchLabels:
      app: docker-registry
  mtls:
    mode: PERMISSIVE
EOF

    # Wait for registry to be ready
    log_info "Waiting for Docker Registry to be ready..."
    kubectl wait --for=condition=available --timeout=300s \
        deployment/docker-registry -n "${REGISTRY_NAMESPACE}" 2>&1 | log_output

    # Configure containerd to use insecure registry
    configure_containerd_registry

    # Test registry
    test_registry

    log_success "Docker Registry installed successfully"
    log_info "Registry URL: http://${REGISTRY_DOMAIN}"
    log_info "Internal URL: docker-registry.${REGISTRY_NAMESPACE}.svc.cluster.local:5000"
}

configure_containerd_registry() {
    log_info "Configuring containerd for insecure registry..."

    local REGISTRY_NAMESPACE="docker-registry"
    local INTERNAL_REGISTRY="docker-registry.${REGISTRY_NAMESPACE}.svc.cluster.local:5000"
    local EXTERNAL_REGISTRY="registry.${SIAB_DOMAIN}"

    # Create containerd registry config
    local CONTAINERD_CONFIG_DIR="/var/lib/rancher/rke2/agent/etc/containerd"
    local REGISTRY_CONFIG="${CONTAINERD_CONFIG_DIR}/certs.d/${INTERNAL_REGISTRY}/hosts.toml"

    mkdir -p "$(dirname "${REGISTRY_CONFIG}")"

    cat > "${REGISTRY_CONFIG}" <<EOF
server = "http://${INTERNAL_REGISTRY}"

[host."http://${INTERNAL_REGISTRY}"]
  capabilities = ["pull", "resolve", "push"]
  skip_verify = true
EOF

    # Also configure for external domain
    local EXTERNAL_CONFIG="${CONTAINERD_CONFIG_DIR}/certs.d/${EXTERNAL_REGISTRY}/hosts.toml"
    mkdir -p "$(dirname "${EXTERNAL_CONFIG}")"

    cat > "${EXTERNAL_CONFIG}" <<EOF
server = "https://${EXTERNAL_REGISTRY}"

[host."https://${EXTERNAL_REGISTRY}"]
  capabilities = ["pull", "resolve", "push"]
  skip_verify = true
EOF

    # Restart containerd to pick up changes
    log_info "Restarting RKE2 to apply registry configuration..."
    systemctl restart rke2-server 2>&1 | log_output || true

    # Wait for Kubernetes to be ready
    sleep 30
    wait_for_api_server

    log_success "Containerd configured for insecure registry"
}

test_registry() {
    log_info "Testing Docker Registry..."

    local REGISTRY_NAMESPACE="docker-registry"
    local INTERNAL_REGISTRY="docker-registry.${REGISTRY_NAMESPACE}.svc.cluster.local:5000"

    # Test from within cluster using a temporary pod
    kubectl run registry-test --image=curlimages/curl:latest --rm -i --restart=Never \
        --command -- curl -sf "http://${INTERNAL_REGISTRY}/v2/" > /dev/null 2>&1

    if [ $? -eq 0 ]; then
        log_success "Registry is accessible from within cluster"
    else
        log_warning "Registry test failed, but continuing..."
    fi
}

uninstall_docker_registry() {
    log_section "Uninstalling Docker Registry"

    local REGISTRY_NAMESPACE="docker-registry"

    # Delete namespace (cascades to all resources)
    kubectl delete namespace "${REGISTRY_NAMESPACE}" --ignore-not-found=true 2>&1 | log_output

    # Remove containerd config
    local CONTAINERD_CONFIG_DIR="/var/lib/rancher/rke2/agent/etc/containerd/certs.d"
    rm -rf "${CONTAINERD_CONFIG_DIR}/docker-registry."* 2>/dev/null || true
    rm -rf "${CONTAINERD_CONFIG_DIR}/registry."* 2>/dev/null || true

    log_success "Docker Registry uninstalled"
}

# If script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    install_docker_registry
fi
