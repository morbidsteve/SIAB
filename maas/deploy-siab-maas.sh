#!/bin/bash
#
# SIAB MAAS Automated Deployment Script
# Automates the complete deployment of SIAB via MAAS on Proxmox
#

set -euo pipefail

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly BOLD='\033[1m'
readonly NC='\033[0m'

# Configuration
MAAS_URL="${MAAS_URL:-http://localhost:5240/MAAS}"
MAAS_API_KEY="${MAAS_API_KEY:-}"
PROXMOX_HOST="${PROXMOX_HOST:-}"
PROXMOX_USER="${PROXMOX_USER:-root}"
PROXMOX_PASS="${PROXMOX_PASS:-}"

VM_NAME="${VM_NAME:-siab-01}"
VM_CORES="${VM_CORES:-8}"
VM_MEMORY="${VM_MEMORY:-32768}"  # MB
VM_STORAGE="${VM_STORAGE:-100G}"
CLOUD_INIT_FILE="${CLOUD_INIT_FILE:-cloud-init-rocky-siab.yaml}"

# Logging
log_info() {
    echo -e "${BLUE}[INFO]${NC} $*"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

log_step() {
    echo ""
    echo -e "${CYAN}${BOLD}==>${NC} ${BOLD}$*${NC}"
}

# Usage
usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Automated SIAB deployment via MAAS and Proxmox

OPTIONS:
    -m, --maas-url URL          MAAS API URL (default: http://localhost:5240/MAAS)
    -k, --maas-key KEY          MAAS API key (required)
    -p, --proxmox-host HOST     Proxmox hostname/IP (required)
    -u, --proxmox-user USER     Proxmox username (default: root)
    -w, --proxmox-pass PASS     Proxmox password (required)
    -n, --vm-name NAME          VM name (default: siab-01)
    -c, --vm-cores NUM          CPU cores (default: 8)
    -r, --vm-memory MB          RAM in MB (default: 32768)
    -s, --vm-storage SIZE       Storage size (default: 100G)
    -f, --cloud-init FILE       Cloud-init config file (default: cloud-init-rocky-siab.yaml)
    -h, --help                  Show this help

EXAMPLES:
    # Interactive mode (prompts for required values)
    $0

    # Full automation
    $0 --maas-key "abc123..." \\
       --proxmox-host 192.168.1.100 \\
       --proxmox-pass "password"

ENVIRONMENT VARIABLES:
    MAAS_URL, MAAS_API_KEY, PROXMOX_HOST, PROXMOX_USER, PROXMOX_PASS

EOF
    exit 0
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -m|--maas-url) MAAS_URL="$2"; shift 2 ;;
            -k|--maas-key) MAAS_API_KEY="$2"; shift 2 ;;
            -p|--proxmox-host) PROXMOX_HOST="$2"; shift 2 ;;
            -u|--proxmox-user) PROXMOX_USER="$2"; shift 2 ;;
            -w|--proxmox-pass) PROXMOX_PASS="$2"; shift 2 ;;
            -n|--vm-name) VM_NAME="$2"; shift 2 ;;
            -c|--vm-cores) VM_CORES="$2"; shift 2 ;;
            -r|--vm-memory) VM_MEMORY="$2"; shift 2 ;;
            -s|--vm-storage) VM_STORAGE="$2"; shift 2 ;;
            -f|--cloud-init) CLOUD_INIT_FILE="$2"; shift 2 ;;
            -h|--help) usage ;;
            *) log_error "Unknown option: $1"; usage ;;
        esac
    done
}

# Interactive prompts for missing values
prompt_missing() {
    if [[ -z "$MAAS_API_KEY" ]]; then
        echo -n "Enter MAAS API key: "
        read -r MAAS_API_KEY
    fi

    if [[ -z "$PROXMOX_HOST" ]]; then
        echo -n "Enter Proxmox hostname/IP: "
        read -r PROXMOX_HOST
    fi

    if [[ -z "$PROXMOX_PASS" ]]; then
        echo -n "Enter Proxmox password: "
        read -rs PROXMOX_PASS
        echo ""
    fi
}

