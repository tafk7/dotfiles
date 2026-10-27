#!/bin/bash
# Runtime helpers — safe to source on every shell startup and bin/ invocation.
# Must not contain install-time code.

[[ -n "${_DOTFILES_RUNTIME_LOADED:-}" ]] && return 0
_DOTFILES_RUNTIME_LOADED=1

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export DOTFILES_DIR

# Ensure ~/.local/bin is in PATH
[[ -d "$HOME/.local/bin" ]] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && \
    export PATH="$HOME/.local/bin:$PATH"

# ==============================================================================
# Colors — gated on stderr being a TTY and NO_COLOR being unset.
# When piped, redirected, or NO_COLOR is set, these expand to empty so
# log output stays clean for grep/awk/CI consumers.
# ==============================================================================

if [[ -t 2 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    PURPLE='\033[0;35m'
    CYAN='\033[0;36m'
    DIM='\033[2m'
    NC='\033[0m'
else
    RED=''
    GREEN=''
    YELLOW=''
    BLUE=''
    PURPLE=''
    CYAN=''
    DIM=''
    NC=''
fi

# ==============================================================================
# Logging
# ==============================================================================

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
# warn/error go to stderr per Unix convention — and so they don't get
# swallowed by callers that capture stdout via $(...).
warn() { echo -e "${YELLOW}[WARN]${NC} $1" >&2; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
wsl_log() { echo -e "${PURPLE}[WSL]${NC} $1"; }

# ==============================================================================
# Helpers
# ==============================================================================

source_if_exists() { [[ -f "$1" ]] && source "$1"; }

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
    arch="${DOTFILES_TEST_ARCH:-$(uname -m)}"
    case "$arch" in
        x86_64|amd64) echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        *) error "Unsupported architecture: $arch"; return 1 ;;
    esac
}

wsl_version() {
    [[ -n "${DOTFILES_TEST_WSL_VERSION:-}" ]] && { printf '%s\n' "$DOTFILES_TEST_WSL_VERSION"; return; }
    is_wsl || { printf '0\n'; return; }
    if grep -qiE 'microsoft-standard-WSL2|WSL2' /proc/sys/kernel/osrelease /proc/version 2>/dev/null; then
        printf '2\n'
    else
        printf '1\n'
    fi
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

# probe_quietly COMMAND ARGS...: run a probe (a --version) that must leave no
# trace. Tools write even for that: gh a telemetry id, Neovim and glow a log,
# glow a default config, starship a cache (under ~/.cache, whatever
# XDG_CACHE_HOME says), Codex helper files under CODEX_HOME, opencode its
# cache, log, and data. So the probe gets its XDG directories, TMPDIR,
# STARSHIP_CACHE, and CODEX_HOME in a scratch directory under /tmp (not
# $TMPDIR, which a caller may be watching), removed afterwards, plus each
# tool's own switch where it has one. HOME stays: rustup finds its toolchains
# there. Returns the command's status.
probe_quietly() {
    local scratch rc=0
    local -a sandbox=(DO_NOT_TRACK=1 NVIM_LOG_FILE=/dev/null)
    if scratch="$(mktemp -d /tmp/dotfiles-probe.XXXXXX 2>/dev/null)"; then
        sandbox+=(XDG_CONFIG_HOME="$scratch" XDG_CACHE_HOME="$scratch" XDG_STATE_HOME="$scratch"
                  XDG_DATA_HOME="$scratch" XDG_RUNTIME_DIR="$scratch" TMPDIR="$scratch"
                  STARSHIP_CACHE="$scratch" CODEX_HOME="$scratch")
    else
        scratch=""
    fi
    env "${sandbox[@]}" "$@" || rc=$?
    [[ -z "$scratch" ]] || rm -rf -- "${scratch:?}"
    return "$rc"
}
