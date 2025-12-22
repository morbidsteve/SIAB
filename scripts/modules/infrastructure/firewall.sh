#!/bin/bash
# SIAB - Firewall Module
# Firewall configuration for RKE2, Canal, and Istio

# Requires: logging.sh, os.sh

# Configure firewall rules for SIAB
configure_firewall() {
    log_info "Configuring firewall for RKE2, Canal, and Istio..."

    if [[ "${FIREWALL_CMD}" == "firewalld" ]]; then
        configure_firewalld
    elif [[ "${FIREWALL_CMD}" == "ufw" ]]; then
        configure_ufw
    fi

    log_info "Firewall configured successfully"
    log_info "Note: CNI interfaces will be added to trusted zone when they are created"
}

# Configure firewalld (RHEL-based systems)
configure_firewalld() {
    # Use comprehensive firewalld configuration script if available
    if [[ -f "${SIAB_REPO_DIR}/scripts/configure-firewalld.sh" ]]; then
        log_info "Running comprehensive firewalld configuration..."
        bash "${SIAB_REPO_DIR}/scripts/configure-firewalld.sh"
    else
        # Fallback to basic configuration if script not found
        log_warn "Firewalld script not found, using basic configuration..."

        # Install firewalld if not present
        dnf install -y firewalld
        systemctl enable --now firewalld

        # Add CNI interfaces to trusted zone
        firewall-cmd --permanent --zone=trusted --add-interface=cni0 2>/dev/null || true
        firewall-cmd --permanent --zone=trusted --add-interface=flannel.1 2>/dev/null || true
        firewall-cmd --permanent --zone=trusted --add-interface=tunl0 2>/dev/null || true

        # Add pod and service CIDRs to trusted zone
        firewall-cmd --permanent --zone=trusted --add-source=10.42.0.0/16  # Pod CIDR
        firewall-cmd --permanent --zone=trusted --add-source=10.43.0.0/16  # Service CIDR

        # RKE2 ports
        firewall-cmd --permanent --add-port=6443/tcp   # Kubernetes API
        firewall-cmd --permanent --add-port=9345/tcp   # RKE2 supervisor API
        firewall-cmd --permanent --add-port=10250/tcp  # Kubelet metrics
        firewall-cmd --permanent --add-port=2379-2380/tcp   # etcd
        firewall-cmd --permanent --add-port=30000-32767/tcp  # NodePort Services (TCP)
        firewall-cmd --permanent --add-port=30000-32767/udp  # NodePort Services (UDP)
        firewall-cmd --permanent --add-port=53/tcp     # DNS (CoreDNS)
        firewall-cmd --permanent --add-port=53/udp     # DNS (CoreDNS)

        # Canal (Calico + Flannel) ports
        firewall-cmd --permanent --add-port=8472/udp   # Flannel VXLAN
        firewall-cmd --permanent --add-port=4789/udp   # Flannel VXLAN (alt)
        firewall-cmd --permanent --add-port=51820-51821/udp  # Flannel Wireguard
        firewall-cmd --permanent --add-port=179/tcp    # Calico BGP
        firewall-cmd --permanent --add-port=5473/tcp   # Calico Typha

        # Istio ports
        firewall-cmd --permanent --add-port=80/tcp     # HTTP ingress (redirects to HTTPS)
        firewall-cmd --permanent --add-port=443/tcp    # HTTPS ingress
        firewall-cmd --permanent --add-port=15010-15017/tcp  # Istio control plane
        firewall-cmd --permanent --add-port=15021/tcp  # Istio health checks
        firewall-cmd --permanent --add-port=15090/tcp  # Istio metrics

        # Enable masquerading
        firewall-cmd --permanent --zone=public --add-masquerade
        firewall-cmd --permanent --zone=trusted --add-masquerade

        firewall-cmd --reload
    fi
}

# Configure UFW (Debian-based systems)
configure_ufw() {
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
    ufw allow 30000:32767/tcp  # NodePort Services (TCP)
    ufw allow 30000:32767/udp  # NodePort Services (UDP)
    ufw allow 53/tcp      # DNS (CoreDNS)
    ufw allow 53/udp      # DNS (CoreDNS)

    # Canal (Calico + Flannel) ports
    ufw allow 8472/udp    # Flannel VXLAN
    ufw allow 4789/udp    # Flannel VXLAN (alt)
    ufw allow 51820:51821/udp  # Flannel Wireguard
    ufw allow 179/tcp     # Calico BGP
    ufw allow 5473/tcp    # Calico Typha

    # Istio ports
    ufw allow 80/tcp      # HTTP ingress (redirects to HTTPS)
    ufw allow 443/tcp     # HTTPS ingress
    ufw allow 15010:15017/tcp  # Istio control plane
    ufw allow 15021/tcp   # Istio health checks
    ufw allow 15090/tcp   # Istio metrics

    # Reload ufw
    ufw reload
}

