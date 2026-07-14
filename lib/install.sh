#!/bin/bash
# Install-time helpers — sourced only by setup.sh and installer scripts.
# Never sourced at shell startup or by bin/ utilities.

# Prevent double-sourcing
[[ -n "${_DOTFILES_INSTALL_LOADED:-}" ]] && return 0
_DOTFILES_INSTALL_LOADED=1

set -euo pipefail

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

    local ubuntu_version ubuntu_codename
    ubuntu_version=$(lsb_release -rs)
    ubuntu_codename=$(lsb_release -cs)

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
        local win_user
        # Strip only the trailing CR/LF from cmd.exe — NOT internal spaces, which
        # are valid in Windows usernames (e.g. "First Last").
        win_user=$(cmd.exe /c "echo %USERNAME%" 2>/dev/null | tr -d '\r\n')

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

    # Call PowerShell by absolute path: shell/env.sh strips the Windows
    # PowerShell directory from PATH, so `powershell.exe` by name won't resolve.
    # Prefer PowerShell 7 when present, otherwise Windows PowerShell 5.
    cat > "$bin_dir/pbpaste" << 'EOF'
#!/bin/bash
if [[ -x "/mnt/c/Program Files/PowerShell/7/pwsh.exe" ]]; then
    "/mnt/c/Program Files/PowerShell/7/pwsh.exe" -NoProfile -Command "Get-Clipboard" | sed 's/\r$//'
else
    /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -Command "Get-Clipboard" | sed 's/\r$//'
fi
EOF

    chmod +x "$bin_dir/pbcopy" "$bin_dir/pbpaste"

    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        export PATH="$HOME/.local/bin:$PATH"
    fi

    success "WSL clipboard integration setup complete"
}

# Write install-time environment to generated/bridge.sh
write_dotfiles_env() {
    local bridge_file="$DOTFILES_DIR/generated/bridge.sh"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "[DRY RUN] Would write $bridge_file"
        return 0
    fi

    mkdir -p "$(dirname "$bridge_file")"

    cat > "$bridge_file" << EOF
# DO NOT EDIT — written by setup.sh write_dotfiles_env()
export DOTFILES_DIR="$DOTFILES_DIR"
EOF

    if is_wsl; then
        echo "export DOTFILES_WSL=1" >> "$bridge_file"
        echo "export WIN_USER=\"$(get_windows_username)\"" >> "$bridge_file"
    fi

    success "Wrote install-time environment to $bridge_file"
}

# ==============================================================================
# Backup Functions
# ==============================================================================

create_backup_dir() {
    mkdir -p "$DOTFILES_BACKUP_PREFIX"
    local backup_dir
    backup_dir="$DOTFILES_BACKUP_PREFIX/backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$backup_dir"
    echo "$backup_dir"
}

# Compute a backup destination that preserves the target's path structure
# relative to $HOME (e.g. ~/.ssh/config -> <backup>/.ssh/config). Preserving
# the path avoids basename collisions between distinct files that share a name,
# such as .ssh/config and .config/bat/config.
backup_dest() {
    local target="$1" backup_dir="$2" rel
    if [[ "$target" == "$HOME/"* ]]; then
        rel="${target#"$HOME"/}"
    else
        rel="${target#/}"
    fi
    printf '%s/%s' "$backup_dir" "$rel"
}

