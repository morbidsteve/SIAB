#!/bin/bash
set -euo pipefail

# Simple PXE Server Setup for SIAB
# This provides a lightweight alternative to MAAS for smaller deployments

readonly PXE_ROOT="/var/lib/tftpboot"
readonly HTTP_ROOT="/var/www/html/siab-provision"
readonly ROCKY_VERSION="${ROCKY_VERSION:-9.3}"

# Colors
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root"
    exit 1
fi

detect_os() {
    if [ -f /etc/redhat-release ]; then
        OS="rhel"
    elif [ -f /etc/debian_version ]; then
        OS="debian"
    else
        log_error "Unsupported OS"
        exit 1
    fi
}

install_dependencies() {
    log_info "Installing dependencies..."

    if [[ "$OS" == "rhel" ]]; then
        dnf install -y \
            tftp-server \
            dhcp-server \
            httpd \
            syslinux \
            xinetd \
            wget \
            curl
    else
        apt-get update
        apt-get install -y \
            tftpd-hpa \
            isc-dhcp-server \
            apache2 \
            syslinux \
            pxelinux \
            wget \
            curl
    fi

    log_info "Dependencies installed"
}

setup_tftp() {
    log_info "Setting up TFTP server..."

    mkdir -p "${PXE_ROOT}/pxelinux.cfg"
    mkdir -p "${PXE_ROOT}/rocky${ROCKY_VERSION}"

    # Copy PXE boot files
    if [[ "$OS" == "rhel" ]]; then
        cp /usr/share/syslinux/pxelinux.0 "${PXE_ROOT}/"
        cp /usr/share/syslinux/menu.c32 "${PXE_ROOT}/"
        cp /usr/share/syslinux/memdisk "${PXE_ROOT}/"
        cp /usr/share/syslinux/mboot.c32 "${PXE_ROOT}/"
        cp /usr/share/syslinux/chain.c32 "${PXE_ROOT}/"
        cp /usr/share/syslinux/ldlinux.c32 "${PXE_ROOT}/"
        cp /usr/share/syslinux/libutil.c32 "${PXE_ROOT}/"
        cp /usr/share/syslinux/libcom32.c32 "${PXE_ROOT}/"
    else
        cp /usr/lib/PXELINUX/pxelinux.0 "${PXE_ROOT}/"
        cp /usr/lib/syslinux/modules/bios/menu.c32 "${PXE_ROOT}/"
        cp /usr/lib/syslinux/modules/bios/ldlinux.c32 "${PXE_ROOT}/"
        cp /usr/lib/syslinux/modules/bios/libutil.c32 "${PXE_ROOT}/"
        cp /usr/lib/syslinux/modules/bios/libcom32.c32 "${PXE_ROOT}/"
    fi

    # Configure TFTP
    if [[ "$OS" == "rhel" ]]; then
        cat > /etc/xinetd.d/tftp <<EOF
service tftp
{
    socket_type = dgram
    protocol = udp
    wait = yes
    user = root
    server = /usr/sbin/in.tftpd
    server_args = -s ${PXE_ROOT}
    disable = no
    per_source = 11
    cps = 100 2
    flags = IPv4
}
EOF
        systemctl enable --now xinetd
    else
        cat > /etc/default/tftpd-hpa <<EOF
TFTP_USERNAME="tftp"
TFTP_DIRECTORY="${PXE_ROOT}"
TFTP_ADDRESS="0.0.0.0:69"
TFTP_OPTIONS="--secure"
EOF
        systemctl enable --now tftpd-hpa
    fi

    log_info "TFTP server configured"
}

download_rocky_images() {
    log_info "Downloading Rocky Linux ${ROCKY_VERSION} boot images..."

    mkdir -p "${HTTP_ROOT}/rocky${ROCKY_VERSION}"
    cd "${HTTP_ROOT}/rocky${ROCKY_VERSION}"

    # Download minimal ISO
    local iso_url="https://download.rockylinux.org/pub/rocky/${ROCKY_VERSION}/isos/x86_64/Rocky-${ROCKY_VERSION}-x86_64-minimal.iso"
    local iso_file="Rocky-${ROCKY_VERSION}-x86_64-minimal.iso"

    if [[ ! -f "${iso_file}" ]]; then
        log_info "Downloading Rocky Linux ISO (this may take a while)..."
        wget -c "${iso_url}" -O "${iso_file}"
    fi

    # Extract boot images
    log_info "Extracting boot images..."
    mkdir -p /tmp/rocky-mount
    mount -o loop "${iso_file}" /tmp/rocky-mount

    cp /tmp/rocky-mount/images/pxeboot/vmlinuz "${PXE_ROOT}/rocky${ROCKY_VERSION}/"
    cp /tmp/rocky-mount/images/pxeboot/initrd.img "${PXE_ROOT}/rocky${ROCKY_VERSION}/"

    # Copy entire ISO content for network install
    rsync -av /tmp/rocky-mount/ "${HTTP_ROOT}/rocky${ROCKY_VERSION}/"

    umount /tmp/rocky-mount
    rmdir /tmp/rocky-mount

    log_info "Rocky Linux images downloaded and extracted"
}