# Restore firewall to default state
restore_firewall() {
    log_info "Restoring firewall to default state..."

    if [[ "${FIREWALL_CMD}" == "firewalld" ]]; then
        # Remove SIAB-specific rules (but keep SSH!)
        firewall-cmd --permanent --zone=trusted --remove-source=10.42.0.0/16 2>/dev/null || true
        firewall-cmd --permanent --zone=trusted --remove-source=10.43.0.0/16 2>/dev/null || true
        firewall-cmd --permanent --zone=trusted --remove-interface=cni0 2>/dev/null || true
        firewall-cmd --permanent --zone=trusted --remove-interface=flannel.1 2>/dev/null || true
        firewall-cmd --permanent --zone=trusted --remove-interface=tunl0 2>/dev/null || true

        # Remove SIAB-specific ports (NOT SSH ports 22, 80, 443)
        for port in 6443/tcp 9345/tcp 10250/tcp 2379-2380/tcp 30000-32767/tcp 30000-32767/udp \
                    8472/udp 4789/udp 51820-51821/udp 179/tcp 5473/tcp \
                    15010-15017/tcp 15021/tcp 15090/tcp 53/tcp 53/udp; do
            firewall-cmd --permanent --remove-port=$port 2>/dev/null || true
        done

        firewall-cmd --reload

    elif [[ "${FIREWALL_CMD}" == "ufw" ]]; then
        # IMPORTANT: Do NOT use 'ufw reset' as it kills SSH connections!
        # Instead, selectively remove only SIAB-added rules while preserving SSH
        log_info "Removing SIAB-specific UFW rules (preserving SSH)..."

        # Remove SIAB-specific ports (leave SSH port 22 intact)
        ufw delete allow 6443/tcp 2>/dev/null || true
        ufw delete allow 9345/tcp 2>/dev/null || true
        ufw delete allow 10250/tcp 2>/dev/null || true
        ufw delete allow 2379/tcp 2>/dev/null || true
        ufw delete allow 2380/tcp 2>/dev/null || true
        ufw delete allow 30000:32767/tcp 2>/dev/null || true
        ufw delete allow 30000:32767/udp 2>/dev/null || true
        ufw delete allow 53/tcp 2>/dev/null || true
        ufw delete allow 53/udp 2>/dev/null || true
        ufw delete allow 8472/udp 2>/dev/null || true
        ufw delete allow 4789/udp 2>/dev/null || true
        ufw delete allow 51820:51821/udp 2>/dev/null || true
        ufw delete allow 179/tcp 2>/dev/null || true
        ufw delete allow 5473/tcp 2>/dev/null || true
        ufw delete allow 80/tcp 2>/dev/null || true
        ufw delete allow 443/tcp 2>/dev/null || true
        ufw delete allow 15010:15017/tcp 2>/dev/null || true
        ufw delete allow 15021/tcp 2>/dev/null || true
        ufw delete allow 15090/tcp 2>/dev/null || true

        # Reload UFW without resetting (keeps SSH intact)
        ufw reload 2>/dev/null || true
    fi

    log_info "Firewall restored (SSH preserved)"
}

# Configure security module (SELinux or AppArmor)
configure_security() {
    if [[ "${SECURITY_MODULE}" == "selinux" ]]; then
        configure_selinux
    elif [[ "${SECURITY_MODULE}" == "apparmor" ]]; then
        configure_apparmor
    fi
}

# Configure SELinux
configure_selinux() {
    log_info "Configuring SELinux..."

    # Ensure SELinux is enforcing
    if [[ $(getenforce) != "Enforcing" ]]; then
        setenforce 1
        sed -i 's/^SELINUX=.*/SELINUX=enforcing/' /etc/selinux/config
    fi

    # Set SELinux booleans for containers
    setsebool -P container_manage_cgroup on

    log_info "SELinux configured in enforcing mode"
}

# Configure AppArmor
configure_apparmor() {
    log_info "Configuring AppArmor..."

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
}
