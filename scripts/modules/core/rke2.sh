#!/bin/bash
# SIAB - RKE2 Module
# RKE2 Kubernetes installation and management

# Requires: logging.sh, config.sh, progress/status.sh, checks/preflight.sh

# Cleanup existing RKE2 installation
cleanup_rke2() {
    log_info "Checking for existing RKE2 installation..."

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
    log_info "Setting up RKE2 prerequisites..."

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

# Increase inotify limits to prevent "Too many open files" errors
# Required for Kubernetes, Longhorn, and monitoring tools
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 512
fs.inotify.max_queued_events = 32768
fs.file-max = 2097152
EOF

    # Set ulimits for the system to prevent file descriptor exhaustion
    log_info "Configuring system limits..."
    cat > /etc/security/limits.d/90-rke2.conf <<EOF
# Increase file descriptor limits for Kubernetes
* soft nofile 1048576
* hard nofile 1048576
* soft nproc 1048576
* hard nproc 1048576
root soft nofile 1048576
root hard nofile 1048576
root soft nproc 1048576
root hard nproc 1048576
EOF

    # Load required kernel modules
    modprobe br_netfilter 2>/dev/null || true
    modprobe overlay 2>/dev/null || true

    # Apply sysctl settings
    sysctl --system > /dev/null 2>&1

    log_info "Prerequisites configured"
}

# Install RKE2 Kubernetes
install_rke2() {
    start_step "RKE2 Kubernetes"

    # Check if RKE2 is already properly installed
    if check_rke2_installed; then
        skip_step "RKE2 Kubernetes" "Already installed and running correctly"
        # Still setup kubectl access if needed
        mkdir -p ~/.kube
        cp /etc/rancher/rke2/rke2.yaml ~/.kube/config 2>/dev/null || true
        chmod 600 ~/.kube/config 2>/dev/null || true
        export PATH=$PATH:/var/lib/rancher/rke2/bin
        return 0
    fi

    log_info "Installing RKE2 ${RKE2_VERSION}..."

    # Clean up any existing installation first
    cleanup_rke2

    # Setup prerequisites
    setup_rke2_prerequisites

    # Create RKE2 config directory
    mkdir -p /etc/rancher/rke2
    mkdir -p /var/lib/rancher/rke2/server/manifests

    # Get hostname and IP for TLS SANs
    local hostname_val
    hostname_val=$(hostname)
    local ip_val
    ip_val=$(hostname -I | awk '{print $1}')

    # Create simplified RKE2 configuration
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
        local svc_status
        svc_status=$(systemctl is-active rke2-server 2>/dev/null || echo "unknown")

        if [[ "$svc_status" == "failed" ]]; then
            echo ""
            log_error "RKE2 service failed!"
            echo "----------------------------------------"
            systemctl status rke2-server --no-pager -l 2>/dev/null || true
            echo "----------------------------------------"
            log_error "Recent logs:"
            journalctl -u rke2-server --no-pager -n 20
            fail_step "RKE2 Kubernetes" "Service failed to start"
            return 1
        fi

        # Show status every 30 seconds
        if [[ $((elapsed - last_status_time)) -ge 30 ]] || [[ $elapsed -eq 0 ]]; then
            echo ""
            echo "=== RKE2 Status (${elapsed}s elapsed) ==="
            local active_state
            active_state=$(systemctl show rke2-server --property=ActiveState --value 2>/dev/null || echo "unknown")
            local sub_state
            sub_state=$(systemctl show rke2-server --property=SubState --value 2>/dev/null || echo "unknown")
            echo "Service: ${active_state} (${sub_state})"
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
        fail_step "RKE2 Kubernetes" "Startup timeout"
        return 1
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

    complete_step "RKE2 Kubernetes"
    log_info "RKE2 installed successfully"
}

