#!/bin/bash
# Simplified Dotfiles Installation Script
# Clean, direct installation without complexity theater

set -euo pipefail

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Set DOTFILES_DIR before sourcing lib
DOTFILES_DIR="$SCRIPT_DIR"
export DOTFILES_DIR

# Load install library (pulls in runtime.sh + config.sh)
source "$SCRIPT_DIR/lib/install.sh"

# Installation options
INSTALL_TIER="config"  # Default tier: config, shell, dev, work
INSTALL_AI=false       # Orthogonal: install AI CLIs (claude, codex). Off by default.
FORCE_OVERWRITE=false
FORCE_REINSTALL=false
SHOW_HELP=false
DRY_RUN=false
NO_HOOKS=false

# Git identity (optional; falls back to existing config or interactive prompt).
# Read by process_git_config() in lib/install.sh.
DOTFILES_GIT_NAME="${DOTFILES_GIT_NAME:-}"
DOTFILES_GIT_EMAIL="${DOTFILES_GIT_EMAIL:-}"

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                INSTALL_TIER="config"
                shift
                ;;
            --shell)
                INSTALL_TIER="shell"
                shift
                ;;
            --dev)
                INSTALL_TIER="dev"
                shift
                ;;
            --work)
                INSTALL_TIER="work"
                shift
                ;;
            --full)
                # Convenience: everything. Equivalent to --work --ai.
                INSTALL_TIER="work"
                INSTALL_AI=true
                shift
                ;;
            --ai)
                # Orthogonal opt-in; combines with any tier.
                INSTALL_AI=true
                shift
                ;;
            --force)
                FORCE_OVERWRITE=true
                FORCE_REINSTALL=true
                shift
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --no-hooks)
                NO_HOOKS=true
                shift
                ;;
            --git-name)
                DOTFILES_GIT_NAME="$2"
                shift 2
                ;;
            --git-email)
                DOTFILES_GIT_EMAIL="$2"
                shift 2
                ;;
            --help)
                SHOW_HELP=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                SHOW_HELP=true
                shift
                ;;
        esac
    done
}

# Check if current tier includes the required tier level
# AI tooling (claude, codex) is NOT part of this chain — it is gated by the
# orthogonal INSTALL_AI flag so an org-managed AI install can be left alone.
tier_includes() {
    local required="$1"
    case "$INSTALL_TIER" in
        work) return 0 ;;
        dev) [[ "$required" != "work" ]] ;;
        shell) [[ "$required" == "config" || "$required" == "shell" ]] ;;
        config) [[ "$required" == "config" ]] ;;
    esac
}

# Show help information
show_help() {
    cat << EOF
Dotfiles Installation Script - Tiered Installation System

USAGE:
    ./setup.sh [TIER] [OPTIONS]

TIERS (cumulative - each tier includes all previous tiers):
    --config            Symlinks only. Zero installs. No sudo required.
                        Creates symlinks for all configuration files.

    --shell             Config + modern CLI tools. Requires sudo.
                        Installs binary tools via eget (starship, eza, fzf,
                        zoxide, delta, btop, glow, lazygit, uv) plus APT
                        packages (bat, fd, ripgrep, direnv).

    --dev               Shell + development tools. Requires sudo.
                        Adds: neovim, tmux

    --work              Dev + heavier environment tooling. Requires sudo.
                        Adds: NVM, Docker, Azure CLI
                        (Everything except the AI CLIs — for machines where an
                        org manages the Claude/Codex install.)

    --full              Everything: --work plus the AI CLIs. Requires sudo.
                        Equivalent to: --work --ai

AI TOOLING (orthogonal - combines with any tier):
    --ai                Install the AI CLIs (Claude Code, Codex) into
                        ~/.local/bin. Leave this off when your org manages the
                        install; the shell aliases/shortcuts load either way and
                        resolve whatever 'claude'/'codex' is on PATH.

OPTIONS:
    --force             Force overwrite configs and reinstall tools
    --dry-run           Preview actions without making changes
    --no-hooks          Don't install dotfiles git hooks (pre-commit lint)
    --git-name NAME     Set git user.name (for non-interactive installs)
    --git-email EMAIL   Set git user.email (for non-interactive installs)
    --help              Show this help message

ENVIRONMENT:
    DOTFILES_GIT_NAME   Same as --git-name
    DOTFILES_GIT_EMAIL  Same as --git-email

EXAMPLES:
    ./setup.sh                       # Default: config tier (symlinks only)
    ./setup.sh --config              # Explicit config tier
    ./setup.sh --shell               # Modern shell experience
    ./setup.sh --dev                 # Development setup (no AI CLIs)
    ./setup.sh --dev --ai            # Development setup + self-managed AI CLIs
    ./setup.sh --work                # Full environment, org manages AI
    ./setup.sh --full                # Absolutely everything (--work --ai)
    ./setup.sh --shell --dry-run     # Preview shell tier installation

TIER SUMMARY:
    ┌──────────┬─────────────────────────────────────────────────┬───────────┐
    │ Tier     │ What It Installs                                │ Sudo?     │
    ├──────────┼─────────────────────────────────────────────────┼───────────┤
    │ config   │ Symlinks only (zero installs)                   │ No        │
    │ shell    │ + eget, starship, eza, fzf, zoxide, delta,      │ Yes       │
    │          │   btop, glow, lazygit, uv, bat, fd, ripgrep     │           │
    │ dev      │ + neovim, tmux                                  │ Yes       │
    │ work     │ + NVM, Docker, Azure CLI                        │ Yes       │
    ├──────────┼─────────────────────────────────────────────────┼───────────┤
    │ --ai     │ + Claude Code, Codex (orthogonal flag)          │ No*       │
    │ --full   │ = work + ai (everything)                        │ Yes       │
    └──────────┴─────────────────────────────────────────────────┴───────────┘
    * --ai installs into ~/.local/bin and needs no sudo on its own.

The script will:
1. Verify system requirements
2. Install packages based on selected tier
3. Create symlinks for all configuration files
4. Setup WSL integration if running on WSL

All configuration files are backed up before being replaced.
EOF
}


