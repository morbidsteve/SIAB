#!/bin/bash
set -euo pipefail

# SIAB - Secure Infrastructure as a Box
# One-command secure Kubernetes platform installer

readonly SIAB_VERSION="1.0.0"
readonly SIAB_DIR="/opt/siab"
readonly SIAB_CONFIG_DIR="/etc/siab"
readonly SIAB_LOG_DIR="/var/log/siab"
readonly SIAB_BIN_DIR="/usr/local/bin"

# Detect OS
detect_os() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="${ID}"
        OS_VERSION_ID="${VERSION_ID}"
        OS_NAME="${NAME}"
    else
        log_error "Cannot detect operating system"
        exit 1
    fi
}

# Run OS detection
detect_os

# Set OS-specific variables
case "${OS_ID}" in
    rocky|rhel|centos|ol|almalinux)
        # RHEL family: Rocky, RHEL, CentOS, Oracle Linux, AlmaLinux
        OS_FAMILY="rhel"
        PKG_MANAGER="dnf"
        FIREWALL_CMD="firewalld"
        SECURITY_MODULE="selinux"
        ;;
    ubuntu|xubuntu|kubuntu|lubuntu|debian)
        # Debian family: Ubuntu variants and Debian
        OS_FAMILY="debian"
        PKG_MANAGER="apt"
        FIREWALL_CMD="ufw"
        SECURITY_MODULE="apparmor"
        ;;
    *)
        log_error "Unsupported operating system: ${OS_ID}"
        log_error "Supported: Rocky Linux, RHEL, CentOS, Oracle Linux, AlmaLinux, Ubuntu, Xubuntu, Debian"
        exit 1
        ;;
esac

# Component versions (pinned for security)
readonly RKE2_VERSION="${RKE2_VERSION:-v1.28.4+rke2r1}"
readonly HELM_VERSION="${HELM_VERSION:-v3.13.3}"
readonly ISTIO_VERSION="${ISTIO_VERSION:-1.20.1}"
readonly KEYCLOAK_VERSION="${KEYCLOAK_VERSION:-23.0.3}"
readonly MINIO_VERSION="${MINIO_VERSION:-5.0.15}"
readonly TRIVY_VERSION="${TRIVY_VERSION:-0.18.4}"
readonly GATEKEEPER_VERSION="${GATEKEEPER_VERSION:-3.14.0}"
readonly CERTMANAGER_VERSION="${CERTMANAGER_VERSION:-v1.13.3}"

# Configuration
SIAB_DOMAIN="${SIAB_DOMAIN:-siab.local}"
SIAB_ADMIN_EMAIL="${SIAB_ADMIN_EMAIL:-admin@${SIAB_DOMAIN}}"
SIAB_SKIP_MONITORING="${SIAB_SKIP_MONITORING:-false}"
SIAB_SKIP_STORAGE="${SIAB_SKIP_STORAGE:-false}"
SIAB_MINIO_SIZE="${SIAB_MINIO_SIZE:-100Gi}"
SIAB_SINGLE_NODE="${SIAB_SINGLE_NODE:-true}"

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Error handling
trap 'log_error "Installation failed at line $LINENO. Check ${SIAB_LOG_DIR}/install.log for details."' ERR

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        exit 1
    fi
}

# Check system requirements
check_requirements() {
    log_step "Checking system requirements..."

    # Check OS
    log_info "Detected OS: ${OS_NAME} (${OS_ID} ${OS_VERSION_ID})"
    log_info "OS Family: ${OS_FAMILY}"

    # Check CPU cores
    local cpu_cores
    cpu_cores=$(nproc)
    if [[ $cpu_cores -lt 4 ]]; then
        log_error "Minimum 4 CPU cores required (found: $cpu_cores)"
        exit 1
    fi

    # Check RAM
    local total_ram
    total_ram=$(free -g | awk '/^Mem:/{print $2}')
    if [[ $total_ram -lt 14 ]]; then
        log_error "Minimum 16GB RAM required (found: ${total_ram}GB)"
        exit 1
    fi

    # Check disk space
    local free_space
    free_space=$(df -BG / | awk 'NR==2 {print $4}' | sed 's/G//')
    if [[ $free_space -lt 80 ]]; then
        log_error "Minimum 100GB free disk space required (found: ${free_space}GB)"
        exit 1
    fi

    log_info "System requirements met"
}

