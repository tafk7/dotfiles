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
INSTALL_TIER="config"  # Base when only orthogonal flags are given: config, bash, dev, work
INSTALL_AI=false       # Orthogonal: any AI CLI requested (--ai or a per-tool flag).
AI_ALL=false           # --ai / --full: install every AI-capability tool.
declare -a AI_TOOLS=() # Individual AI selections: --claude / --codex / --opencode / --pi.
INSTALL_RDP=false      # Orthogonal: xrdp RDP server. Off by default; NOT implied by --full.
INSTALL_TAIL=false     # Orthogonal: Tailscale package/service; no enrollment.
INSTALL_AZURE=false
INSTALL_GCLOUD=false
INSTALL_AWS=false
THEME_REQUEST=""       # Empty preserves preference; enabled/disabled are explicit changes.
AGENT_BADGE_REQUEST=""
FORCE_OVERWRITE=false
FORCE_REINSTALL=false
SHOW_HELP=false
DRY_RUN=false
NO_HOOKS=false
NO_GIT=false          # --no-git: skip ~/.gitconfig entirely (no prompt, no write).
PARSE_ERROR=false

tier_rank() {
    case "$1" in
        config) echo 0 ;;
        bash) echo 1 ;;
        dev) echo 2 ;;
        work) echo 3 ;;
        *) return 1 ;;
    esac
}

request_tier() {
    local requested="$1" current_rank requested_rank
    current_rank="$(tier_rank "$INSTALL_TIER")"
    requested_rank="$(tier_rank "$requested")"
    if (( requested_rank > current_rank )); then
        INSTALL_TIER="$requested"
    fi
}

require_option_value() {
    local option="$1" value="${2:-}"
    if [[ -z "$value" || "$value" == --* ]]; then
        error "$option requires a value"
        PARSE_ERROR=true
        return 1
    fi
}

# Git identity (optional; falls back to existing config or interactive prompt).
# Read by process_git_config() in lib/install.sh.
DOTFILES_GIT_NAME="${DOTFILES_GIT_NAME:-}"
DOTFILES_GIT_EMAIL="${DOTFILES_GIT_EMAIL:-}"

# Parse command line arguments
parse_arguments() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --config)
                # Reconcile action: lay down base configs + configs for whatever
                # tools are currently installed. No package installs, no sudo.
                request_tier "config"
                shift
                ;;
            --bash)
                request_tier "bash"
                shift
                ;;
            --dev)
                request_tier "dev"
                shift
                ;;
            --work)
                request_tier "work"
                shift
                ;;
            --full)
                # Convenience: exactly --work --ai.
                request_tier "work"
                INSTALL_AI=true
                AI_ALL=true
                shift
                ;;
            --ai)
                # Orthogonal opt-in; combines with any tier. Installs every
                # AI-capability tool; use the per-tool flags below to pick individually.
                INSTALL_AI=true
                AI_ALL=true
                shift
                ;;
            --claude|--codex|--opencode|--pi)
                # Per-tool AI selection (orthogonal; composes with any tier).
                INSTALL_AI=true
                AI_TOOLS+=("${1#--}")
                shift
                ;;
            --rdp)
                # Orthogonal opt-in; combines with any tier. Never implied by
                # --full — installing it opens a network listener.
                INSTALL_RDP=true
                shift
                ;;
            --tail)
                INSTALL_TAIL=true
                shift
                ;;
            --azure)
                INSTALL_AZURE=true
                shift
                ;;
            --gcloud)
                INSTALL_GCLOUD=true
                shift
                ;;
            --aws)
                INSTALL_AWS=true
                shift
                ;;
            --theme)
                THEME_REQUEST="enabled"
                shift
                ;;
            --no-theme)
                THEME_REQUEST="disabled"
                shift
                ;;
            --agent-badge)
                AGENT_BADGE_REQUEST="enabled"
                shift
                ;;
            --no-agent-badge)
                AGENT_BADGE_REQUEST="disabled"
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
            --no-git)
                NO_GIT=true
                shift
                ;;
            --git-name)
                require_option_value "$1" "${2:-}" || { shift; continue; }
                DOTFILES_GIT_NAME="$2"
                shift 2
                ;;
            --git-email)
                require_option_value "$1" "${2:-}" || { shift; continue; }
                DOTFILES_GIT_EMAIL="$2"
                shift 2
                ;;
            --help)
                SHOW_HELP=true
                shift
                ;;
            *)
                error "Unknown option: $1"
                PARSE_ERROR=true
                shift
                ;;
        esac
    done
    [[ "$PARSE_ERROR" == "false" ]]
}

