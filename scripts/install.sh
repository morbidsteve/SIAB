#!/bin/bash
# SIAB - Secure Infrastructure as a Box
# Modular Installer Orchestrator
#
# This is the main installation script that orchestrates all modules.
# Individual components are defined in the modules/ directory.

set -euo pipefail

# Get script directory for module loading
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set SIAB_REPO_DIR to the source repository (parent of scripts/)
# This ensures manifests, app-deployer code, etc. are found during install
export SIAB_REPO_DIR="$(dirname "$SCRIPT_DIR")"

# ==============================================================================
# Load Libraries (order matters - dependencies first)
# ==============================================================================

source "${SCRIPT_DIR}/lib/common/colors.sh"
source "${SCRIPT_DIR}/lib/common/config.sh"
source "${SCRIPT_DIR}/lib/common/logging.sh"
source "${SCRIPT_DIR}/lib/common/os.sh"
source "${SCRIPT_DIR}/lib/common/utils.sh"
source "${SCRIPT_DIR}/lib/progress/status.sh"
source "${SCRIPT_DIR}/lib/checks/preflight.sh"
source "${SCRIPT_DIR}/lib/kubernetes/kubectl.sh"
source "${SCRIPT_DIR}/lib/kubernetes/helm.sh"
source "${SCRIPT_DIR}/lib/kubernetes/cleanup.sh"

# ==============================================================================
# Load Modules
# ==============================================================================

# Core modules
source "${SCRIPT_DIR}/modules/core/rke2.sh"
source "${SCRIPT_DIR}/modules/core/helm.sh"
source "${SCRIPT_DIR}/modules/core/k9s.sh"

# Infrastructure modules
source "${SCRIPT_DIR}/modules/infrastructure/firewall.sh"
source "${SCRIPT_DIR}/modules/infrastructure/cert-manager.sh"
source "${SCRIPT_DIR}/modules/infrastructure/metallb.sh"
source "${SCRIPT_DIR}/modules/infrastructure/longhorn.sh"
source "${SCRIPT_DIR}/modules/infrastructure/istio.sh"

# Security modules
source "${SCRIPT_DIR}/modules/security/keycloak.sh"
source "${SCRIPT_DIR}/modules/security/oauth2-proxy.sh"
source "${SCRIPT_DIR}/modules/security/gatekeeper.sh"
source "${SCRIPT_DIR}/modules/security/trivy.sh"

# Application modules
source "${SCRIPT_DIR}/modules/applications/minio.sh"
source "${SCRIPT_DIR}/modules/applications/monitoring.sh"
source "${SCRIPT_DIR}/modules/applications/dashboard.sh"
source "${SCRIPT_DIR}/modules/applications/siab-apps.sh"

# Configuration modules
source "${SCRIPT_DIR}/modules/config/credentials.sh"
source "${SCRIPT_DIR}/modules/config/network.sh"
source "${SCRIPT_DIR}/modules/config/sso.sh"

# ==============================================================================
# Main Installation Function
# ==============================================================================

main() {
    # Check root privileges
    check_root

    # Detect operating system
    detect_os

    # Initialize logging
    init_logging "install"

    # Setup file descriptors for progress display
    setup_progress_fds
    setup_error_handler

    # Initialize step status tracking
    init_step_status

    echo ""
    echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}${CYAN}║              SIAB - Secure Infrastructure as a Box                  ║${NC}"
    echo -e "${BOLD}${CYAN}║                     Installation v${SIAB_VERSION}                             ║${NC}"
    echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}Installing on:${NC} ${OS_NAME} (${OS_ID} ${OS_VERSION_ID})"
    echo -e "${BOLD}Domain:${NC} ${SIAB_DOMAIN}"
    echo ""

    # ==== Phase 1: Pre-flight Checks ====
    start_step "System Requirements"
    if check_requirements; then
        complete_step "System Requirements"
    else
        fail_step "System Requirements" "Requirements not met"
        exit 1
    fi

    # ==== Phase 2: Setup ====
    setup_directories
    start_step "System Dependencies"
    install_dependencies
    complete_step "System Dependencies"

    clone_siab_repo

    start_step "Firewall Configuration"
    configure_firewall
    complete_step "Firewall Configuration"

    start_step "Security Configuration"
    configure_security
    complete_step "Security Configuration"

    # ==== Phase 3: Core Infrastructure ====
    install_rke2
    configure_calico_network
    install_helm
    install_k9s
    generate_credentials

    # ==== Phase 4: Create Namespaces ====
    create_namespaces

    # ==== Phase 5: Infrastructure Components ====
    install_cert_manager
    install_metallb
    install_longhorn
    install_istio
    create_istio_gateway

    # ==== Phase 6: Identity & Access Management ====
    install_keycloak
    configure_keycloak_realm
    install_oauth2_proxy
    configure_sso

    # ==== Phase 7: Storage & Monitoring ====
    install_minio
    install_trivy
    install_gatekeeper
    install_monitoring

    # ==== Phase 8: User Interfaces ====
    install_kubernetes_dashboard
    install_siab_tools
    apply_security_policies
    install_siab_crds
    install_dashboard
    install_deployer

    # ==== Phase 9: Final Configuration ====
    final_configuration

    # Print summary
    print_status_dashboard

    echo ""
    echo -e "${GREEN}${BOLD}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║                    Installation Complete!                            ║${NC}"
    echo -e "${GREEN}${BOLD}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "${BOLD}Access Points:${NC}"
    echo -e "  Dashboard:    https://dashboard.${SIAB_DOMAIN}"
    echo -e "  Keycloak:     https://keycloak.${SIAB_DOMAIN}"
    echo -e "  Grafana:      https://grafana.${SIAB_DOMAIN}"
    echo -e "  MinIO:        https://minio.${SIAB_DOMAIN}"
    echo -e "  K8s Dashboard: https://k8s-dashboard.${SIAB_DOMAIN}"
    echo -e "  Deployer:     https://deployer.${SIAB_DOMAIN}"
    echo ""
    echo -e "${BOLD}Credentials:${NC} ${SIAB_CONFIG_DIR}/credentials.env"
    echo -e "${BOLD}Logs:${NC} ${SIAB_LOG_DIR}/install-latest.log"
    echo ""

    # Get gateway IPs and print /etc/hosts entries
    local admin_ip user_ip
    admin_ip=$(kubectl get svc istio-ingress-admin -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)
    user_ip=$(kubectl get svc istio-ingress-user -n istio-system -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null)

    echo -e "${YELLOW}${BOLD}Add to /etc/hosts on client machines:${NC}"
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    if [[ -n "$admin_ip" ]]; then
        echo -e "${admin_ip}  keycloak.${SIAB_DOMAIN} grafana.${SIAB_DOMAIN} minio.${SIAB_DOMAIN} k8s-dashboard.${SIAB_DOMAIN}"
    fi
    if [[ -n "$user_ip" ]]; then
        echo -e "${user_ip}  dashboard.${SIAB_DOMAIN} deployer.${SIAB_DOMAIN} auth.${SIAB_DOMAIN} ${SIAB_DOMAIN}"
    fi
    echo -e "${CYAN}────────────────────────────────────────────────────────────────${NC}"
    echo ""
    echo -e "Run ${BOLD}siab-status${NC} to check installation status."
    echo -e "Run ${BOLD}siab-info${NC} to view access information."
    echo ""
}

# ==============================================================================
# Run Main
# ==============================================================================

main "$@"
