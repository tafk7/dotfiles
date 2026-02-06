#!/bin/bash
# Dotfiles utilities library
# Ubuntu-only support

# Prevent double-sourcing
[[ -n "${DOTFILES_LIB_LOADED:-}" ]] && return 0
readonly DOTFILES_LIB_LOADED=1

set -e

# ==============================================================================
# Path and Environment Setup
# ==============================================================================

DOTFILES_DIR="${DOTFILES_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
export DOTFILES_DIR

# Backup directory
DOTFILES_BACKUP_PREFIX="$DOTFILES_DIR/.backups"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

# ==============================================================================
# Logging Functions
# ==============================================================================

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
wsl_log() { echo -e "${PURPLE}[WSL]${NC} $1"; }

# ==============================================================================
# WSL Functions
# ==============================================================================

# Check if running on WSL
is_wsl() {
    [[ -f /proc/sys/fs/binfmt_misc/WSLInterop ]] || \
    [[ -n "${WSL_DISTRO_NAME:-}" ]] || \
    grep -qiE "(microsoft|wsl)" /proc/version 2>/dev/null || \
    grep -qiE "(microsoft|wsl)" /proc/sys/kernel/osrelease 2>/dev/null
}

# Get Windows username for WSL operations
get_windows_username() {
    if is_wsl; then
        # Use cmd.exe to get Windows username - simple and reliable
        local win_user=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' | tr -d ' ')

        # Validate it's not empty or a system account
        if [[ -z "$win_user" ]] || [[ "$win_user" == "SYSTEM" ]] || [[ "$win_user" == "Administrator" ]]; then
            # Fallback to current user
            win_user="$USER"
        fi

        echo "$win_user"
    fi
}

# Setup WSL clipboard integration
setup_wsl_clipboard() {
    if ! is_wsl; then
        return 0
    fi

    wsl_log "Setting up WSL clipboard integration..."

    local bin_dir="$HOME/.local/bin"
    mkdir -p "$bin_dir"

    # Create pbcopy script
    cat > "$bin_dir/pbcopy" << 'EOF'
#!/bin/bash
clip.exe
EOF

    # Create pbpaste script
    cat > "$bin_dir/pbpaste" << 'EOF'
#!/bin/bash
powershell.exe -command "Get-Clipboard" | sed 's/\r$//'
EOF

    chmod +x "$bin_dir/pbcopy" "$bin_dir/pbpaste"

    # Ensure ~/.local/bin is in PATH
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        export PATH="$HOME/.local/bin:$PATH"
    fi

    success "WSL clipboard integration setup complete"
}


# ==============================================================================
# Backup Functions
# ==============================================================================

# Create backup directory with timestamp
create_backup_dir() {
    # Ensure .backups directory exists
    mkdir -p "$DOTFILES_BACKUP_PREFIX"

    local backup_dir="$DOTFILES_BACKUP_PREFIX/backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    echo "$backup_dir"
}

# Backup a single file
backup_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        # Ensure .backups directory exists
        mkdir -p "$DOTFILES_BACKUP_PREFIX"

        local filename=$(basename "$file")
        local backup="$DOTFILES_BACKUP_PREFIX/${filename}.backup-$(date +%Y%m%d-%H%M%S)"
        cp "$file" "$backup"
        log "Backed up: $file -> $backup"
    fi
}

# Create symlink with backup
safe_symlink() {
    local source="$1"
    local target="$2"
    local backup_dir="$3"

    # Check if source exists
    if [[ ! -e "$source" ]]; then
        error "Source file does not exist: $source"
        return 1
    fi

    # Skip backup if force overwrite is enabled
    if [[ "${FORCE_OVERWRITE:-false}" == "true" && -e "$target" ]]; then
        log "Force overwrite enabled, removing $target"
        rm -rf "$target"
    elif [[ -e "$target" && ! -L "$target" ]]; then
        # If target exists and is not a symlink, back it up
        log "Backing up existing $target"
        mv "$target" "$backup_dir/$(basename "$target")"
    elif [[ -L "$target" ]]; then
        # Remove existing symlink
        rm "$target"
    fi

    # Create the symlink
    ln -s "$source" "$target"
    success "Linked $source -> $target"
}