# Check if current tier includes the required tier level.
# Cumulative chain: config → bash → dev → work. The sudo boundary sits at dev
# (bash is eget-only, no root). AI tooling (claude, codex) is NOT part of this
# chain — it is gated by the orthogonal INSTALL_AI flag so an org-managed AI
# install can be left alone.
tier_includes() {
    local required="$1"
    case "$INSTALL_TIER" in
        work) return 0 ;;
        dev) [[ "$required" != "work" ]] ;;
        bash) [[ "$required" == "config" || "$required" == "bash" ]] ;;
        config) [[ "$required" == "config" ]] ;;
    esac
}

capability_selected() {
    case "$1" in
        ai) [[ "$INSTALL_AI" == true ]] ;;
        rdp) [[ "$INSTALL_RDP" == true ]] ;;
        tail) [[ "$INSTALL_TAIL" == true ]] ;;
        azure) [[ "$INSTALL_AZURE" == true ]] ;;
        gcloud) [[ "$INSTALL_GCLOUD" == true ]] ;;
        aws) [[ "$INSTALL_AWS" == true ]] ;;
        *) return 1 ;;
    esac
}

component_selected() {
    local name="$1" capability
    tool_in_cumulative_tier "$name" "$INSTALL_TIER" && return 0
    for capability in ai rdp tail azure gcloud aws; do
        capability_selected "$capability" && tool_has_capability "$name" "$capability" && return 0
    done
    return 1
}

