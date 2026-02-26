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

# Ensure ~/.local/bin is in PATH (where we install all binary tools)
[[ -d "$HOME/.local/bin" ]] && [[ ":$PATH:" != *":$HOME/.local/bin:"* ]] && \
    export PATH="$HOME/.local/bin:$PATH"

# Backup directory
DOTFILES_BACKUP_PREFIX="$DOTFILES_DIR/.backups"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
DIM='\033[2m'
NC='\033[0m'

# ==============================================================================
# Install Result Tracking
# ==============================================================================

INSTALL_OK=()
INSTALL_SKIP=()
INSTALL_FAIL=()

track_install() {
    local name="$1" status="$2"
    case "$status" in
        ok)   INSTALL_OK+=("$name") ;;
        skip) INSTALL_SKIP+=("$name") ;;
        fail) INSTALL_FAIL+=("$name") ;;
    esac
}

print_install_summary() {
    [[ ${#INSTALL_OK[@]} -eq 0 && ${#INSTALL_SKIP[@]} -eq 0 && ${#INSTALL_FAIL[@]} -eq 0 ]] && return 0

    echo
    echo "Installation Summary"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    [[ ${#INSTALL_OK[@]} -gt 0 ]]   && echo -e "  ${GREEN}✓${NC} ${INSTALL_OK[*]}"
    [[ ${#INSTALL_SKIP[@]} -gt 0 ]] && echo -e "  ${DIM}─ ${INSTALL_SKIP[*]} (up to date)${NC}"
    [[ ${#INSTALL_FAIL[@]} -gt 0 ]] && echo -e "  ${RED}✗${NC} ${INSTALL_FAIL[*]}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ==============================================================================
# Logging Functions
# ==============================================================================

log() { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
error() { echo -e "${RED}[ERROR]${NC} $1"; }
wsl_log() { echo -e "${PURPLE}[WSL]${NC} $1"; }

# ==============================================================================
# System Detection
# ==============================================================================

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

# ==============================================================================
# Installer Helpers
# ==============================================================================

# Fetch latest release version from GitHub. Args: "owner/repo" [--strip-v]
# Returns the version string (e.g. "0.10.4" with --strip-v, or "v0.10.4" without)
github_latest_version() {
    local repo="$1"
    local strip_v=false
    [[ "${2:-}" == "--strip-v" ]] && strip_v=true

    local tag
    tag=$(curl -sf "https://api.github.com/repos/${repo}/releases/latest" \
        | grep -Po '"tag_name": "\K[^"]*')

    if [[ -z "$tag" ]]; then
        error "Failed to fetch latest version from $repo (rate-limited or network error)"
        return 1
    fi

    if [[ "$strip_v" == true ]]; then
        echo "${tag#v}"
    else
        echo "$tag"
    fi
}

# Verify a binary exists AND runs. Returns 1 if missing or broken.
# Usage: verify_binary <command> [version_flag]
verify_binary() {
    local cmd="$1"
    local flag="${2:---version}"
    command -v "$cmd" >/dev/null 2>&1 && "$cmd" "$flag" >/dev/null 2>&1
}

# ==============================================================================
# WSL Functions
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

# Write install-time environment to ~/.config/dotfiles/env
# Avoids re-deriving known values on every shell startup
write_dotfiles_env() {
    local env_file="$HOME/.config/dotfiles/env"
    local env_dir="$(dirname "$env_file")"
    local marker="# Managed by dotfiles setup.sh — edits will be overwritten on next install"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would write $env_file"
        return 0
    fi

    mkdir -p "$env_dir"

    # Preserve any user-added lines (those without our marker or managed exports)
    local user_lines=""
    if [[ -f "$env_file" ]]; then
        user_lines="$(grep -v -e "^$marker$" \
                           -e '^export DOTFILES_DIR=' \
                           -e '^export WIN_USER=' \
                           "$env_file" || true)"
    fi

    # Build the managed block
    local managed_block="$marker"
    managed_block+=$'\n'"export DOTFILES_DIR=\"$DOTFILES_DIR\""

    if is_wsl; then
        managed_block+=$'\n'"export WIN_USER=\"$(get_windows_username)\""
    fi

    # Write: managed block first, then preserved user lines
    echo "$managed_block" > "$env_file"
    if [[ -n "$user_lines" ]]; then
        echo "$user_lines" >> "$env_file"
    fi

    success "Wrote install-time environment to $env_file"
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
        # Back up the file the symlink points to (if it still exists)
        local link_target
        link_target="$(readlink -f "$target" 2>/dev/null || true)"
        if [[ -n "$link_target" && -f "$link_target" && "$link_target" != "$(readlink -f "$source")" ]]; then
            log "Backing up symlink target $target -> $link_target"
            cp "$link_target" "$backup_dir/$(basename "$target")"
        fi
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
        warn "lsb_release not found — skipping environment detection"
        return 0
    fi

    local ubuntu_version=$(lsb_release -rs)
    local ubuntu_codename=$(lsb_release -cs)

    log "Detected Ubuntu $ubuntu_version ($ubuntu_codename)"

    if is_wsl; then
        wsl_log "Running on Windows Subsystem for Linux"
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

    # Process template with sed (use | delimiter to avoid issues with / in values)
    git_name_escaped=$(printf '%s\n' "$git_name" | sed 's/[[\.*^$()+?{|]/\\&/g')
    git_email_escaped=$(printf '%s\n' "$git_email" | sed 's/[[\.*^$()+?{|]/\\&/g')

    sed -e "s|{{GIT_NAME}}|$git_name_escaped|g" \
        -e "s|{{GIT_EMAIL}}|$git_email_escaped|g" \
        "$source" > "$target"

    success "Git config created: $target"
}

# ==============================================================================
# Package Management
# ==============================================================================

# Package definitions using associative array
declare -A PACKAGES=(
    [core]="git build-essential"
    [development]="zsh direnv bison libevent-dev libncurses-dev xclip"
    [modern]="bat fd-find ripgrep"
    [terminal]="htop tree"
    [languages]="python3-pip"
    [wsl]="socat wslu"
    [docker]="docker-ce docker-ce-cli containerd.io docker-compose-plugin"
    [personal]="ffmpeg yt-dlp"
    [diagramming]="default-jre graphviz"
)

# Install APT packages, skipping already-installed ones
install_apt() {
    local label="$1"
    shift
    local packages=("$@")

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would install $label APT packages: ${packages[*]}"
        return 0
    fi

    local missing=()
    for pkg in "${packages[@]}"; do
        dpkg -s "$pkg" &>/dev/null || missing+=("$pkg")
    done

    if [[ ${#missing[@]} -eq 0 ]]; then
        log "All $label APT packages already installed"
        return 0
    fi

    update_packages
    log "Installing $label APT packages: ${missing[*]}"
    if safe_sudo apt-get install -y "${missing[@]}"; then
        success "$label APT packages installed"
    else
        warn "Some $label packages failed to install"
    fi
}

# Update package lists
update_packages() {
    log "Updating package lists..."
    safe_sudo apt-get update 2>&1 | grep -v '^W:' || true
}

# Ensure Docker's official apt repository is configured
ensure_docker_repo() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would ensure Docker apt repo is configured"
        return 0
    fi

    # Skip if repo already configured
    if [[ -f /etc/apt/sources.list.d/docker.list ]]; then
        return 0
    fi

    log "Adding Docker official apt repository..."
    safe_sudo apt-get install -y ca-certificates curl gnupg

    safe_sudo install -m 0755 -d /etc/apt/keyrings
    if [[ ! -f /etc/apt/keyrings/docker.gpg ]]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | safe_sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        safe_sudo chmod a+r /etc/apt/keyrings/docker.gpg
    fi

    local codename
    codename=$(lsb_release -cs)
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $codename stable" | \
        safe_sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    # Force package list refresh since we added a new repo
    _APT_UPDATED=""
    update_packages
    success "Docker apt repository configured"
}


# ==============================================================================
# Tiered Installation Functions
# ==============================================================================

# Run installer script with consistent error handling
# Exit codes: 0 = installed/updated, 2 = already up to date, 1 = failed
run_installer() {
    local name="$1"
    local critical="${2:-false}"
    local script="$DOTFILES_DIR/install/install-$name.sh"

    if [[ ! -f "$script" ]]; then
        error "Installer script not found: $script"
        track_install "$name" fail
        [[ "$critical" == "true" ]] && exit 1
        return 1
    fi

    local args=()
    [[ "${FORCE_REINSTALL:-false}" == "true" ]] && args+=(--force)

    local rc=0
    "$script" "${args[@]+"${args[@]}"}" || rc=$?

    case $rc in
        0) track_install "$name" ok ;;
        2) track_install "$name" skip ;;
        *)
            track_install "$name" fail
            if [[ "$critical" == "true" ]]; then
                error "$name installation failed"
                exit 1
            else
                warn "$name installation failed"
            fi
            ;;
    esac
}

# Install all binary tools declared in eget.toml
# Bootstraps eget first, then runs eget --download-all
install_eget_tools() {
    run_installer "eget" true

    local config="$DOTFILES_DIR/eget.toml"
    if [[ ! -f "$config" ]]; then
        error "eget.toml not found at $config"
        return 1
    fi

    log "Installing binary tools via eget..."

    local eget_args=("--download-all")

    # Force reinstall: remove existing binaries so eget re-downloads them
    if [[ "${FORCE_REINSTALL:-false}" == "true" ]]; then
        log "Force reinstall: clearing eget-managed binaries..."
        local tools
        tools=$(grep -oP '^\["\K[^"]+' "$config")
        for repo in $tools; do
            local name="${repo##*/}"
            rm -f "$HOME/.local/bin/$name"
        done
    fi

    if EGET_CONFIG="$config" eget "${eget_args[@]}"; then
        # Track each tool from the config
        local tools
        tools=$(grep -oP '^\["\K[^"]+' "$config")
        for repo in $tools; do
            local name="${repo##*/}"
            track_install "$name" ok
        done
    else
        warn "Some eget tools failed to install"
        local tools
        tools=$(grep -oP '^\["\K[^"]+' "$config")
        for repo in $tools; do
            local name="${repo##*/}"
            if verify_binary "$name"; then
                track_install "$name" ok
            else
                track_install "$name" fail
            fi
        done
    fi
}

# Shell tier: modern CLI tools (starship, eza, bat, fd, ripgrep, fzf, zoxide, delta, btop, glow)
install_shell_packages() {
    log "Installing shell tier packages..."

    local packages=(${PACKAGES[core]} ${PACKAGES[development]} ${PACKAGES[modern]} ${PACKAGES[languages]} ${PACKAGES[terminal]})
    is_wsl && packages+=(${PACKAGES[wsl]})

    install_apt "shell" "${packages[@]}"

    # bat/fd symlinks for Ubuntu renames
    if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$(which batcat)" "$HOME/.local/bin/bat"
    fi
    if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$(which fdfind)" "$HOME/.local/bin/fd"
    fi

    # Install all binary tools via eget (starship, eza, fzf, zoxide, delta, btop, glow, lazygit, uv)
    install_eget_tools

    success "Shell tier installation complete"
}

# Dev tier: development tools (neovim, tmux, plantuml + graphviz)
# Note: lazygit is installed via eget in shell tier
install_dev_packages() {
    log "Installing dev tier packages..."

    install_apt "dev" ${PACKAGES[diagramming]}

    log "Installing dev tier tools via scripts..."
    run_installer "tmux"
    run_installer "neovim"
    run_installer "plantuml"

    success "Dev tier installation complete"
}

# Full tier: complete environment (NVM, pyenv, Docker, Azure CLI)
# Note: uv is installed via eget in shell tier
install_full_packages() {
    log "Installing full tier packages..."

    # Azure CLI
    if ! command -v az >/dev/null 2>&1; then
        log "Installing Azure CLI..."
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would install Azure CLI"
        else
            curl -sL https://aka.ms/InstallAzureCLIDeb | safe_sudo bash
        fi
    else
        log "Azure CLI already installed"
    fi

    # Azure DevOps git credential helper
    if [[ -f "$DOTFILES_DIR/bin/git-credential-azdo" ]]; then
        mkdir -p "$HOME/.local/bin"
        ln -sf "$DOTFILES_DIR/bin/git-credential-azdo" "$HOME/.local/bin/git-credential-azdo"
        success "Azure DevOps credential helper linked"
    fi

    # Docker: ensure official repo is configured before installing
    ensure_docker_repo

    # Python dev tools + Docker
    install_apt "full" python3-dev python3-venv ${PACKAGES[docker]}

    # Docker group (non-fatal — user may already be in group from a previous run)
    if command -v docker >/dev/null 2>&1 && ! groups | grep -q docker; then
        log "Adding $USER to docker group..."
        if safe_sudo usermod -aG docker "$USER"; then
            success "Added to docker group (restart shell to activate)"
        else
            warn "Could not add to docker group (try: sudo usermod -aG docker $USER)"
        fi
    fi

    # Version managers
    run_installer "nvm" true
    run_installer "pyenv" true
    run_installer "poetry"

    success "Full tier installation complete"
}

# Install personal packages (claude-code lives here — work systems use the VS Code extension)
install_personal_packages() {
    install_apt "personal" ${PACKAGES[personal]}
    run_installer "claude-code"
}

# Note: Functions are available when this file is sourced
# No need to export in bash/zsh - they're already in the current shell context
