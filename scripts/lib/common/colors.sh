#!/bin/bash
# SIAB - Colors and Symbols Library
# Shared ANSI color codes and status symbols

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly BOLD='\033[1m'
readonly DIM='\033[2m'
readonly NC='\033[0m' # No Color

# Status tracking symbols
readonly SYMBOL_PENDING="○"
readonly SYMBOL_RUNNING="◐"
readonly SYMBOL_DONE="●"
readonly SYMBOL_SKIP="◌"
readonly SYMBOL_FAIL="✗"
