#!/bin/bash
# Runtime helpers — safe to source on every shell startup and bin/ invocation.
# Must not contain install-time code.

# Prevent double-sourcing
[[ -n "${_DOTFILES_RUNTIME_LOADED:-}" ]] && return 0
_DOTFILES_RUNTIME_LOADED=1

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export DOTFILES_DIR

# Ensure ~/.local/bin is in PATH
[[ -d "$HOME/.local/bin" ]] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && \
    export PATH="$HOME/.local/bin:$PATH"

# ==============================================================================
# Colors
# ==============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

# ==============================================================================
# Logging
# ==============================================================================

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
wsl_log() { echo -e "${PURPLE}[WSL]${NC} $1"; }

# ==============================================================================
# Helpers
# ==============================================================================

# Source a file if it exists
source_if_exists() { [[ -f "$1" ]] && source "$1"; }

# Check if a command is available
command_exists() { command -v "$1" >/dev/null 2>&1; }

# ==============================================================================
# System Detection
# ==============================================================================

# Check if running on WSL (cached after first call)
is_wsl() {
    if [[ -z "${_IS_WSL+x}" ]]; then
        if [[ -f /proc/sys/fs/binfmt_misc/WSLInterop ]] || \
           [[ -n "${WSL_DISTRO_NAME:-}" ]] || \
           grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null || \
           grep -qiE "(microsoft|wsl)" /proc/sys/kernel/osrelease 2>/dev/null; then
            _IS_WSL=1
        else
            _IS_WSL=0
        fi
    fi
    [[ "$_IS_WSL" -eq 1 ]]
}

# Normalize architecture to x86_64 or aarch64
get_arch() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        *) error "Unsupported architecture: $arch"; return 1 ;;
    esac
}

# Parse system glibc version (e.g. "2.31")
get_glibc_version() {
    ldd --version 2>&1 | head -1 | grep -oP '[0-9]+\.[0-9]+$'
}

# Dotted version comparison: returns 0 (true) if $1 >= $2
version_gte() {
    printf '%s\n%s\n' "$2" "$1" | sort -V -C
}

# Verify a binary exists AND runs. Returns 1 if missing or broken.
verify_binary() {
    local cmd="$1"
    local flag="${2:---version}"
    command -v "$cmd" >/dev/null 2>&1 && "$cmd" "$flag" >/dev/null 2>&1
}
