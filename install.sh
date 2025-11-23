#!/bin/bash
set -euo pipefail

# SIAB - Secure Infrastructure as a Box
# One-command secure Kubernetes platform installer

readonly SIAB_VERSION="1.0.0"
readonly SIAB_DIR="/opt/siab"
readonly SIAB_CONFIG_DIR="/etc/siab"
readonly SIAB_LOG_DIR="/var/log/siab"
readonly SIAB_BIN_DIR="/usr/local/bin"

# Ensure SIAB bin directory is in PATH
export PATH="${SIAB_BIN_DIR}:/var/lib/rancher/rke2/bin:${PATH}"

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
SIAB_MINIO_SIZE="${SIAB_MINIO_SIZE:-20Gi}"
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
    if [[ $free_space -lt 25 ]]; then
        log_error "Minimum 30GB free disk space required (found: ${free_space}GB)"
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
        # Remove any leftover RKE2 repos from previous installs to avoid GPG issues
        rm -f /etc/yum.repos.d/rancher-rke2*.repo 2>/dev/null || true
        dnf clean all
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

# Clean up any existing RKE2 installation
cleanup_rke2() {
    log_step "Checking for existing RKE2 installation..."

    # Check if RKE2 is installed
    if [[ -f /usr/local/bin/rke2 ]] || [[ -f /var/lib/rancher/rke2 ]] || \
       systemctl is-active --quiet rke2-server 2>/dev/null || \
       systemctl is-enabled --quiet rke2-server 2>/dev/null; then

        log_info "Existing RKE2 installation found. Cleaning up..."

        # Stop services
        log_info "Stopping RKE2 services..."
        systemctl stop rke2-server 2>/dev/null || true
        systemctl stop rke2-agent 2>/dev/null || true
        systemctl disable rke2-server 2>/dev/null || true
        systemctl disable rke2-agent 2>/dev/null || true
        sleep 3

        # Kill any remaining processes
        log_info "Cleaning up processes..."
        pkill -9 -f "rke2" 2>/dev/null || true
        pkill -9 -f "containerd-shim" 2>/dev/null || true
        pkill -9 -f "kubelet" 2>/dev/null || true
        sleep 2

        # Run official uninstall script if available
        if [[ -f /usr/local/bin/rke2-uninstall.sh ]]; then
            log_info "Running RKE2 uninstall script..."
            /usr/local/bin/rke2-uninstall.sh 2>/dev/null || true
        fi

        # Remove all RKE2 data and config
        log_info "Removing RKE2 data directories..."
        rm -rf /var/lib/rancher/rke2
        rm -rf /etc/rancher/rke2
        rm -rf /var/lib/kubelet
        rm -rf /var/lib/cni
        rm -rf /var/log/pods
        rm -rf /var/log/containers
        rm -rf /run/k3s
        rm -f /usr/local/bin/rke2*
        rm -f /usr/local/bin/kubectl
        rm -rf /usr/local/lib/systemd/system/rke2*
        rm -f /etc/yum.repos.d/rancher-rke2*.repo 2>/dev/null || true

        # Reload systemd
        systemctl daemon-reload

        log_info "RKE2 cleanup complete"
    else
        log_info "No existing RKE2 installation found"
    fi
}

# Setup RKE2 prerequisites
setup_rke2_prerequisites() {
    log_step "Setting up RKE2 prerequisites..."

    # Create etcd user and group (required for CIS profile)
    if ! getent group etcd >/dev/null 2>&1; then
        groupadd --system etcd
        log_info "Created etcd group"
    fi
    if ! getent passwd etcd >/dev/null 2>&1; then
        useradd --system --gid etcd --shell /sbin/nologin --comment "etcd user" etcd
        log_info "Created etcd user"
    fi

    # Set required kernel parameters
    log_info "Setting kernel parameters..."
    cat > /etc/sysctl.d/90-rke2-cis.conf <<EOF
# RKE2 CIS Profile Requirements
kernel.panic = 10
kernel.panic_on_oops = 1
vm.overcommit_memory = 1
vm.panic_on_oom = 0
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

    # Load required kernel modules
    modprobe br_netfilter 2>/dev/null || true
    modprobe overlay 2>/dev/null || true

    # Apply sysctl settings
    sysctl --system > /dev/null 2>&1

    log_info "Prerequisites configured"
}