# Phase 1: System Verification
phase_verify_system() {
    log "Phase 1: System Verification"

    # Check Ubuntu - soft requirement for config tier, hard for others
    if ! command -v lsb_release >/dev/null 2>&1; then
        if tier_includes "shell"; then
            error "This script requires Ubuntu for package installation"
            exit 1
        else
            warn "Not running on Ubuntu - proceeding with config-only mode"
        fi
    fi

    # Check basic tools that should exist
    for cmd in curl wget git; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            if tier_includes "shell"; then
                error "Required command not found: $cmd"
                exit 1
            else
                warn "Command not found: $cmd (not required for config tier)"
            fi
        fi
    done

    detect_environment

    # Generate locale if not present (skip for config tier - requires sudo)
    if tier_includes "shell" && [[ "$DRY_RUN" != "true" ]]; then
        if ! locale -a | grep -qi "en_US.utf8"; then
            log "Generating en_US.UTF-8 locale..."
            if safe_sudo locale-gen en_US.UTF-8 && safe_sudo update-locale LANG=en_US.UTF-8; then
                success "Locale generated"
            else
                warn "Locale generation failed - some shell features may not work correctly"
            fi
        fi
    fi

    success "System verification complete"
}

# Phase 2: Package Installation
phase_install_packages() {
    log "Phase 2: Package Installation"

    # Nothing to install for a bare config tier with no --ai.
    if ! tier_includes "shell" && [[ "$INSTALL_AI" != "true" ]]; then
        log "Config tier: skipping package installation"
        return 0
    fi

    if tier_includes "shell"; then
        install_shell_packages
    fi

    if tier_includes "dev"; then
        install_dev_packages
    fi

    if tier_includes "work"; then
        install_work_packages
    fi

    # AI CLIs are orthogonal to the tier chain (--ai, or --full which implies it).
    if [[ "$INSTALL_AI" == "true" ]]; then
        install_ai_packages
    fi

    success "Package installation complete"
}

# Phase 3: Configuration and Validation
phase_setup_configs() {
    log "Phase 3: Configuration and Validation"
    
    # Single backup directory for this installation
    local backup_dir
    backup_dir=$(create_backup_dir)
    log "Backup directory: $backup_dir"
    
    # Process configurations
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would process configurations:"
        readarray -t sorted_configs < <(printf '%s\n' "${!CONFIG_MAP[@]}" | sort)
        for config in "${sorted_configs[@]}"; do
            local mapping="${CONFIG_MAP[$config]}"
            local target="${mapping%%:*}"
            local type="${mapping##*:}"
            if [[ -e "$target" ]]; then
                if [[ -L "$target" ]]; then
                    log "  ↻ $target (symlink exists - would update)"
                else
                    log "  ⚠️  $target (file exists - would backup)"
                fi
            else
                log "  ✓ $target (would create $type)"
            fi
        done
        is_wsl && log "[DRY RUN] Would setup WSL clipboard integration"
    else
        readarray -t sorted_configs < <(printf '%s\n' "${!CONFIG_MAP[@]}" | sort)
        for config in "${sorted_configs[@]}"; do
            local mapping="${CONFIG_MAP[$config]}"
            local target="${mapping%%:*}"
            local type="${mapping##*:}"
            local source
            source="$(config_source_path "$config")"
            
            case "$type" in
                symlink)
                    process_symlink "$source" "$target" "$backup_dir"
                    ;;
                gitconfig)
                    process_git_config "$source" "$target" "$backup_dir" "$FORCE_OVERWRITE"
                    ;;
                *)
                    error "Unknown config type: $type for $config"
                    ;;
            esac
        done
    fi
    
    # WSL-specific setup
    if is_wsl && [[ "$DRY_RUN" != "true" ]]; then
        setup_wsl_clipboard
    fi

    # Initialize default theme if none is set (theme-switcher owns the default)
    if [[ "$DRY_RUN" == "true" ]]; then
        if [[ ! -f "$DOTFILES_DIR/generated/theme.sh" ]]; then
            log "[DRY RUN] Would initialize default theme"
        fi
    else
        "$DOTFILES_DIR/bin/theme-switcher" --init
    fi

    # Install pre-commit git hooks (default: on; opt out with --no-hooks).
    # Idempotent and safe — refuses to clobber an unrelated existing hook.
    if [[ "$NO_HOOKS" == "true" ]]; then
        log "Skipping git hooks install (--no-hooks)"
    elif [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would install git hooks (use --no-hooks to skip)"
    else
        "$DOTFILES_DIR/bin/install-git-hooks" --quiet || warn "git hooks install failed"
    fi

    # Write install-time environment to generated/bridge.sh
    write_dotfiles_env

    # Cleanup
    cleanup_old_backups 10

    success "Configuration complete"
}