# Guard against catastrophic deletion. Targets come from the declarative
# CONFIG_MAP, but a malformed mapping must never be able to remove anything
# that is not strictly inside the invoking user's $HOME.
assert_safe_home_target() {
    local target="$1"
    if [[ -z "$target" ]]; then
        error "Refusing destructive operation on empty target path"
        exit 1
    fi

    local home_canon parent_canon canon
    home_canon="$(cd "$HOME" 2>/dev/null && pwd -P)" || { error "Cannot resolve \$HOME"; exit 1; }
    parent_canon="$(cd "$(dirname "$target")" 2>/dev/null && pwd -P)" || {
        error "Cannot resolve parent of target: $target"
        exit 1
    }
    canon="$parent_canon/$(basename "$target")"

    if [[ "$canon" == "$home_canon" ]]; then
        error "Refusing to delete \$HOME itself: $canon"
        exit 1
    fi
    if [[ "$canon" != "$home_canon"/* ]]; then
        error "Refusing to delete target outside \$HOME: $canon"
        exit 1
    fi
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
        assert_safe_home_target "$target"
        if [[ -L "$target" ]]; then
            rm -f "$target"
        else
            # Even under --force, preserve real files/dirs in the backup rather
            # than destroying them with rm -rf.
            local dest
            dest="$(backup_dest "$target" "$backup_dir")"
            mkdir -p "$(dirname "$dest")"
            log "Force overwrite: backing up $target -> $dest"
            mv "$target" "$dest"
        fi
    elif [[ -e "$target" && ! -L "$target" ]]; then
        local dest
        dest="$(backup_dest "$target" "$backup_dir")"
        mkdir -p "$(dirname "$dest")"
        log "Backing up existing $target -> $dest"
        mv "$target" "$dest"
    elif [[ -L "$target" ]]; then
        local link_target
        link_target="$(readlink -f "$target" 2>/dev/null || true)"
        if [[ -n "$link_target" && -f "$link_target" && "$link_target" != "$(readlink -f "$source")" ]]; then
            local dest
            dest="$(backup_dest "$target" "$backup_dir")"
            mkdir -p "$(dirname "$dest")"
            log "Backing up symlink target $target -> $link_target"
            cp "$link_target" "$dest"
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

    # Backups are named backup-YYYYMMDD-HHMMSS, so a lexical glob sort is also
    # chronological (oldest first). Collect into an array instead of parsing
    # `ls` and piping to `xargs rm -rf`, which would word-split on any path
    # containing spaces (e.g. a DOTFILES_DIR under a spaced parent directory).
    shopt -s nullglob
    local -a backups
    if [[ -n "$backup_type" ]]; then
        backups=("$DOTFILES_BACKUP_PREFIX"/*"$backup_type"*)
    else
        backups=("$DOTFILES_BACKUP_PREFIX"/*)
    fi
    shopt -u nullglob

    local total=${#backups[@]}
    (( total > keep_count )) || return 0

    # Glob expands ascending (oldest first); remove all but the last keep_count.
    local i
    for (( i = 0; i < total - keep_count; i++ )); do
        rm -rf "${backups[i]}"
    done
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
    # Explicit identity via --git-name/--git-email or DOTFILES_GIT_NAME/EMAIL
    # takes precedence over everything else.
    git_name="${DOTFILES_GIT_NAME:-}"
    git_email="${DOTFILES_GIT_EMAIL:-}"

    local existing_name existing_email
    existing_name=$(git config --global user.name 2>/dev/null || true)
    existing_email=$(git config --global user.email 2>/dev/null || true)

    if [[ -t 0 ]]; then
        if [[ -n "$git_name" && -n "$git_email" ]]; then
            success "Using provided git config (user.name: $git_name, user.email: $git_email)"
        elif [[ -n "$existing_name" && -n "$existing_email" && "$force" != "true" ]]; then
            git_name="$existing_name"
            git_email="$existing_email"
            success "Using existing git config (user.name: $git_name, user.email: $git_email)"
        else
            local def_name="${git_name:-$existing_name}"
            local def_email="${git_email:-$existing_email}"
            if [[ -n "$def_name" ]]; then
                read -p "Enter your git name [$def_name]: " git_name
                git_name="${git_name:-$def_name}"
            else
                read -p "Enter your git name: " git_name
            fi

            if [[ -n "$def_email" ]]; then
                read -p "Enter your git email [$def_email]: " git_email
                git_email="${git_email:-$def_email}"
            else
                read -p "Enter your git email: " git_email
            fi
        fi
    else
        # Non-interactive: explicit values, then existing config, else fail.
        # Never silently fabricate $USER@$HOSTNAME — that produces bogus commits.
        [[ -z "$git_name" ]] && git_name="$existing_name"
        [[ -z "$git_email" ]] && git_email="$existing_email"
        if [[ -z "$git_name" || -z "$git_email" ]]; then
            error "Git identity required but not provided in non-interactive mode."
            error "Pass --git-name/--git-email or set DOTFILES_GIT_NAME/DOTFILES_GIT_EMAIL."
            exit 1
        fi
        log "Using git identity: $git_name <$git_email>"
    fi

    if [[ ! "$git_email" =~ ^[^@]+@[^@]+\.[^@]+$ ]]; then
        warn "Email format looks incorrect: $git_email"
    fi

    if [[ -f "$target" && ! -L "$target" ]]; then
        local dest
        dest="$(backup_dest "$target" "$backup_dir")"
        mkdir -p "$(dirname "$dest")"
        log "Backing up existing git config -> $dest"
        mv "$target" "$dest"
    elif [[ -L "$target" ]]; then
        rm "$target"
    fi

    # First clause: escape regex metachars so the value is safe as-is on the
    # search side. Second clause: escape `&`, which means "matched text" on the
    # *replacement* side of sed. Without the second pass, a name like
    # "Smith & Co" would expand to "Smith {{GIT_NAME}} Co" in the output.
    # Order matters — the first clause uses `\&` as a backreference, so adding
    # `&` to its character class would break that escape.
    git_name_escaped=$(printf '%s' "$git_name" | sed -e 's/[][\\.*^$()+?{}|]/\\&/g' -e 's/&/\\\&/g')
    git_email_escaped=$(printf '%s' "$git_email" | sed -e 's/[][\\.*^$()+?{}|]/\\&/g' -e 's/&/\\\&/g')
    dotfiles_dir_escaped=$(printf '%s' "$DOTFILES_DIR" | sed -e 's/[][\\.*^$()+?{}|]/\\&/g' -e 's/&/\\\&/g')

    sed -e "s|{{GIT_NAME}}|$git_name_escaped|g" \
        -e "s|{{GIT_EMAIL}}|$git_email_escaped|g" \
        -e "s|{{DOTFILES_DIR}}|$dotfiles_dir_escaped|g" \
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

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
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
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "[DRY RUN] Would ensure Docker apt repo is configured"
        return 0
    fi

    if [[ -f /etc/apt/sources.list.d/docker.list ]]; then
        return 0
    fi

    log "Adding Docker official apt repository..."

    # Remove conflicting distro packages that shadow Docker CE (per Docker's
    # official install guidance). Only removes packages that are present.
    local pkg
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 podman-docker containerd runc; do
        if dpkg -s "$pkg" &>/dev/null; then
            log "Removing conflicting package: $pkg"
            safe_sudo apt-get remove -y "$pkg" || warn "Could not remove $pkg"
        fi
    done

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

    update_packages
    success "Docker apt repository configured"
}

# Install Azure CLI from Microsoft's signed apt repository.
# Replaces the previous `curl https://aka.ms/InstallAzureCLIDeb | sudo bash`,
# which executed an unpinned remote script as root.
install_azure_cli() {
    if command -v az >/dev/null 2>&1; then
        log "Azure CLI already installed"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "[DRY RUN] Would add Microsoft apt repo and install azure-cli"
        return 0
    fi

    log "Installing Azure CLI from Microsoft's signed apt repository..."
    safe_sudo apt-get install -y ca-certificates curl gnupg
    safe_sudo install -m 0755 -d /etc/apt/keyrings

    if [[ ! -f /etc/apt/keyrings/microsoft.gpg ]]; then
        curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
            | gpg --dearmor \
            | safe_sudo tee /etc/apt/keyrings/microsoft.gpg > /dev/null
        safe_sudo chmod a+r /etc/apt/keyrings/microsoft.gpg
    fi

    local codename
    codename=$(lsb_release -cs)
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ $codename main" | \
        safe_sudo tee /etc/apt/sources.list.d/azure-cli.list > /dev/null

    update_packages
    install_apt "azure-cli" azure-cli
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

    # Collect eget tool names from registry
    local -a eget_tools=()
    local name
    for name in "${!TOOL_METHOD[@]}"; do
        [[ "${TOOL_METHOD[$name]}" == "eget" ]] && eget_tools+=("$name")
    done

    if [[ "${FORCE_REINSTALL:-false}" == "true" ]]; then
        log "Force reinstall: clearing eget-managed binaries..."
        for name in "${eget_tools[@]}"; do
            rm -f "$HOME/.local/bin/${TOOL_BINARY[$name]}"
        done
    fi

    # eget was just installed to ~/.local/bin, which is not necessarily on PATH
    # yet on a fresh machine — resolve the binary explicitly rather than relying
    # on PATH. Otherwise every tool download silently fails on the first run.
    local eget_bin="$HOME/.local/bin/eget"
    command -v eget >/dev/null 2>&1 && eget_bin="$(command -v eget)"
    if [[ ! -x "$eget_bin" ]]; then
        error "eget not found at $eget_bin after install"
        return 1
    fi

    # upgrade_only (eget.toml) makes eget skip tools already at their pinned
    # version, so a re-run downloads nothing — the point of this whole function
    # being idempotent. eget's batch exit code doesn't cleanly separate "skipped
    # because up to date" from "failed", so don't trust it: run eget, then judge
    # each tool by whether its binary is actually present on disk.
    EGET_CONFIG="$config" "$eget_bin" --download-all || true

    local any_missing=false
    for name in "${eget_tools[@]}"; do
        if verify_binary "${TOOL_BINARY[$name]}"; then
            track_install "$name" ok
        else
            track_install "$name" fail
            any_missing=true
        fi
    done
    [[ "$any_missing" == true ]] && warn "Some eget tools are missing after install (see summary)"
}

# ==============================================================================
# Tiered Installation Functions
# ==============================================================================

install_shell_packages() {
    log "Installing shell tier packages..."

    # PACKAGES values are intentionally space-separated lists meant to be
    # word-split into the array — the alternative (per-key arrays) would
    # bloat the data file. shellcheck flags this as SC2206; that's expected.
    # shellcheck disable=SC2206
    local packages=(${PACKAGES[core]} ${PACKAGES[development]} ${PACKAGES[modern]} ${PACKAGES[languages]} ${PACKAGES[terminal]})
    # shellcheck disable=SC2206
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

# AI CLIs (Claude Code, Codex, opencode). Orthogonal to the tier chain —
# installed only when --ai/--full or a per-tool flag (--claude/--codex/
# --opencode) is passed. Which tools run is driven by setup.sh's AI_ALL /
# AI_TOOLS globals; AI_ALL expands to every ai-tier tool in the registry, so a
# new AI CLI is picked up automatically once registered. Kept separate so an
# org-managed install can be left untouched — each installer refuses to shadow
# an external binary already on PATH.
install_ai_packages() {
    local -a tools=()
    if [[ "${AI_ALL:-false}" == "true" ]]; then
        readarray -t tools < <(tools_for_tier ai)
    else
        # Individual selections, de-duplicated while preserving order.
        local t
        for t in "${AI_TOOLS[@]:-}"; do
            [[ -z "$t" ]] && continue
            [[ " ${tools[*]-} " == *" $t "* ]] || tools+=("$t")
        done
    fi

    [[ ${#tools[@]} -eq 0 ]] && return 0

    log "Installing AI CLIs: ${tools[*]}"
    local t
    for t in "${tools[@]}"; do
        run_installer "$t"
    done

    success "AI CLIs installation complete"
}

# xfce4 pulls in a display manager (e.g. lightdm). On a machine that already
# runs one, that DM's postinst asks — via debconf — which should be the system
# default. Two hazards: the dialog blocks a scripted install, and answering it
# (even silently, under noninteractive) can switch the console login manager
# away from the one already in use. xrdp needs no DM at all (it starts its own
# X session via ~/.xsession), so the safe move is to pin the answer to whatever
# is already configured, changing nothing. No-op when no DM is configured yet
# (single-DM and headless installs never raise the question).
preserve_default_display_manager() {
    command -v debconf-set-selections >/dev/null 2>&1 || return 0
    local dmfile=/etc/X11/default-display-manager
    [[ -r "$dmfile" ]] || return 0

    local dm_path dm
    dm_path="$(cat "$dmfile" 2>/dev/null || true)"
    [[ -n "$dm_path" ]] || return 0
    dm="$(basename "$dm_path")"
    [[ -n "$dm" && "$dm" != "." ]] || return 0

    log "Preserving current display manager ($dm) across the xfce4 install"
    printf '%s shared/default-x-display-manager select %s\n' "$dm" "$dm" \
        | safe_sudo debconf-set-selections
}

# RDP server (xrdp + XFCE session). Orthogonal to the tier chain — installed
# only when --rdp is passed, and deliberately NOT implied by --full: no tier
# should silently open a network listener. See issues/xrdp-remote-desktop.md.
install_rdp_packages() {
    log "Installing RDP server (xrdp + XFCE session)..."

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "[DRY RUN] Would install rdp APT packages: ${PACKAGES[rdp]}"
        log "[DRY RUN] Would configure xrdp (installers/install-xrdp.sh)"
        return 0
    fi

    # Pin the display-manager answer before apt can ask (see helper above).
    preserve_default_display_manager

    # Deliberately not install_apt: we need a preseeded, fully non-interactive
    # apt run. DEBIAN_FRONTEND=noninteractive suppresses the dialog; DEBIAN_PRIORITY
    # =critical is a second guard so only critical questions could ever surface.
    # env, not a bare assignment, because sudo resets the environment.
    update_packages
    # shellcheck disable=SC2086
    if safe_sudo env DEBIAN_FRONTEND=noninteractive DEBIAN_PRIORITY=critical \
        apt-get install -y ${PACKAGES[rdp]}; then
        success "rdp APT packages installed"
    else
        error "rdp APT package installation failed"
        track_install "xrdp" fail
        return 1
    fi

    # System config + service enablement (idempotent; owns /etc/xrdp edits)
    run_installer "xrdp"

    success "RDP server installation complete"
}

install_work_packages() {
    log "Installing work tier packages..."

    # Azure CLI
    install_azure_cli

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
            # Security disclosure: the docker group is root-equivalent — its
            # members can mount the host filesystem and run privileged containers.
            warn "Note: membership in the 'docker' group grants root-equivalent access to this host."
        else
            warn "Could not add to docker group (try: sudo usermod -aG docker $USER)"
        fi
    fi

    # Enable and start the daemon when systemd is managing the system (native
    # Linux, or WSL with systemd=true). No-op when systemd isn't running.
    if command -v docker >/dev/null 2>&1 && [[ -d /run/systemd/system ]]; then
        safe_sudo systemctl enable --now docker || warn "Could not enable/start docker via systemd"
    fi

    # Verify the daemon is reachable. Non-fatal: docker group membership only
    # takes effect on a new login, and WSL without systemd may need
    # `sudo service docker start`.
    if command -v docker >/dev/null 2>&1 && [[ "${DRY_RUN:-false}" != "true" ]]; then
        if docker info >/dev/null 2>&1; then
            success "Docker daemon is running"
        else
            warn "Docker installed but 'docker info' failed — start the daemon and re-login for group access"
        fi
    fi

    # Version managers (Python is handled by uv, installed in the shell tier)
    run_installer "nvm" true
    # Rust toolchain (userspace, no sudo). Non-critical: unlike node (which
    # underpins the AI CLIs), nothing else in setup depends on it.
    run_installer "rust"

    success "Work tier installation complete"
}
