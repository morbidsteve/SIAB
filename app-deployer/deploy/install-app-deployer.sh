#!/bin/bash
#
# SIAB Application Deployer Installation Script
# Deploys the complete application deployment system
#

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="$(dirname "$SCRIPT_DIR")/backend"
FRONTEND_DIR="$(dirname "$SCRIPT_DIR")/frontend"

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_step() {
    echo ""
    echo -e "${CYAN}${BOLD}==>${NC} ${BOLD}$*${NC}"
}

# Check prerequisites
check_prereqs() {
    log_step "Checking prerequisites..."

    if ! command -v kubectl &>/dev/null; then
        log_error "kubectl not found. Please install kubectl."
        exit 1
    fi

    if ! kubectl cluster-info &>/dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Deploy namespace and RBAC
deploy_namespace() {
    log_step "Creating namespace and RBAC..."

    kubectl apply -f - <<EOF
apiVersion: v1
kind: Namespace
metadata:
  name: siab-deployer
  labels:
    istio-injection: enabled
---
apiVersion: v1
kind: ServiceAccount
metadata:
  name: app-deployer
  namespace: siab-deployer
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: app-deployer
rules:
  - apiGroups: [""]
    resources: ["namespaces"]
    verbs: ["get", "list", "create", "update", "patch"]
  - apiGroups: ["apps"]
    resources: ["deployments", "replicasets", "statefulsets", "daemonsets"]
    verbs: ["get", "list", "create", "update", "patch", "delete"]
  - apiGroups: [""]
    resources: ["services", "endpoints"]
    verbs: ["get", "list", "create", "update", "patch", "delete"]
  - apiGroups: [""]
    resources: ["configmaps", "secrets"]
    verbs: ["get", "list", "create", "update", "patch", "delete"]
  - apiGroups: [""]
    resources: ["persistentvolumeclaims", "persistentvolumes"]
    verbs: ["get", "list", "create", "update", "patch", "delete"]
  - apiGroups: ["networking.istio.io"]
    resources: ["virtualservices", "destinationrules", "gateways"]
    verbs: ["get", "list", "create", "update", "patch", "delete"]
  - apiGroups: [""]
    resources: ["pods", "pods/log", "events"]
    verbs: ["get", "list", "watch"]
  - apiGroups: ["networking.k8s.io"]
    resources: ["ingresses", "networkpolicies"]
    verbs: ["get", "list", "create", "update", "patch", "delete"]
---
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: app-deployer
subjects:
  - kind: ServiceAccount
    name: app-deployer
    namespace: siab-deployer
roleRef:
  kind: ClusterRole
  name: app-deployer
  apiGroup: rbac.authorization.k8s.io
EOF

    log_success "Namespace and RBAC created"
}

# Create ConfigMaps from files
create_configmaps() {
    log_step "Creating ConfigMaps from source files..."

    # Backend code
    if [[ -f "$BACKEND_DIR/app-deployer-api.py" ]]; then
        kubectl create configmap deployer-backend-code \
            --from-file=app-deployer-api.py="$BACKEND_DIR/app-deployer-api.py" \
            --from-file=requirements.txt="$BACKEND_DIR/requirements.txt" \
            -n siab-deployer \
            --dry-run=client -o yaml | kubectl apply -f -
        log_success "Backend ConfigMap created"
    else
        log_error "Backend files not found at $BACKEND_DIR"
        exit 1
    fi

    # Frontend HTML
    if [[ -f "$FRONTEND_DIR/index.html" ]]; then
        kubectl create configmap deployer-frontend-html \
            --from-file=index.html="$FRONTEND_DIR/index.html" \
            -n siab-deployer \
            --dry-run=client -o yaml | kubectl apply -f -
        log_success "Frontend ConfigMap created"
    else
        log_error "Frontend files not found at $FRONTEND_DIR"
        exit 1
    fi

    # Nginx config
    kubectl apply -f - <<'EOF'
apiVersion: v1
kind: ConfigMap
metadata:
  name: deployer-nginx-config
  namespace: siab-deployer
data:
  default.conf: |
    server {
        listen 8080;
        server_name _;
        root /usr/share/nginx/html;
        index index.html;

        location / {
            try_files $uri $uri/ /index.html;
        }

        location /api/ {
            proxy_pass http://app-deployer-backend:5000/api/;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
        }

        location /health {
            access_log off;
            return 200 "healthy\n";
            add_header Content-Type text/plain;
        }
    }
EOF

    log_success "Nginx ConfigMap created"
}

# Deploy backend
deploy_backend() {
    log_step "Deploying backend API..."

    kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-deployer-backend
  namespace: siab-deployer
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app-deployer-backend
  template:
    metadata:
      labels:
        app: app-deployer-backend
    spec:
      serviceAccountName: app-deployer
      securityContext:
        runAsNonRoot: true
        runAsUser: 1000
        fsGroup: 1000
      containers:
        - name: api
          image: python:3.11-slim
          command:
            - "/bin/sh"
            - "-c"
            - |
              apt-get update && apt-get install -y --no-install-recommends kubectl curl && \
              pip install --no-cache-dir -r /app/requirements.txt && \
              python /app/app-deployer-api.py
          ports:
            - containerPort: 5000
              name: http
          env:
            - name: FLASK_ENV
              value: "production"
            - name: SIAB_DOMAIN
              value: "siab.local"
          volumeMounts:
            - name: app-code
              mountPath: /app
          resources:
            requests:
              cpu: 200m
              memory: 256Mi
            limits:
              cpu: 1000m
              memory: 1Gi
          livenessProbe:
            httpGet:
              path: /health
              port: 5000
            initialDelaySeconds: 60
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /health
              port: 5000
            initialDelaySeconds: 30
            periodSeconds: 5
      volumes:
        - name: app-code
          configMap:
            name: deployer-backend-code
---
apiVersion: v1
kind: Service
metadata:
  name: app-deployer-backend
  namespace: siab-deployer
spec:
  selector:
    app: app-deployer-backend
  ports:
    - port: 5000
      targetPort: 5000
      name: http
EOF

    log_success "Backend deployed"
}

# Deploy frontend
deploy_frontend() {
    log_step "Deploying frontend web UI..."

    kubectl apply -f - <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-deployer-frontend
  namespace: siab-deployer
spec:
  replicas: 2
  selector:
    matchLabels:
      app: app-deployer-frontend
  template:
    metadata:
      labels:
        app: app-deployer-frontend
    spec:
      securityContext:
        runAsNonRoot: true
        runAsUser: 101
        fsGroup: 101
      containers:
        - name: nginx
          image: nginx:1.25-alpine
          ports:
            - containerPort: 8080
              name: http
          volumeMounts:
            - name: html
              mountPath: /usr/share/nginx/html
            - name: nginx-config
              mountPath: /etc/nginx/conf.d/default.conf
              subPath: default.conf
          resources:
            requests:
              cpu: 50m
              memory: 64Mi
            limits:
              cpu: 200m
              memory: 128Mi
          livenessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 10
            periodSeconds: 10
          readinessProbe:
            httpGet:
              path: /health
              port: 8080
            initialDelaySeconds: 5
            periodSeconds: 5
      volumes:
        - name: html
          configMap:
            name: deployer-frontend-html
        - name: nginx-config
          configMap:
            name: deployer-nginx-config
---
apiVersion: v1
kind: Service
metadata:
  name: app-deployer-frontend
  namespace: siab-deployer
spec:
  selector:
    app: app-deployer-frontend
  ports:
    - port: 80
      targetPort: 8080
      name: http
EOF

    log_success "Frontend deployed"
}

# Create Istio VirtualService
create_virtualservice() {
    log_step "Creating Istio VirtualService..."

    kubectl apply -f - <<'EOF'
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: app-deployer
  namespace: istio-system
spec:
  hosts:
    - "deployer.siab.local"
  gateways:
    - siab-gateway
  http:
    - route:
        - destination:
            host: app-deployer-frontend.siab-deployer.svc.cluster.local
            port:
              number: 80
EOF

    log_success "VirtualService created"
}

# Wait for deployment
wait_for_deployment() {
    log_step "Waiting for deployments to be ready..."

    kubectl wait --for=condition=available \
        deployment/app-deployer-backend \
        -n siab-deployer \
        --timeout=180s

    kubectl wait --for=condition=available \
        deployment/app-deployer-frontend \
        -n siab-deployer \
        --timeout=180s

    log_success "All deployments ready"
}

# Show access information
show_access_info() {
    log_step "Installation complete!"

    echo ""
    echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║         SIAB Application Deployer Installed!                   ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Get gateway IP
    local gateway_ip
    gateway_ip=$(kubectl get svc -n istio-system istio-ingressgateway-user -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")

    if [[ -n "$gateway_ip" ]]; then
        echo "Access the Application Deployer:"
        echo ""
        echo -e "${BOLD}URL:${NC} https://deployer.siab.local"
        echo ""
        echo "Add to /etc/hosts:"
        echo -e "${BOLD}$gateway_ip deployer.siab.local${NC}"
        echo ""
        echo "Or run:"
        echo -e "${CYAN}echo '$gateway_ip deployer.siab.local' | sudo tee -a /etc/hosts${NC}"
    else
        echo "Gateway IP not found. Check Istio installation."
    fi

    echo ""
    echo "Pod status:"
    kubectl get pods -n siab-deployer
    echo ""
    echo "For troubleshooting:"
    echo "  kubectl logs -n siab-deployer -l app=app-deployer-backend"
    echo "  kubectl logs -n siab-deployer -l app=app-deployer-frontend"
    echo ""
}

# Main installation
main() {
    echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║       SIAB Application Deployer Installation                   ║${NC}"
    echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    check_prereqs
    deploy_namespace
    create_configmaps
    deploy_backend
    deploy_frontend
    create_virtualservice
    wait_for_deployment
    show_access_info

    log_success "Installation complete!"
}

# Run main
main "$@"
