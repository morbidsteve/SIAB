#!/bin/bash
set -euo pipefail

# Hardware Discovery Script for SIAB
# Scans network for potential bare metal servers

readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_scan() { echo -e "${BLUE}[SCAN]${NC} $1"; }

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]

Discover bare metal hardware on the network.

Options:
  -s, --subnet CIDR       Network to scan (e.g., 192.168.1.0/24)
  -p, --pxe               Show only PXE-capable devices
  -i, --ipmi              Scan for IPMI interfaces
  -o, --output FILE       Save results to JSON file
  -h, --help              Show this help

Examples:
  # Scan local subnet
  $0 --subnet 192.168.1.0/24

  # Find PXE-capable devices
  $0 --subnet 192.168.1.0/24 --pxe

  # Scan for IPMI and save results
  $0 --subnet 192.168.1.0/24 --ipmi --output inventory.json
EOF
    exit 0
}

# Default values
SUBNET=""
SCAN_PXE=false
SCAN_IPMI=false
OUTPUT_FILE=""

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -s|--subnet)
            SUBNET="$2"
            shift 2
            ;;
        -p|--pxe)
            SCAN_PXE=true
            shift
            ;;
        -i|--ipmi)
            SCAN_IPMI=true
            shift
            ;;
        -o|--output)
            OUTPUT_FILE="$2"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            echo "Unknown option: $1"
            usage
            ;;
    esac
done