# Cleanup old backups (keep most recent N backups)
cleanup_old_backups() {
    local keep_count="${1:-10}"  # Default to keeping 10 backups
    local backup_type="${2:-}"   # Optional backup type filter

    if [[ ! -d "$DOTFILES_BACKUP_PREFIX" ]]; then
        return 0
    fi

    log "Cleaning up old backups (keeping last $keep_count)..."

    # If backup type specified, filter by it
    if [[ -n "$backup_type" ]]; then
        # List directories matching the type pattern
        ls -dt "$DOTFILES_BACKUP_PREFIX"/*"$backup_type"* 2>/dev/null | tail -n +$((keep_count + 1)) | xargs rm -rf 2>/dev/null || true
    else
        # Clean all backup directories
        ls -dt "$DOTFILES_BACKUP_PREFIX"/* 2>/dev/null | tail -n +$((keep_count + 1)) | xargs rm -rf 2>/dev/null || true
    fi
}

# ==============================================================================
# Core Utility Functions
# ==============================================================================

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

    # Check if running on WSL
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
    local force="${4:-false}"

    # Get user information
    local git_name git_email

    if [[ -t 0 ]]; then  # Interactive terminal
        # Check if already configured (BEFORE backing up the file!)
        local existing_name=$(git config --global user.name 2>/dev/null || true)
        local existing_email=$(git config --global user.email 2>/dev/null || true)

        # Skip prompts if already configured (unless forced)
        if [[ -n "$existing_name" && -n "$existing_email" && "$force" != "true" ]]; then
            git_name="$existing_name"
            git_email="$existing_email"
            success "Using existing git config (user.name: $git_name, user.email: $git_email)"
        else
            # Prompt for configuration
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
        fi
    else
        # Non-interactive fallback
        git_name="${USER:-dotfiles}"
        git_email="${USER:-dotfiles}@${HOSTNAME:-localhost}"
        warn "Non-interactive mode: using default git config ($git_name, $git_email)"
    fi

    # Backup existing config AFTER we've read the git user info
    if [[ -f "$target" && ! -L "$target" ]]; then
        log "Backing up existing git config"
        mv "$target" "$backup_dir/"
    elif [[ -L "$target" ]]; then
        rm "$target"
    fi

    # Process template with sed (escape special characters)
    git_name_escaped=$(printf '%s\n' "$git_name" | sed 's/[[\.*^$()+?{|]/\\&/g')
    git_email_escaped=$(printf '%s\n' "$git_email" | sed 's/[[\.*^$()+?{|]/\\&/g')

    sed -e "s/{{GIT_NAME}}/$git_name_escaped/g" \
        -e "s/{{GIT_EMAIL}}/$git_email_escaped/g" \
        "$source" > "$target"

    success "Git config created: $target"
}

# ==============================================================================
# Package Management
# ==============================================================================

# Package definitions using associative array
declare -A PACKAGES=(
    [core]="git build-essential"
    [development]="zsh direnv"
    [modern]="bat fd-find ripgrep fzf"
    [terminal]="htop tree"
    [languages]="python3-pip"
    [wsl]="socat wslu"
    [docker]="docker.io docker-compose-v2"
    [personal]="ffmpeg yt-dlp"
)

# Simple package installation - trust apt
install_package_set() {
    local set_name="$1"
    local packages="${PACKAGES[$set_name]}"

    if [[ -z "$packages" ]]; then
        error "Unknown package set: $set_name"
        return 1
    fi

    log "Installing $set_name packages..."
    # shellcheck disable=SC2086
    if safe_sudo apt-get install -y $packages; then
        success "$set_name packages installed"
        return 0
    else
        # Some packages might fail, that's OK
        warn "Some $set_name packages failed to install"
        return 0
    fi
}

# Update package lists
update_packages() {
    log "Updating package lists..."
    safe_sudo apt-get update
}

# Get package list for dry-run display
get_tier_packages() {
    local tier="$1"
    local packages=""

    case "$tier" in
        shell)
            packages="${PACKAGES[core]} ${PACKAGES[development]} ${PACKAGES[modern]} ${PACKAGES[languages]} ${PACKAGES[terminal]}"
            if is_wsl; then
                packages="$packages ${PACKAGES[wsl]}"
            fi
            ;;
        personal)
            packages="${PACKAGES[personal]}"
            ;;
    esac

    echo "$packages"
}

# ==============================================================================
# Tiered Installation Functions
# ==============================================================================

# Run installer script with consistent error handling
run_installer() {
    local name="$1"
    local critical="${2:-false}"
    local script="$DOTFILES_DIR/install/install-$name.sh"

    if [[ ! -f "$script" ]]; then
        error "Installer script not found: $script"
        [[ "$critical" == "true" ]] && exit 1
        return 1
    fi

    if [[ "$critical" == "true" ]]; then
        "$script" || { error "$name installation failed"; exit 1; }
    else
        "$script" || warn "$name installation failed"
    fi
}

# Shell tier: modern CLI tools (starship, eza, bat, fd, ripgrep, fzf, zoxide, delta, btop)
install_shell_packages() {
    log "Installing shell tier packages..."

    update_packages

    # APT packages for shell tier
    local shell_packages="${PACKAGES[core]} ${PACKAGES[development]} ${PACKAGES[modern]} ${PACKAGES[languages]} ${PACKAGES[terminal]}"

    # Add WSL packages if on WSL
    if is_wsl; then
        shell_packages="$shell_packages ${PACKAGES[wsl]}"
    fi

    log "Installing shell tier APT packages..."
    # shellcheck disable=SC2086
    if safe_sudo apt-get install -y $shell_packages; then
        success "Shell tier APT packages installed"
    else
        warn "Some shell tier packages failed to install"
    fi

    # Create command aliases for renamed packages (user-local symlinks)
    if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$(which batcat)" "$HOME/.local/bin/bat"
    fi
    if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"
    fi

    # Install modern tools via dedicated installers (graceful failures)
    log "Installing shell tier tools via scripts..."
    run_installer "starship"
    run_installer "eza"
    run_installer "zoxide"
    run_installer "delta"
    run_installer "btop"

    success "Shell tier installation complete"
}

# Dev tier: development tools (neovim, lazygit, tmux, Claude Code)
install_dev_packages() {
    log "Installing dev tier packages..."

    # Install tmux via APT if not present
    if ! command -v tmux >/dev/null 2>&1; then
        log "Installing tmux..."
        safe_sudo apt-get install -y tmux || warn "tmux installation failed"
    fi

    # Install neovim and lazygit via scripts (graceful failures)
    log "Installing dev tier tools via scripts..."
    run_installer "neovim"
    run_installer "lazygit"

    # Install Claude Code CLI
    log "Installing Claude Code..."
    run_installer "claude-code" true

    success "Dev tier installation complete"
}

# Full tier: complete environment (NVM, pyenv, Docker, Azure CLI)
install_full_packages() {
    log "Installing full tier packages..."

    # Azure CLI and Python dev tools
    install_work_packages

    # Docker
    install_docker

    # Install NVM and Node.js
    log "Installing NVM..."
    run_installer "nvm" true

    # Install pyenv for Python version management
    log "Installing pyenv..."
    run_installer "pyenv" true

    # Install uv (fast Python package manager)
    log "Installing uv..."
    run_installer "uv"

    # Install Poetry (Python dependency manager)
    log "Installing Poetry..."
    run_installer "poetry"

    success "Full tier installation complete"
}

# Install work packages (Azure CLI, Python tools, etc.)
install_work_packages() {
    log "Installing work tools..."

    # Azure CLI
    if ! command -v az >/dev/null 2>&1; then
        log "Installing Azure CLI..."
        curl -sL https://aka.ms/InstallAzureCLIDeb | safe_sudo bash
    else
        log "Azure CLI already installed"
    fi

    # Python development tools (system-level only)
    log "Installing Python development tools..."
    safe_sudo apt-get install -y python3-dev python3-venv

    success "Work tools installed"
}

# Install personal packages
install_personal_packages() {
    install_package_set "personal"
}

# Install Docker
install_docker() {
    if command -v docker >/dev/null 2>&1; then
        log "Docker already installed"
        return 0
    fi

    install_package_set "docker"

    # Add user to docker group
    if ! groups | grep -q docker; then
        log "Adding $USER to docker group..."
        safe_sudo usermod -aG docker "$USER"
        success "Added to docker group (restart shell to activate)"
    fi
}

# Note: Functions are available when this file is sourced
# No need to export in bash/zsh - they're already in the current shell context
