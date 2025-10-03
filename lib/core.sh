#!/bin/bash
# Core utilities for simplified dotfiles installation
# Ubuntu-only support, human-readable, well-engineered

# Prevent double-sourcing
[[ -n "${DOTFILES_CORE_LOADED:-}" ]] && return 0
readonly DOTFILES_CORE_LOADED=1

set -e

# Path setup
DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../" && pwd)}"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Logging functions
log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
wsl_log() { echo -e "${PURPLE}[WSL]${NC} $1"; }

# Source other library files
source "$DOTFILES_DIR/lib/backup.sh"
source "$DOTFILES_DIR/lib/wsl.sh"

# Safe sudo wrapper - shows commands before execution
safe_sudo() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "[DRY RUN] Would execute: sudo $*"
        return 0
    fi
    
    log "Executing: sudo $*"
    if ! sudo "$@"; then
        error "Command failed: sudo $*"
        return 1
    fi
}


# Detect Ubuntu version and WSL
detect_environment() {
    if ! command -v lsb_release >/dev/null 2>&1; then
        error "This script requires Ubuntu. lsb_release not found."
        exit 1
    fi
    
    local ubuntu_version=$(lsb_release -rs)
    local ubuntu_codename=$(lsb_release -cs)
    
    log "Detected Ubuntu $ubuntu_version ($ubuntu_codename)"
    
    if is_wsl; then
        wsl_log "Running on Windows Subsystem for Linux"
        local win_user=$(get_windows_username)
        wsl_log "Windows username: $win_user"
    fi
}

# Process git config template with user input
process_git_config() {
    local source="$1"
    local target="$2"
    local backup_dir="$3"
    
    # Backup existing config if it exists
    if [[ -f "$target" && ! -L "$target" ]]; then
        log "Backing up existing git config"
        mv "$target" "$backup_dir/"
    elif [[ -L "$target" ]]; then
        rm "$target"
    fi
    
    # Get user information
    local git_name git_email
    
    if [[ -t 0 ]]; then  # Interactive terminal
        # Check if already configured
        local existing_name=$(git config --global user.name 2>/dev/null || true)
        local existing_email=$(git config --global user.email 2>/dev/null || true)
        
        if [[ -n "$existing_name" ]]; then
            read -p "Enter your git name [$existing_name]: " git_name
            git_name="${git_name:-$existing_name}"
        else
            read -p "Enter your git name: " git_name
        fi
        
        if [[ -n "$existing_email" ]]; then
            read -p "Enter your git email [$existing_email]: " git_email
            git_email="${git_email:-$existing_email}"
        else
            read -p "Enter your git email: " git_email
        fi
        
        # Basic email validation
        if [[ ! "$git_email" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
            warn "Email format looks incorrect: $git_email"
        fi
    else
        # Non-interactive fallback
        git_name="${USER}"
        git_email="${USER}@localhost"
        warn "Non-interactive mode: using default git config ($git_name, $git_email)"
    fi
    
    # Process template with sed (escape special characters)
    git_name_escaped=$(printf '%s\n' "$git_name" | sed 's/[[\.*^$()+?{|]/\\&/g')
    git_email_escaped=$(printf '%s\n' "$git_email" | sed 's/[[\.*^$()+?{|]/\\&/g')
    
    sed -e "s/{{GIT_NAME}}/$git_name_escaped/g" \
        -e "s/{{GIT_EMAIL}}/$git_email_escaped/g" \
        "$source" > "$target"
    
    success "Git config created: $target"
}

# Setup NPM global directory (consolidated function)
setup_npm_global() {
    if ! command -v npm >/dev/null 2>&1; then
        return 0
    fi
    
    log "Setting up NPM global directory..."
    
    # Force Unix-style path on WSL
    local npm_global_dir="$HOME/.npm-global"
    if is_wsl; then
        # Ensure we use Linux path, not Windows path
        npm_global_dir="$(cd ~ && pwd)/.npm-global"
    fi
    
    mkdir -p "$npm_global_dir"
    
    # Configure npm to use our global directory
    npm config set prefix "$npm_global_dir"
    
    # Verify the prefix was set correctly
    local actual_prefix=$(npm config get prefix)
    if [[ "$actual_prefix" =~ \\\\ ]]; then
        warn "NPM prefix contains Windows path: $actual_prefix"
        warn "Forcing Unix-style path..."
        # Force set with explicit Unix path
        npm config set prefix "$(cd ~ && pwd)/.npm-global"
    fi
    
    # Add to PATH if not already there
    if [[ ":$PATH:" != *":$npm_global_dir/bin:"* ]]; then
        export PATH="$npm_global_dir/bin:$PATH"
    fi
    
    success "NPM global directory configured: $npm_global_dir"
}

# Validation functions
validate_prerequisites() {
    log "Validating prerequisites..."
    
    # Check for required commands
    local required_commands=("curl" "wget" "git")
    for cmd in "${required_commands[@]}"; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            error "Required command not found: $cmd"
            exit 1
        fi
    done
    
    # Check bash version
    if [[ ${BASH_VERSION%%.*} -lt 4 ]]; then
        error "Bash 4.0+ required (found: $BASH_VERSION)"
        exit 1
    fi
    
    # Check available disk space (need at least 100MB)
    local available_kb=$(df "$HOME" | awk 'NR==2 {print $4}')
    local required_kb=102400  # 100MB
    
    if [[ $available_kb -lt $required_kb ]]; then
        error "Insufficient disk space. Need 100MB, have $(($available_kb/1024))MB"
        exit 1
    fi
    
    success "Prerequisites validated"
}

# Post-installation validation
validate_installation() {
    log "Validating installation..."
    
    local failed_validations=0
    
    # Check critical files (some are symlinks, .gitconfig is templated)
    local critical_files=("$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.config/nvim/init.vim" "$HOME/.gitconfig")
    for file in "${critical_files[@]}"; do
        if [[ "$file" == "$HOME/.gitconfig" ]]; then
            # .gitconfig is a templated file, not a symlink
            if [[ ! -f "$file" ]]; then
                error "Git config file missing: $file"
                ((failed_validations++))
            elif [[ ! -r "$file" ]]; then
                error "Git config file not readable: $file"
                ((failed_validations++))
            fi
        else
            # All other files should be symlinks
            if [[ ! -L "$file" ]]; then
                error "Critical symlink missing: $file"
                ((failed_validations++))
            else
                # Validate symlink target exists and is readable
                if [[ ! -r "$file" ]]; then
                    error "Symlink target not readable: $file -> $(readlink "$file")"
                    ((failed_validations++))
                fi
            fi
        fi
    done
    
    # Check shell configuration loading
    if [[ -f "$HOME/.bashrc" ]]; then
        if ! grep -q "DOTFILES_DIR" "$HOME/.bashrc"; then
            warn "Dotfiles integration may not be working in .bashrc - DOTFILES_DIR not found"
        fi
    fi
    
    
    if [[ $failed_validations -eq 0 ]]; then
        success "Installation validation passed"
        return 0
    else
        error "Installation validation failed ($failed_validations issues)"
        return 1
    fi
}