# Check prerequisites
check_prereqs() {
    log_step "Checking prerequisites..."

    # Check maas CLI
    if ! command -v maas &>/dev/null; then
        log_error "MAAS CLI not found. Install with: sudo snap install maas"
        exit 1
    fi

    # Check jq
    if ! command -v jq &>/dev/null; then
        log_error "jq not found. Install with: sudo apt install jq"
        exit 1
    fi

    # Check cloud-init file
    if [[ ! -f "$CLOUD_INIT_FILE" ]]; then
        log_error "Cloud-init file not found: $CLOUD_INIT_FILE"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Login to MAAS
maas_login() {
    log_step "Logging in to MAAS..."

    maas login admin "$MAAS_URL" "$MAAS_API_KEY" || {
        log_error "MAAS login failed"
        exit 1
    }

    log_success "MAAS login successful"
}

# Add Proxmox as VM host
add_proxmox_host() {
    log_step "Adding Proxmox as VM host..."

    # Check if already exists
    local existing
    existing=$(maas admin vm-hosts read | jq -r --arg host "$PROXMOX_HOST" '.[] | select(.power_parameters.power_address | contains($host)) | .id' || echo "")

    if [[ -n "$existing" ]]; then
        log_warn "Proxmox host already exists (ID: $existing)"
        echo "$existing"
        return
    fi

    # Add new VM host
    local power_address="qemu+ssh://${PROXMOX_USER}@${PROXMOX_HOST}/system"
    local vm_host_id
    vm_host_id=$(maas admin vm-hosts create \
        type=virsh \
        power_address="$power_address" \
        power_pass="$PROXMOX_PASS" | jq -r '.id')

    if [[ -z "$vm_host_id" ]]; then
        log_error "Failed to add Proxmox host"
        exit 1
    fi

    log_success "Proxmox host added (ID: $vm_host_id)"
    echo "$vm_host_id"
}

# Compose VM
compose_vm() {
    local vm_host_id="$1"

    log_step "Composing VM: $VM_NAME..."

    local system_id
    system_id=$(maas admin vm-host compose "$vm_host_id" \
        cores="$VM_CORES" \
        memory="$VM_MEMORY" \
        storage="$VM_STORAGE" \
        hostname="$VM_NAME" | jq -r '.system_id')

    if [[ -z "$system_id" ]]; then
        log_error "Failed to compose VM"
        exit 1
    fi

    log_success "VM composed (System ID: $system_id)"
    echo "$system_id"
}

# Set cloud-init user data
set_cloud_init() {
    local system_id="$1"

    log_step "Configuring cloud-init..."

    maas admin machine set-user-data "$system_id" \
        user_data@="$CLOUD_INIT_FILE" || {
        log_error "Failed to set cloud-init data"
        exit 1
    }

    log_success "Cloud-init configured"
}

# Commission machine
commission_machine() {
    local system_id="$1"

    log_step "Commissioning machine..."

    maas admin machine commission "$system_id" || {
        log_error "Commissioning failed"
        exit 1
    }

    # Wait for commissioning to complete
    log_info "Waiting for commissioning to complete..."
    while true; do
        local status
        status=$(maas admin machine read "$system_id" | jq -r '.status_name')

        case "$status" in
            "Ready")
                log_success "Commissioning complete"
                break
                ;;
            "Failed testing"|"Failed commissioning")
                log_error "Commissioning failed with status: $status"
                exit 1
                ;;
            *)
                echo -n "."
                sleep 5
                ;;
        esac
    done
    echo ""
}

# Deploy machine
deploy_machine() {
    local system_id="$1"

    log_step "Deploying SIAB..."

    maas admin machine deploy "$system_id" \
        distro_series=rocky9 || {
        log_error "Deployment failed"
        exit 1
    }

    # Wait for deployment
    log_info "Waiting for deployment (this may take 10-15 minutes)..."
    while true; do
        local status
        status=$(maas admin machine read "$system_id" | jq -r '.status_name')

        case "$status" in
            "Deployed")
                log_success "Deployment complete!"
                break
                ;;
            "Failed deployment")
                log_error "Deployment failed"
                exit 1
                ;;
            *)
                echo -n "."
                sleep 10
                ;;
        esac
    done
    echo ""
}

# Get machine IP
get_machine_ip() {
    local system_id="$1"

    log_step "Getting machine IP address..."

    local ip
    ip=$(maas admin machine read "$system_id" | jq -r '.ip_addresses[0]')

    if [[ -z "$ip" ]] || [[ "$ip" == "null" ]]; then
        log_error "Could not get machine IP"
        exit 1
    fi

    log_success "Machine IP: $ip"
    echo "$ip"
}

# Monitor SIAB installation
monitor_siab() {
    local ip="$1"

    log_step "Monitoring SIAB installation..."

    log_info "Waiting for SSH to become available..."
    local max_wait=300
    local elapsed=0
    while ! ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no "siab@$ip" "echo 'SSH ready'" &>/dev/null; do
        if [[ $elapsed -ge $max_wait ]]; then
            log_error "SSH timeout after ${max_wait}s"
            exit 1
        fi
        sleep 5
        ((elapsed+=5))
    done

    log_success "SSH connection established"

    log_info "SIAB installation is running in the background on the VM"
    log_info "Monitor with: ssh siab@$ip 'tail -f /var/log/siab-install.log'"
    echo ""
    log_info "Installation takes approximately 15-20 minutes"
}

# Show summary
show_summary() {
    local ip="$1"

    echo ""
    echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║              SIAB Deployment Complete!                         ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo "VM Details:"
    echo "  Name:     $VM_NAME"
    echo "  IP:       $ip"
    echo "  Cores:    $VM_CORES"
    echo "  Memory:   ${VM_MEMORY}MB"
    echo "  Storage:  $VM_STORAGE"
    echo ""
    echo "Access the VM:"
    echo "  ${BOLD}ssh siab@$ip${NC}"
    echo ""
    echo "Monitor SIAB installation:"
    echo "  ${BOLD}ssh siab@$ip 'tail -f /var/log/siab-install.log'${NC}"
    echo ""
    echo "Check installation status:"
    echo "  ${BOLD}ssh siab@$ip 'cloud-init status'${NC}"
    echo ""
    echo "After SIAB installation completes (~20 minutes), access services:"
    echo "  Get gateway IPs:"
    echo "    ${BOLD}ssh siab@$ip 'sudo kubectl get svc -n istio-system | grep ingress'${NC}"
    echo ""
    echo "  Add to /etc/hosts and access:"
    echo "    - https://keycloak.siab.local"
    echo "    - https://minio.siab.local"
    echo "    - https://grafana.siab.local"
    echo "    - https://dashboard.siab.local"
    echo ""
}

# Main execution
main() {
    echo -e "${CYAN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}${BOLD}║          SIAB MAAS Automated Deployment                        ║${NC}"
    echo -e "${CYAN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    parse_args "$@"
    prompt_missing
    check_prereqs
    maas_login

    local vm_host_id
    vm_host_id=$(add_proxmox_host)

    local system_id
    system_id=$(compose_vm "$vm_host_id")

    set_cloud_init "$system_id"
    commission_machine "$system_id"
    deploy_machine "$system_id"

    local ip
    ip=$(get_machine_ip "$system_id")

    monitor_siab "$ip"
    show_summary "$ip"

    log_success "Deployment automation complete!"
}

# Run main
main "$@"