create_pxe_menu() {
    log_info "Creating PXE boot menu..."

    local server_ip
    server_ip=$(hostname -I | awk '{print $1}')

    cat > "${PXE_ROOT}/pxelinux.cfg/default" <<EOF
DEFAULT menu.c32
PROMPT 0
TIMEOUT 300
ONTIMEOUT rocky-siab

MENU TITLE SIAB PXE Boot Menu

LABEL rocky-siab
    MENU LABEL Install Rocky Linux ${ROCKY_VERSION} with SIAB
    KERNEL rocky${ROCKY_VERSION}/vmlinuz
    APPEND initrd=rocky${ROCKY_VERSION}/initrd.img inst.repo=http://${server_ip}/siab-provision/rocky${ROCKY_VERSION} inst.ks=http://${server_ip}/siab-provision/kickstart/siab-rocky9.ks ip=dhcp

LABEL rocky-manual
    MENU LABEL Install Rocky Linux ${ROCKY_VERSION} (Manual)
    KERNEL rocky${ROCKY_VERSION}/vmlinuz
    APPEND initrd=rocky${ROCKY_VERSION}/initrd.img inst.repo=http://${server_ip}/siab-provision/rocky${ROCKY_VERSION} ip=dhcp

LABEL local
    MENU LABEL Boot from local disk
    LOCALBOOT 0
EOF

    log_info "PXE boot menu created"
}

setup_http() {
    log_info "Setting up HTTP server..."

    mkdir -p "${HTTP_ROOT}/kickstart"

    # Copy kickstart file
    cp "$(dirname "$0")/../kickstart/siab-rocky9.ks" "${HTTP_ROOT}/kickstart/" || \
        log_warn "Kickstart file not found in expected location"

    # Configure web server
    if [[ "$OS" == "rhel" ]]; then
        # Apache on RHEL
        cat > /etc/httpd/conf.d/siab-provision.conf <<EOF
Alias /siab-provision ${HTTP_ROOT}
<Directory ${HTTP_ROOT}>
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>
EOF
        systemctl enable --now httpd

        # Configure firewall
        firewall-cmd --permanent --add-service=http
        firewall-cmd --reload
    else
        # Apache on Debian
        cat > /etc/apache2/sites-available/siab-provision.conf <<EOF
Alias /siab-provision ${HTTP_ROOT}
<Directory ${HTTP_ROOT}>
    Options Indexes FollowSymLinks
    AllowOverride None
    Require all granted
</Directory>
EOF
        a2ensite siab-provision
        systemctl enable --now apache2
    fi

    log_info "HTTP server configured"
}

