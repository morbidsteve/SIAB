#!/bin/bash
set -euo pipefail

# SIAB MAAS Integration Setup
# This script configures MAAS to provision Linux distributions with SIAB

readonly MAAS_VERSION="${MAAS_VERSION:-3.4}"
readonly ROCKY_VERSION="${ROCKY_VERSION:-9.3}"
readonly UBUNTU_VERSION="${UBUNTU_VERSION:-22.04}"
readonly ORACLE_VERSION="${ORACLE_VERSION:-9}"
readonly ALMA_VERSION="${ALMA_VERSION:-9}"
readonly SIAB_PROVISION_DIR="/var/www/siab-provision"

# Which OS images to import (comma-separated): rocky,ubuntu,oracle,alma
readonly IMPORT_OSES="${IMPORT_OSES:-rocky,ubuntu}"

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Check root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

install_maas() {
    log_info "Installing MAAS ${MAAS_VERSION}..."

    # Add MAAS PPA
    add-apt-repository -y ppa:maas/${MAAS_VERSION}
    apt update

    # Install MAAS
    apt install -y maas maas-region-api maas-rack-controller postgresql

    log_info "MAAS installed"
}

configure_maas() {
    log_info "Configuring MAAS..."

    # Initialize MAAS
    maas init region+rack --database-uri "postgres://maas:maas@localhost/maas"

    # Create admin user
    maas createadmin --username admin --password admin --email admin@siab.local

    # Get API key
    local api_key
    api_key=$(maas apikey --username admin)

    # Login to MAAS
    maas login admin http://localhost:5240/MAAS/api/2.0/ "${api_key}"

    log_info "MAAS configured. Admin credentials:"
    log_info "  URL: http://$(hostname -I | awk '{print $1}'):5240/MAAS"
    log_info "  Username: admin"
    log_info "  Password: admin"
    log_info "  API Key: ${api_key}"

    # Save API key
    echo "MAAS_API_KEY=${api_key}" > /etc/siab/maas.env
    chmod 600 /etc/siab/maas.env
}

import_ubuntu_images() {
    log_info "Importing Ubuntu ${UBUNTU_VERSION} images..."

    # Ubuntu is natively supported by MAAS
    maas admin boot-resources import os=ubuntu series=${UBUNTU_VERSION/./}

    log_info "Ubuntu ${UBUNTU_VERSION} images imported"
}

import_rocky_images() {
    log_info "Importing Rocky Linux ${ROCKY_VERSION} images..."

    # Rocky Linux is not in default MAAS images, so we need to import custom image
    # First, create the image directory
    mkdir -p "${SIAB_PROVISION_DIR}/images"

    # Download Rocky Linux boot images
    cd "${SIAB_PROVISION_DIR}/images"

    local rocky_iso="Rocky-${ROCKY_VERSION}-x86_64-minimal.iso"
    local rocky_url="https://download.rockylinux.org/pub/rocky/${ROCKY_VERSION}/isos/x86_64/${rocky_iso}"

    log_info "Downloading Rocky Linux ${ROCKY_VERSION}..."
    wget -c "${rocky_url}" -O "${rocky_iso}"

    # Extract kernel and initrd from ISO
    mkdir -p /tmp/rocky-mount
    mount -o loop "${rocky_iso}" /tmp/rocky-mount

    mkdir -p "${SIAB_PROVISION_DIR}/boot/rocky-${ROCKY_VERSION}"
    cp /tmp/rocky-mount/images/pxeboot/vmlinuz "${SIAB_PROVISION_DIR}/boot/rocky-${ROCKY_VERSION}/"
    cp /tmp/rocky-mount/images/pxeboot/initrd.img "${SIAB_PROVISION_DIR}/boot/rocky-${ROCKY_VERSION}/"

    umount /tmp/rocky-mount
    rmdir /tmp/rocky-mount

    log_info "Rocky Linux boot images extracted"
}

import_oracle_images() {
    log_info "Importing Oracle Linux ${ORACLE_VERSION} images..."

    mkdir -p "${SIAB_PROVISION_DIR}/images"
    cd "${SIAB_PROVISION_DIR}/images"

    local oracle_iso="OracleLinux-R${ORACLE_VERSION}-U0-x86_64-dvd.iso"
    local oracle_url="https://yum.oracle.com/ISOS/OracleLinux/OL${ORACLE_VERSION}/u0/x86_64/${oracle_iso}"

    log_info "Downloading Oracle Linux ${ORACLE_VERSION}..."
    wget -c "${oracle_url}" -O "${oracle_iso}"

    # Extract kernel and initrd from ISO
    mkdir -p /tmp/oracle-mount
    mount -o loop "${oracle_iso}" /tmp/oracle-mount

    mkdir -p "${SIAB_PROVISION_DIR}/boot/oracle-${ORACLE_VERSION}"
    cp /tmp/oracle-mount/images/pxeboot/vmlinuz "${SIAB_PROVISION_DIR}/boot/oracle-${ORACLE_VERSION}/"
    cp /tmp/oracle-mount/images/pxeboot/initrd.img "${SIAB_PROVISION_DIR}/boot/oracle-${ORACLE_VERSION}/"

    umount /tmp/oracle-mount
    rmdir /tmp/oracle-mount

    log_info "Oracle Linux boot images extracted"
}

