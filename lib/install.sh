#!/bin/bash
# Install-time helpers — sourced only by setup.sh and installer scripts.
# Never sourced at shell startup or by bin/ utilities.

# Prevent double-sourcing
[[ -n "${_DOTFILES_INSTALL_LOADED:-}" ]] && return 0
_DOTFILES_INSTALL_LOADED=1

set -e

# Source runtime helpers (logging, is_wsl, etc.)
source "$(dirname "${BASH_SOURCE[0]}")/runtime.sh"
# Source declarative config (PACKAGES, CONFIG_MAP)
source "$(dirname "${BASH_SOURCE[0]}")/config.sh"

# Backup directory
DOTFILES_BACKUP_PREFIX="$DOTFILES_DIR/.backups"

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
# Core Install Utilities
# ==============================================================================

# Safe sudo wrapper
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

# Fetch latest release version from GitHub. Args: "owner/repo" [--strip-v]
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

# Get Windows username for WSL operations
get_windows_username() {
    if is_wsl; then
        local win_user=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n' | tr -d ' ')

        if [[ -z "$win_user" ]] || [[ "$win_user" == "SYSTEM" ]] || [[ "$win_user" == "Administrator" ]]; then
            win_user="$USER"
        fi

        echo "$win_user"
    fi
}

# ==============================================================================
# WSL Install Helpers
# ==============================================================================

# Setup WSL clipboard integration
setup_wsl_clipboard() {
    if ! is_wsl; then
        return 0
    fi

    wsl_log "Setting up WSL clipboard integration..."

    local bin_dir="$HOME/.local/bin"
    mkdir -p "$bin_dir"

    cat > "$bin_dir/pbcopy" << 'EOF'
#!/bin/bash
clip.exe
EOF

    cat > "$bin_dir/pbpaste" << 'EOF'
#!/bin/bash
powershell.exe -command "Get-Clipboard" | sed 's/\r$//'
EOF

    chmod +x "$bin_dir/pbcopy" "$bin_dir/pbpaste"

    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        export PATH="$HOME/.local/bin:$PATH"
    fi

    success "WSL clipboard integration setup complete"
}

# Write install-time environment to ~/.config/dotfiles/env
write_dotfiles_env() {
    local env_file="$HOME/.config/dotfiles/env"
    local env_dir="$(dirname "$env_file")"
    local marker="# Managed by dotfiles setup.sh — edits will be overwritten on next install"

    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would write $env_file"
        return 0
    fi

    mkdir -p "$env_dir"

    local user_lines=""
    if [[ -f "$env_file" ]]; then
        user_lines="$(grep -v -e "^$marker$" \
                           -e '^export DOTFILES_DIR=' \
                           -e '^export WIN_USER=' \
                           "$env_file" || true)"
    fi

    local managed_block="$marker"
    managed_block+=$'\n'"export DOTFILES_DIR=\"$DOTFILES_DIR\""

    if is_wsl; then
        managed_block+=$'\n'"export WIN_USER=\"$(get_windows_username)\""
    fi

    echo "$managed_block" > "$env_file"
    if [[ -n "$user_lines" ]]; then
        echo "$user_lines" >> "$env_file"
    fi

    success "Wrote install-time environment to $env_file"
}

# ==============================================================================
# Backup Functions
# ==============================================================================

create_backup_dir() {
    mkdir -p "$DOTFILES_BACKUP_PREFIX"
    local backup_dir="$DOTFILES_BACKUP_PREFIX/backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    echo "$backup_dir"
}

