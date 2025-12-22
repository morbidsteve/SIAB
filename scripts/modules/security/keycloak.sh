#!/bin/bash
# SIAB - Keycloak Module
# Identity and Access Management installation

# Requires: logging.sh, config.sh, progress/status.sh

# Install Keycloak
install_keycloak() {
    start_step "Keycloak Identity"

    # Check if Keycloak is already installed and ready
    if kubectl get deployment keycloak -n keycloak -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -q "1"; then
        skip_step "Keycloak Identity" "Already installed and running"
        return 0
    fi

    log_info "Installing Keycloak..."

    # Load credentials
    source "${SIAB_CONFIG_DIR}/credentials.env"

    # Clean up any existing Keycloak installation
    log_info "Cleaning up any existing Keycloak installation..."
    helm uninstall keycloak -n keycloak 2>/dev/null || true
    kubectl delete statefulset,deployment,service,secret -l app=keycloak -n keycloak 2>/dev/null || true
    kubectl delete statefulset,deployment,service -l app.kubernetes.io/name=keycloakx -n keycloak 2>/dev/null || true
    kubectl delete pvc --all -n keycloak 2>/dev/null || true
    kubectl delete pods --all -n keycloak --force --grace-period=0 2>/dev/null || true
    sleep 3

    # Create namespace
    kubectl create namespace keycloak 2>/dev/null || true
    kubectl label namespace keycloak istio-injection=disabled --overwrite

    # Create secrets
    local pg_password
    pg_password=$(openssl rand -base64 24 | tr -d '=+/' | head -c 24)

    # Deploy Keycloak with PostgreSQL
    cat <<EOF | kubectl apply -f -
---
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-credentials
  namespace: keycloak
type: Opaque
stringData:
  admin-user: admin
  admin-password: "${KEYCLOAK_ADMIN_PASSWORD}"
---
apiVersion: v1
kind: Secret
metadata:
  name: keycloak-postgresql
  namespace: keycloak
type: Opaque
stringData:
  password: "${pg_password}"
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: keycloak-postgresql
  namespace: keycloak
spec:
  replicas: 1
  selector:
    matchLabels:
      app: keycloak-postgresql
  template:
    metadata:
      labels:
        app: keycloak-postgresql
    spec:
      containers:
      - name: postgresql
        image: postgres:15-alpine
        ports:
        - containerPort: 5432
        env:
        - name: POSTGRES_DB
          value: keycloak
        - name: POSTGRES_USER
          value: postgres
        - name: POSTGRES_PASSWORD
          valueFrom:
            secretKeyRef:
              name: keycloak-postgresql
              key: password
        resources:
          requests:
            memory: 256Mi
            cpu: 100m
---
apiVersion: v1
kind: Service
metadata:
  name: keycloak-postgresql
  namespace: keycloak
spec:
  ports:
  - port: 5432
  selector:
    app: keycloak-postgresql
---
apiVersion: apps/v1
kind: StatefulSet
metadata:
  name: keycloak
  namespace: keycloak
spec:
  serviceName: keycloak-headless
  replicas: 1
  selector:
    matchLabels:
      app: keycloak
  template:
    metadata:
      labels:
        app: keycloak
    spec:
      containers:
      - name: keycloak
        image: quay.io/keycloak/keycloak:${KEYCLOAK_VERSION}
        args:
        - start
        - --hostname-strict=false
        - --http-enabled=true
        - --proxy=edge
        env:
        - name: KEYCLOAK_ADMIN
          valueFrom:
            secretKeyRef:
              name: keycloak-credentials
              key: admin-user
        - name: KEYCLOAK_ADMIN_PASSWORD
          valueFrom:
            secretKeyRef:
              name: keycloak-credentials
              key: admin-password
        - name: KC_DB
          value: postgres
        - name: KC_DB_URL
          value: jdbc:postgresql://keycloak-postgresql:5432/keycloak
        - name: KC_DB_USERNAME
          value: postgres
        - name: KC_DB_PASSWORD
          valueFrom:
            secretKeyRef:
              name: keycloak-postgresql
              key: password
        - name: KC_HEALTH_ENABLED
          value: "true"
        ports:
        - name: http
          containerPort: 8080
        - name: https
          containerPort: 8443
        resources:
          requests:
            memory: 512Mi
            cpu: 250m
          limits:
            memory: 1Gi
            cpu: 1
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
---
apiVersion: v1
kind: Service
metadata:
  name: keycloak
  namespace: keycloak
spec:
  ports:
  - name: http
    port: 8080
    targetPort: 8080
  selector:
    app: keycloak
EOF

    # Wait for Keycloak to be ready
    log_info "Waiting for Keycloak to be ready..."
    local max_wait=600
    local elapsed=0

    while [[ $elapsed -lt $max_wait ]]; do
        if kubectl get statefulset keycloak -n keycloak -o jsonpath='{.status.readyReplicas}' 2>/dev/null | grep -q "1"; then
            log_info "Keycloak is ready!"
            break
        fi
        sleep 10
        elapsed=$((elapsed + 10))
        if [[ $((elapsed % 60)) -eq 0 ]]; then
            echo "  Waiting for Keycloak... (${elapsed}s)"
            kubectl get pods -n keycloak 2>/dev/null || true
        fi
    done

    if [[ $elapsed -ge $max_wait ]]; then
        log_warn "Keycloak startup timeout (may still be initializing)"
    fi

    # Create Istio VirtualService for Keycloak
    log_info "Creating Keycloak VirtualService..."
    cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: keycloak
  namespace: istio-system
spec:
  hosts:
  - keycloak.${SIAB_DOMAIN}
  - auth.${SIAB_DOMAIN}
  gateways:
  - admin-gateway
  http:
  - match:
    - uri:
        prefix: /
    route:
    - destination:
        host: keycloak.keycloak.svc.cluster.local
        port:
          number: 8080
EOF

    complete_step "Keycloak Identity"
    log_info "Keycloak installed"
}

# Configure Keycloak realm
configure_keycloak_realm() {
    start_step "Keycloak Realm Setup"

    log_info "Configuring Keycloak realm..."

    # Run realm configuration script if available
    if [[ -f "${SIAB_REPO_DIR}/scripts/configure-keycloak.sh" ]]; then
        bash "${SIAB_REPO_DIR}/scripts/configure-keycloak.sh"
    else
        log_warn "Keycloak configuration script not found"
    fi

    complete_step "Keycloak Realm Setup"
    log_info "Keycloak realm configured"
}

# Uninstall Keycloak
uninstall_keycloak() {
    log_info "Uninstalling Keycloak..."

    kubectl delete statefulset keycloak -n keycloak 2>/dev/null || true
    kubectl delete deployment keycloak-postgresql -n keycloak 2>/dev/null || true
    kubectl delete service keycloak keycloak-postgresql keycloak-headless -n keycloak 2>/dev/null || true
    kubectl delete secret keycloak-credentials keycloak-postgresql -n keycloak 2>/dev/null || true
    kubectl delete pvc --all -n keycloak 2>/dev/null || true
    kubectl delete namespace keycloak --wait=false 2>/dev/null || true

    log_info "Keycloak uninstalled"
}
