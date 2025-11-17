#!/bin/bash
set -euo pipefail

# SIAB Cluster Provisioning Script
# Deploy SIAB across multiple nodes via MAAS or PXE

readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly RED='\033[0;31m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Configuration
CLUSTER_NAME="${CLUSTER_NAME:-siab-cluster}"
CLUSTER_SIZE="${CLUSTER_SIZE:-3}"
PROVISIONING_METHOD="${PROVISIONING_METHOD:-maas}"  # maas or pxe
MAAS_URL="${MAAS_URL:-http://localhost:5240/MAAS}"
MAAS_API_KEY="${MAAS_API_KEY:-}"

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Deploy SIAB cluster on bare metal hardware.

Options:
  -m, --method METHOD     Provisioning method: maas or pxe (default: maas)
  -n, --nodes NUM         Number of nodes (default: 3)
  -c, --cluster NAME      Cluster name (default: siab-cluster)
  -h, --help              Show this help message

Environment Variables:
  MAAS_URL                MAAS server URL
  MAAS_API_KEY            MAAS API key
  CLUSTER_NAME            Name for the cluster
  CLUSTER_SIZE            Number of nodes to provision

Examples:
  # Deploy 3-node cluster using MAAS
  $0 --method maas --nodes 3

  # Deploy single-node cluster using PXE
  $0 --method pxe --nodes 1

  # Use environment variables
  export MAAS_URL="http://maas.example.com:5240/MAAS"
  export MAAS_API_KEY="your-api-key"
  $0 --nodes 5
EOF
    exit 0
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -m|--method)
            PROVISIONING_METHOD="$2"
            shift 2
            ;;
        -n|--nodes)
            CLUSTER_SIZE="$2"
            shift 2
            ;;
        -c|--cluster)
            CLUSTER_NAME="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            log_error "Unknown option: $1"
            usage
            ;;
    esac
done

check_maas_connection() {
    log_step "Checking MAAS connection..."

    if [[ -z "${MAAS_API_KEY}" ]]; then
        log_error "MAAS_API_KEY not set"
        log_info "Set it with: export MAAS_API_KEY=\$(sudo maas apikey --username admin)"
        exit 1
    fi

    # Login to MAAS
    maas login admin "${MAAS_URL}/api/2.0/" "${MAAS_API_KEY}" >/dev/null

    if ! maas admin version read >/dev/null 2>&1; then
        log_error "Failed to connect to MAAS at ${MAAS_URL}"
        exit 1
    fi

    log_info "Connected to MAAS successfully"
}

discover_available_machines() {
    log_step "Discovering available machines..."

    local ready_machines
    ready_machines=$(maas admin machines read | jq -r '.[] | select(.status_name=="Ready") | .system_id')

    local ready_count
    ready_count=$(echo "${ready_machines}" | wc -l)

    if [[ ${ready_count} -lt ${CLUSTER_SIZE} ]]; then
        log_error "Insufficient ready machines. Found: ${ready_count}, Required: ${CLUSTER_SIZE}"
        log_info "Commission more machines first"
        exit 1
    fi

    log_info "Found ${ready_count} ready machines"
    echo "${ready_machines}"
}

deploy_node_maas() {
    local system_id=$1
    local node_role=$2  # master or worker

    log_info "Deploying node ${system_id} as ${node_role}..."

    # Set hostname
    local hostname="${CLUSTER_NAME}-${node_role}-${system_id:0:8}"
    maas admin machine update "${system_id}" hostname="${hostname}"

    # Deploy
    maas admin machine deploy "${system_id}" \
        osystem="custom" \
        distro_series="rocky9" \
        user_data="$(cat <<EOF
#cloud-config
write_files:
  - path: /etc/siab/cluster-config
    content: |
      CLUSTER_NAME=${CLUSTER_NAME}
      NODE_ROLE=${node_role}
      PROVISIONED_BY=maas
    permissions: '0644'

runcmd:
  - echo "SIAB_DOMAIN=${CLUSTER_NAME}.siab.local" >> /etc/environment
  - systemctl enable siab-autoinstall.service
EOF
)"

    log_info "Node ${system_id} deployment initiated"
}