# Install RKE2
install_rke2() {
    log_step "Installing RKE2 ${RKE2_VERSION}..."

    # Clean up any existing installation first
    cleanup_rke2

    # Setup prerequisites
    setup_rke2_prerequisites

    # Create RKE2 config directory
    mkdir -p /etc/rancher/rke2
    mkdir -p /var/lib/rancher/rke2/server/manifests

    # Get hostname and IP for TLS SANs
    local hostname_val=$(hostname)
    local ip_val=$(hostname -I | awk '{print $1}')

    # Create simplified RKE2 configuration (CIS profile causes issues on some systems)
    # Security is still enforced via other means (network policies, pod security, etc.)
    cat > /etc/rancher/rke2/config.yaml <<EOF
# RKE2 Configuration for SIAB
write-kubeconfig-mode: "0644"
tls-san:
  - ${hostname_val}
  - ${ip_val}
  - localhost
  - 127.0.0.1
# Secrets encryption
secrets-encryption: true
EOF

    # Install RKE2 using tarball method (avoids GPG issues with RPM repos)
    log_info "Downloading and installing RKE2..."
    curl -sfL https://get.rke2.io | INSTALL_RKE2_METHOD="tar" sh -

    # Enable RKE2 service
    systemctl daemon-reload
    systemctl enable rke2-server.service

    # Start RKE2 and monitor startup
    log_info "Starting RKE2 service..."
    log_info "First startup takes 5-10 minutes. Monitoring progress..."
    echo ""
    systemctl start rke2-server.service &

    # Monitor RKE2 startup with real-time status display
    local max_wait=600  # 10 minutes
    local elapsed=0
    local last_status_time=0

    while [[ $elapsed -lt $max_wait ]]; do
        # Check if service failed
        local svc_status=$(systemctl is-active rke2-server 2>/dev/null || echo "unknown")

        if [[ "$svc_status" == "failed" ]]; then
            echo ""
            log_error "RKE2 service failed!"
            echo "----------------------------------------"
            systemctl status rke2-server --no-pager -l 2>/dev/null || true
            echo "----------------------------------------"
            log_error "Recent logs:"
            journalctl -u rke2-server --no-pager -n 20
            exit 1
        fi

        # Show status every 30 seconds
        if [[ $((elapsed - last_status_time)) -ge 30 ]] || [[ $elapsed -eq 0 ]]; then
            echo ""
            echo "=== RKE2 Status (${elapsed}s elapsed) ==="
            # Show brief service status
            local active_state=$(systemctl show rke2-server --property=ActiveState --value 2>/dev/null || echo "unknown")
            local sub_state=$(systemctl show rke2-server --property=SubState --value 2>/dev/null || echo "unknown")
            echo "Service: ${active_state} (${sub_state})"

            # Show what's happening from recent logs (last 3 lines)
            echo "Recent activity:"
            journalctl -u rke2-server --no-pager -n 3 -q 2>/dev/null | tail -3 || echo "  (waiting for logs...)"
            echo "================================="
            last_status_time=$elapsed
        fi

        # Check if kubectl is available and working
        if [[ -f /var/lib/rancher/rke2/bin/kubectl ]] && \
           [[ -f /etc/rancher/rke2/rke2.yaml ]]; then
            if /var/lib/rancher/rke2/bin/kubectl \
               --kubeconfig /etc/rancher/rke2/rke2.yaml \
               get nodes &>/dev/null 2>&1; then
                echo ""
                log_info "RKE2 is ready!"
                # Show final node status
                echo ""
                /var/lib/rancher/rke2/bin/kubectl \
                    --kubeconfig /etc/rancher/rke2/rke2.yaml \
                    get nodes
                break
            fi
        fi

        sleep 5
        elapsed=$((elapsed + 5))
    done

    if [[ $elapsed -ge $max_wait ]]; then
        echo ""
        log_error "RKE2 startup timeout after ${max_wait}s"
        log_error "Final status:"
        systemctl status rke2-server --no-pager -l 2>/dev/null || true
        log_error "Check logs: journalctl -fu rke2-server"
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

    # Download and extract Helm
    local helm_url="https://get.helm.sh/helm-${HELM_VERSION}-linux-amd64.tar.gz"
    log_info "Downloading Helm from ${helm_url}..."

    if ! curl -fsSL "${helm_url}" -o /tmp/helm.tar.gz; then
        log_error "Failed to download Helm"
        exit 1
    fi

    cd /tmp
    tar xzf helm.tar.gz
    mv linux-amd64/helm "${SIAB_BIN_DIR}/helm"
    rm -rf linux-amd64 helm.tar.gz
    chmod +x "${SIAB_BIN_DIR}/helm"
    cd - >/dev/null

    # Verify helm binary exists
    if [[ ! -x "${SIAB_BIN_DIR}/helm" ]]; then
        log_error "Helm binary not found at ${SIAB_BIN_DIR}/helm"
        exit 1
    fi

    log_info "Helm binary installed at ${SIAB_BIN_DIR}/helm"

    # Ensure PATH is updated
    export PATH="${SIAB_BIN_DIR}:${PATH}"
    hash -r 2>/dev/null || true

    # Add Helm repos using full path
    log_info "Adding Helm repositories..."
    "${SIAB_BIN_DIR}/helm" repo add istio https://istio-release.storage.googleapis.com/charts || true
    "${SIAB_BIN_DIR}/helm" repo add jetstack https://charts.jetstack.io || true
    "${SIAB_BIN_DIR}/helm" repo add codecentric https://codecentric.github.io/helm-charts || true
    "${SIAB_BIN_DIR}/helm" repo add aqua https://aquasecurity.github.io/helm-charts/ || true
    "${SIAB_BIN_DIR}/helm" repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts || true
    "${SIAB_BIN_DIR}/helm" repo add minio https://charts.min.io/ || true
    "${SIAB_BIN_DIR}/helm" repo update

    log_info "Helm installed successfully"
}