import_alma_images() {
    log_info "Importing AlmaLinux ${ALMA_VERSION} images..."

    mkdir -p "${SIAB_PROVISION_DIR}/images"
    cd "${SIAB_PROVISION_DIR}/images"

    local alma_iso="AlmaLinux-${ALMA_VERSION}-x86_64-minimal.iso"
    local alma_url="https://repo.almalinux.org/almalinux/${ALMA_VERSION}/isos/x86_64/${alma_iso}"

    log_info "Downloading AlmaLinux ${ALMA_VERSION}..."
    wget -c "${alma_url}" -O "${alma_iso}"

    # Extract kernel and initrd from ISO
    mkdir -p /tmp/alma-mount
    mount -o loop "${alma_iso}" /tmp/alma-mount

    mkdir -p "${SIAB_PROVISION_DIR}/boot/alma-${ALMA_VERSION}"
    cp /tmp/alma-mount/images/pxeboot/vmlinuz "${SIAB_PROVISION_DIR}/boot/alma-${ALMA_VERSION}/"
    cp /tmp/alma-mount/images/pxeboot/initrd.img "${SIAB_PROVISION_DIR}/boot/alma-${ALMA_VERSION}/"

    umount /tmp/alma-mount
    rmdir /tmp/alma-mount

    log_info "AlmaLinux boot images extracted"
}

import_os_images() {
    log_info "Importing OS images: ${IMPORT_OSES}"

    IFS=',' read -ra OSES <<< "$IMPORT_OSES"
    for os in "${OSES[@]}"; do
        case "$os" in
            ubuntu)
                import_ubuntu_images
                ;;
            rocky)
                import_rocky_images
                ;;
            oracle)
                import_oracle_images
                ;;
            alma)
                import_alma_images
                ;;
            *)
                log_warn "Unknown OS: $os, skipping..."
                ;;
        esac
    done
}

create_siab_curtin_config() {
    log_info "Creating SIAB Curtin configuration for MAAS..."

    # Curtin is MAAS's installation tool
    cat > /etc/maas/preseeds/curtin_userdata_siab <<'EOF'
#cloud-config
debconf_selections:
  maas: |
    cloud-init cloud-init/datasources multiselect MAAS

late_commands:
  # Install SIAB after OS installation
  siab_install: ["curtin", "in-target", "--", "sh", "-c", "curl -sfL https://raw.githubusercontent.com/morbidsteve/SIAB/main/install.sh | bash"]

power_state:
  mode: reboot
  timeout: 1800
  condition: True
EOF

    log_info "SIAB Curtin config created"
}

create_rocky_preseed() {
    log_info "Creating Rocky Linux preseed configuration..."

    mkdir -p /var/lib/maas/preseeds

    cat > /var/lib/maas/preseeds/rocky_siab.preseed <<'EOF'
# Rocky Linux Preseed for SIAB
# This runs after installation

# Set timezone
d-i time/zone string UTC
d-i clock-setup/utc boolean true

# Partitioning
d-i partman-auto/method string lvm
d-i partman-auto-lvm/guided_size string max
d-i partman-lvm/device_remove_lvm boolean true
d-i partman-lvm/confirm boolean true
d-i partman-lvm/confirm_nooverwrite boolean true
d-i partman-auto/choose_recipe select atomic

# Network configuration
d-i netcfg/choose_interface select auto
d-i netcfg/get_hostname string siab-node
d-i netcfg/get_domain string siab.local

# Package selection
d-i pkgsel/include string openssh-server curl wget
d-i pkgsel/upgrade select full-upgrade

# Post-install script
d-i preseed/late_command string \
    in-target sh -c 'curl -sfL https://raw.githubusercontent.com/morbidsteve/SIAB/main/provisioning/scripts/post-install.sh | bash'
EOF

    log_info "Rocky preseed created"
}