# Show help information
show_help() {
    cat << 'EOF'
Dotfiles Installation Script - Tiered Installation System

USAGE:
    ./setup.sh <TIER|ACTION> [OPTIONS]

    Bare `./setup.sh` (no arguments) prints this help and changes nothing —
    installing packages and rewriting $HOME configs must always be explicit.

    --config            Reconcile action: (re)create symlinks for base configs
                        plus configs for whatever tools are already installed.
                        Zero package installs. No sudo. Safe to re-run anytime —
                        it syncs your symlinks to what's actually on the system.

TIERS (cumulative - each tier includes all previous tiers):
    --bash              Config + modern CLI tools. NO SUDO — every tool installs
                        to ~/.local/bin via eget: starship, eza, fzf, zoxide,
                        delta, btop, gdu, glow, lazygit, gh, uv, sd, bat, fd,
                        ripgrep, direnv. The non-sudo base for managed systems.
                        (git is assumed present; a tool already installed
                        system-wide is left alone unless --force.)

    --dev               Bash + development tools. Requires sudo (first APT layer).
                        Adds APT: zsh, build tools, clipboard, graphviz, etc.
                        Adds: neovim, tmux

    --work              Dev + local development/agent execution. Requires sudo.
                        Adds: NVM, Docker, sbx, KVM host access, Rust
                        Requires native Ubuntu 24.04/26.04 with KVM available
                        for local sandbox readiness.
                        AI, Tailscale, RDP, and cloud CLIs stay orthogonal; leave
                        AI off where an organization manages those CLIs.

    --full              Work tier plus all AI CLIs. Requires sudo.
                        Equivalent to: --work --ai

AI TOOLING (orthogonal - combines with any tier):
    --ai                Install ALL AI CLIs (Claude Code, Codex, opencode, Pi) into
                        ~/.local/bin. Leave this off when your org manages the
                        install; the shell aliases/shortcuts load either way and
                        resolve whatever binary is on PATH.
    --claude            Install only Claude Code.
    --codex             Install only Codex.
    --opencode          Install only opencode.
    --pi                Install only Pi. Unlike the others Pi is an npm package,
                        so it needs Node >=22.19 (the work tier's NVM provides
                        it); the requested install fails with instructions if
                        Node is missing rather than pulling in a toolchain.
                        (Per-tool flags combine: --claude --opencode installs
                        just those two. --ai / --full install all of them.)

RDP SERVER (orthogonal - combines with any tier):
    --rdp               Install + configure the xrdp RDP server with an XFCE
                        session. Requires sudo. NOT implied by --full (opens a
                        WSL: listens on localhost:3390 for the Windows host
                        (connect with mstsc). Native: port 3389 — keep it
                        behind a VPN/firewall. See issues/xrdp-remote-desktop.md.

TAILSCALE AND CLOUD (orthogonal - combine with any tier):
    --tail              Install Tailscale and enable tailscaled under systemd.
                        Does not enroll, configure routes/SSH, or change firewall
                        policy. Requires sudo on Ubuntu 22.04/24.04/26.04.
    --azure             Azure CLI + Azure DevOps Git credential integration.
    --gcloud            Google Cloud CLI from Google's signed APT repository.
    --aws               AWS CLI v2 from AWS's signature-verified distribution.
                        These selections require sudo independently of the tier.

OPTIONS:
    --force             Force overwrite configs and reinstall tools
    --dry-run           Preview actions without making changes
    --no-hooks          Don't install dotfiles git hooks (pre-commit lint)
    --no-git            Skip ~/.gitconfig (no identity prompt; leaves any existing
                        one alone). Also skips the delta pager wiring.
    --theme             Enable the coordinated theme feature (default).
    --no-theme          Persistently disable theme generation and runtime hooks.
    --agent-badge       Enable agent-badge for supported AI CLIs (default with AI).
    --no-agent-badge    Install AI CLIs without registering agent-badge.
    --git-name NAME     Set git user.name (for non-interactive installs)
    --git-email EMAIL   Set git user.email (for non-interactive installs)
    --help              Show this help message

ENVIRONMENT:
    DOTFILES_GIT_NAME   Same as --git-name
    DOTFILES_GIT_EMAIL  Same as --git-email
    DOTFILES_APT_LOCK_TIMEOUT
                        Seconds APT waits for another package operation (default: 120)

EXAMPLES:
    ./setup.sh                       # Prints this help; changes nothing
    ./setup.sh --config              # Reconcile symlinks to installed tools
    ./setup.sh --bash                # Modern shell experience, NO sudo
    ./setup.sh --dev                 # Development setup (no AI CLIs)
    ./setup.sh --dev --ai            # Development setup + all AI CLIs
    ./setup.sh --dev --claude        # Development setup + only Claude Code
    ./setup.sh --claude --opencode   # Config + just those two AI CLIs
    ./setup.sh --work                # Local work environment, AI stays separate
    ./setup.sh --full                # Exactly --work --ai
    ./setup.sh --work --tail         # Local sbx work environment + Tailscale
    ./setup.sh --work --claude --codex --tail
    ./setup.sh --full --tail --gcloud
    ./setup.sh --work --azure        # Former --work cloud-tool behavior
    ./setup.sh --dev --rdp           # Dev setup + RDP into this machine's desktop
    ./setup.sh --bash --dry-run      # Preview bash tier installation

TIER SUMMARY:
    ┌──────────┬─────────────────────────────────────────────────┬───────────┐
    │ Tier     │ What It Installs                                │ Sudo?     │
    ├──────────┼─────────────────────────────────────────────────┼───────────┤
    │ config   │ Symlinks only (reconcile to installed tools)    │ No        │
    │ bash     │ + eget: starship, eza, fzf, zoxide, delta, btop,│ No        │
    │          │   gdu, glow, lazygit, gh, uv, sd, bat, fd,      │           │
    │          │   ripgrep, direnv  (all to ~/.local/bin)        │           │
    │ dev      │ + zsh, build tools, clipboard, neovim, tmux     │ Yes       │
    │ work     │ + NVM, Docker, sbx, KVM access, Rust            │ Yes       │
    ├──────────┼─────────────────────────────────────────────────┼───────────┤
    │ --ai     │ + Claude Code, Codex, opencode, Pi (orthogonal) │ No        │
    │          │   (or --claude/--codex/--opencode/--pi singly)  │           │
    │ --rdp    │ + xrdp server + XFCE desktop (orthogonal flag)  │ Yes       │
    │ --tail   │ + Tailscale package/service (no enrollment)     │ Yes       │
    │ cloud    │ --azure / --gcloud / --aws                      │ Yes       │
    │ --full   │ = work + ai (no Tailscale, RDP, or cloud CLIs)  │ Yes       │
    └──────────┴─────────────────────────────────────────────────┴───────────┘
    The tier sudo boundary is at dev. Tailscale, RDP, and APT-backed cloud
    selections require sudo independently of the selected tier.

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

    # Check the distribution identity, not merely whether lsb_release happens
    # to be installed on an unrelated distribution.
    local os_release="${DOTFILES_OS_RELEASE:-/etc/os-release}" os_id="" os_version=""
    if [[ -r "$os_release" ]]; then
        os_id="$(awk -F= '$1 == "ID" { gsub(/^"|"$/, "", $2); print $2; exit }' "$os_release")"
        os_version="$(awk -F= '$1 == "VERSION_ID" { gsub(/^"|"$/, "", $2); print $2; exit }' "$os_release")"
    fi
    if [[ "$os_id" != "ubuntu" ]]; then
        if tier_includes "dev" || [[ "$INSTALL_RDP" == true || "$INSTALL_TAIL" == true || "$INSTALL_AZURE" == true || "$INSTALL_GCLOUD" == true || "$INSTALL_AWS" == true ]]; then
            error "APT-backed tiers, Tailscale, RDP, and cloud selections require Ubuntu (detected: ${os_id:-unknown})"
            return 1
        fi
        warn "Ubuntu not detected - APT-backed features are unavailable"
    elif [[ "$os_version" != 22.04 && "$os_version" != 24.04 && "$os_version" != 26.04 ]]; then
        if tier_includes "dev" || [[ "$INSTALL_RDP" == true || "$INSTALL_TAIL" == true || "$INSTALL_AZURE" == true || "$INSTALL_GCLOUD" == true || "$INSTALL_AWS" == true ]]; then
            error "Unsupported Ubuntu release: ${os_version:-unknown} (supported: 22.04, 24.04, 26.04)"
            return 1
        fi
        warn "Ubuntu ${os_version:-unknown} is outside the tested support matrix"
    fi
    get_arch >/dev/null || return 1
    if is_wsl && [[ "$(wsl_version)" != 2 ]]; then
        error "WSL1 is unsupported; use WSL2"
        return 1
    fi

    # Check basic tools that should exist. The bash tier needs curl (eget
    # bootstrap + downloads) and git; apt is not involved until the dev tier.
    for cmd in curl git; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            if tier_includes "bash" || { [[ "$cmd" == curl && ( "$INSTALL_AI" == true || "$INSTALL_TAIL" == true || "$INSTALL_AZURE" == true || "$INSTALL_GCLOUD" == true || "$INSTALL_AWS" == true ) ]]; }; then
                error "Required command not found: $cmd"
                return 1
            else
                warn "Command not found: $cmd (not required for config tier)"
            fi
        fi
    done
    if [[ "$INSTALL_RDP" == true || "$INSTALL_TAIL" == true || "$INSTALL_AZURE" == true || "$INSTALL_GCLOUD" == true || "$INSTALL_AWS" == true ]]; then
        for cmd in apt-get sudo systemctl; do
            [[ "$cmd" != systemctl || "$INSTALL_RDP" == true ]] || continue
            command -v "$cmd" >/dev/null 2>&1 || { error "Requested APT/service capability requires: $cmd"; return 1; }
        done
    fi

    local capability component
    if tier_includes work && ! tool_applicable sbx; then
        error "--work requires native Ubuntu 24.04/26.04 with supported KVM architecture"
        return 1
    fi

    for capability in tail azure gcloud aws; do
        capability_selected "$capability" || continue
        while IFS= read -r component; do
            tool_applicable "$component" || {
                error "--$capability is unsupported on ${os_id:-unknown} ${os_version:-unknown}/$(tool_arch 2>/dev/null || printf unknown) ($component is not applicable)"
                return 1
            }
        done < <(tools_for_capability "$capability")
    done

    detect_environment

    success "System verification complete"
}

# Phase 2: Package Installation
phase_install_packages() {
    log "Phase 2: Package Installation"

    # Nothing to install for a bare config tier with no orthogonal flags.
    if ! tier_includes "bash" && [[ "$INSTALL_AI" != true && "$INSTALL_RDP" != true && "$INSTALL_TAIL" != true && "$INSTALL_AZURE" != true && "$INSTALL_GCLOUD" != true && "$INSTALL_AWS" != true ]]; then
        log "Config tier: skipping package installation"
        return 0
    fi

    if tier_includes "bash"; then
        install_bash_packages || INSTALLATION_FAILED=true
    fi

    if tier_includes "dev"; then
        install_dev_packages || INSTALLATION_FAILED=true
    fi

    if tier_includes "work"; then
        install_work_packages || INSTALLATION_FAILED=true
    fi

    # AI CLIs are orthogonal to the tier chain (--ai, or --full which implies it).
    if [[ "$INSTALL_AI" == "true" ]]; then
        install_ai_packages || INSTALLATION_FAILED=true
    fi

    # RDP server is orthogonal too, and NOT implied by --full.
    if [[ "$INSTALL_RDP" == "true" ]]; then
        install_rdp_packages || INSTALLATION_FAILED=true
    fi

    [[ "$INSTALL_TAIL" != true ]] || install_tail_packages || INSTALLATION_FAILED=true

    [[ "$INSTALL_AZURE" != true ]] || install_cloud_capability azure || INSTALLATION_FAILED=true
    [[ "$INSTALL_GCLOUD" != true ]] || install_cloud_capability gcloud || INSTALLATION_FAILED=true
    [[ "$INSTALL_AWS" != true ]] || install_cloud_capability aws || INSTALLATION_FAILED=true

    if [[ "$INSTALLATION_FAILED" == "true" ]]; then
        error "One or more requested package operations failed"
        return 1
    fi
    success "Package installation complete"
}

# Phase 3: Configuration and Validation
phase_setup_configs() {
    log "Phase 3: Configuration and Validation"
    local failed=false
    
    # Backups are created lazily by the first operation that actually displaces
    # user data. Matching symlinks and dry-runs create no backup directories.
    ACTIVE_BACKUP_DIR=""
    
    # Process configurations
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would process configurations:"
        readarray -t sorted_configs < <(printf '%s\n' "${!CONFIG_MAP[@]}" | sort)
        for config in "${sorted_configs[@]}"; do
            local mapping="${CONFIG_MAP[$config]}"
            local target type owner
            IFS=: read -r target type owner <<< "$mapping"
            if ! config_owner_present "$owner"; then
                log "  ⊘ $target (skipped — $owner not installed)"
                continue
            fi
            if [[ "$type" == "gitconfig" && "$NO_GIT" == "true" ]]; then
                log "  ⊘ $target (skipped — --no-git)"
                continue
            fi
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
        is_wsl && [[ -f "$HOME/.ssh/use-windows-agent" ]] && log "[DRY RUN] Would install the WSL ssh-agent bridge service (marker present)"
    else
        readarray -t sorted_configs < <(printf '%s\n' "${!CONFIG_MAP[@]}" | sort)
        for config in "${sorted_configs[@]}"; do
            local mapping="${CONFIG_MAP[$config]}"
            local target type owner
            IFS=: read -r target type owner <<< "$mapping"

            # Skip configs whose owning tool isn't present, so a bare/partial
            # install never lays down orphaned configs (see config_owner_present).
            if ! config_owner_present "$owner"; then
                log "Skipping $target — $owner not installed"
                continue
            fi

            local source
            source="$(config_source_path "$config")"

            case "$type" in
                symlink)
                    if process_symlink "$source" "$target"; then
                        ledger_record "config.${config//\//.}" yes dotfiles installed "" "$target" symlink || failed=true
                    else
                        failed=true
                    fi
                    ;;
                gitconfig)
                    if [[ "$NO_GIT" == "true" ]]; then
                        log "Skipping $target (--no-git)"
                    else
                        if process_git_config "$source" "$target" "$FORCE_OVERWRITE"; then
                            ledger_record config.git yes dotfiles installed "" \
                                "${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles/gitconfig" include || failed=true
                        else
                            failed=true
                        fi
                    fi
                    ;;
                *)
                    error "Unknown config type: $type for $config"
                    failed=true
                    ;;
            esac
        done
    fi
    
    # WSL-specific setup
    if is_wsl && [[ "$DRY_RUN" != "true" ]]; then
        setup_wsl_clipboard || failed=true
        setup_wsl_ssh_agent || failed=true
    fi

    # Initialize theme artifacts only when the feature is enabled. Persistent
    # preference handling is centralized in lib/state.sh.
    if feature_enabled theme; then
        if [[ "$DRY_RUN" == "true" ]]; then
            log "[DRY RUN] Would initialize theme feature"
        else
            "$DOTFILES_DIR/bin/theme-switcher" --init || failed=true
        fi
    else
        log "Theme feature disabled; skipping generated artifacts"
        [[ "$DRY_RUN" == "true" ]] || "$DOTFILES_DIR/bin/theme-switcher" tmux-unwire || failed=true
    fi

    # Install pre-commit git hooks (default: on; opt out with --no-hooks).
    # Idempotent and safe — refuses to clobber an unrelated existing hook.
    if [[ "$NO_HOOKS" == "true" ]]; then
        log "Skipping git hooks install (--no-hooks)"
    elif [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would install git hooks (use --no-hooks to skip)"
    else
        "$DOTFILES_DIR/bin/install-git-hooks" --quiet || { warn "git hooks install failed"; failed=true; }
    fi

    # Record the checkout location and WSL details in data-only XDG state.
    write_dotfiles_env || failed=true
    reconcile_observed_components || failed=true

    # Cleanup
    if [[ "$DRY_RUN" != "true" && -n "${ACTIVE_BACKUP_DIR:-}" ]]; then
        cleanup_old_backups 10
    fi

    if [[ "$failed" == true ]]; then
        error "Configuration reconciliation failed"
        return 1
    fi
    success "Configuration complete"
}