# Install k9s for cluster monitoring
install_k9s() {
    log_step "Installing k9s..."

    local k9s_version="v0.32.5"
    local k9s_url="https://github.com/derailed/k9s/releases/download/${k9s_version}/k9s_Linux_amd64.tar.gz"

    if ! curl -fsSL "${k9s_url}" -o /tmp/k9s.tar.gz; then
        log_error "Failed to download k9s"
        exit 1
    fi

    cd /tmp
    tar xzf k9s.tar.gz k9s
    mv k9s "${SIAB_BIN_DIR}/k9s"
    rm -f k9s.tar.gz
    chmod +x "${SIAB_BIN_DIR}/k9s"
    cd - >/dev/null

    log_info "k9s installed at ${SIAB_BIN_DIR}/k9s"
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
    log_step "Installing Keycloak..."

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

    # Disable Istio sidecar injection for keycloak namespace
    kubectl label namespace keycloak istio-injection=disabled --overwrite 2>/dev/null || true

    # Create secrets
    local pg_password=$(openssl rand -base64 24 | tr -d '=+/' | head -c 24)

    # Deploy Keycloak directly without helm (avoids chart configuration issues)
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
kind: Deployment
metadata:
  name: keycloak
  namespace: keycloak
  labels:
    app: keycloak
spec:
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
        image: quay.io/keycloak/keycloak:24.0
        args:
        - start
        - --hostname-strict=false
        - --http-enabled=true
        - --proxy=edge
        - --cache=local
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
        - name: KC_METRICS_ENABLED
          value: "true"
        ports:
        - name: http
          containerPort: 8080
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 8080
          initialDelaySeconds: 30
          periodSeconds: 10
        livenessProbe:
          httpGet:
            path: /health/live
            port: 8080
          initialDelaySeconds: 60
          periodSeconds: 30
        resources:
          requests:
            memory: 512Mi
            cpu: 250m
---
apiVersion: v1
kind: Service
metadata:
  name: keycloak
  namespace: keycloak
spec:
  ports:
  - name: http
    port: 80
    targetPort: 8080
  selector:
    app: keycloak
EOF

    # Monitor Keycloak deployment
    log_info "Waiting for Keycloak to be ready (this may take 3-5 minutes)..."
    local max_wait=600
    local elapsed=0
    local last_status_time=0

    while [[ $elapsed -lt $max_wait ]]; do
        # Show status every 30 seconds
        if [[ $((elapsed - last_status_time)) -ge 30 ]] || [[ $elapsed -eq 0 ]]; then
            echo ""
            echo "=== Keycloak Status (${elapsed}s elapsed) ==="
            kubectl get pods -n keycloak -o wide 2>/dev/null || echo "  (waiting for pods...)"
            echo "================================="
            last_status_time=$elapsed
        fi

        # Check if Keycloak is ready
        if kubectl get deployment keycloak -n keycloak -o jsonpath='{.status.availableReplicas}' 2>/dev/null | grep -q "1"; then
            echo ""
            log_info "Keycloak is ready!"
            break
        fi

        # Check for crash loops or errors
        local pod_status=$(kubectl get pods -n keycloak -l app=keycloak -o jsonpath='{.items[0].status.containerStatuses[0].state.waiting.reason}' 2>/dev/null)
        if [[ "$pod_status" == "CrashLoopBackOff" ]] || [[ "$pod_status" == "Error" ]] || [[ "$pod_status" == "ImagePullBackOff" ]]; then
            echo ""
            log_error "Keycloak pod is in $pod_status state"
            kubectl describe pods -n keycloak -l app=keycloak 2>/dev/null | tail -30 || true
            kubectl logs -n keycloak -l app=keycloak --tail=50 2>/dev/null || true
            exit 1
        fi

        sleep 10
        elapsed=$((elapsed + 10))
    done

    if [[ $elapsed -ge $max_wait ]]; then
        log_error "Keycloak installation timeout after ${max_wait}s"
        kubectl describe pods -n keycloak
        exit 1
    fi

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

    # Clean up any existing/stuck MinIO installation
    log_info "Cleaning up any existing MinIO installation..."
    helm uninstall minio -n minio 2>/dev/null || true
    kubectl delete jobs --all -n minio 2>/dev/null || true
    kubectl delete pods --all -n minio --force --grace-period=0 2>/dev/null || true
    kubectl delete pvc --all -n minio 2>/dev/null || true
    sleep 3

    # Create MinIO secret
    kubectl create secret generic minio-creds \
        --namespace minio \
        --from-literal=rootUser="${MINIO_ROOT_USER}" \
        --from-literal=rootPassword="${MINIO_ROOT_PASSWORD}" \
        --dry-run=client -o yaml | kubectl apply -f -

    # Install MinIO (persistence disabled for single-node setup without storage provisioner)
    # Don't use --wait as post-install jobs can hang with Istio sidecars
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
        --set postJob.podAnnotations."sidecar\.istio\.io/inject"=false \
        --timeout=600s

    # Wait for MinIO deployment to be ready
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
        if [[ $((elapsed % 30)) -eq 0 ]]; then
            echo "  Waiting for MinIO... (${elapsed}s)"
            kubectl get pods -n minio 2>/dev/null || true
        fi
    done

    if [[ $elapsed -ge $max_wait ]]; then
        log_error "MinIO installation timeout"
        kubectl describe pods -n minio
        exit 1
    fi

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

    # Setup kubectl access for non-root users
    setup_nonroot_access

    log_info "Final configuration complete"
}