safe_symlink() {
    local source="$1"
    local target="$2"
    local backup_dir="$3"

    if [[ ! -e "$source" ]]; then
        error "Source file does not exist: $source"
        return 1
    fi

    if [[ "${FORCE_OVERWRITE:-false}" == "true" && -e "$target" ]]; then
        log "Force overwrite enabled, removing $target"
        rm -rf "$target"
    elif [[ -e "$target" && ! -L "$target" ]]; then
        log "Backing up existing $target"
        mv "$target" "$backup_dir/$(basename "$target")"
    elif [[ -L "$target" ]]; then
        local link_target
        link_target="$(readlink -f "$target" 2>/dev/null || true)"
        if [[ -n "$link_target" && -f "$link_target" && "$link_target" != "$(readlink -f "$source")" ]]; then
            log "Backing up symlink target $target -> $link_target"
            cp "$link_target" "$backup_dir/$(basename "$target")"
        fi
        rm "$target"
    fi

    ln -s "$source" "$target"
    success "Linked $source -> $target"
}

cleanup_old_backups() {
    local keep_count="${1:-10}"
    local backup_type="${2:-}"

    if [[ ! -d "$DOTFILES_BACKUP_PREFIX" ]]; then
        return 0
    fi

    log "Cleaning up old backups (keeping last $keep_count)..."

    if [[ -n "$backup_type" ]]; then
        ls -dt "$DOTFILES_BACKUP_PREFIX"/*"$backup_type"* 2>/dev/null | tail -n +$((keep_count + 1)) | xargs rm -rf 2>/dev/null || true
    else
        ls -dt "$DOTFILES_BACKUP_PREFIX"/* 2>/dev/null | tail -n +$((keep_count + 1)) | xargs rm -rf 2>/dev/null || true
    fi
}

# ==============================================================================
# Git Config Template
# ==============================================================================

process_git_config() {
    local source="$1"
    local target="$2"
    local backup_dir="$3"
    local force="${4:-false}"

    local git_name git_email

    if [[ -t 0 ]]; then
        local existing_name=$(git config --global user.name 2>/dev/null || true)
        local existing_email=$(git config --global user.email 2>/dev/null || true)

        if [[ -n "$existing_name" && -n "$existing_email" && "$force" != "true" ]]; then
            git_name="$existing_name"
            git_email="$existing_email"
            success "Using existing git config (user.name: $git_name, user.email: $git_email)"
        else
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

            if [[ ! "$git_email" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
                warn "Email format looks incorrect: $git_email"
            fi
        fi
    else
        git_name="${USER:-dotfiles}"
        git_email="${USER:-dotfiles}@${HOSTNAME:-localhost}"
        warn "Non-interactive mode: using default git config ($git_name, $git_email)"
    fi

    if [[ -f "$target" && ! -L "$target" ]]; then
        log "Backing up existing git config"
        mv "$target" "$backup_dir/"
    elif [[ -L "$target" ]]; then
        rm "$target"
    fi

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

update_packages() {
    log "Updating package lists..."
    safe_sudo apt-get update 2>&1 | grep -v '^W:' || true
}

ensure_docker_repo() {
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would ensure Docker apt repo is configured"
        return 0
    fi

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

    _APT_UPDATED=""
    update_packages
    success "Docker apt repository configured"
}

# ==============================================================================
# Installer Runner
# ==============================================================================

# Run installer script with consistent error handling
# Exit codes: 0 = installed/updated, 2 = already up to date, 1 = failed
run_installer() {
    local name="$1"
    local critical="${2:-false}"
    local script="$DOTFILES_DIR/installers/install-$name.sh"

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
install_eget_tools() {
    run_installer "eget" true

    local config="$DOTFILES_DIR/eget.toml"
    if [[ ! -f "$config" ]]; then
        error "eget.toml not found at $config"
        return 1
    fi

    log "Installing binary tools via eget..."

    local eget_args=("--download-all")

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

# ==============================================================================
# Tiered Installation Functions
# ==============================================================================

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

    install_eget_tools

    success "Shell tier installation complete"
}

install_dev_packages() {
    log "Installing dev tier packages..."

    install_apt "dev" ${PACKAGES[diagramming]}

    log "Installing dev tier tools via scripts..."
    run_installer "tmux"
    run_installer "neovim"
    run_installer "plantuml"

    success "Dev tier installation complete"
}

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

    # Docker
    ensure_docker_repo
    install_apt "full" python3-dev python3-venv ${PACKAGES[docker]}

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
