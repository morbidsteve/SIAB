#!/bin/bash
#
# SIAB UI and Logging Library
# Provides static UI updates and comprehensive logging
#

# ============================================================================
# LOGGING INFRASTRUCTURE
# ============================================================================

# Log file paths (set by main install script)
INSTALL_LOG_FILE="${SIAB_LOG_DIR}/install-$(date +%Y%m%d-%H%M%S).log"
INSTALL_LOG_LINK="${SIAB_LOG_DIR}/install.log"

# Initialize logging system
init_logging() {
    mkdir -p "${SIAB_LOG_DIR}"

    # Create timestamped log file
    touch "${INSTALL_LOG_FILE}"
    chmod 644 "${INSTALL_LOG_FILE}"

    # Create/update symlink to latest log
    ln -sf "$(basename "${INSTALL_LOG_FILE}")" "${INSTALL_LOG_LINK}"

    # Write log header
    {
        echo "================================================================================"
        echo "SIAB Installation Log"
        echo "Version: ${SIAB_VERSION}"
        echo "Started: $(date)"
        echo "System: ${OS_NAME} ${OS_VERSION_ID}"
        echo "Log File: ${INSTALL_LOG_FILE}"
        echo "================================================================================"
        echo ""
    } >> "${INSTALL_LOG_FILE}"

    log_info_file "Logging initialized"
}

# Log to file only (with timestamp and level)
log_to_file() {
    local level="$1"
    shift
    printf "[%s] [%-5s] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$level" "$*" >> "${INSTALL_LOG_FILE}"
}

# Specific log level functions for file logging
log_info_file() {
    log_to_file "INFO" "$*"
}

log_warn_file() {
    log_to_file "WARN" "$*"
}

log_error_file() {
    log_to_file "ERROR" "$*"
}

log_debug_file() {
    log_to_file "DEBUG" "$*"
}

# Execute command with full logging
log_cmd() {
    local cmd="$*"
    log_to_file "CMD" "Executing: $cmd"

    {
        echo ">>> Command: $cmd"
        echo ">>> Started: $(date '+%Y-%m-%d %H:%M:%S')"
        eval "$cmd" 2>&1
        local exit_code=$?
        echo ">>> Exit code: $exit_code"
        echo ">>> Finished: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        return $exit_code
    } >> "${INSTALL_LOG_FILE}" 2>&1
}

# ============================================================================
# STATIC UI INFRASTRUCTURE
# ============================================================================

# Colors for terminal output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m'

# ANSI escape codes for cursor control
readonly CURSOR_HIDE='\033[?25l'
readonly CURSOR_SHOW='\033[?25h'
readonly CLEAR_SCREEN='\033[2J'
readonly CLEAR_LINE='\033[2K'

# Move cursor to specific row/column
cursor_to() {
    local row=$1
    local col=${2:-1}
    printf "\033[${row};${col}H"
}

# Status symbols
readonly SYMBOL_PENDING="○"
readonly SYMBOL_RUNNING="◐"
readonly SYMBOL_DONE="●"
readonly SYMBOL_SKIP="◌"
readonly SYMBOL_FAIL="✗"

# Terminal dimensions
TERM_ROWS=$(tput lines 2>/dev/null || echo 24)
TERM_COLS=$(tput cols 2>/dev/null || echo 80)

# UI layout positions
UI_ENABLED=true
HEADER_ROW=1
STATUS_START_ROW=5
CURRENT_STEP_ROW=19
LOG_OUTPUT_ROW=21
FOOTER_ROW=$((TERM_ROWS - 1))

# Check if we should use static UI (not in pipe, not in legacy mode)
should_use_static_ui() {
    # Check if stdout is a terminal
    [[ -t 1 ]] || return 1

    # Check for legacy mode
    [[ "${SIAB_LEGACY_OUTPUT:-0}" != "1" ]] || return 1

    # Check terminal size is reasonable
    [[ $TERM_ROWS -ge 24 ]] && [[ $TERM_COLS -ge 80 ]] || return 1

    return 0
}

