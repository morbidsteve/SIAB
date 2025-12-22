#!/bin/bash
# SIAB - Logging Library
# Unified logging functions for install and uninstall scripts

# Requires: colors.sh to be sourced first

# Log directory (can be overridden)
: "${SIAB_LOG_DIR:=/var/log/siab}"

# Initialize logging
# Usage: init_logging "install" or init_logging "uninstall"
init_logging() {
    local log_type="${1:-install}"
    local timestamp
    timestamp="$(date '+%Y%m%d-%H%M%S')"

    # Ensure log directory exists
    mkdir -p "$SIAB_LOG_DIR" 2>/dev/null || true

    # Set log file path
    SIAB_LOG_FILE="${SIAB_LOG_DIR}/${log_type}-${timestamp}.log"

    # Create symlink to latest log
    ln -sf "${log_type}-${timestamp}.log" "${SIAB_LOG_DIR}/${log_type}-latest.log" 2>/dev/null || true

    export SIAB_LOG_FILE
}

# Log to file only (for install script with progress bar)
log_info() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" >> "${SIAB_LOG_FILE:-/dev/null}" 2>/dev/null || true
}

log_warn() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARN] $*" >> "${SIAB_LOG_FILE:-/dev/null}" 2>/dev/null || true
}

log_error() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >> "${SIAB_LOG_FILE:-/dev/null}" 2>/dev/null || true
    # Also print errors to stderr if fd 4 is available, otherwise use stderr
    if { true >&4; } 2>/dev/null; then
        echo -e "${RED}[ERROR]${NC} $*" >&4
    else
        echo -e "${RED}[ERROR]${NC} $*" >&2
    fi
}

log_step() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STEP] $*" >> "${SIAB_LOG_FILE:-/dev/null}" 2>/dev/null || true
}

log_success() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $*" >> "${SIAB_LOG_FILE:-/dev/null}" 2>/dev/null || true
}

# Verbose logging functions (log to both console and file)
# Used by uninstall script where we want visible output
log_info_verbose() {
    echo -e "${BLUE}[INFO]${NC} $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $*" >> "${SIAB_LOG_FILE:-/dev/null}" 2>/dev/null || true
}

log_success_verbose() {
    echo -e "${GREEN}[SUCCESS]${NC} $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [SUCCESS] $*" >> "${SIAB_LOG_FILE:-/dev/null}" 2>/dev/null || true
}

log_warning_verbose() {
    echo -e "${YELLOW}[WARNING]${NC} $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $*" >> "${SIAB_LOG_FILE:-/dev/null}" 2>/dev/null || true
}

log_error_verbose() {
    echo -e "${RED}[ERROR]${NC} $*"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $*" >> "${SIAB_LOG_FILE:-/dev/null}" 2>/dev/null || true
}

log_step_verbose() {
    echo ""
    echo -e "${CYAN}${BOLD}==>${NC} ${BOLD}$*${NC}"
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [STEP] $*" >> "${SIAB_LOG_FILE:-/dev/null}" 2>/dev/null || true
}