configure_dhcp() {
    log_info "Configuring DHCP for MAAS..."

    # Configure MAAS DHCP
    # You need to specify your network details
    read -p "Enter your subnet (e.g., 192.168.1.0/24): " subnet
    read -p "Enter your gateway IP: " gateway
    read -p "Enter DNS server (or press enter for 8.8.8.8): " dns_server
    dns_server=${dns_server:-8.8.8.8}

    # Create MAAS fabric and VLAN
    maas admin subnets create cidr="${subnet}"

    # Enable DHCP
    local fabric_id
    fabric_id=$(maas admin fabrics read | jq -r '.[0].id')
    local vlan_id
    vlan_id=$(maas admin fabrics read | jq -r '.[0].vlans[0].id')

    maas admin ipranges create type=dynamic \
        start_ip="$(echo ${subnet} | cut -d/ -f1 | awk -F. '{print $1"."$2"."$3".100"}')" \
        end_ip="$(echo ${subnet} | cut -d/ -f1 | awk -F. '{print $1"."$2"."$3".200"}')"

    maas admin vlan update "${fabric_id}" "${vlan_id}" dhcp_on=True \
        primary_rack="$(hostname)"

    log_info "DHCP configured"
}

create_siab_deploy_script() {
    log_info "Creating SIAB deployment script for MAAS..."

    mkdir -p /var/lib/maas/scripts

    cat > /var/lib/maas/scripts/deploy-siab.sh <<'EOF'
#!/bin/bash
# MAAS deployment script for SIAB
# This script runs on the deployed machine

set -euo pipefail

# Wait for network to be ready
sleep 10

# Update system
dnf update -y

# Install dependencies
dnf install -y curl wget git

# Download and run SIAB installer
curl -sfL https://raw.githubusercontent.com/morbidsteve/SIAB/main/install.sh -o /tmp/siab-install.sh
chmod +x /tmp/siab-install.sh

# Run installer
bash /tmp/siab-install.sh

# Save installation info
echo "SIAB installed via MAAS on $(date)" > /etc/siab/maas-deployed
EOF

    chmod +x /var/lib/maas/scripts/deploy-siab.sh

    # Register the script with MAAS
    maas admin node-scripts create \
        name=deploy-siab \
        script@=/var/lib/maas/scripts/deploy-siab.sh \
        type=commissioning

    log_info "SIAB deployment script registered with MAAS"
}

setup_pxe_boot() {
    log_info "Setting up PXE boot configuration..."

    # Configure MAAS to use Rocky Linux for PXE boot
    mkdir -p /var/lib/maas/boot-resources

    # Create custom boot configuration
    cat > /etc/maas/templates/pxe/config.rocky.template <<EOF
DEFAULT linux
LABEL linux
    KERNEL ${SIAB_PROVISION_DIR}/boot/rocky-${ROCKY_VERSION}/vmlinuz
    APPEND initrd=${SIAB_PROVISION_DIR}/boot/rocky-${ROCKY_VERSION}/initrd.img inst.ks=http://{{server_host}}:5240/MAAS/kickstart/siab.ks ip=dhcp
EOF

    log_info "PXE boot configured"
}

display_usage() {
    cat <<EOF

====================================================================
MAAS Setup Complete!
====================================================================

Access MAAS UI:
  URL: http://$(hostname -I | awk '{print $1}'):5240/MAAS
  Username: admin
  Password: admin

Next Steps:
  1. Add hardware to MAAS:
     - Power on machines with PXE boot enabled
     - MAAS will discover them automatically

  2. Commission hardware:
     maas admin machines commission <system-id>

  3. Deploy SIAB:
     maas admin machine deploy <system-id> osystem=rocky distro_series=${ROCKY_VERSION}

  4. Monitor deployment:
     maas admin events query level=INFO

For bulk deployment, use:
  ./provision-cluster.sh

Documentation:
  /home/user/SIAB/docs/bare-metal-provisioning.md

====================================================================
EOF
}

main() {
    log_info "Starting MAAS setup for SIAB..."

    # Check if Ubuntu (MAAS only officially supports Ubuntu)
    if ! grep -q "Ubuntu" /etc/os-release 2>/dev/null; then
        log_warn "MAAS is designed for Ubuntu. Consider running this on Ubuntu 22.04 LTS"
        read -p "Continue anyway? (yes/no): " continue
        [[ "$continue" != "yes" ]] && exit 1
    fi

    install_maas
    configure_maas
    import_os_images
    create_siab_curtin_config
    configure_dhcp
    create_siab_deploy_script
    setup_pxe_boot

    display_usage
}

main "$@"
EOF
chmod +x /home/user/SIAB/provisioning/maas/setup-maas.sh