# Initialize static UI
init_ui() {
    if ! should_use_static_ui; then
        UI_ENABLED=false
        return
    fi

    # Hide cursor
    printf "%b" "${CURSOR_HIDE}"

    # Clear screen
    clear

    # Draw header
    draw_header

    # Draw initial status dashboard
    draw_status_dashboard

    # Draw footer
    draw_footer
}

# Draw header
draw_header() {
    if [[ "$UI_ENABLED" != "true" ]]; then return; fi

    cursor_to $HEADER_ROW
    echo -e "${BOLD}${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
    cursor_to $((HEADER_ROW + 1))
    echo -e "${BOLD}${CYAN}║              SIAB Installation Progress                        ║${NC}"
    cursor_to $((HEADER_ROW + 2))
    echo -e "${BOLD}${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
}

# Draw status dashboard
draw_status_dashboard() {
    if [[ "$UI_ENABLED" != "true" ]]; then return; fi

    local start_row=$STATUS_START_ROW
    local col1_steps=()
    local col2_steps=()

    # Split steps into two columns
    local half=$((${#INSTALL_STEPS[@]} / 2 + ${#INSTALL_STEPS[@]} % 2))

    for i in "${!INSTALL_STEPS[@]}"; do
        if [[ $i -lt $half ]]; then
            col1_steps+=("${INSTALL_STEPS[$i]}")
        else
            col2_steps+=("${INSTALL_STEPS[$i]}")
        fi
    done

    # Draw each row
    local row=$start_row
    for i in "${!col1_steps[@]}"; do
        local step1="${col1_steps[$i]}"
        local step2="${col2_steps[$i]:-}"

        cursor_to $row
        printf "%b" "${CLEAR_LINE}"

        # Format step 1
        local status1="${STEP_STATUS[$step1]:-pending}"
        local symbol1 color1
        case "$status1" in
            pending) symbol1="$SYMBOL_PENDING"; color1="$DIM" ;;
            running) symbol1="$SYMBOL_RUNNING"; color1="$CYAN" ;;
            done)    symbol1="$SYMBOL_DONE"; color1="$GREEN" ;;
            skipped) symbol1="$SYMBOL_SKIP"; color1="$YELLOW" ;;
            failed)  symbol1="$SYMBOL_FAIL"; color1="$RED" ;;
        esac

        printf "  %b%s %-28s%b" "$color1" "$symbol1" "$step1" "$NC"

        # Format step 2 if exists
        if [[ -n "$step2" ]]; then
            local status2="${STEP_STATUS[$step2]:-pending}"
            local symbol2 color2
            case "$status2" in
                pending) symbol2="$SYMBOL_PENDING"; color2="$DIM" ;;
                running) symbol2="$SYMBOL_RUNNING"; color2="$CYAN" ;;
                done)    symbol2="$SYMBOL_DONE"; color2="$GREEN" ;;
                skipped) symbol2="$SYMBOL_SKIP"; color2="$YELLOW" ;;
                failed)  symbol2="$SYMBOL_FAIL"; color2="$RED" ;;
            esac
            printf "  %b%s %-28s%b" "$color2" "$symbol2" "$step2" "$NC"
        fi

        ((row++))
    done
}

# Update current step message
update_current_step() {
    local message="$1"

    if [[ "$UI_ENABLED" == "true" ]]; then
        cursor_to $CURRENT_STEP_ROW
        printf "%b" "${CLEAR_LINE}"
        printf "%b▶%b %b%s%b\n" "$BOLD" "$CYAN" "$NC" "$BOLD" "$message" "$NC"
    else
        # Legacy output
        echo -e "${BLUE}[STEP]${NC} $message"
    fi

    log_info_file "Current step: $message"
}

