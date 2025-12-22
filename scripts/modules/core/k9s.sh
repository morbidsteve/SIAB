#!/bin/bash
# SIAB - K9s Module
# K9s cluster UI installation

# Requires: logging.sh, config.sh, progress/status.sh, checks/preflight.sh

# K9s version
readonly K9S_VERSION="${K9S_VERSION:-v0.32.5}"

# Install k9s cluster UI
install_k9s() {
    start_step "k9s Cluster UI"

    # Check if k9s is already properly installed
    if check_k9s_installed; then
        skip_step "k9s Cluster UI" "Already installed and working"
        return 0
    fi

    log_info "Installing k9s ${K9S_VERSION}..."

    local k9s_url="https://github.com/derailed/k9s/releases/download/${K9S_VERSION}/k9s_Linux_amd64.tar.gz"

    if ! curl -fsSL "${k9s_url}" -o /tmp/k9s.tar.gz; then
        log_error "Failed to download k9s"
        fail_step "k9s Cluster UI" "Download failed"
        return 1
    fi

    cd /tmp
    tar xzf k9s.tar.gz k9s
    mv k9s "${SIAB_BIN_DIR}/k9s"
    rm -f k9s.tar.gz
    chmod +x "${SIAB_BIN_DIR}/k9s"
    cd - >/dev/null

    # Ensure SIAB bin directory is in PATH for all users
    cat > /etc/profile.d/siab.sh <<'EOF'
# SIAB - Secure Infrastructure as a Box
# Add SIAB and Kubernetes tools to PATH
export PATH="${PATH}:/usr/local/bin:/var/lib/rancher/rke2/bin"
export KUBECONFIG="${KUBECONFIG:-$HOME/.kube/config}"
EOF
    chmod +x /etc/profile.d/siab.sh

    # Also add to /etc/environment for non-login shells
    if ! grep -q "/usr/local/bin" /etc/environment 2>/dev/null; then
        if [[ -f /etc/environment ]]; then
            # Update existing PATH in /etc/environment
            if grep -q "^PATH=" /etc/environment; then
                sed -i 's|^PATH="\(.*\)"|PATH="\1:/usr/local/bin:/var/lib/rancher/rke2/bin"|' /etc/environment
            else
                echo 'PATH="/usr/local/bin:/var/lib/rancher/rke2/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin"' >> /etc/environment
            fi
        else
            echo 'PATH="/usr/local/bin:/var/lib/rancher/rke2/bin:/usr/local/sbin:/usr/sbin:/usr/bin:/sbin:/bin"' > /etc/environment
        fi
    fi

    complete_step "k9s Cluster UI"
    log_info "k9s installed at ${SIAB_BIN_DIR}/k9s"
    log_info "PATH configured in /etc/profile.d/siab.sh"
}

# Uninstall k9s
uninstall_k9s() {
    log_info "Removing k9s..."
    rm -f "${SIAB_BIN_DIR}/k9s"
    log_info "k9s removed"
}
