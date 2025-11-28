#!/bin/bash
# Test script for SIAB UI library

source lib/ui.sh

SIAB_VERSION="1.0.0-test"
SIAB_LOG_DIR="/tmp"
SIAB_CONFIG_DIR="/tmp"

declare -a INSTALL_STEPS=(
    "System Check"
    "Download Files"
    "Install Package"
    "Configure Service"
    "Start Service"
)

declare -A STEP_STATUS
declare -A STEP_MESSAGE

for step in "${INSTALL_STEPS[@]}"; do
    STEP_STATUS["$step"]="pending"
done

init_logging
init_ui

sleep 1

start_step "System Check"
update_log_output "Checking CPU..."
sleep 1
update_log_output "Checking memory..."
sleep 1
complete_step "System Check"

start_step "Download Files"
update_log_output "Downloading package 1/3..."
sleep 1
update_log_output "Downloading package 2/3..."
sleep 1
update_log_output "Downloading package 3/3..."
sleep 1
complete_step "Download Files"

start_step "Install Package"
update_log_output "Extracting files..."
sleep 1
skip_step "Install Package" "Already installed"

start_step "Configure Service"
update_log_output "Writing configuration..."
sleep 1
update_log_output "Setting permissions..."
sleep 1
complete_step "Configure Service"

start_step "Start Service"
update_log_output "Starting service..."
sleep 1
update_log_output "Verifying service is running..."
sleep 1
complete_step "Start Service"

show_summary