# Uninstall RKE2 completely (SSH-safe version)
uninstall_rke2() {
    log_info "Uninstalling RKE2 (SSH-safe mode)..."

    # CRITICAL: Detect the primary network interface used for SSH before any cleanup
    local primary_iface=""
    local ssh_ip=""

    # Try to get the interface from SSH_CONNECTION or default route
    if [[ -n "${SSH_CONNECTION:-}" ]]; then
        ssh_ip=$(echo "$SSH_CONNECTION" | awk '{print $3}')
        primary_iface=$(ip -o addr show | grep "$ssh_ip" | awk '{print $2}' | head -1)
    fi

    # Fallback: get interface from default route
    if [[ -z "$primary_iface" ]]; then
        primary_iface=$(ip route show default 2>/dev/null | awk '/default/ {print $5}' | head -1)
    fi

    log_info "Primary network interface: ${primary_iface:-unknown} (preserving for SSH)"

    # Ensure SSH port is open in firewall before any changes
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --add-port=22/tcp 2>/dev/null || true
        firewall-cmd --add-service=ssh 2>/dev/null || true
    fi
    if command -v ufw &>/dev/null; then
        ufw allow 22/tcp 2>/dev/null || true
    fi
    # Also ensure iptables has SSH allowed
    iptables -I INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || true

    # Stop and disable services
    log_info "Stopping RKE2 services..."
    systemctl stop rke2-server 2>/dev/null || true
    systemctl stop rke2-agent 2>/dev/null || true
    systemctl disable rke2-server 2>/dev/null || true
    systemctl disable rke2-agent 2>/dev/null || true
    sleep 3

    # Kill containerd-shim processes (but NOT networking)
    log_info "Stopping container processes..."
    pkill -9 -f "containerd-shim" 2>/dev/null || true
    sleep 2

    # Kill RKE2/Kubernetes processes (but avoid network disruption)
    pkill -9 -f "rke2 server" 2>/dev/null || true
    pkill -9 -f "rke2 agent" 2>/dev/null || true
    pkill -9 -f "kubelet" 2>/dev/null || true
    pkill -9 -f "kube-proxy" 2>/dev/null || true
    pkill -9 -f "kube-apiserver" 2>/dev/null || true
    pkill -9 -f "kube-controller" 2>/dev/null || true
    pkill -9 -f "kube-scheduler" 2>/dev/null || true
    pkill -9 -f "etcd" 2>/dev/null || true
    sleep 2

    # Unmount kubernetes volumes safely
    log_info "Unmounting Kubernetes volumes..."
    mount | grep "/var/lib/kubelet" | awk '{print $3}' | sort -r | while read -r mnt; do
        umount -l "$mnt" 2>/dev/null || true
    done
    mount | grep "/run/k3s" | awk '{print $3}' | sort -r | while read -r mnt; do
        umount -l "$mnt" 2>/dev/null || true
    done
    mount | grep "/run/netns/cni" | awk '{print $3}' | sort -r | while read -r mnt; do
        umount -l "$mnt" 2>/dev/null || true
    done

    # Clean up CNI network interfaces (but NOT the primary interface!)
    log_info "Cleaning CNI network interfaces (preserving $primary_iface)..."
    for iface in cni0 flannel.1 flannel.4096 flannel-wg vxlan.calico kube-ipvs0; do
        if [[ "$iface" != "$primary_iface" ]] && ip link show "$iface" &>/dev/null; then
            ip link set "$iface" down 2>/dev/null || true
            ip link delete "$iface" 2>/dev/null || true
        fi
    done

    # Clean up veth interfaces that belong to CNI (master cni0)
    ip link show 2>/dev/null | grep 'master cni0' | while read -r _ iface _; do
        iface="${iface%%@*}"
        if [[ -n "$iface" ]] && [[ "$iface" != "$primary_iface" ]]; then
            ip link delete "$iface" 2>/dev/null || true
        fi
    done

    # Remove CNI network namespaces
    log_info "Cleaning CNI network namespaces..."
    find /run/netns -name 'cni-*' -exec rm -f {} \; 2>/dev/null || true

    # Clean iptables rules SAFELY - only remove K8s/CNI rules, preserve SSH
    log_info "Cleaning Kubernetes iptables rules (preserving SSH)..."

    # Save current rules, filter out K8s/CNI rules, but ensure SSH is preserved
    if iptables-save 2>/dev/null | grep -q "KUBE-\|CNI-\|cali"; then
        # Create a backup of current rules
        iptables-save > /tmp/iptables-backup-$$.rules 2>/dev/null || true

        # Filter out K8s rules but keep everything else
        iptables-save 2>/dev/null | \
            grep -v "KUBE-" | \
            grep -v "CNI-" | \
            grep -v "cali-" | \
            grep -v "cali:" | \
            grep -v "CILIUM_" | \
            grep -v "flannel" | \
            iptables-restore 2>/dev/null || true

        # CRITICAL: Re-ensure SSH is allowed after iptables changes
        iptables -I INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || true
    fi

    # Run official uninstall script (but we've already done the dangerous parts safely)
    # Only use it for file cleanup, not network cleanup
    if [[ -f /usr/local/bin/rke2-uninstall.sh ]]; then
        log_info "Running RKE2 file cleanup..."
        # Temporarily rename the killall script so uninstall doesn't call it
        if [[ -f /usr/local/bin/rke2-killall.sh ]]; then
            mv /usr/local/bin/rke2-killall.sh /usr/local/bin/rke2-killall.sh.bak 2>/dev/null || true
        fi
        /usr/local/bin/rke2-uninstall.sh 2>/dev/null || true
        # Restore (so we can delete it properly)
        if [[ -f /usr/local/bin/rke2-killall.sh.bak ]]; then
            mv /usr/local/bin/rke2-killall.sh.bak /usr/local/bin/rke2-killall.sh 2>/dev/null || true
        fi
    fi

    # Remove data directories
    log_info "Removing RKE2 data directories..."
    rm -rf /var/lib/rancher
    rm -rf /etc/rancher
    rm -rf /var/lib/kubelet
    rm -rf /var/lib/cni
    rm -rf /var/log/pods
    rm -rf /var/log/containers
    rm -rf /run/k3s
    rm -f /usr/local/bin/rke2*
    rm -f /usr/local/bin/kubectl
    rm -rf ~/.kube

    # Reload systemd
    systemctl daemon-reload

    # FINAL: Ensure SSH is still allowed
    if command -v firewall-cmd &>/dev/null; then
        firewall-cmd --add-port=22/tcp 2>/dev/null || true
    fi
    iptables -I INPUT -p tcp --dport 22 -j ACCEPT 2>/dev/null || true

    log_info "RKE2 uninstall complete (SSH preserved)"
}

