#!/bin/bash
# SIAB - OS Detection Library
# Operating system detection and package manager selection

# Requires: logging.sh to be sourced first

# OS information variables (set by detect_os)
OS_ID=""
OS_VERSION_ID=""
OS_NAME=""
OS_FAMILY=""
PKG_MANAGER=""
FIREWALL_CMD=""
SECURITY_MODULE=""

# Detect operating system
detect_os() {
    if [ -f /etc/os-release ]; then
        # shellcheck source=/dev/null
        . /etc/os-release
        OS_ID="${ID}"
        OS_VERSION_ID="${VERSION_ID}"
        OS_NAME="${NAME}"
    else
        log_error "Cannot detect operating system"
        exit 1
    fi

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
            # Set non-interactive mode for Debian/Ubuntu systems
            export DEBIAN_FRONTEND=noninteractive
            ;;
        *)
            log_error "Unsupported operating system: ${OS_ID}"
            log_error "Supported: Rocky Linux, RHEL, CentOS, Oracle Linux, AlmaLinux, Ubuntu, Xubuntu, Debian"
            exit 1
            ;;
    esac

    export OS_ID OS_VERSION_ID OS_NAME OS_FAMILY PKG_MANAGER FIREWALL_CMD SECURITY_MODULE
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root"
        echo "Please run: sudo $0"
        exit 1
    fi
}