# Update log output area (last activity)
update_log_output() {
    local message="$1"

    if [[ "$UI_ENABLED" == "true" ]]; then
        cursor_to $LOG_OUTPUT_ROW
        printf "%b" "${CLEAR_LINE}"
        printf "%b%s%b\n" "$DIM" "$message" "$NC"
    else
        # Legacy output
        echo -e "${DIM}$message${NC}"
    fi

    log_debug_file "$message"
}

# Draw footer
draw_footer() {
    if [[ "$UI_ENABLED" != "true" ]]; then return; fi

    cursor_to $FOOTER_ROW
    printf "%b" "${CLEAR_LINE}"
    printf "%bLog: %s%b" "$DIM" "$INSTALL_LOG_FILE" "$NC"
}

# Cleanup UI on exit
cleanup_ui() {
    if [[ "$UI_ENABLED" == "true" ]]; then
        # Show cursor
        printf "%b" "${CURSOR_SHOW}"
        # Move to bottom
        cursor_to $((TERM_ROWS))
        echo ""
    fi
}

# Set trap for cleanup
trap cleanup_ui EXIT INT TERM

# ============================================================================
# STEP MANAGEMENT
# ============================================================================

# Update step status and redraw
set_step_status() {
    local step="$1"
    local status="$2"
    local message="${3:-}"

    STEP_STATUS["$step"]="$status"
    STEP_MESSAGE["$step"]="$message"

    # Redraw dashboard
    if [[ "$UI_ENABLED" == "true" ]]; then
        draw_status_dashboard
    fi

    # Log to file
    log_to_file "STATUS" "$step: $status${message:+ - $message}"
}

# Start a step
start_step() {
    local step="$1"
    set_step_status "$step" "running"
    update_current_step "$step..."

    if [[ "$UI_ENABLED" != "true" ]]; then
        echo -e "${CYAN}${BOLD}==>${NC} ${BOLD}$step${NC}"
    fi
}

# Complete a step
complete_step() {
    local step="$1"
    local message="${2:-}"
    set_step_status "$step" "done" "$message"
    update_log_output "✓ $step completed"

    if [[ "$UI_ENABLED" != "true" ]]; then
        echo -e "${GREEN}[✓]${NC} $step completed${message:+ - $message}"
    fi
}

# Skip a step
skip_step() {
    local step="$1"
    local reason="${2:-Already configured}"
    set_step_status "$step" "skipped" "$reason"
    update_log_output "◌ $step skipped: $reason"

    if [[ "$UI_ENABLED" != "true" ]]; then
        echo -e "${YELLOW}[◌]${NC} $step skipped: $reason"
    fi
}

# Fail a step
fail_step() {
    local step="$1"
    local reason="${2:-Unknown error}"
    set_step_status "$step" "failed" "$reason"
    update_log_output "✗ $step FAILED: $reason"

    if [[ "$UI_ENABLED" != "true" ]]; then
        echo -e "${RED}[✗]${NC} $step FAILED: $reason"
    fi
}

# Legacy logging functions (for compatibility)
log_info() {
    local msg="$1"
    if [[ "$UI_ENABLED" != "true" ]]; then
        echo -e "${GREEN}[INFO]${NC} $msg"
    fi
    log_info_file "$msg"
}

log_warn() {
    local msg="$1"
    if [[ "$UI_ENABLED" != "true" ]]; then
        echo -e "${YELLOW}[WARN]${NC} $msg"
    fi
    log_warn_file "$msg"
}

log_error() {
    local msg="$1"
    if [[ "$UI_ENABLED" != "true" ]]; then
        echo -e "${RED}[ERROR]${NC} $msg"
    fi
    log_error_file "$msg"
}

log_step() {
    local msg="$1"
    if [[ "$UI_ENABLED" != "true" ]]; then
        echo -e "${BLUE}[STEP]${NC} $msg"
    fi
    log_info_file "$msg"
}

# ============================================================================
# FINAL SUMMARY
# ============================================================================

