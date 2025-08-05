#!/bin/bash
# Core utilities for dotfiles - Pragmatic version
# Keeps essential functions, removes over-engineering

# Prevent double-sourcing
[[ -n "${DOTFILES_CORE_LOADED:-}" ]] && return 0
readonly DOTFILES_CORE_LOADED=1

set -euo pipefail

# Essential colors only
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

# Logging functions (heavily used - 100+ calls)
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1" >&2; }
wsl_log() { echo -e "${PURPLE}[WSL]${NC} $1"; }

# Basic helpers
command_exists() { command -v "$1" >/dev/null 2>&1; }
is_wsl() { [[ -f /proc/sys/fs/binfmt_misc/WSLInterop ]]; }

# WSL username - simplified to one reliable method
get_windows_username() {
    is_wsl && cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' || echo "$USER"
}

# Safe sudo with logging
safe_sudo() {
    log "Executing: sudo $*"
    sudo "$@"
}

# Environment detection - simplified
detect_environment() {
    if ! command_exists lsb_release; then
        error "This script requires Ubuntu"
        exit 1
    fi
    
    log "Ubuntu $(lsb_release -rs) detected"
    
    if is_wsl; then
        wsl_log "Running on WSL"
        export IS_WSL=true
    else
        export IS_WSL=false
    fi
}

# Paths setup
if [[ -z "${DOTFILES_DIR:-}" ]]; then
    DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../" && pwd)"
fi

# Simple backup function
backup_file() {
    local file="$1"
    [[ -f "$file" ]] && cp "$file" "$file.bak.$(date +%Y%m%d-%H%M%S)"
}

# Symlink with backup
safe_symlink() {
    local source="$1" target="$2"
    
    if [[ ! -e "$source" ]]; then
        error "Source not found: $source"
        return 1
    fi
    
    # Backup existing file if not a symlink
    if [[ -e "$target" && ! -L "$target" ]]; then
        backup_file "$target"
    fi
    
    ln -sf "$source" "$target"
    success "Linked $source -> $target"
}

# Git config processing
process_git_config() {
    local source="$1" target="$2"
    
    [[ -f "$target" ]] && backup_file "$target"
    
    local name email
    if [[ -t 0 ]]; then
        read -p "Git name: " name
        read -p "Git email: " email
    else
        name="$USER"
        email="$USER@localhost"
        warn "Non-interactive: using defaults"
    fi
    
    sed -e "s/{{GIT_NAME}}/$name/g" \
        -e "s/{{GIT_EMAIL}}/$email/g" \
        "$source" > "$target"
    
    success "Git config created"
}

# WSL clipboard setup
setup_wsl_clipboard() {
    is_wsl || return 0
    
    wsl_log "Setting up clipboard integration..."
    mkdir -p "$HOME/.local/bin"
    
    echo -e '#!/bin/bash\nclip.exe' > "$HOME/.local/bin/pbcopy"
    echo -e '#!/bin/bash\npowershell.exe -command "Get-Clipboard" | sed "s/\\r$//"' > "$HOME/.local/bin/pbpaste"
    
    chmod +x "$HOME/.local/bin/pbcopy" "$HOME/.local/bin/pbpaste"
    success "WSL clipboard configured"
}

# Basic validation
validate_installation() {
    log "Validating installation..."
    
    local errors=0
    local files=("$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.gitconfig")
    
    for file in "${files[@]}"; do
        if [[ ! -e "$file" ]]; then
            error "Missing: $file"
            ((errors++))
        fi
    done
    
    if [[ $errors -eq 0 ]]; then
        success "Validation passed"
        return 0
    else
        error "Validation failed ($errors errors)"
        return 1
    fi
}

# Export commonly used functions
export -f is_wsl command_exists