# Check dependencies
check_dependencies() {
    local missing=()

    command -v nmap >/dev/null || missing+=("nmap")
    command -v jq >/dev/null || missing+=("jq")

    if [[ ${#missing[@]} -gt 0 ]]; then
        log_warn "Missing dependencies: ${missing[*]}"
        log_info "Install with: dnf install -y ${missing[*]}"
        exit 1
    fi
}

# Auto-detect subnet if not provided
detect_subnet() {
    if [[ -z "${SUBNET}" ]]; then
        log_info "Auto-detecting subnet..."
        local ip
        ip=$(ip -4 addr show | grep -oP '(?<=inet\s)\d+(\.\d+){3}' | grep -v '127.0.0.1' | head -1)
        local subnet_prefix="${ip%.*}.0/24"
        SUBNET="${subnet_prefix}"
        log_info "Using subnet: ${SUBNET}"
    fi
}

# Scan for live hosts
scan_network() {
    log_scan "Scanning network ${SUBNET} for live hosts..."

    nmap -sn "${SUBNET}" -oG - | awk '/Up$/{print $2}' > /tmp/siab-live-hosts.txt

    local count
    count=$(wc -l < /tmp/siab-live-hosts.txt)
    log_info "Found ${count} live hosts"
}

# Detailed scan of each host
scan_hosts() {
    log_scan "Performing detailed scan of discovered hosts..."

    local results=()

    while IFS= read -r ip; do
        log_scan "Scanning ${ip}..."

        # Get hostname
        local hostname
        hostname=$(nmap -sn "${ip}" | grep -oP '(?<=Nmap scan report for )[^ ]+' || echo "unknown")

        # Get MAC address
        local mac
        mac=$(nmap -sn "${ip}" | grep -oP '(?<=MAC Address: )[^ ]+' || echo "unknown")

        # Check open ports
        local ports
        ports=$(nmap -p 22,80,443,623,5900,8080 --open "${ip}" -oG - | grep -oP '(?<=Ports: )[^;]+' || echo "none")

        # Check if SSH is available
        local ssh_available=false
        if echo "${ports}" | grep -q "22/open"; then
            ssh_available=true
        fi

        # Check for IPMI (port 623)
        local ipmi_available=false
        if echo "${ports}" | grep -q "623/open"; then
            ipmi_available=true
        fi

        # Check for PXE capability (indirect - check if no OS installed)
        local pxe_capable=false
        if [[ "${ssh_available}" == "false" ]] && [[ "${mac}" != "unknown" ]]; then
            pxe_capable=true
        fi

        # Store result
        local result=$(jq -n \
            --arg ip "${ip}" \
            --arg hostname "${hostname}" \
            --arg mac "${mac}" \
            --arg ports "${ports}" \
            --argjson ssh "${ssh_available}" \
            --argjson ipmi "${ipmi_available}" \
            --argjson pxe "${pxe_capable}" \
            '{
                ip: $ip,
                hostname: $hostname,
                mac: $mac,
                ports: $ports,
                ssh_available: $ssh,
                ipmi_available: $ipmi,
                pxe_capable: $pxe,
                scanned_at: (now | strftime("%Y-%m-%dT%H:%M:%SZ"))
            }')

        results+=("${result}")

    done < /tmp/siab-live-hosts.txt

    # Combine results
    printf '%s\n' "${results[@]}" | jq -s '.' > /tmp/siab-scan-results.json
}

# Get hardware details via IPMI
scan_ipmi_details() {
    if [[ "${SCAN_IPMI}" == "false" ]]; then
        return
    fi

    log_scan "Scanning IPMI interfaces for hardware details..."

    # Check if ipmitool is available
    if ! command -v ipmitool >/dev/null; then
        log_warn "ipmitool not installed. Skipping IPMI scan."
        log_info "Install with: dnf install -y ipmitool"
        return
    fi

    # Scan each IPMI-capable host
    jq -r '.[] | select(.ipmi_available==true) | .ip' /tmp/siab-scan-results.json | while read -r ip; do
        log_scan "Querying IPMI at ${ip}..."

        # Try common default credentials (SECURITY WARNING: Change these!)
        local users=("ADMIN" "admin" "root")
        local passwords=("ADMIN" "admin" "calvin" "password")

        for user in "${users[@]}"; do
            for pass in "${passwords[@]}"; do
                if timeout 5 ipmitool -I lanplus -H "${ip}" -U "${user}" -P "${pass}" chassis status >/dev/null 2>&1; then
                    log_info "IPMI access successful at ${ip} (${user}/${pass})"

                    # Get hardware info
                    local fru_info
                    fru_info=$(ipmitool -I lanplus -H "${ip}" -U "${user}" -P "${pass}" fru print 2>/dev/null || echo "unavailable")

                    # Get sensor data
                    local sensors
                    sensors=$(ipmitool -I lanplus -H "${ip}" -U "${user}" -P "${pass}" sensor list 2>/dev/null || echo "unavailable")

                    # Update JSON with IPMI data
                    jq --arg ip "${ip}" \
                       --arg fru "${fru_info}" \
                       --arg sensors "${sensors}" \
                       '(.[] | select(.ip==$ip)) += {ipmi_fru: $fru, ipmi_sensors: $sensors}' \
                       /tmp/siab-scan-results.json > /tmp/siab-scan-results-tmp.json
                    mv /tmp/siab-scan-results-tmp.json /tmp/siab-scan-results.json

                    break 2
                fi
            done
        done
    done
}

# Filter results
filter_results() {
    local filtered="/tmp/siab-scan-results.json"

    if [[ "${SCAN_PXE}" == "true" ]]; then
        log_info "Filtering for PXE-capable devices..."
        jq '[.[] | select(.pxe_capable==true)]' /tmp/siab-scan-results.json > /tmp/siab-filtered.json
        filtered="/tmp/siab-filtered.json"
    fi

    if [[ "${SCAN_IPMI}" == "true" ]]; then
        log_info "Filtering for IPMI-capable devices..."
        jq '[.[] | select(.ipmi_available==true)]' "${filtered}" > /tmp/siab-filtered2.json
        filtered="/tmp/siab-filtered2.json"
    fi

    cat "${filtered}"
}

# Display results
display_results() {
    log_info "Hardware Discovery Results:"
    echo ""

    local results
    results=$(filter_results)

    # Summary table
    echo "=== Discovered Hardware ==="
    echo ""
    printf "%-15s %-20s %-17s %-6s %-6s %-6s\n" "IP Address" "Hostname" "MAC Address" "SSH" "IPMI" "PXE"
    echo "--------------------------------------------------------------------------------"

    echo "${results}" | jq -r '.[] | "\(.ip)\t\(.hostname)\t\(.mac)\t\(.ssh_available)\t\(.ipmi_available)\t\(.pxe_capable)"' | \
    while IFS=$'\t' read -r ip hostname mac ssh ipmi pxe; do
        printf "%-15s %-20s %-17s %-6s %-6s %-6s\n" "${ip}" "${hostname}" "${mac}" "${ssh}" "${ipmi}" "${pxe}"
    done

    echo ""

    # Statistics
    local total
    total=$(echo "${results}" | jq '. | length')
    local pxe_count
    pxe_count=$(echo "${results}" | jq '[.[] | select(.pxe_capable==true)] | length')
    local ipmi_count
    ipmi_count=$(echo "${results}" | jq '[.[] | select(.ipmi_available==true)] | length')

    echo "=== Statistics ==="
    echo "Total hosts found: ${total}"
    echo "PXE-capable hosts: ${pxe_count}"
    echo "IPMI-capable hosts: ${ipmi_count}"
    echo ""

    # Save to file if requested
    if [[ -n "${OUTPUT_FILE}" ]]; then
        echo "${results}" > "${OUTPUT_FILE}"
        log_info "Results saved to: ${OUTPUT_FILE}"
    fi
}

# Generate MAAS import script
generate_maas_import() {
    log_info "Generating MAAS import script..."

    cat > /tmp/import-to-maas.sh <<'EOF'
#!/bin/bash
# Import discovered hardware into MAAS

# Load MAAS credentials
source /etc/siab/maas.env

# Import each IPMI-capable host
jq -r '.[] | select(.ipmi_available==true) | "\(.ip)\t\(.mac)"' inventory.json | \
while IFS=$'\t' read -r ip mac; do
    echo "Adding ${ip} to MAAS..."

    maas admin machines create \
        architecture=amd64/generic \
        mac_addresses="${mac}" \
        power_type=ipmi \
        power_parameters_power_address="${ip}" \
        power_parameters_power_user=ADMIN \
        power_parameters_power_pass=ADMIN

    echo "Added ${ip}"
done

echo "Import complete. Commission machines with:"
echo "  maas admin machines commission all"
EOF

    chmod +x /tmp/import-to-maas.sh
    log_info "MAAS import script created: /tmp/import-to-maas.sh"
}

main() {
    log_info "SIAB Hardware Discovery Tool"
    echo ""

    check_dependencies
    detect_subnet
    scan_network
    scan_hosts
    scan_ipmi_details
    display_results

    if [[ -n "${OUTPUT_FILE}" ]]; then
        generate_maas_import
    fi

    log_info "Discovery complete!"
}

main "$@"