show_summary() {
    # Cleanup UI first
    cleanup_ui

    # Clear screen for summary
    clear

    echo -e "${GREEN}${BOLD}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}${BOLD}║              SIAB Installation Complete!                       ║${NC}"
    echo -e "${GREEN}${BOLD}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # Count statistics
    local total=${#INSTALL_STEPS[@]}
    local done=0
    local skipped=0
    local failed=0

    for step in "${INSTALL_STEPS[@]}"; do
        case "${STEP_STATUS[$step]}" in
            done) ((done++)) ;;
            skipped) ((skipped++)) ;;
            failed) ((failed++)) ;;
        esac
    done

    echo "Installation Statistics:"
    echo "  Total steps:     $total"
    echo -e "  ${GREEN}●${NC} Completed:     $done"
    echo -e "  ${YELLOW}◌${NC} Skipped:       $skipped"
    echo -e "  ${RED}✗${NC} Failed:        $failed"
    echo ""

    if [[ $failed -gt 0 ]]; then
        echo -e "${RED}${BOLD}Installation completed with errors.${NC}"
        echo ""
        echo "Failed steps:"
        for step in "${INSTALL_STEPS[@]}"; do
            if [[ "${STEP_STATUS[$step]}" == "failed" ]]; then
                echo -e "  ${RED}✗${NC} $step"
                if [[ -n "${STEP_MESSAGE[$step]}" ]]; then
                    echo -e "    ${DIM}${STEP_MESSAGE[$step]}${NC}"
                fi
            fi
        done
        echo ""
        echo -e "${CYAN}Review the log for details: ${INSTALL_LOG_FILE}${NC}"
        return 1
    fi

    # Success - show access information
    echo -e "${GREEN}Installation completed successfully!${NC}"
    echo ""

    # Load gateway IPs if available
    if [[ -f "${SIAB_CONFIG_DIR}/install-info.json" ]]; then
        local admin_ip=$(grep -oP '"admin_gateway_ip":\s*"\K[^"]+' "${SIAB_CONFIG_DIR}/install-info.json" 2>/dev/null || echo "")
        local user_ip=$(grep -oP '"user_gateway_ip":\s*"\K[^"]+' "${SIAB_CONFIG_DIR}/install-info.json" 2>/dev/null || echo "")
        local domain=$(grep -oP '"domain":\s*"\K[^"]+' "${SIAB_CONFIG_DIR}/install-info.json" 2>/dev/null || echo "siab.local")

        if [[ -n "$admin_ip" ]] && [[ -n "$user_ip" ]]; then
            echo "Access your services:"
            echo ""
            echo -e "${BOLD}Admin Services:${NC}"
            echo "  Keycloak:      https://keycloak.${domain}"
            echo "  MinIO:         https://minio.${domain}"
            echo "  Grafana:       https://grafana.${domain}"
            echo "  Longhorn:      https://longhorn.${domain}"
            echo "  K8s Dashboard: https://k8s-dashboard.${domain}"
            echo ""
            echo -e "${BOLD}User Services:${NC}"
            echo "  Dashboard:     https://dashboard.${domain}"
            echo "  Catalog:       https://catalog.${domain}"
            echo ""
            echo -e "${BOLD}Add to /etc/hosts:${NC}"
            echo "  $admin_ip  keycloak.${domain} minio.${domain} grafana.${domain} longhorn.${domain} k8s-dashboard.${domain}"
            echo "  $user_ip  dashboard.${domain} catalog.${domain}"
            echo ""
        fi
    fi

    echo "Next steps:"
    echo "  1. Run ./siab-status.sh to check system status"
    echo "  2. Review documentation in docs/"
    echo "  3. Deploy your first application (see docs/APPLICATION-DEPLOYMENT-GUIDE.md)"
    echo ""
    echo -e "${CYAN}Full installation log: ${INSTALL_LOG_FILE}${NC}"
    echo ""

    return 0
}