# Process symlink configuration
process_symlink() {
    local source="$1" target="$2" backup_dir="$3"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would link $source -> $target"
        return 0
    fi
    
    # Create parent directory if needed
    local parent_dir
    parent_dir="$(dirname "$target")"
    if [[ ! -d "$parent_dir" ]]; then
        mkdir -p "$parent_dir"
    fi

    # SSH directory requires strict permissions
    if [[ "$parent_dir" == *"/.ssh"* || "$parent_dir" == *"/.ssh" ]]; then
        chmod 700 "$parent_dir"
        mkdir -p "$parent_dir/sockets"
        chmod 700 "$parent_dir/sockets"
    fi
    
    safe_symlink "$source" "$target" "$backup_dir"
}

# Main installation workflow
run_installation() {
    phase_verify_system
    phase_install_packages
    phase_setup_configs

    # Show what happened with tool installs
    print_install_summary

    # Success message
    echo
    success "Dotfiles installation complete! (tier: $INSTALL_TIER$([[ "$INSTALL_AI" == "true" ]] && echo " +ai"))"
    echo

    # Post-installation instructions
    local needs_restart=false

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Next Steps:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    # Check if Docker group was added (work tier only)
    if tier_includes "work" && command -v docker >/dev/null 2>&1; then
        if grep "^docker:" /etc/group | grep -q "\b$USER\b"; then
            if ! groups | grep -q docker; then
                echo "* Docker group membership requires restart"
                needs_restart=true
            fi
        fi
    fi

    # Check if NVM was installed (work tier only)
    local nvm_installed=false
    if tier_includes "work" && [[ -d "$HOME/.nvm" ]]; then
        nvm_installed=true
    fi

    # Restart recommendation based on tier
    local step=1
    if tier_includes "shell"; then
        echo "$step. Restart your shell session:"
        if is_wsl; then
            echo "   - Type 'exit' then reopen WSL, OR"
            echo "   - From PowerShell/CMD: wsl --terminate Ubuntu"
        else
            echo "   - Type 'exit' then reconnect to your terminal"
        fi
        if [[ "$needs_restart" == "true" ]]; then
            echo "   (Required for Docker group and locale changes)"
        else
            echo "   (Recommended for locale and shell changes)"
        fi
        echo
        ((step++))
    fi

    echo "$step. Verify installation:"
    echo "   ./bin/verify"
    echo
    ((step++))

    # WSL personal machines: nudge toward the Windows SSH agent bridge.
    if is_wsl && tier_includes "shell"; then
        echo "$step. (Personal WSL) Use your Windows SSH agent (Bitwarden/1Password):"
        echo "   ./bin/ssh-bridge enable     # bridges vault keys into WSL, then reload"
        echo "   (Work machines using local keys: skip — leave it disabled.)"
        echo
        ((step++))
    fi

    if [[ "$nvm_installed" == "true" ]]; then
        echo "$step. Test Node.js/npm:"
        echo "   node --version && npm --version"
        echo
        ((step++))
    fi

    echo "$step. Switch theme (default: gruvbox):"
    echo "   ./bin/theme-switcher"

    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# Main entry point
main() {
    # Refuse to run as root. The installer writes throughout $HOME, configures
    # the invoking user's group membership (docker), and calls sudo only where
    # a step genuinely needs it. Running as root would target /root and grant
    # root's groups instead.
    if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
        echo "Error: do not run setup.sh as root." >&2
        echo "Run it as your normal user; the script invokes sudo only where required." >&2
        exit 1
    fi

    # Parse command line arguments
    parse_arguments "$@"
    
    # Show help if requested
    if [[ "$SHOW_HELP" == "true" ]]; then
        show_help
        exit 0
    fi
    
    # Show banner
    echo "Dotfiles Installation"
    echo "===================================="
    echo "Target: Ubuntu (including WSL)"
    echo "Tier: $INSTALL_TIER"
    echo "AI CLIs (claude, codex): $([[ "$INSTALL_AI" == "true" ]] && echo "yes (--ai)" || echo "no")"
    [[ "$DRY_RUN" == "true" ]] && echo "Mode: DRY RUN (no changes will be made)"
    echo
    
    # Run installation
    run_installation
}

# Execute main function
main "$@"