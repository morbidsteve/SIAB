#!/bin/bash
# SIAB - Credentials Module
# Credential generation and management

# Requires: logging.sh, config.sh, utils.sh, progress/status.sh

# Generate secure credentials
generate_credentials() {
    start_step "Credentials Generation"

    # Check if credentials already exist
    if [[ -f "${SIAB_CONFIG_DIR}/credentials.env" ]]; then
        log_info "Credentials file already exists, preserving existing credentials"
        # Source existing credentials so they're available for other steps
        source "${SIAB_CONFIG_DIR}/credentials.env"
        skip_step "Credentials Generation" "Already exists"
        return 0
    fi

    log_info "Generating secure credentials..."

    # Ensure config directory exists
    mkdir -p "${SIAB_CONFIG_DIR}"
    chmod 700 "${SIAB_CONFIG_DIR}"

    # Generate passwords
    local keycloak_admin_password
    local minio_root_password
    local grafana_admin_password

    keycloak_admin_password=$(openssl rand -base64 24 | tr -d '=+/' | head -c 24)
    minio_root_password=$(openssl rand -base64 24 | tr -d '=+/' | head -c 24)
    grafana_admin_password=$(openssl rand -base64 24 | tr -d '=+/' | head -c 24)

    # Write credentials file
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

    # Export credentials for use in current session
    export KEYCLOAK_ADMIN_USER=admin
    export KEYCLOAK_ADMIN_PASSWORD="${keycloak_admin_password}"
    export MINIO_ROOT_USER=admin
    export MINIO_ROOT_PASSWORD="${minio_root_password}"
    export GRAFANA_ADMIN_USER=admin
    export GRAFANA_ADMIN_PASSWORD="${grafana_admin_password}"

    complete_step "Credentials Generation"
    log_info "Credentials generated and saved to ${SIAB_CONFIG_DIR}/credentials.env"
}

# Setup directories
setup_directories() {
    log_info "Setting up directories..."
    mkdir -p "${SIAB_DIR}"
    mkdir -p "${SIAB_CONFIG_DIR}"
    mkdir -p "${SIAB_LOG_DIR}"
    mkdir -p "${SIAB_BIN_DIR}"
    chmod 700 "${SIAB_CONFIG_DIR}"
}

# Clone or update SIAB repository
clone_siab_repo() {
    start_step "Repository Clone"

    local siab_repo_url="https://github.com/morbidsteve/SIAB.git"

    # Check if we're already running from a cloned repo
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

    # Look for repo indicators in parent directories
    local check_dir="$script_dir"
    while [[ "$check_dir" != "/" ]]; do
        if [[ -f "${check_dir}/siab-status.sh" ]] && [[ -d "${check_dir}/crds" ]]; then
            log_info "Running from existing repo clone, using local files..."
            SIAB_REPO_DIR="${check_dir}"
            export SIAB_REPO_DIR
            skip_step "Repository Clone" "Using local repo"
            return 0
        fi
        check_dir=$(dirname "$check_dir")
    done

    # Need to clone the repo
    log_info "Cloning SIAB repository..."
    if [[ -d "${SIAB_REPO_DIR}/.git" ]]; then
        log_info "Updating existing SIAB repository..."
        cd "${SIAB_REPO_DIR}"
        git pull origin main 2>/dev/null || git pull 2>/dev/null || true
        cd - >/dev/null
    else
        rm -rf "${SIAB_REPO_DIR}"
        git clone --depth 1 "${siab_repo_url}" "${SIAB_REPO_DIR}"
    fi

    export SIAB_REPO_DIR
    complete_step "Repository Clone"
    log_info "SIAB repo available at: ${SIAB_REPO_DIR}"
}

# Install system dependencies
install_dependencies() {
    start_step "System Dependencies"

    log_info "Installing system dependencies..."

    if [[ "${OS_FAMILY}" == "rhel" ]]; then
        # Remove any leftover RKE2 repos from previous installs
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
            auditd \
            chrony \
            iptables

        # Enable time sync
        systemctl enable --now chrony || true

        # Enable audit logging
        systemctl enable --now auditd || true
    fi

    complete_step "System Dependencies"
    log_info "System dependencies installed"
}

# Setup non-root user access
setup_nonroot_access() {
    log_info "Setting up non-root access..."

    # Get non-root users to setup access for
    local users
    users=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1}')

    for user in $users; do
        local user_home
        user_home=$(getent passwd "$user" | cut -d: -f6)

        if [[ -d "$user_home" ]]; then
            # Setup kubeconfig
            mkdir -p "${user_home}/.kube"
            cp /etc/rancher/rke2/rke2.yaml "${user_home}/.kube/config"
            chown -R "$user:$user" "${user_home}/.kube"
            chmod 600 "${user_home}/.kube/config"

            # Copy credentials
            if [[ -f "${SIAB_CONFIG_DIR}/credentials.env" ]]; then
                cp "${SIAB_CONFIG_DIR}/credentials.env" "${user_home}/.siab-credentials.env"
                chown "$user:$user" "${user_home}/.siab-credentials.env"
                chmod 600 "${user_home}/.siab-credentials.env"
            fi

            log_info "Setup access for user: $user"
        fi
    done
}

# Remove SIAB files
remove_siab_files() {
    log_info "Removing SIAB files..."

    rm -rf "${SIAB_DIR}"
    rm -rf "${SIAB_CONFIG_DIR}"
    rm -rf "${SIAB_LOG_DIR}"
    rm -f "${SIAB_BIN_DIR}/siab-*"
    rm -f /etc/profile.d/siab.sh
    rm -f /etc/profile.d/rke2.sh

    # Remove user credentials
    for user_home in /home/*; do
        rm -f "${user_home}/.siab-credentials.env"
    done

    log_info "SIAB files removed"
}