# Setup directories
setup_directories() {
    log_step "Setting up directories..."
    mkdir -p "${SIAB_DIR}"
    mkdir -p "${SIAB_CONFIG_DIR}"
    mkdir -p "${SIAB_LOG_DIR}"
    mkdir -p "${SIAB_BIN_DIR}"
    chmod 700 "${SIAB_CONFIG_DIR}"
}

# Install system dependencies
install_dependencies() {
    log_step "Installing system dependencies..."

    if [[ "${OS_FAMILY}" == "rhel" ]]; then
        dnf update -y
        dnf install -y \
            curl \
            wget \
            tar \
            git \
            jq \
            openssl \
            policycoreutils-python-utils \
            container-selinux \
            iptables \
            chrony \
            audit

        # Enable and start chrony for time sync
        systemctl enable --now chronyd

        # Enable audit logging
        systemctl enable --now auditd

    elif [[ "${OS_FAMILY}" == "debian" ]]; then
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -y
        apt-get install -y \
            curl \
            wget \
            tar \
            git \
            jq \
            openssl \
            iptables \
            chrony \
            auditd \
            apparmor \
            apparmor-utils

        # Install yq separately (not in default repos)
        wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
        chmod +x /usr/local/bin/yq

        # Enable and start chrony for time sync
        systemctl enable --now chrony

        # Enable audit logging
        systemctl enable --now auditd
    fi

    log_info "System dependencies installed"
}

# Configure firewall
configure_firewall() {
    log_step "Configuring firewall..."

    if [[ "${FIREWALL_CMD}" == "firewalld" ]]; then
        # Install firewalld if not present
        dnf install -y firewalld
        systemctl enable --now firewalld

        # RKE2 ports
        firewall-cmd --permanent --add-port=6443/tcp   # Kubernetes API
        firewall-cmd --permanent --add-port=9345/tcp   # RKE2 supervisor API
        firewall-cmd --permanent --add-port=10250/tcp  # Kubelet metrics
        firewall-cmd --permanent --add-port=2379/tcp   # etcd client
        firewall-cmd --permanent --add-port=2380/tcp   # etcd peer
        firewall-cmd --permanent --add-port=30000-32767/tcp  # NodePort Services

        # Istio ports
        firewall-cmd --permanent --add-port=15021/tcp  # Istio health check
        firewall-cmd --permanent --add-port=443/tcp    # HTTPS ingress
        firewall-cmd --permanent --add-port=80/tcp     # HTTP ingress (redirect to HTTPS)

        # CNI ports
        firewall-cmd --permanent --add-port=8472/udp   # VXLAN
        firewall-cmd --permanent --add-port=4789/udp   # VXLAN

        firewall-cmd --reload

    elif [[ "${FIREWALL_CMD}" == "ufw" ]]; then
        # Install ufw if not present
        apt-get install -y ufw

        # Enable ufw (non-interactive)
        ufw --force enable

        # Allow SSH first (prevent lockout)
        ufw allow 22/tcp

        # RKE2 ports
        ufw allow 6443/tcp    # Kubernetes API
        ufw allow 9345/tcp    # RKE2 supervisor API
        ufw allow 10250/tcp   # Kubelet metrics
        ufw allow 2379/tcp    # etcd client
        ufw allow 2380/tcp    # etcd peer
        ufw allow 30000:32767/tcp  # NodePort Services

        # Istio ports
        ufw allow 15021/tcp   # Istio health check
        ufw allow 443/tcp     # HTTPS ingress
        ufw allow 80/tcp      # HTTP ingress (redirect to HTTPS)

        # CNI ports
        ufw allow 8472/udp    # VXLAN
        ufw allow 4789/udp    # VXLAN

        # Reload ufw
        ufw reload
    fi

    log_info "Firewall configured"
}

