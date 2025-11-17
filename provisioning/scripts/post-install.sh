#!/bin/bash
set -euo pipefail

# SIAB Post-Installation Script
# Runs after OS installation to prepare for SIAB deployment

readonly LOG_FILE="/var/log/siab-post-install.log"

exec > >(tee -a "${LOG_FILE}") 2>&1

log_info() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [INFO] $1"
}

log_error() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] [ERROR] $1" >&2
}

log_info "Starting SIAB post-installation configuration..."

# Ensure we're on Rocky Linux
if ! grep -q "Rocky Linux" /etc/os-release; then
    log_error "This script requires Rocky Linux"
    exit 1
fi

# Update system
log_info "Updating system packages..."
dnf update -y

# Install essential packages
log_info "Installing essential packages..."
dnf install -y \
    curl \
    wget \
    git \
    tar \
    openssl \
    net-tools \
    bind-utils \
    policycoreutils-python-utils \
    container-selinux \
    iptables \
    chrony \
    audit \
    firewalld \
    yum-utils \
    device-mapper-persistent-data \
    lvm2 \
    vim \
    tmux \
    htop \
    jq

# Configure time synchronization
log_info "Configuring time synchronization..."
systemctl enable --now chronyd

# Enable and configure firewall
log_info "Configuring firewall..."
systemctl enable --now firewalld

# Enable audit logging
log_info "Enabling audit logging..."
systemctl enable --now auditd

# Configure SELinux
log_info "Configuring SELinux..."
if [[ $(getenforce) != "Enforcing" ]]; then
    setenforce 1
    sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
fi

# Disable swap (required for Kubernetes)
log_info "Disabling swap..."
swapoff -a
sed -i '/ swap / s/^/#/' /etc/fstab

# Configure kernel parameters for Kubernetes
log_info "Configuring kernel parameters..."
cat > /etc/sysctl.d/99-kubernetes.conf <<EOF
# Kubernetes requirements
net.bridge.bridge-nf-call-iptables = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1

# Security hardening
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.secure_redirects = 0
net.ipv4.conf.default.secure_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.default.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1

# Performance tuning
vm.swappiness = 0
fs.file-max = 2097152
net.core.somaxconn = 32768
net.ipv4.tcp_max_syn_backlog = 8192
EOF

# Load kernel modules
log_info "Loading required kernel modules..."
cat > /etc/modules-load.d/kubernetes.conf <<EOF
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

# Apply sysctl params
sysctl --system

# Create SIAB directories
log_info "Creating SIAB directories..."
mkdir -p /opt/siab
mkdir -p /etc/siab
mkdir -p /var/log/siab
mkdir -p /var/lib/rancher

# Set up SSH for automation (if SSH keys provided)
if [[ -n "${SIAB_SSH_KEY:-}" ]]; then
    log_info "Setting up SSH authorized keys..."
    mkdir -p /root/.ssh
    chmod 700 /root/.ssh
    echo "${SIAB_SSH_KEY}" >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
fi

# Download SIAB installer
log_info "Downloading SIAB installer..."
curl -sfL https://raw.githubusercontent.com/morbidsteve/SIAB/main/install.sh -o /opt/siab/install.sh
chmod +x /opt/siab/install.sh

# Create node information file
log_info "Creating node information file..."
cat > /etc/siab/node-info.json <<EOF
{
  "hostname": "$(hostname)",
  "ip_address": "$(hostname -I | awk '{print $1}')",
  "provisioned_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "os_version": "$(cat /etc/rocky-release)",
  "kernel_version": "$(uname -r)",
  "cpu_cores": $(nproc),
  "memory_gb": $(free -g | awk '/^Mem:/{print $2}'),
  "disk_size_gb": $(df -BG / | awk 'NR==2 {print $2}' | sed 's/G//')
}
EOF

# Set hostname based on IP (if not already set)
if [[ "$(hostname)" == "localhost"* ]] || [[ "$(hostname)" == "siab-node" ]]; then
    local ip_suffix
    ip_suffix=$(hostname -I | awk '{print $1}' | awk -F. '{print $4}')
    hostnamectl set-hostname "siab-node-${ip_suffix}.siab.local"
    log_info "Hostname set to: $(hostname)"
fi

# Configure automatic SIAB installation on first boot
log_info "Setting up SIAB auto-installation..."
cat > /etc/systemd/system/siab-autoinstall.service <<'SIABEOF'
[Unit]
Description=SIAB Automated Installation
After=network-online.target
Wants=network-online.target
ConditionPathExists=!/etc/siab/installed

[Service]
Type=oneshot
ExecStart=/opt/siab/install.sh
ExecStartPost=/usr/bin/touch /etc/siab/installed
StandardOutput=journal+console
StandardError=journal+console
RemainAfterExit=yes
TimeoutStartSec=3600

[Install]
WantedBy=multi-user.target
SIABEOF

# Enable auto-install service
systemctl enable siab-autoinstall.service

# Create post-provision hook for custom actions
cat > /etc/siab/post-provision-hook.sh <<'HOOKEOF'
#!/bin/bash
# Custom post-provision hook
# Add any custom configuration here

# Example: Join existing cluster
# export SIAB_JOIN_TOKEN="your-token"
# export SIAB_JOIN_ADDRESS="existing-master:9345"

# Example: Custom domain
# export SIAB_DOMAIN="custom.example.com"

# Example: Skip certain components
# export SIAB_SKIP_MONITORING="true"

exit 0
HOOKEOF

chmod +x /etc/siab/post-provision-hook.sh

# Clean up
log_info "Cleaning up..."
dnf clean all

# Create completion marker
touch /etc/siab/post-install-complete

log_info "Post-installation configuration complete"
log_info "System will automatically install SIAB on next boot"
log_info "Or run manually: /opt/siab/install.sh"

# Display node information
log_info "Node Information:"
cat /etc/siab/node-info.json

exit 0
