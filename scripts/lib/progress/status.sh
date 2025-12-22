#!/bin/bash
# SIAB - Progress Status Library
# Step tracking and status dashboard for install script

# Requires: colors.sh to be sourced first

# Installation steps for status tracking
declare -a INSTALL_STEPS=(
    "System Requirements"
    "System Dependencies"
    "Repository Clone"
    "Firewall Configuration"
    "Security Configuration"
    "RKE2 Kubernetes"
    "Helm Package Manager"
    "k9s Cluster UI"
    "Credentials Generation"
    "Kubernetes Namespaces"
    "cert-manager"
    "MetalLB Load Balancer"
    "Longhorn Block Storage"
    "Istio Service Mesh"
    "Istio Gateways"
    "Keycloak Identity"
    "Keycloak Realm Setup"
    "OAuth2 Proxy"
    "SSO Configuration"
    "MinIO Storage"
    "Trivy Security Scanner"
    "OPA Gatekeeper"
    "Monitoring Stack"
    "Kubernetes Dashboard"
    "SIAB Tools"
    "Security Policies"
    "SIAB CRDs"
    "SIAB Dashboard"
    "SIAB Deployer"
    "Final Configuration"
)

# Status for each step: pending, running, done, skipped, failed
declare -A STEP_STATUS
declare -A STEP_MESSAGE

# Track if we've drawn the dashboard initially
DASHBOARD_DRAWN=false
DASHBOARD_LINES=0
CURRENT_STEP_NAME=""

# Initialize all steps as pending
init_step_status() {
    for step in "${INSTALL_STEPS[@]}"; do
        STEP_STATUS["$step"]="pending"
        STEP_MESSAGE["$step"]=""
    done
}

# Update step status
set_step_status() {
    local step="$1"
    local status="$2"
    local message="${3:-}"
    STEP_STATUS["$step"]="$status"
    STEP_MESSAGE["$step"]="$message"
}

# Count completed and total steps
count_steps() {
    local completed=0
    local total=${#INSTALL_STEPS[@]}
    for step in "${INSTALL_STEPS[@]}"; do
        local status="${STEP_STATUS[$step]:-pending}"
        if [[ "$status" == "done" ]] || [[ "$status" == "skipped" ]]; then
            ((completed++))
        fi
    done
    echo "$completed $total"
}

# Simple single-line progress display (no cursor movement needed)
draw_status_dashboard() {
    local current_action="${1:-}"

    # Count progress
    local counts
    counts=$(count_steps)
    local completed
    completed=$(echo "$counts" | cut -d' ' -f1)
    local total
    total=$(echo "$counts" | cut -d' ' -f2)
    local percent=$((completed * 100 / total))

    # Build progress bar (20 chars wide)
    local bar_filled=$((completed * 20 / total))
    local bar_empty=$((20 - bar_filled))
    local bar=""
    for ((i=0; i<bar_filled; i++)); do bar+="█"; done
    for ((i=0; i<bar_empty; i++)); do bar+="░"; done

    # Print single-line status with carriage return (overwrite previous)
    printf "\r\033[2K${CYAN}[${bar}]${NC} ${GREEN}%d${NC}/${total} │ ${BOLD}%s${NC}" "$completed" "${current_action:0:50}"
}

# Print the full status dashboard at the end
print_status_dashboard() {
    echo ""  # New line to move past progress bar
    echo ""
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║                    SIAB Installation Summary                         ║${NC}"
    echo -e "${BOLD}╠══════════════════════════════════════════════════════════════════════╣${NC}"

    # Calculate columns
    local col1_steps=()
    local col2_steps=()
    local half=$((${#INSTALL_STEPS[@]} / 2 + ${#INSTALL_STEPS[@]} % 2))

    for i in "${!INSTALL_STEPS[@]}"; do
        if [[ $i -lt $half ]]; then
            col1_steps+=("${INSTALL_STEPS[$i]}")
        else
            col2_steps+=("${INSTALL_STEPS[$i]}")
        fi
    done

    # Draw status rows
    for i in "${!col1_steps[@]}"; do
        local step1="${col1_steps[$i]}"
        local step2="${col2_steps[$i]:-}"

        # Get symbol and color for step 1
        local status1="${STEP_STATUS[$step1]:-pending}"
        local symbol1 color1
        case "$status1" in
            pending) symbol1="○"; color1="${DIM}" ;;
            running) symbol1="◐"; color1="${CYAN}" ;;
            done)    symbol1="●"; color1="${GREEN}" ;;
            skipped) symbol1="◌"; color1="${YELLOW}" ;;
            failed)  symbol1="✗"; color1="${RED}" ;;
        esac

        # Pad step1 name to 22 chars
        local step1_padded
        step1_padded=$(printf '%-22.22s' "$step1")

        # Build step 2 portion
        local step2_part=""
        if [[ -n "$step2" ]]; then
            local status2="${STEP_STATUS[$step2]:-pending}"
            local symbol2 color2
            case "$status2" in
                pending) symbol2="○"; color2="${DIM}" ;;
                running) symbol2="◐"; color2="${CYAN}" ;;
                done)    symbol2="●"; color2="${GREEN}" ;;
                skipped) symbol2="◌"; color2="${YELLOW}" ;;
                failed)  symbol2="✗"; color2="${RED}" ;;
            esac
            local step2_padded
            step2_padded=$(printf '%-22.22s' "$step2")
            step2_part="${color2}${symbol2} ${step2_padded}${NC}"
        else
            step2_part="                        "
        fi

        echo -e "║ ${color1}${symbol1} ${step1_padded}${NC}  │  ${step2_part} ║"
    done

    echo -e "╚══════════════════════════════════════════════════════════════════════╝"
}