setup_dhcp() {
    log_info "Setting up DHCP server..."

    local server_ip
    server_ip=$(hostname -I | awk '{print $1}')

    # Get network information from user
    read -p "Enter your subnet (e.g., 192.168.1.0): " subnet
    read -p "Enter your netmask (e.g., 255.255.255.0): " netmask
    read -p "Enter your gateway IP: " gateway
    read -p "Enter DHCP range start (e.g., 192.168.1.100): " dhcp_start
    read -p "Enter DHCP range end (e.g., 192.168.1.200): " dhcp_end
    read -p "Enter DNS server (press enter for 8.8.8.8): " dns_server
    dns_server=${dns_server:-8.8.8.8}

    if [[ "$OS" == "rhel" ]]; then
        cat > /etc/dhcp/dhcpd.conf <<EOF
option space pxelinux;
option pxelinux.magic code 208 = string;
option pxelinux.configfile code 209 = text;
option pxelinux.pathprefix code 210 = text;
option pxelinux.reboottime code 211 = unsigned integer 32;
option architecture-type code 93 = unsigned integer 16;

subnet ${subnet} netmask ${netmask} {
    range ${dhcp_start} ${dhcp_end};
    option routers ${gateway};
    option domain-name-servers ${dns_server};
    option broadcast-address $(echo ${subnet} | awk -F. '{print $1"."$2"."$3".255"}');
    default-lease-time 600;
    max-lease-time 7200;

    next-server ${server_ip};

    if exists user-class and option user-class = "iPXE" {
        filename "http://${server_ip}/siab-provision/boot.ipxe";
    } elsif option architecture-type = 00:07 {
        filename "uefi/shim.efi";
    } else {
        filename "pxelinux.0";
    }
}
EOF
        systemctl enable --now dhcpd

        # Configure firewall
        firewall-cmd --permanent --add-service=dhcp
        firewall-cmd --permanent --add-service=tftp
        firewall-cmd --reload
    else
        cat > /etc/dhcp/dhcpd.conf <<EOF
option space pxelinux;
option pxelinux.magic code 208 = string;
option pxelinux.configfile code 209 = text;
option pxelinux.pathprefix code 210 = text;
option pxelinux.reboottime code 211 = unsigned integer 32;
option architecture-type code 93 = unsigned integer 16;

subnet ${subnet} netmask ${netmask} {
    range ${dhcp_start} ${dhcp_end};
    option routers ${gateway};
    option domain-name-servers ${dns_server};
    option broadcast-address $(echo ${subnet} | awk -F. '{print $1"."$2"."$3".255"}');
    default-lease-time 600;
    max-lease-time 7200;

    next-server ${server_ip};
    filename "pxelinux.0";
}
EOF
        systemctl enable --now isc-dhcp-server
    fi

    log_info "DHCP server configured"
}

create_inventory_script() {
    log_info "Creating hardware inventory script..."

    mkdir -p "$(dirname "$0")/../scripts"

    cat > "$(dirname "$0")/../scripts/inventory-hardware.sh" <<'EOF'
#!/bin/bash
# Hardware inventory script for SIAB provisioning

echo "Scanning for PXE-booted systems..."

# Check DHCP leases
echo "=== DHCP Leases ==="
if [ -f /var/lib/dhcp/dhcpd.leases ]; then
    grep -E "lease|hardware ethernet|hostname" /var/lib/dhcp/dhcpd.leases | \
    awk '/lease/ {ip=$2} /hardware ethernet/ {mac=$3} /hostname/ {host=$2; print ip, mac, host}'
fi

echo ""
echo "=== Recent TFTP Requests ==="
journalctl -u tftpd-hpa -u xinetd --since "1 hour ago" | grep -i "request" | tail -20

echo ""
echo "To deploy SIAB to a specific machine:"
echo "  1. Note the MAC address from above"
echo "  2. Create a specific PXE config: ${PXE_ROOT}/pxelinux.cfg/01-<mac-with-dashes>"
echo "  3. Reboot the machine"
EOF

    chmod +x "$(dirname "$0")/../scripts/inventory-hardware.sh"

    log_info "Inventory script created"
}

display_summary() {
    local server_ip
    server_ip=$(hostname -I | awk '{print $1}')

    cat <<EOF

====================================================================
PXE Server Setup Complete!
====================================================================

Server IP: ${server_ip}

Services:
  - TFTP: Running on port 69
  - DHCP: Running on port 67
  - HTTP: Running on port 80

Boot Images:
  - Rocky Linux ${ROCKY_VERSION}: ${PXE_ROOT}/rocky${ROCKY_VERSION}/

Kickstart Configuration:
  - http://${server_ip}/siab-provision/kickstart/siab-rocky9.ks

Next Steps:
  1. Configure target machines to PXE boot
  2. Connect them to the same network as this server
  3. Power on the machines
  4. They will automatically:
     - PXE boot from this server
     - Install Rocky Linux ${ROCKY_VERSION}
     - Run SIAB installer after first boot

To monitor deployments:
  - DHCP leases: /var/lib/dhcp/dhcpd.leases
  - TFTP requests: journalctl -u tftpd-hpa -f
  - HTTP access: tail -f /var/log/httpd/access_log (or /var/log/apache2/access.log)

For hardware inventory:
  ./provisioning/scripts/inventory-hardware.sh

Documentation:
  See docs/bare-metal-provisioning.md for advanced configurations

====================================================================
EOF
}

main() {
    log_info "Starting PXE server setup for SIAB..."

    detect_os
    install_dependencies
    setup_tftp
    download_rocky_images
    create_pxe_menu
    setup_http
    setup_dhcp
    create_inventory_script

    display_summary
}

main "$@"