# Configure security module (SELinux or AppArmor)
configure_security() {
    if [[ "${SECURITY_MODULE}" == "selinux" ]]; then
        log_step "Configuring SELinux..."

        # Ensure SELinux is enforcing
        if [[ $(getenforce) != "Enforcing" ]]; then
            setenforce 1
            sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
        fi

        # Set SELinux booleans for containers
        setsebool -P container_manage_cgroup on

        log_info "SELinux configured in enforcing mode"

    elif [[ "${SECURITY_MODULE}" == "apparmor" ]]; then
        log_step "Configuring AppArmor..."

        # Ensure AppArmor is enabled
        systemctl enable --now apparmor

        # Check AppArmor status
        if ! aa-status >/dev/null 2>&1; then
            log_warn "AppArmor not available, skipping..."
        else
            # Set AppArmor to enforcing mode
            aa-enforce /etc/apparmor.d/* 2>/dev/null || true
            log_info "AppArmor configured in enforcing mode"
        fi
    fi
}

# Install RKE2
install_rke2() {
    log_step "Installing RKE2 ${RKE2_VERSION}..."

    # Create RKE2 config directory
    mkdir -p /etc/rancher/rke2

    # RKE2 hardened configuration
    cat > /etc/rancher/rke2/config.yaml <<EOF
# RKE2 Security Hardened Configuration
write-kubeconfig-mode: "0600"
kube-apiserver-arg:
  - "admission-control-config-file=/etc/rancher/rke2/admission-control-config.yaml"
  - "audit-log-path=/var/log/kubernetes/audit/audit.log"
  - "audit-log-maxage=30"
  - "audit-log-maxbackup=10"
  - "audit-log-maxsize=100"
  - "audit-policy-file=/etc/rancher/rke2/audit-policy.yaml"
  - "enable-admission-plugins=NodeRestriction,PodSecurity"
  - "encryption-provider-config=/etc/rancher/rke2/encryption-config.yaml"
  - "tls-cipher-suites=TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"
  - "tls-min-version=VersionTLS12"
kube-controller-manager-arg:
  - "terminated-pod-gc-threshold=10"
  - "use-service-account-credentials=true"
kubelet-arg:
  - "streaming-connection-idle-timeout=5m"
  - "protect-kernel-defaults=true"
  - "make-iptables-util-chains=true"
  - "event-qps=0"
  - "rotate-certificates=true"
  - "tls-cipher-suites=TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_RSA_WITH_AES_256_GCM_SHA384,TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305,TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384"
profile: "cis-1.23"
selinux: ${SECURITY_MODULE_ENABLED}
secrets-encryption: true
EOF

    # Set the security module flag based on OS
    if [[ "${SECURITY_MODULE}" == "selinux" ]]; then
        sed -i "s/selinux: \${SECURITY_MODULE_ENABLED}/selinux: true/" /etc/rancher/rke2/config.yaml
    else
        sed -i "s/selinux: \${SECURITY_MODULE_ENABLED}/selinux: false/" /etc/rancher/rke2/config.yaml
    fi

    # Create audit policy
    mkdir -p /var/log/kubernetes/audit
    cat > /etc/rancher/rke2/audit-policy.yaml <<EOF
apiVersion: audit.k8s.io/v1
kind: Policy
rules:
  - level: Metadata
    omitStages:
      - RequestReceived
EOF

    # Create admission control config
    cat > /etc/rancher/rke2/admission-control-config.yaml <<EOF
apiVersion: apiserver.config.k8s.io/v1
kind: AdmissionConfiguration
plugins:
  - name: PodSecurity
    configuration:
      apiVersion: pod-security.admission.config.k8s.io/v1
      kind: PodSecurityConfiguration
      defaults:
        enforce: "restricted"
        enforce-version: "latest"
        audit: "restricted"
        audit-version: "latest"
        warn: "restricted"
        warn-version: "latest"
      exemptions:
        usernames: []
        runtimeClasses: []
        namespaces:
          - kube-system
          - istio-system
          - cert-manager
          - siab-system
EOF

    # Create encryption config
    local encryption_key
    encryption_key=$(head -c 32 /dev/urandom | base64)
    cat > /etc/rancher/rke2/encryption-config.yaml <<EOF
apiVersion: apiserver.config.k8s.io/v1
kind: EncryptionConfiguration
resources:
  - resources:
      - secrets
    providers:
      - aescbc:
          keys:
            - name: key1
              secret: ${encryption_key}
      - identity: {}
EOF
    chmod 600 /etc/rancher/rke2/encryption-config.yaml

    # Install RKE2
    curl -sfL https://get.rke2.io | INSTALL_RKE2_VERSION="${RKE2_VERSION}" sh -

    # Enable and start RKE2
    systemctl enable rke2-server.service
    systemctl start rke2-server.service

    # Wait for RKE2 to be ready
    log_info "Waiting for RKE2 to be ready..."
    sleep 30

    local retries=30
    while [[ $retries -gt 0 ]]; do
        if /var/lib/rancher/rke2/bin/kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml get nodes &>/dev/null; then
            break
        fi
        sleep 10
        retries=$((retries - 1))
    done

    if [[ $retries -eq 0 ]]; then
        log_error "RKE2 failed to start"
        exit 1
    fi

    # Setup kubectl access
    mkdir -p ~/.kube
    cp /etc/rancher/rke2/rke2.yaml ~/.kube/config
    chmod 600 ~/.kube/config

    # Add RKE2 bins to PATH
    echo 'export PATH=$PATH:/var/lib/rancher/rke2/bin' >> /etc/profile.d/rke2.sh
    export PATH=$PATH:/var/lib/rancher/rke2/bin

    # Create symlinks
    ln -sf /var/lib/rancher/rke2/bin/kubectl "${SIAB_BIN_DIR}/kubectl"

    log_info "RKE2 installed successfully"
}

# Install Helm
install_helm() {
    log_step "Installing Helm ${HELM_VERSION}..."

    curl -fsSL https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz | tar xz
    mv linux-amd64/helm "${SIAB_BIN_DIR}/helm"
    rm -rf linux-amd64
    chmod +x "${SIAB_BIN_DIR}/helm"

    # Add Helm repos
    helm repo add istio https://istio-release.storage.googleapis.com/charts
    helm repo add jetstack https://charts.jetstack.io
    helm repo add bitnami https://charts.bitnami.com/bitnami
    helm repo add aqua https://aquasecurity.github.io/helm-charts/
    helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
    helm repo add minio https://charts.min.io/
    helm repo update

    log_info "Helm installed successfully"
}

# Generate secure credentials
generate_credentials() {
    log_step "Generating secure credentials..."

    local keycloak_admin_password
    local minio_root_password
    local grafana_admin_password

    keycloak_admin_password=$(openssl rand -base64 24 | tr -d '=+/' | head -c 24)
    minio_root_password=$(openssl rand -base64 24 | tr -d '=+/' | head -c 24)
    grafana_admin_password=$(openssl rand -base64 24 | tr -d '=+/' | head -c 24)

    cat > "${SIAB_CONFIG_DIR}/credentials.env" <<EOF
# SIAB Platform Credentials
# Generated on $(date)
# KEEP THIS FILE SECURE!

KEYCLOAK_ADMIN_USER=admin
KEYCLOAK_ADMIN_PASSWORD=${keycloak_admin_password}

MINIO_ROOT_USER=admin
MINIO_ROOT_PASSWORD=${minio_root_password}

GRAFANA_ADMIN_USER=admin
GRAFANA_ADMIN_PASSWORD=${grafana_admin_password}

SIAB_DOMAIN=${SIAB_DOMAIN}
EOF
    chmod 600 "${SIAB_CONFIG_DIR}/credentials.env"

    log_info "Credentials generated and saved to ${SIAB_CONFIG_DIR}/credentials.env"
}

# Create namespaces
create_namespaces() {
    log_step "Creating namespaces..."

    kubectl create namespace siab-system --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace keycloak --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace minio --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace monitoring --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace cert-manager --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace trivy-system --dry-run=client -o yaml | kubectl apply -f -
    kubectl create namespace gatekeeper-system --dry-run=client -o yaml | kubectl apply -f -

    # Label namespaces for Istio injection
    kubectl label namespace default istio-injection=enabled --overwrite
    kubectl label namespace siab-system istio-injection=enabled --overwrite
    kubectl label namespace keycloak istio-injection=enabled --overwrite
    kubectl label namespace minio istio-injection=enabled --overwrite
    kubectl label namespace monitoring istio-injection=enabled --overwrite

    log_info "Namespaces created"
}

# Install cert-manager
install_cert_manager() {
    log_step "Installing cert-manager ${CERTMANAGER_VERSION}..."

    kubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/${CERTMANAGER_VERSION}/cert-manager.crds.yaml

    helm upgrade --install cert-manager jetstack/cert-manager \
        --namespace cert-manager \
        --version ${CERTMANAGER_VERSION} \
        --set installCRDs=false \
        --set global.leaderElection.namespace=cert-manager \
        --set securityContext.runAsNonRoot=true \
        --wait

    # Wait for cert-manager to be ready
    kubectl wait --for=condition=Available deployment --all -n cert-manager --timeout=300s

    # Create self-signed cluster issuer for internal use
    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: siab-selfsigned-issuer
spec:
  selfSigned: {}
---
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: siab-ca
  namespace: cert-manager
spec:
  isCA: true
  commonName: siab-ca
  secretName: siab-ca-secret
  privateKey:
    algorithm: ECDSA
    size: 256
  issuerRef:
    name: siab-selfsigned-issuer
    kind: ClusterIssuer
    group: cert-manager.io
---
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: siab-ca-issuer
spec:
  ca:
    secretName: siab-ca-secret
EOF

    log_info "cert-manager installed"
}

# Install Istio
install_istio() {
    log_step "Installing Istio ${ISTIO_VERSION}..."

    # Install Istio base
    helm upgrade --install istio-base istio/base \
        --namespace istio-system \
        --create-namespace \
        --version ${ISTIO_VERSION} \
        --wait

    # Install Istio control plane with security settings
    helm upgrade --install istiod istio/istiod \
        --namespace istio-system \
        --version ${ISTIO_VERSION} \
        --set global.proxy.privileged=false \
        --set global.mtls.enabled=true \
        --set meshConfig.enableAutoMtls=true \
        --set meshConfig.accessLogFile=/dev/stdout \
        --set pilot.autoscaleEnabled=true \
        --set pilot.autoscaleMin=2 \
        --wait

    # Wait for Istio to be ready
    kubectl wait --for=condition=Available deployment --all -n istio-system --timeout=300s

    # Install Istio ingress gateway
    helm upgrade --install istio-ingress istio/gateway \
        --namespace istio-system \
        --version ${ISTIO_VERSION} \
        --set service.type=NodePort \
        --wait

    # Apply strict mTLS policy
    cat <<EOF | kubectl apply -f -
apiVersion: security.istio.io/v1beta1
kind: PeerAuthentication
metadata:
  name: default
  namespace: istio-system
spec:
  mtls:
    mode: STRICT
EOF

    log_info "Istio installed with strict mTLS"
}

# Install Keycloak
install_keycloak() {
    log_step "Installing Keycloak ${KEYCLOAK_VERSION}..."

    # Load credentials
    source "${SIAB_CONFIG_DIR}/credentials.env"

    # Create Keycloak secret
    kubectl create secret generic keycloak-admin \
        --namespace keycloak \
        --from-literal=admin-password="${KEYCLOAK_ADMIN_PASSWORD}" \
        --dry-run=client -o yaml | kubectl apply -f -

    # Install Keycloak using Helm
    helm upgrade --install keycloak bitnami/keycloak \
        --namespace keycloak \
        --version ${KEYCLOAK_VERSION} \
        --set auth.adminUser=admin \
        --set auth.existingSecret=keycloak-admin \
        --set auth.passwordSecretKey=admin-password \
        --set production=true \
        --set proxy=edge \
        --set httpRelativePath="/" \
        --set postgresql.enabled=true \
        --set postgresql.auth.postgresPassword="$(openssl rand -base64 24 | tr -d '=+/')" \
        --set containerSecurityContext.runAsNonRoot=true \
        --set containerSecurityContext.allowPrivilegeEscalation=false \
        --set containerSecurityContext.capabilities.drop[0]=ALL \
        --set resources.requests.memory=512Mi \
        --set resources.requests.cpu=250m \
        --wait --timeout=600s

    # Create Istio VirtualService for Keycloak
    cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: keycloak
  namespace: keycloak
spec:
  hosts:
    - "keycloak.${SIAB_DOMAIN}"
  gateways:
    - istio-system/siab-gateway
  http:
    - route:
        - destination:
            host: keycloak
            port:
              number: 80
EOF

    log_info "Keycloak installed"
}

# Install MinIO
install_minio() {
    log_step "Installing MinIO..."

    if [[ "${SIAB_SKIP_STORAGE}" == "true" ]]; then
        log_warn "Skipping MinIO installation"
        return
    fi

    # Load credentials
    source "${SIAB_CONFIG_DIR}/credentials.env"

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
        --set persistence.enabled=true \
        --set persistence.size="${SIAB_MINIO_SIZE}" \
        --set resources.requests.memory=1Gi \
        --set securityContext.runAsUser=1000 \
        --set securityContext.runAsGroup=1000 \
        --set securityContext.fsGroup=1000 \
        --set consoleService.type=ClusterIP \
        --wait --timeout=600s

    # Create Istio VirtualService for MinIO Console
    cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: VirtualService
metadata:
  name: minio-console
  namespace: minio
spec:
  hosts:
    - "minio.${SIAB_DOMAIN}"
  gateways:
    - istio-system/siab-gateway
  http:
    - route:
        - destination:
            host: minio-console
            port:
              number: 9001
EOF

    log_info "MinIO installed"
}

# Install Trivy Operator
install_trivy() {
    log_step "Installing Trivy Operator ${TRIVY_VERSION}..."

    helm upgrade --install trivy-operator aqua/trivy-operator \
        --namespace trivy-system \
        --version ${TRIVY_VERSION} \
        --set trivy.ignoreUnfixed=false \
        --set operator.scanJobTimeout=10m \
        --set operator.vulnerabilityScannerEnabled=true \
        --set operator.configAuditScannerEnabled=true \
        --set operator.rbacAssessmentScannerEnabled=true \
        --set operator.infraAssessmentScannerEnabled=true \
        --set operator.clusterComplianceEnabled=true \
        --wait

    log_info "Trivy Operator installed"
}

# Install OPA Gatekeeper
install_gatekeeper() {
    log_step "Installing OPA Gatekeeper ${GATEKEEPER_VERSION}..."

    helm upgrade --install gatekeeper gatekeeper/gatekeeper \
        --namespace gatekeeper-system \
        --version ${GATEKEEPER_VERSION} \
        --set replicas=2 \
        --set audit.replicas=1 \
        --set constraintViolationsLimit=100 \
        --set auditInterval=60 \
        --set enableExternalData=true \
        --wait

    # Wait for Gatekeeper to be ready
    kubectl wait --for=condition=Available deployment --all -n gatekeeper-system --timeout=300s

    log_info "OPA Gatekeeper installed"
}

# Apply security policies
apply_security_policies() {
    log_step "Applying security policies..."

    # Default deny network policy for default namespace
    cat <<EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: default-deny-all
  namespace: default
spec:
  podSelector: {}
  policyTypes:
    - Ingress
    - Egress
---
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-dns
  namespace: default
spec:
  podSelector: {}
  policyTypes:
    - Egress
  egress:
    - to:
        - namespaceSelector: {}
      ports:
        - protocol: UDP
          port: 53
EOF

    log_info "Security policies applied"
}

# Install SIAB CRDs
install_siab_crds() {
    log_step "Installing SIAB Custom Resource Definitions..."

    # Copy CRDs from install location
    if [[ -d "${SIAB_DIR}/crds" ]]; then
        kubectl apply -f "${SIAB_DIR}/crds/"
    fi

    log_info "SIAB CRDs installed"
}

# Install landing page dashboard
install_dashboard() {
    log_step "Installing SIAB Dashboard..."

    # Deploy dashboard
    if [[ -d "${SIAB_DIR}/manifests/apps" ]]; then
        kubectl apply -f "${SIAB_DIR}/manifests/apps/dashboard.yaml"
    fi

    log_info "Dashboard installed"
}

# Create Istio Gateway
create_istio_gateway() {
    log_step "Creating Istio Gateway..."

    cat <<EOF | kubectl apply -f -
apiVersion: networking.istio.io/v1beta1
kind: Gateway
metadata:
  name: siab-gateway
  namespace: istio-system
spec:
  selector:
    istio: ingress
  servers:
    - port:
        number: 443
        name: https
        protocol: HTTPS
      tls:
        mode: SIMPLE
        credentialName: siab-gateway-cert
      hosts:
        - "*.${SIAB_DOMAIN}"
    - port:
        number: 80
        name: http
        protocol: HTTP
      hosts:
        - "*.${SIAB_DOMAIN}"
      tls:
        httpsRedirect: true
EOF

    # Create certificate for gateway
    cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: siab-gateway-cert
  namespace: istio-system
spec:
  secretName: siab-gateway-cert
  issuerRef:
    name: siab-ca-issuer
    kind: ClusterIssuer
  commonName: "*.${SIAB_DOMAIN}"
  dnsNames:
    - "*.${SIAB_DOMAIN}"
    - "${SIAB_DOMAIN}"
EOF

    log_info "Istio Gateway created"
}

# Final configuration
final_configuration() {
    log_step "Performing final configuration..."

    # Save installation info
    cat > "${SIAB_CONFIG_DIR}/install-info.json" <<EOF
{
  "version": "${SIAB_VERSION}",
  "installed_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "domain": "${SIAB_DOMAIN}",
  "components": {
    "rke2": "${RKE2_VERSION}",
    "istio": "${ISTIO_VERSION}",
    "keycloak": "${KEYCLOAK_VERSION}",
    "minio": "${MINIO_VERSION}",
    "trivy": "${TRIVY_VERSION}",
    "gatekeeper": "${GATEKEEPER_VERSION}",
    "cert_manager": "${CERTMANAGER_VERSION}"
  }
}
EOF

    # Add hosts entries for local access
    if ! grep -q "${SIAB_DOMAIN}" /etc/hosts; then
        local node_ip
        node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}')
        cat >> /etc/hosts <<EOF

# SIAB Platform
${node_ip} ${SIAB_DOMAIN}
${node_ip} keycloak.${SIAB_DOMAIN}
${node_ip} minio.${SIAB_DOMAIN}
${node_ip} grafana.${SIAB_DOMAIN}
${node_ip} dashboard.${SIAB_DOMAIN}
EOF
    fi

    log_info "Final configuration complete"
}

# Print completion message
print_completion() {
    local ingress_port
    ingress_port=$(kubectl get svc -n istio-system istio-ingress -o jsonpath='{.spec.ports[?(@.name=="https")].nodePort}')

    echo ""
    echo "============================================"
    echo -e "${GREEN}SIAB Installation Complete!${NC}"
    echo "============================================"
    echo ""
    echo "Access your platform:"
    echo "  Dashboard:  https://dashboard.${SIAB_DOMAIN}:${ingress_port}"
    echo "  Keycloak:   https://keycloak.${SIAB_DOMAIN}:${ingress_port}"
    echo "  MinIO:      https://minio.${SIAB_DOMAIN}:${ingress_port}"
    echo ""
    echo "Credentials saved to: ${SIAB_CONFIG_DIR}/credentials.env"
    echo ""
    echo "To deploy applications, use the SIABApplication CRD:"
    echo "  kubectl apply -f my-siab-app.yaml"
    echo ""
    echo "Documentation: ${SIAB_DIR}/docs/"
    echo ""
    echo "Thank you for installing SIAB!"
    echo "============================================"
}

# Main installation
main() {
    log_info "Starting SIAB ${SIAB_VERSION} installation..."

    check_root
    setup_directories
    check_requirements

    # Redirect all output to log file while still showing on console
    exec > >(tee -a "${SIAB_LOG_DIR}/install.log") 2>&1

    install_dependencies
    configure_firewall
    configure_security
    install_rke2
    install_helm
    generate_credentials
    create_namespaces
    install_cert_manager
    install_istio
    create_istio_gateway
    install_keycloak
    install_minio
    install_trivy
    install_gatekeeper
    apply_security_policies
    install_siab_crds
    install_dashboard
    final_configuration
    print_completion

    log_info "Installation completed successfully!"
}

# Run main function
main "$@"