# Start a step (mark as running and update display)
# Usage: start_step "Step Name"
# Note: Uses fd 3 for output if available
start_step() {
    local step="$1"
    CURRENT_STEP_NAME="$step"
    set_step_status "$step" "running"

    # Write to fd 3 if available (for in-place progress), otherwise to stdout
    if { true >&3; } 2>/dev/null; then
        draw_status_dashboard "Installing: $step..." >&3
    else
        draw_status_dashboard "Installing: $step..."
    fi
}

# Complete a step
# Usage: complete_step "Step Name" ["Optional message"]
complete_step() {
    local step="$1"
    local message="${2:-}"
    set_step_status "$step" "done" "$message"

    if { true >&3; } 2>/dev/null; then
        draw_status_dashboard "Completed: $step" >&3
    else
        draw_status_dashboard "Completed: $step"
    fi
}

# Skip a step
# Usage: skip_step "Step Name" ["Reason"]
skip_step() {
    local step="$1"
    local reason="${2:-Already configured}"
    set_step_status "$step" "skipped" "$reason"

    if { true >&3; } 2>/dev/null; then
        draw_status_dashboard "Skipped: $step" >&3
    else
        draw_status_dashboard "Skipped: $step"
    fi
}

# Fail a step
# Usage: fail_step "Step Name" ["Reason"]
fail_step() {
    local step="$1"
    local reason="${2:-Unknown error}"
    set_step_status "$step" "failed" "$reason"

    if { true >&3; } 2>/dev/null; then
        draw_status_dashboard "FAILED: $step" >&3
    else
        draw_status_dashboard "FAILED: $step"
    fi

    log_error "$step failed: $reason"
}

# Save original file descriptors for progress display
# Usage: setup_progress_fds
setup_progress_fds() {
    exec 3>&1 4>&2
}

# Error handling - restore output and show error
# Usage: Call setup_error_handler after setup_progress_fds
setup_error_handler() {
    trap 'exec 1>&3 2>&4; log_error "Installation failed at line $LINENO. Check ${SIAB_LOG_DIR}/install-latest.log for details."' ERR
}
