#!/bin/bash
# SIAB - Utility Functions Library
# Common utility functions for install and uninstall scripts

# Requires: logging.sh to be sourced first

# Run a command silently, capturing output to log file
# Usage: run_quiet command args...
run_quiet() {
    "$@" >> "${SIAB_LOG_FILE:-/dev/null}" 2>&1
}

# Run a command silently, ignoring errors
# Usage: run_quiet_ok command args...
run_quiet_ok() {
    "$@" >> "${SIAB_LOG_FILE:-/dev/null}" 2>&1 || true
}

# Run a command with a timeout
# Usage: run_with_timeout seconds command args...
run_with_timeout() {
    local timeout_seconds="$1"
    shift
    timeout "${timeout_seconds}" "$@" 2>/dev/null || true
}

# Wait for a condition to be true with timeout
# Usage: wait_for_condition timeout_seconds check_command
wait_for_condition() {
    local timeout_seconds="$1"
    local interval="${2:-5}"
    shift 2
    local check_cmd=("$@")
    local elapsed=0

    while [[ $elapsed -lt $timeout_seconds ]]; do
        if "${check_cmd[@]}" >/dev/null 2>&1; then
            return 0
        fi
        sleep "$interval"
        ((elapsed += interval))
    done
    return 1
}

# Generate a random password
# Usage: generate_password [length]
generate_password() {
    local length="${1:-32}"
    openssl rand -base64 "$length" | tr -dc 'a-zA-Z0-9' | head -c "$length"
}

# Generate a cookie/token secret (base64 encoded)
# Usage: generate_secret [bytes]
generate_secret() {
    local bytes="${1:-32}"
    openssl rand -base64 "$bytes"
}

# Get IP address of the primary interface
get_primary_ip() {
    ip route get 1 | awk '{print $(NF-2);exit}' 2>/dev/null || \
    hostname -I | awk '{print $1}' 2>/dev/null || \
    echo "127.0.0.1"
}

# Calculate IP base (first 3 octets)
get_ip_base() {
    local ip
    ip=$(get_primary_ip)
    echo "${ip%.*}"
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if a file exists and is not empty
file_exists() {
    [[ -f "$1" && -s "$1" ]]
}

# Retry a command with exponential backoff
# Usage: retry_command max_attempts command args...
retry_command() {
    local max_attempts="$1"
    shift
    local attempt=1
    local delay=2

    while [[ $attempt -le $max_attempts ]]; do
        if "$@" >/dev/null 2>&1; then
            return 0
        fi
        log_info "Attempt $attempt/$max_attempts failed, retrying in ${delay}s..."
        sleep "$delay"
        ((attempt++))
        ((delay *= 2))
    done
    return 1
}