deploy_cluster_maas() {
    log_step "Deploying SIAB cluster via MAAS..."

    check_maas_connection

    local available_machines
    available_machines=$(discover_available_machines)

    # Deploy first node as master
    local first_node
    first_node=$(echo "${available_machines}" | head -1)
    deploy_node_maas "${first_node}" "master"

    # Wait for master to be deployed
    log_info "Waiting for master node to deploy..."
    while true; do
        local status
        status=$(maas admin machine read "${first_node}" | jq -r '.status_name')

        if [[ "${status}" == "Deployed" ]]; then
            log_info "Master node deployed successfully"
            break
        elif [[ "${status}" == "Failed deployment" ]]; then
            log_error "Master node deployment failed"
            exit 1
        fi

        sleep 10
    done

    # Get master node IP
    local master_ip
    master_ip=$(maas admin machine read "${first_node}" | jq -r '.ip_addresses[0]')
    log_info "Master node IP: ${master_ip}"

    # Deploy worker nodes
    local node_count=1
    for node_id in $(echo "${available_machines}" | tail -n +2 | head -n $((CLUSTER_SIZE - 1))); do
        deploy_node_maas "${node_id}" "worker-${node_count}"
        ((node_count++))
    done

    log_info "All nodes deployment initiated"
    monitor_deployment_maas
}

monitor_deployment_maas() {
    log_step "Monitoring cluster deployment..."

    local total_nodes=${CLUSTER_SIZE}
    local deployed_nodes=0

    while [[ ${deployed_nodes} -lt ${total_nodes} ]]; do
        deployed_nodes=$(maas admin machines read | jq -r '.[] | select(.status_name=="Deployed") | .system_id' | wc -l)

        log_info "Deployed: ${deployed_nodes}/${total_nodes}"

        if [[ ${deployed_nodes} -lt ${total_nodes} ]]; then
            sleep 30
        fi
    done

    log_info "All nodes deployed successfully!"
    display_cluster_info
}

deploy_cluster_pxe() {
    log_step "Deploying SIAB cluster via PXE..."

    log_warn "PXE deployment requires manual intervention:"
    log_info "1. Ensure PXE server is running"
    log_info "2. Boot ${CLUSTER_SIZE} machines via PXE"
    log_info "3. Machines will automatically install Rocky Linux and SIAB"

    read -p "Press Enter when all machines have been PXE booted..."

    log_info "Waiting for nodes to complete installation..."
    log_info "Monitor progress with: journalctl -u tftpd-hpa -f"
}

display_cluster_info() {
    log_step "Cluster Information"

    if [[ "${PROVISIONING_METHOD}" == "maas" ]]; then
        echo "=== ${CLUSTER_NAME} Cluster ==="
        maas admin machines read | jq -r '.[] | select(.status_name=="Deployed") |
            "\(.hostname) - \(.ip_addresses[0]) - \(.architecture)"'

        echo ""
        echo "Access SIAB Dashboard:"
        local master_ip
        master_ip=$(maas admin machines read | jq -r '.[] | select(.status_name=="Deployed") | .ip_addresses[0]' | head -1)
        echo "  https://dashboard.${CLUSTER_NAME}.siab.local (add to /etc/hosts: ${master_ip})"

        echo ""
        echo "SSH Access:"
        echo "  ssh root@${master_ip}"

        echo ""
        echo "Get kubectl config:"
        echo "  scp root@${master_ip}:/etc/rancher/rke2/rke2.yaml ~/.kube/config-${CLUSTER_NAME}"
    fi

    cat <<EOF

====================================================================
Next Steps:
====================================================================

1. Wait for SIAB installation to complete (~30 minutes)
   Monitor: ssh root@<node-ip> 'journalctl -u siab-autoinstall -f'

2. Access the cluster:
   export KUBECONFIG=~/.kube/config-${CLUSTER_NAME}
   kubectl get nodes

3. Deploy applications:
   kubectl apply -f examples/simple-app.yaml

4. Access platform services:
   - Dashboard: https://dashboard.${CLUSTER_NAME}.siab.local
   - Keycloak: https://keycloak.${CLUSTER_NAME}.siab.local
   - MinIO: https://minio.${CLUSTER_NAME}.siab.local

For more information, see: docs/bare-metal-provisioning.md
====================================================================
EOF
}

main() {
    log_info "SIAB Cluster Provisioning"
    log_info "Cluster: ${CLUSTER_NAME}"
    log_info "Nodes: ${CLUSTER_SIZE}"
    log_info "Method: ${PROVISIONING_METHOD}"
    echo ""

    case "${PROVISIONING_METHOD}" in
        maas)
            deploy_cluster_maas
            ;;
        pxe)
            deploy_cluster_pxe
            ;;
        *)
            log_error "Invalid provisioning method: ${PROVISIONING_METHOD}"
            log_info "Valid methods: maas, pxe"
            exit 1
            ;;
    esac
}

main "$@"