# Configure Calico/Canal for proper connectivity
configure_calico_network() {
    log_info "Configuring Calico/Canal network for optimal connectivity..."

    # Wait for Calico to be ready before configuring
    log_info "Waiting for Canal/Calico pods to be ready..."
    local max_wait=120
    local elapsed=0
    while [[ $elapsed -lt $max_wait ]]; do
        local canal_ready
        canal_ready=$(kubectl get pods -n kube-system -l k8s-app=canal --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l)
        if [[ $canal_ready -ge 1 ]]; then
            log_info "Canal/Calico is ready"
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    # Create GlobalNetworkPolicy to allow all pod traffic
    log_info "Creating Calico GlobalNetworkPolicy for pod communication..."
    cat <<EOF | kubectl apply -f - 2>/dev/null || true
apiVersion: crd.projectcalico.org/v1
kind: GlobalNetworkPolicy
metadata:
  name: allow-all-pods
spec:
  order: 1
  selector: all()
  types:
    - Ingress
    - Egress
  ingress:
    - action: Allow
  egress:
    - action: Allow
EOF

    # Configure Felix for optimal connectivity
    log_info "Configuring Calico Felix for optimal performance..."
    cat <<EOF | kubectl apply -f - 2>/dev/null || true
apiVersion: crd.projectcalico.org/v1
kind: FelixConfiguration
metadata:
  name: default
spec:
  defaultEndpointToHostAction: Accept
  iptablesFilterAllowAction: Accept
  iptablesMangleAllowAction: Accept
  logSeverityScreen: Info
  reportingInterval: 0s
EOF

    log_info "Calico/Canal network configured for optimal connectivity"
}