# Process symlink configuration
process_symlink() {
    local source="$1" target="$2"
    
    if [[ "$DRY_RUN" == "true" ]]; then
        log "[DRY RUN] Would link $source -> $target"
        return 0
    fi
    
    # Create parent directory if needed
    local parent_dir
    parent_dir="$(dirname "$target")"
    if [[ ! -d "$parent_dir" ]]; then
        mkdir -p "$parent_dir" || return 1
    fi

    # SSH directory requires strict permissions
    if [[ "$parent_dir" == *"/.ssh"* || "$parent_dir" == *"/.ssh" ]]; then
        chmod 700 "$parent_dir" || return 1
        mkdir -p "$parent_dir/sockets" || return 1
        chmod 700 "$parent_dir/sockets" || return 1
    fi
    
    safe_symlink "$source" "$target"
}

# Main installation workflow
run_installation() {
    INSTALLATION_FAILED=false
    if journal_pending; then
        if [[ "$DRY_RUN" == true ]]; then
            warn "Incomplete component transaction detected; dry-run will not reconcile it."
        else
            warn "Recovering an interrupted component transaction before setup."
            journal_reconcile || INSTALLATION_FAILED=true
        fi
    fi
    phase_verify_system || INSTALLATION_FAILED=true
    if [[ "$INSTALLATION_FAILED" != "true" ]]; then
        apply_feature_requests || INSTALLATION_FAILED=true
    fi
    if [[ "$INSTALLATION_FAILED" != "true" ]]; then
        phase_install_packages || INSTALLATION_FAILED=true
        phase_setup_configs || INSTALLATION_FAILED=true
    fi

    # Show what happened with tool installs
    print_install_summary

    if [[ "$INSTALLATION_FAILED" == "true" || ${#INSTALL_FAIL[@]} -gt 0 ]]; then
        echo
        error "Dotfiles installation incomplete; see the summary above."
        return 1
    fi

    # Success message
    echo
    success "Dotfiles installation complete! (tier: $INSTALL_TIER$([[ "$INSTALL_AI" == true ]] && echo " +ai")$([[ "$INSTALL_RDP" == true ]] && echo " +rdp")$([[ "$INSTALL_TAIL" == true ]] && echo " +tail")$([[ "$INSTALL_AZURE" == true ]] && echo " +azure")$([[ "$INSTALL_GCLOUD" == true ]] && echo " +gcloud")$([[ "$INSTALL_AWS" == true ]] && echo " +aws"))"
    echo

    # Post-installation instructions
    local needs_restart=false

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Next Steps:"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo

    # Check if Docker group was added (work tier only)
    if tier_includes "work" && command -v docker >/dev/null 2>&1; then
        if [[ "$(host_group_state docker)" == pending ]]; then
                echo "* Docker group membership requires restart"
                needs_restart=true
        fi
    fi

    if tier_includes "work" && [[ "$(host_group_state kvm)" == pending ]]; then
        echo "* KVM group membership requires a new login"
        needs_restart=true
    fi

    # Check if NVM was installed (work tier only)
    local nvm_installed=false
    if tier_includes "work" && [[ -d "$HOME/.nvm" ]]; then
        nvm_installed=true
    fi

    # Restart recommendation based on tier
    local step=1
    if tier_includes "bash"; then
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
    if tier_includes "work"; then
        if [[ "$INSTALL_TAIL" == true ]]; then
            echo "   ./bin/verify --tier work --tail"
        else
            echo "   ./bin/verify --tier work"
        fi
    else
        echo "   ./bin/verify"
    fi
    echo
    ((step++))

    if tier_includes "work"; then
        echo "$step. Authenticate and smoke-test local sandboxes manually:"
        echo "   sbx login"
        echo "   ./bin/verify --tier work --smoke"
        echo
        ((step++))
    fi

    if [[ "$INSTALL_TAIL" == true ]]; then
        echo "$step. Enroll Tailscale with your intended routing/SSH policy:"
        echo "   sudo tailscale up"
        echo
        ((step++))
    fi

    # RDP connect instructions (port/security depend on WSL vs native).
    if [[ "$INSTALL_RDP" == "true" ]]; then
        echo "$step. Connect to the RDP desktop:"
        if is_wsl; then
            echo "   From this machine's Windows host: mstsc -> localhost:3390"
        else
            echo "   mstsc -> $(hostname):3389  (keep behind VPN/Tailscale — never expose to the internet)"
        fi
        echo
        ((step++))
    fi

    # WSL personal machines: nudge toward the Windows SSH agent bridge.
    if is_wsl && tier_includes "bash"; then
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

    if feature_enabled theme; then
        echo "$step. Switch theme (default: gruvbox):"
        echo "   ./bin/theme-switcher"
    else
        echo "$step. Theme feature is disabled (enable with: ./bin/dotfiles-feature enable theme)"
    fi

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

    # Bare invocation shows help and mutates nothing. setup.sh installs packages
    # and rewrites $HOME configs, so it must never run by accident — an explicit
    # tier/action flag is required. Use --config to just reconcile symlinks.
    if [[ $# -eq 0 ]]; then
        show_help
        exit 0
    fi

    # Parse command line arguments
    if ! parse_arguments "$@"; then
        show_help >&2
        exit 64
    fi

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
    if [[ "$INSTALL_AI" == "true" ]]; then
        if [[ "$AI_ALL" == "true" ]]; then
            echo "AI CLIs: all (claude, codex, opencode, pi)"
        else
            echo "AI CLIs: ${AI_TOOLS[*]}"
        fi
    else
        echo "AI CLIs: none"
    fi
    [[ "$INSTALL_RDP" == "true" ]] && echo "RDP server (xrdp): yes (--rdp)"
    [[ "$INSTALL_TAIL" == true ]] && echo "Tailscale: yes (--tail)"
    [[ "$INSTALL_AZURE" == true ]] && echo "Azure CLI: yes (--azure)"
    [[ "$INSTALL_GCLOUD" == true ]] && echo "Google Cloud CLI: yes (--gcloud)"
    [[ "$INSTALL_AWS" == true ]] && echo "AWS CLI v2: yes (--aws)"
    [[ "$DRY_RUN" == "true" ]] && echo "Mode: DRY RUN (no changes will be made)"
    echo
    
    # Run installation
    run_installation
}

# Execute main function
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    main "$@"
fi
