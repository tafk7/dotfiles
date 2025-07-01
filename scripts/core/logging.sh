#!/bin/bash

# Unified Logging System for Dotfiles
# Provides consistent logging functionality across all scripts

# Color definitions
declare -g RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
declare -g BLUE='\033[0;34m' PURPLE='\033[0;35m' CYAN='\033[0;36m' NC='\033[0m'

# State tracking
declare -g STATE_FILE="${STATE_FILE:-$HOME/.dotfiles_state}"

# Core logging functions - output to stderr to avoid interfering with command substitution
log() { echo -e "${BLUE}[INFO]${NC} $1" >&2; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1" >&2; }
warn() { echo -e "${YELLOW}[WARNING]${NC} $1" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }

# Specialized logging functions
wsl_log() { echo -e "${PURPLE}[WSL]${NC} $1" >&2; }
work_log() { echo -e "${CYAN}[WORK]${NC} $1" >&2; }

# Simple action logging for tracking progress
log_action() {
    local action="$1"
    echo "$(date +%Y%m%d-%H%M%S) $action" >> "$STATE_FILE"
}

# Export functions for use by other scripts
export -f log success warn error wsl_log work_log log_action