# Setup kubectl access for non-root users
setup_nonroot_access() {
    log_info "Setting up kubectl access for non-root users..."

    # Get the user who ran sudo (if any)
    local real_user="${SUDO_USER:-}"
    local real_home=""

    if [[ -n "$real_user" ]] && [[ "$real_user" != "root" ]]; then
        real_home=$(getent passwd "$real_user" | cut -d: -f6)

        if [[ -n "$real_home" ]]; then
            log_info "Configuring kubectl for user: $real_user"

            # Create .kube directory for the user
            mkdir -p "${real_home}/.kube"

            # Copy kubeconfig
            cp /etc/rancher/rke2/rke2.yaml "${real_home}/.kube/config"

            # Fix permissions
            chown -R "${real_user}:${real_user}" "${real_home}/.kube"
            chmod 600 "${real_home}/.kube/config"

            # Add RKE2 and SIAB bins to user's PATH
            if ! grep -q "/var/lib/rancher/rke2/bin" "${real_home}/.bashrc" 2>/dev/null; then
                cat >> "${real_home}/.bashrc" <<'EOF'

# SIAB - Kubernetes tools
export PATH=$PATH:/var/lib/rancher/rke2/bin:/usr/local/bin
export KUBECONFIG=$HOME/.kube/config
EOF
                chown "${real_user}:${real_user}" "${real_home}/.bashrc"
            fi

            log_info "User $real_user can now run kubectl, helm, and k9s without sudo"
        fi
    fi

    # Also ensure the credentials file is readable
    if [[ -n "$real_user" ]] && [[ "$real_user" != "root" ]]; then
        # Create a copy of credentials for the user
        if [[ -f "${SIAB_CONFIG_DIR}/credentials.env" ]]; then
            cp "${SIAB_CONFIG_DIR}/credentials.env" "${real_home}/.siab-credentials.env"
            chown "${real_user}:${real_user}" "${real_home}/.siab-credentials.env"
            chmod 600 "${real_home}/.siab-credentials.env"
            log_info "Credentials copied to ${real_home}/.siab-credentials.env"
        fi
    fi
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
    echo "Cluster monitoring with k9s:"
    echo "  k9s"
    echo ""
    if [[ -n "${SUDO_USER:-}" ]] && [[ "${SUDO_USER}" != "root" ]]; then
        echo "Non-root access configured for user: ${SUDO_USER}"
        echo "  Run: source ~/.bashrc  (or log out and back in)"
        echo "  Then use kubectl, helm, k9s without sudo"
        echo ""
    fi
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
    install_k9s
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
