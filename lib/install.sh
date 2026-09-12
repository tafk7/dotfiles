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
source "$(dirname "${BASH_SOURCE[0]}")/state.sh"
source "$(dirname "${BASH_SOURCE[0]}")/work-host.sh"

# Backups are machine state, not repository content.
DOTFILES_BACKUP_PREFIX="${DOTFILES_BACKUP_PREFIX:-$DOTFILES_STATE_DIR/backups}"

# ==============================================================================
# Install Result Tracking
# ==============================================================================

INSTALL_OK=()
INSTALL_SKIP=()
INSTALL_FAIL=()
INSTALL_NA=()
ACTIVE_BACKUP_DIR=""

track_install() {
    local name="$1" status="$2"
    case "$status" in
        ok)   INSTALL_OK+=("$name") ;;
        skip) INSTALL_SKIP+=("$name") ;;
        fail) INSTALL_FAIL+=("$name") ;;
        not-applicable) INSTALL_NA+=("$name") ;;
    esac
    if [[ "${DRY_RUN:-false}" != "true" && -n "${TOOL_BINARY[$name]:-}" ]]; then
        record_component_outcome "$name" "$status" || {
            INSTALL_FAIL+=("state:$name")
            return 1
        }
    fi
}

record_component_outcome() {
    local name="$1" result="$2" binary path="" ownership="unknown" version="" status applicable=yes note existing_record existing_note
    binary="${TOOL_BINARY[$name]}"
    if [[ "${TOOL_METHOD[$name]:-}" == eget && -x "$HOME/.local/bin/$binary" ]]; then
        path="$HOME/.local/bin/$binary"
    else
        path="$(command -v "$binary" 2>/dev/null || true)"
    fi
    [[ -n "$path" ]] && path="$(readlink -f "$path" 2>/dev/null || printf '%s' "$path")"
    if [[ -z "$path" && "$result" != fail ]]; then
        local candidate
        while IFS= read -r candidate; do
            if [[ -e "$candidate" || -L "$candidate" ]]; then
                path="$candidate"
                break
            fi
        done < <(tool_uninstall_paths "$name")
    fi
    if [[ -n "$path" ]]; then
        if tool_owned_path "$name" "$path"; then ownership="dotfiles"; else ownership="external"; fi
        version="$("$path" --version 2>/dev/null | head -n1 || true)"
    fi
    if [[ "${TOOL_METHOD[$name]:-}" == apt && "$result" == ok ]] \
       && dpkg-query -W "${TOOL_APT_PACKAGE[$name]:-$name}" >/dev/null 2>&1; then
        ownership="package-manager"
    fi
    case "$result" in
        ok) if [[ "$ownership" == external ]]; then status=present; else status=installed; fi ;;
        skip) if [[ "$ownership" == dotfiles ]]; then status=installed; else status=present; fi ;;
        not-applicable) status=not-applicable; applicable=no ;;
        fail)
            if [[ -n "$path" && -x "$path" ]]; then status=update-failed; else status=failed; fi
            ;;
        *) status="$result" ;;
    esac
    note="${TOOL_UPDATE_CONTRACT[$name]:-unknown}"
    existing_record="$(ledger_line "$name" 2>/dev/null || true)"
    if [[ -n "$existing_record" ]]; then
        IFS=$'\t' read -r _ _ _ _ _ _ existing_note _ <<< "$existing_record"
        [[ "$existing_note" != *' pin='* ]] || note="$existing_note"
    fi
    ledger_record "$name" "$applicable" "$ownership" "$status" "$version" "$path" "$note"
}

observed_component_version() {
    local name="$1" path="$2" package version=""

    # Executing an externally owned CLI merely to discover its version is not
    # reliably read-only. Azure CLI, for example, creates ~/.azure metadata and
    # appends telemetry even for `az --version`. Prefer package-manager metadata
    # for registered APT components, which is both faster and side-effect-free.
    package="${TOOL_APT_PACKAGE[$name]:-}"
    if [[ "${TOOL_METHOD[$name]:-}" == "apt" && -n "$package" ]] \
       && command -v dpkg-query >/dev/null 2>&1; then
        version="$(dpkg-query -W -f='${Version}\n' "$package" 2>/dev/null || true)"
    fi

    if [[ -z "$version" && -n "$path" && -x "$path" ]]; then
        version="$("$path" --version 2>/dev/null | head -n1 || true)"
    fi
    printf '%s\n' "$version"
}

reconcile_observed_components() {
    [[ "${DRY_RUN:-false}" == "true" ]] && return 0
    local name verify_cmd path version ownership
    for name in "${!TOOL_BINARY[@]}"; do
        ledger_line "$name" >/dev/null 2>&1 && continue
        tool_applicable "$name" || {
            ledger_record "$name" no unknown not-applicable "" "" "platform/architecture"
            continue
        }
        verify_cmd="$(tool_verify_command "$name")"
        eval "$verify_cmd" || continue
        path="$(command -v "${TOOL_BINARY[$name]}" 2>/dev/null || true)"
        [[ -n "$path" ]] && path="$(readlink -f "$path" 2>/dev/null || printf '%s' "$path")"
        version="$(observed_component_version "$name" "$path")"
        ownership=unknown
        [[ -n "$path" ]] && ! tool_owned_path "$name" "$path" && ownership=external
        ledger_record "$name" yes "$ownership" present "$version" "$path" "observed during reconciliation; ownership unclaimed"
    done
}

print_install_summary() {
    [[ ${#INSTALL_OK[@]} -eq 0 && ${#INSTALL_SKIP[@]} -eq 0 && ${#INSTALL_FAIL[@]} -eq 0 && ${#INSTALL_NA[@]} -eq 0 ]] && return 0

    echo
    echo "Installation Summary"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    [[ ${#INSTALL_OK[@]} -gt 0 ]]   && echo -e "  ${GREEN}✓${NC} ${INSTALL_OK[*]}"
    [[ ${#INSTALL_SKIP[@]} -gt 0 ]] && echo -e "  ${DIM}─ ${INSTALL_SKIP[*]} (up to date)${NC}"
    [[ ${#INSTALL_NA[@]} -gt 0 ]]   && echo -e "  ${DIM}⊘ ${INSTALL_NA[*]} (not applicable)${NC}"
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
    local ubuntu_version ubuntu_codename
    ubuntu_version="$(awk -F= '$1 == "VERSION_ID" { gsub(/^"|"$/, "", $2); print $2; exit }' "${DOTFILES_OS_RELEASE:-/etc/os-release}" 2>/dev/null || true)"
    ubuntu_codename="$(awk -F= '$1 == "VERSION_CODENAME" { gsub(/^"|"$/, "", $2); print $2; exit }' "${DOTFILES_OS_RELEASE:-/etc/os-release}" 2>/dev/null || true)"

    [[ -z "$ubuntu_version" ]] || log "Detected Ubuntu $ubuntu_version (${ubuntu_codename:-unknown codename})"

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
    tag=$(curl --proto '=https' --tlsv1.2 --fail --silent --show-error --max-time 30 \
        "https://api.github.com/repos/${repo}/releases/latest" \
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

download_https() {
    local url="$1" destination="$2"
    [[ "$url" == https://* ]] || { error "Refusing non-HTTPS download: $url"; return 1; }
    curl --proto '=https' --tlsv1.2 --fail --location --silent --show-error \
        --connect-timeout 10 --max-time "${DOTFILES_DOWNLOAD_TIMEOUT:-300}" \
        --output "$destination" "$url"
    [[ -s "$destination" ]] || { error "Downloaded artifact is empty: $url"; return 1; }
}

download_installer_script() {
    local url="$1" destination="$2"
    download_https "$url" "$destination" || return 1
    if ! head -n1 "$destination" | grep -Eq '^#!.*(sh|bash)([[:space:]]|$)'; then
        error "Downloaded installer does not begin with a shell shebang: $url"
        return 1
    fi
    chmod 700 "$destination"
}

validate_tar_archive() {
    local archive="$1"
    tar -tf "$archive" | awk '
        /^\// { bad=1 }
        /(^|\/)\.\.($|\/)/ { bad=1 }
        END { exit bad ? 1 : 0 }
    ' || { error "Archive contains an unsafe path: $archive"; return 1; }
}

atomic_replace_binary() {
    local component="$1" staged="$2" target="$3" metadata="${4:-}"
    [[ -x "$staged" ]] || { error "Staged $component binary is not executable: $staged"; return 1; }
    mkdir -p "$(dirname "$target")"
    local pending="${target}.dotfiles-new.$$"
    journal_begin "$component" "$target" "$staged" "$target"
    mv "$staged" "$pending"
    mv -f "$pending" "$target"
    local version
    version="$("$target" --version 2>/dev/null | head -n1 || true)"
    local note="${TOOL_UPDATE_CONTRACT[$component]:-staged}"
    [[ -z "$metadata" ]] || note+=" $metadata"
    ledger_record "$component" yes dotfiles installed "$version" "$target" "$note"
    journal_clear
}

atomic_replace_tree() {
    local component="$1" staged="$2" target="$3" verify_relative="$4" link_path="${5:-}"
    [[ -d "$staged" && -x "$staged/$verify_relative" ]] \
        || { error "Staged $component tree is incomplete: $staged"; return 1; }
    "$staged/$verify_relative" --version >/dev/null 2>&1 \
        || { error "Staged $component tree failed verification"; return 1; }
    mkdir -p "$(dirname "$target")"
    local rollback_root rollback version
    rollback_root="$(dirname "$target")/.dotfiles-${component}-rollback"
    rollback="$rollback_root/${BASHPID:-$$}"
    mkdir -p "$rollback_root"
    journal_begin "$component" "$rollback" "$staged" "$target"
    if [[ -e "$target" ]]; then mv "$target" "$rollback"; fi
    if ! mv "$staged" "$target"; then
        [[ ! -e "$rollback" ]] || mv "$rollback" "$target"
        return 1
    fi
    if [[ -n "$link_path" ]]; then
        mkdir -p "$(dirname "$link_path")"
        ln -sfn "$target/$verify_relative" "$link_path"
    fi
    if ! "${link_path:-$target/$verify_relative}" --version >/dev/null 2>&1; then
        rm -rf "$target"
        [[ ! -e "$rollback" ]] || mv "$rollback" "$target"
        if [[ -n "$link_path" ]]; then
            if [[ -e "$target/$verify_relative" ]]; then
                ln -sfn "$target/$verify_relative" "$link_path"
            else
                rm -f "$link_path"
            fi
        fi
        return 1
    fi
    version="$("${link_path:-$target/$verify_relative}" --version 2>/dev/null | head -n1 || true)"
    ledger_record "$component" yes dotfiles installed "$version" "${link_path:-$target}" "${TOOL_UPDATE_CONTRACT[$component]:-staged}"
    rm -rf "$rollback"
    rmdir "$rollback_root" 2>/dev/null || true
    journal_clear
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

    # Render outside HOME so a no-op rerun preserves both file and directory
    # mtimes. Replace only changed wrappers, matching config reconciliation.
    local staged file
    staged="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-clipboard.XXXXXX")" || return 1
    cat > "$staged/pbcopy" << 'EOF'
#!/bin/bash
clip.exe
EOF

    # Call PowerShell by absolute path: shell/env.sh strips the Windows
    # PowerShell directory from PATH, so `powershell.exe` by name won't resolve.
    # Prefer PowerShell 7 when present, otherwise Windows PowerShell 5.
    cat > "$staged/pbpaste" << 'EOF'
#!/bin/bash
if [[ -x "/mnt/c/Program Files/PowerShell/7/pwsh.exe" ]]; then
    "/mnt/c/Program Files/PowerShell/7/pwsh.exe" -NoProfile -Command "Get-Clipboard" | sed 's/\r$//'
else
    /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -Command "Get-Clipboard" | sed 's/\r$//'
fi
EOF

    for file in pbcopy pbpaste; do
        if ! cmp -s "$staged/$file" "$bin_dir/$file"; then
            install -m 0755 "$staged/$file" "$bin_dir/$file" || {
                rm -rf "$staged"
                return 1
            }
        elif [[ ! -x "$bin_dir/$file" ]]; then
            chmod +x "$bin_dir/$file" || { rm -rf "$staged"; return 1; }
        fi
    done
    rm -rf "$staged"

    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        export PATH="$HOME/.local/bin:$PATH"
    fi

    success "WSL clipboard integration setup complete"
}

# Install + enable the systemd user service that bridges the Windows ssh-agent
# (Bitwarden) into WSL2. The relay then runs at BOOT — visible to every shell,
# tmux pane, and captured environment (Claude Code's shell snapshot, etc.), and
# survives reboots — instead of only being (re)started at interactive shell
# startup by shell/platform/wsl.sh. No sudo (a --user service); linger is
# best-effort. OPT-IN per machine via the same marker the shell bridge uses:
# leave ~/.ssh/use-windows-agent absent on work machines and this is a no-op.
setup_wsl_ssh_agent() {
    is_wsl || return 0

    # Opt-in gate — only personal machines that asked for the Windows-agent bridge.
    if [[ ! -f "$HOME/.ssh/use-windows-agent" ]]; then
        wsl_log "ssh-agent bridge: marker ~/.ssh/use-windows-agent absent — skipping (work machine / not opted in)"
        return 0
    fi

    # Needs a reachable systemd user instance and the relay binary (shell tier).
    if ! command -v systemctl >/dev/null 2>&1 || ! systemctl --user show-environment >/dev/null 2>&1; then
        wsl_log "ssh-agent bridge: no systemd user instance — leaning on the shell-startup fallback in wsl.sh"
        return 0
    fi
    if ! command -v wsl2-ssh-agent >/dev/null 2>&1; then
        warn "ssh-agent bridge: wsl2-ssh-agent not installed (run ./setup.sh --bash) — skipping service"
        return 0
    fi

    local unit_src="$DOTFILES_DIR/configs/wsl2-ssh-agent.service"
    local unit_dir="$HOME/.config/systemd/user"

    mkdir -p "$unit_dir"
    ln -sfn "$unit_src" "$unit_dir/wsl2-ssh-agent.service"

    systemctl --user daemon-reload
    if systemctl --user enable --now wsl2-ssh-agent.service >/dev/null 2>&1; then
        success "WSL ssh-agent bridge service installed + started (wsl2-ssh-agent.service)"
    else
        warn "ssh-agent bridge: 'systemctl --user enable --now' failed — is Bitwarden's SSH agent enabled + unlocked on Windows?"
    fi

    # Start at boot even with no interactive login. May require polkit/sudo.
    loginctl enable-linger "$USER" 2>/dev/null \
        || wsl_log "ssh-agent bridge: for boot-start without a login, run:  sudo loginctl enable-linger $USER"
}

# Record the checkout path in durable machine state. Shell entrypoints normally
# derive it from their symlink; this handles flattened copies/bind mounts.
write_dotfiles_env() {
    local path_file="$DOTFILES_STATE_DIR/install-path"

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "[DRY RUN] Would record install path in $path_file"
        return 0
    fi

    record_install_path "$DOTFILES_DIR"
    if is_wsl; then
        preference_set platform.wsl enabled
        preference_set machine.win_user "$(get_windows_username)"
    fi
    success "Recorded install path in $path_file"
}

# ==============================================================================
# Backup Functions
# ==============================================================================

create_backup_dir() {
    mkdir -p "$DOTFILES_BACKUP_PREFIX"
    ACTIVE_BACKUP_DIR="$DOTFILES_BACKUP_PREFIX/backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$ACTIVE_BACKUP_DIR"
}

ensure_backup_dir() {
    if [[ -z "${ACTIVE_BACKUP_DIR:-}" ]]; then
        create_backup_dir
        log "Backup directory: $ACTIVE_BACKUP_DIR"
    fi
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

    if [[ ! -e "$source" ]]; then
        error "Source file does not exist: $source"
        return 1
    fi

    if [[ -L "$target" ]] \
       && [[ "$(readlink -f "$target" 2>/dev/null || true)" == "$(readlink -f "$source")" ]]; then
        log "Symlink already current: $target"
        return 0
    fi

    if [[ "${FORCE_OVERWRITE:-false}" == "true" && -e "$target" ]]; then
        assert_safe_home_target "$target"
        if [[ -L "$target" ]]; then
            rm -f "$target"
        else
            # Even under --force, preserve real files/dirs in the backup rather
            # than destroying them with rm -rf.
            local dest
            ensure_backup_dir
            dest="$(backup_dest "$target" "$ACTIVE_BACKUP_DIR")"
            mkdir -p "$(dirname "$dest")"
            log "Force overwrite: backing up $target -> $dest"
            mv "$target" "$dest"
        fi
    elif [[ -e "$target" && ! -L "$target" ]]; then
        local dest
        ensure_backup_dir
        dest="$(backup_dest "$target" "$ACTIVE_BACKUP_DIR")"
        mkdir -p "$(dirname "$dest")"
        log "Backing up existing $target -> $dest"
        mv "$target" "$dest"
    elif [[ -L "$target" ]]; then
        local link_target
        link_target="$(readlink -f "$target" 2>/dev/null || true)"
        if [[ -n "$link_target" && -f "$link_target" && "$link_target" != "$(readlink -f "$source")" ]]; then
            local dest
            ensure_backup_dir
            dest="$(backup_dest "$target" "$ACTIVE_BACKUP_DIR")"
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
    local force="${3:-false}"
    local portable_dir="${XDG_CONFIG_HOME:-$HOME/.config}/dotfiles"
    local portable="$portable_dir/gitconfig"
    local rendered git_version conflict_style="diff3" theme_cache azure_portable azure_enabled=false

    mkdir -p "$portable_dir"
    rendered="$(mktemp "${TMPDIR:-/tmp}/dotfiles-gitconfig.XXXXXX")"

    git_version=$(git --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)+' | head -n1)
    if [[ -n "$git_version" ]] && version_gte "$git_version" "2.35"; then
        conflict_style="zdiff3"
    fi
    theme_cache="${DOTFILES_THEME_CACHE_DIR:-${DOTFILES_GENERATED_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/dotfiles/theme}}"
    azure_portable="$portable_dir/gitconfig-azure"
    local azure_present=false
    case "${DOTFILES_TEST_AZURE_PRESENT:-}" in
        1) azure_present=true ;;
        0) azure_present=false ;;
        *) command -v az >/dev/null 2>&1 && azure_present=true ;;
    esac
    if [[ "${INSTALL_AZURE:-false}" == true || "$azure_present" == true ]]; then
        azure_enabled=true
        mkdir -p "$HOME/.local/bin"
        safe_symlink "$DOTFILES_DIR/bin/git-credential-azdo" "$HOME/.local/bin/git-credential-azdo"
        if [[ ! -f "$azure_portable" ]] || ! cmp -s "$DOTFILES_DIR/configs/gitconfig-azure" "$azure_portable"; then
            install -m 0600 "$DOTFILES_DIR/configs/gitconfig-azure" "$azure_portable"
        fi
    fi

    sed -e "s|{{CONFLICT_STYLE}}|$conflict_style|g" "$source" |
        if feature_enabled theme; then
            awk -v path="$theme_cache/delta.gitconfig" '
                $0 == "{{THEME_INCLUDE}}" {
                    print "[include]"
                    print "    # Optional theme feature index."
                    print "    path = \"" path "\""
                    next
                }
                { print }
            '
        else
            awk '$0 != "{{THEME_INCLUDE}}" { print }'
        fi |
        awk -v enabled="$azure_enabled" -v path="$azure_portable" '
            $0 == "{{AZURE_INCLUDE}}" {
                if (enabled == "true") {
                    print "[include]"
                    print "    # Optional Azure DevOps credential integration."
                    print "    path = \"" path "\""
                }
                next
            }
            { print }
        ' > "$rendered"

    if [[ ! -f "$portable" ]] || ! cmp -s "$rendered" "$portable"; then
        mv "$rendered" "$portable"
        chmod 600 "$portable"
        success "Portable Git config updated: $portable"
    else
        rm -f "$rendered"
        log "Portable Git config already current: $portable"
    fi

    # Preserve the user's global file and identity. Only add our include entries
    # when absent; no timestamp backup or whole-file rendering is needed.
    local existing
    existing="$(git config --file "$target" --get-all include.path 2>/dev/null || true)"
    if ! grep -Fxq "$portable" <<< "$existing"; then
        git config --file "$target" --add include.path "$portable"
    fi
    if ! grep -Fxq "$HOME/.gitconfig.local" <<< "$existing"; then
        git config --file "$target" --add include.path "$HOME/.gitconfig.local"
    fi

    if [[ -n "${DOTFILES_GIT_NAME:-}" ]]; then
        [[ "$(git config --file "$HOME/.gitconfig.local" user.name 2>/dev/null || true)" == "$DOTFILES_GIT_NAME" ]] \
            || git config --file "$HOME/.gitconfig.local" user.name "$DOTFILES_GIT_NAME"
    fi
    if [[ -n "${DOTFILES_GIT_EMAIL:-}" ]]; then
        [[ "$(git config --file "$HOME/.gitconfig.local" user.email 2>/dev/null || true)" == "$DOTFILES_GIT_EMAIL" ]] \
            || git config --file "$HOME/.gitconfig.local" user.email "$DOTFILES_GIT_EMAIL"
    fi

    if [[ -z "$(git config --file "$HOME/.gitconfig.local" user.name 2>/dev/null || git config --global user.name 2>/dev/null || true)" \
       || -z "$(git config --file "$HOME/.gitconfig.local" user.email 2>/dev/null || git config --global user.email 2>/dev/null || true)" ]]; then
        warn "Git identity is not configured; set it in ~/.gitconfig.local or pass --git-name/--git-email."
    fi

    # force is accepted for command compatibility; portable reconciliation is
    # content-addressed and never overwrites unrelated user settings.
    : "$target" "$force"
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

    if ! update_packages; then
        track_install "$label apt" fail
        return 1
    fi
    log "Installing $label APT packages: ${missing[*]}"
    if safe_sudo apt-get install -y "${missing[@]}"; then
        success "$label APT packages installed"
    else
        error "Some $label packages failed to install"
        track_install "$label apt" fail
        return 1
    fi
}

update_packages() {
    log "Updating package lists..."
    local output rc=0
    output="$(safe_sudo apt-get update 2>&1)" || rc=$?
    printf '%s\n' "$output" | grep -v '^W:' || true
    if (( rc != 0 )); then
        error "APT package index update failed"
        return "$rc"
    fi
}

ensure_docker_repo() {
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "[DRY RUN] Would ensure Docker apt repo is configured"
        return 0
    fi

    local sources_dir="${DOTFILES_APT_SOURCES_DIR:-/etc/apt/sources.list.d}"
    local keyrings_dir="${DOTFILES_APT_KEYRINGS_DIR:-/etc/apt/keyrings}"
    local main_list="${DOTFILES_APT_MAIN_LIST:-/etc/apt/sources.list}" codename source_file

    codename="$(awk -F= '$1 == "VERSION_CODENAME" { gsub(/^"|"$/, "", $2); print $2; exit }' "${DOTFILES_OS_RELEASE:-/etc/os-release}")"
    [[ -n "$codename" ]] || { error "Cannot determine Ubuntu codename for Docker repository"; return 1; }

    # Reuse either legacy .list or current deb822 .sources definitions. Repository
    # preparation is also used by sbx and must never migrate container runtimes.
    source_file="$(grep -RslE '^[[:space:]]*(deb .*|URIs:[[:space:]]*)https://download\.docker\.com/linux/ubuntu' \
        "$sources_dir" "$main_list" 2>/dev/null | head -n1 || true)"
    if [[ -n "$source_file" ]]; then
        if grep -Eq "(^|[[:space:]])${codename}([[:space:]]|$)|^Suites:[[:space:]]*${codename}([[:space:]]|$)" "$source_file"; then
            log "Docker apt repository already configured; reusing existing definition"
            return 0
        fi
        error "Existing Docker repository does not target Ubuntu codename '$codename': $source_file"
        error "Correct or remove that repository definition manually, then re-run setup."
        return 1
    fi

    log "Adding Docker official apt repository..."

    safe_sudo apt-get install -y ca-certificates curl gnupg || return 1

    safe_sudo install -m 0755 -d "$keyrings_dir" || return 1
    if [[ ! -f "$keyrings_dir/docker.gpg" ]]; then
        local docker_key docker_keyring fingerprint docker_tmp
        docker_tmp="$(mktemp -d)"
        mkdir -m 0700 "$docker_tmp/gnupg"
        docker_key="$docker_tmp/docker.asc"; docker_keyring="$docker_tmp/docker.gpg"
        download_https https://download.docker.com/linux/ubuntu/gpg "$docker_key" \
            || { rm -rf "$docker_tmp"; return 1; }
        fingerprint="$(GNUPGHOME="$docker_tmp/gnupg" gpg --batch --show-keys --with-colons "$docker_key" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')"
        if [[ "$fingerprint" != 9DC858229FC7DD38854AE2D88D81803C0EBFCD88 ]]; then
            rm -rf "$docker_tmp"
            error "Docker repository key fingerprint mismatch: ${fingerprint:-missing}"
            return 1
        fi
        GNUPGHOME="$docker_tmp/gnupg" gpg --batch --dearmor --output "$docker_keyring" "$docker_key" \
            || { rm -rf "$docker_tmp"; return 1; }
        safe_sudo install -m 0644 "$docker_keyring" "$keyrings_dir/docker.gpg" \
            || { rm -rf "$docker_tmp"; return 1; }
        rm -rf "$docker_tmp"
        safe_sudo chmod a+r "$keyrings_dir/docker.gpg"
    fi

    printf 'deb [arch=%s signed-by=%s/docker.gpg] https://download.docker.com/linux/ubuntu %s stable\n' \
        "$(dpkg --print-architecture)" "$keyrings_dir" "$codename" | \
        safe_sudo tee "$sources_dir/docker.list" > /dev/null

    update_packages || return 1
    success "Docker apt repository configured"
}

# Install Azure CLI from Microsoft's signed apt repository.
# Replaces the previous `curl https://aka.ms/InstallAzureCLIDeb | sudo bash`,
# which executed an unpinned remote script as root.
install_azure_cli() {
    if [[ "${FORCE_REINSTALL:-false}" != true ]] && command -v az >/dev/null 2>&1; then
        log "Azure CLI already installed"
        return 0
    fi

    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "[DRY RUN] Would add Microsoft apt repo and install azure-cli"
        return 0
    fi

    log "Installing Azure CLI from Microsoft's signed apt repository..."
    safe_sudo apt-get install -y ca-certificates curl gnupg || return 1
    local sources_dir="${DOTFILES_APT_SOURCES_DIR:-/etc/apt/sources.list.d}"
    local keyrings_dir="${DOTFILES_APT_KEYRINGS_DIR:-/etc/apt/keyrings}"
    safe_sudo install -m 0755 -d "$keyrings_dir" "$sources_dir" || return 1

    if [[ ! -f "$keyrings_dir/microsoft.gpg" ]]; then
        local microsoft_key microsoft_keyring fingerprint
        microsoft_key="$(mktemp)"; microsoft_keyring="$(mktemp)"
        download_https https://packages.microsoft.com/keys/microsoft.asc "$microsoft_key" || return 1
        local microsoft_gnupg
        microsoft_gnupg="$(mktemp -d)"; chmod 700 "$microsoft_gnupg"
        fingerprint="$(GNUPGHOME="$microsoft_gnupg" gpg --batch --show-keys --with-colons "$microsoft_key" 2>/dev/null | awk -F: '$1 == "fpr" { print $10; exit }')"
        if [[ "$fingerprint" != BC528686B50D79E339D3721CEB3E94ADBE1229CF ]]; then
            rm -f "$microsoft_key" "$microsoft_keyring"; rm -rf "$microsoft_gnupg"
            error "Microsoft repository key fingerprint mismatch: ${fingerprint:-missing}"
            return 1
        fi
        GNUPGHOME="$microsoft_gnupg" gpg --batch --dearmor --output "$microsoft_keyring" "$microsoft_key" \
            || { rm -f "$microsoft_key" "$microsoft_keyring"; rm -rf "$microsoft_gnupg"; return 1; }
        safe_sudo install -m 0644 "$microsoft_keyring" "$keyrings_dir/microsoft.gpg" || return 1
        rm -f "$microsoft_key" "$microsoft_keyring"; rm -rf "$microsoft_gnupg"
        safe_sudo chmod a+r "$keyrings_dir/microsoft.gpg"
    fi

    local codename
    codename="$(awk -F= '$1 == "VERSION_CODENAME" { gsub(/^"|"$/, "", $2); print $2; exit }' "${DOTFILES_OS_RELEASE:-/etc/os-release}")"
    [[ -n "$codename" ]] || { error "Cannot determine Ubuntu codename for Azure CLI repository"; return 1; }
    printf 'deb [arch=%s signed-by=%s/microsoft.gpg] https://packages.microsoft.com/repos/azure-cli/ %s main\n' \
        "$(dpkg --print-architecture)" "$keyrings_dir" "$codename" | safe_sudo tee "$sources_dir/azure-cli.list" > /dev/null

    update_packages || return 1
    if [[ "${FORCE_REINSTALL:-false}" == true ]] && dpkg-query -W azure-cli >/dev/null 2>&1; then
        safe_sudo apt-get install --reinstall -y azure-cli
    else
        install_apt "azure-cli" azure-cli
    fi
}

# ==============================================================================
# Installer Runner
# ==============================================================================

# Run installer script with consistent error handling
# Exit codes: 0 = installed/updated, 2 = already up to date, 1 = failed
run_installer() {
    local name="$1"
    local critical="${2:-false}"
    : "$critical"  # retained for compatibility with older callers
    local script="$DOTFILES_DIR/installers/install-$name.sh"

    if [[ ! -f "$script" ]]; then
        error "Installer script not found: $script"
        track_install "$name" fail
        [[ "$critical" == "true" ]] && exit 1
        return 1
    fi

    # DRY RUN: don't execute the installer. The per-tool scripts download and
    # write to disk (and only some self-guard on an existing install), so running
    # them would mutate the system — exactly what a dry run must not do.
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        log "[DRY RUN] Would run installer: $name"
        return 0
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
            error "$name installation failed"
            return 1
            ;;
    esac
}

# Install all binary tools declared in eget.toml
install_eget_tools() {
    local config="$DOTFILES_DIR/eget.toml"
    if [[ ! -f "$config" ]]; then
        error "eget.toml not found at $config"
        return 1
    fi

    # Collect eget tool names from registry, honoring the selected tier. This
    # function runs from install_bash_packages, which fires at bash tier and up
    # (cumulative chain), so gating each tool on tier_includes its own tier keeps
    # a dev-tier eget tool (e.g. shellcheck) out of a --bash run but pulls it in
    # at --dev. tier_includes lives in setup.sh; if this is ever called with it
    # undefined (installer sourcing lib standalone), fall back to installing all.
    local -a eget_tools=()
    local name
    for name in "${!TOOL_METHOD[@]}"; do
        [[ "${TOOL_METHOD[$name]}" == "eget" ]] || continue
        if declare -F tier_includes >/dev/null 2>&1; then
            tier_includes "${TOOL_TIER[$name]}" || continue
        fi
        if ! tool_applicable "$name"; then
            [[ "${DRY_RUN:-false}" == "true" ]] || track_install "$name" not-applicable
            continue
        fi
        eget_tools+=("$name")
    done

    # Respect system-managed copies. A binary already on PATH outside our prefix
    # (~/.local/bin) is one the admin/apt installed — downloading our pinned copy
    # would shadow it (~/.local/bin sorts earlier on PATH) for no gain. Skip those
    # here so eget only fetches tools we actually own; --force overrides to install
    # the pinned version regardless. Same courtesy the AI installers extend to an
    # org-managed binary on PATH.
    if [[ "${FORCE_REINSTALL:-false}" != "true" ]]; then
        local -a to_download=() existing binary managed_target
        local verify_cmd
        for name in "${eget_tools[@]}"; do
            binary="${TOOL_BINARY[$name]}"
            managed_target="$HOME/.local/bin/$binary"
            if [[ -x "$managed_target" ]]; then
                existing="$managed_target"
            else
                existing="$(command -v "$binary" 2>/dev/null || true)"
            fi
            if [[ -n "$existing" && "$existing" != "$HOME/.local/bin/"* ]]; then
                verify_cmd="$(tool_verify_command "$name")"
                if eval "$verify_cmd"; then
                    log "Skipping $name — system copy at $existing (use --force to override)"
                    [[ "${DRY_RUN:-false}" != "true" ]] && track_install "$name" skip
                else
                    log "Ignoring incidental $name candidate at $existing"
                    to_download+=("$name")
                fi
            else
                to_download+=("$name")
            fi
        done
        eget_tools=("${to_download[@]}")
    fi

    # DRY RUN: report what would be fetched, then stop before touching disk. This
    # must come before the eget bootstrap and any download — the whole function is
    # otherwise a mutation.
    if [[ "${DRY_RUN:-false}" == "true" ]]; then
        if [[ ${#eget_tools[@]} -eq 0 ]]; then
            log "[DRY RUN] All eget tools already provided by the system — nothing to download"
        else
            log "[DRY RUN] Would install eget + download: ${eget_tools[*]}"
        fi
        return 0
    fi

    run_installer "eget" true || return 1
    log "Installing binary tools via eget..."

    if [[ ${#eget_tools[@]} -eq 0 ]]; then
        log "All eget tools already provided by the system — nothing to download"
        return 0
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

    # Map each tool name to its eget repo slug by parsing the config headers
    # (["owner/repo"]). eget.toml stays the single source of truth for slugs. The
    # repo basename is the registry tool name except where TOOL_EGET_REPO says
    # otherwise (gh ships from cli/cli); an override must still name a slug that
    # eget.toml pins, so a typo can't fetch an unpinned release.
    local -A tool_slug=() pinned_slug=()
    local slug
    while IFS= read -r slug; do
        tool_slug["${slug##*/}"]="$slug"
        pinned_slug["$slug"]=1
    done < <(grep -Po '^\["\K[^"]+' "$config")

    # Drive eget per surviving tool rather than --download-all: the guard above
    # dropped system-provided tools from eget_tools, and a per-target invocation
    # (eget applies this repo's TOML config — tag, asset_filters, target) ensures
    # those are never fetched. upgrade_only (eget.toml) still makes each call a
    # no-op when the pinned version is already present, so re-runs download nothing.
    # eget's exit code doesn't cleanly separate "skipped, up to date" from "failed",
    # so don't trust it: judge each tool by whether its binary lands on disk.
    local any_missing=false
    for name in "${eget_tools[@]}"; do
        slug="${TOOL_EGET_REPO[$name]:-${tool_slug[$name]:-}}"
        if [[ -z "$slug" || -z "${pinned_slug[$slug]:-}" ]]; then
            warn "No eget.toml entry for $name${slug:+ ($slug)} — skipping"
            track_install "$name" fail
            any_missing=true
            continue
        fi
        local pinned current_output target existing_record recorded_note recorded_hash actual_hash
        pinned="$(awk -v section="[\"$slug\"]" '
            $0 == section { active=1; next }
            active && /^\[/ { exit }
            active && /^[[:space:]]*tag[[:space:]]*=/ {
                line=$0; sub(/^[^"]*"/, "", line); sub(/".*$/, "", line); print line; exit
            }
        ' "$config")"
        target="$HOME/.local/bin/${TOOL_BINARY[$name]}"
        if [[ "${FORCE_REINSTALL:-false}" != "true" && -x "$target" && -n "$pinned" ]]; then
            existing_record="$(ledger_line "$name" 2>/dev/null || true)"
            recorded_note=""
            if [[ -n "$existing_record" ]]; then
                IFS=$'\t' read -r _ _ _ _ _ _ recorded_note _ <<< "$existing_record"
            fi
            if [[ "$recorded_note" == *" pin=$pinned "* && "$recorded_note" =~ sha256=([0-9a-f]{64}) ]]; then
                recorded_hash="${BASH_REMATCH[1]}"
                actual_hash="$(sha256sum "$target" | awk '{print $1}')"
                if [[ "$actual_hash" == "$recorded_hash" ]]; then
                    track_install "$name" skip
                    continue
                fi
            fi
            current_output="$("$target" --version 2>/dev/null || true)"
            if [[ "$current_output" == *"${pinned#v}"* ]]; then
                track_install "$name" skip
                continue
            fi
        fi

        local stage_home stage_config staged staged_hash
        stage_home="$(mktemp -d "${TMPDIR:-/tmp}/dotfiles-eget-${name}.XXXXXX")"
        stage_config="$stage_home/eget.toml"
        mkdir -p "$stage_home/.local/bin"
        sed "s|~/.local/bin|$stage_home/.local/bin|g" "$config" > "$stage_config"
        if ! HOME="$stage_home" EGET_CONFIG="$stage_config" "$eget_bin" "$slug"; then
            rm -rf "$stage_home"
            track_install "$name" fail
            any_missing=true
            continue
        fi
        staged="$stage_home/.local/bin/${TOOL_BINARY[$name]}"
        if [[ ! -x "$staged" ]] || ! "$staged" --version >/dev/null 2>&1; then
            rm -rf "$stage_home"
            track_install "$name" fail
            any_missing=true
            continue
        fi
        staged_hash="$(sha256sum "$staged" | awk '{print $1}')"
        atomic_replace_binary "$name" "$staged" "$target" "pin=$pinned sha256=$staged_hash"
        PATH="$HOME/.local/bin:$PATH"
        export PATH
        hash -r
        rm -rf "$stage_home"
        # Judge by the binary on disk at our prefix, NOT command -v: on a fresh
        # machine ~/.local/bin isn't on PATH yet, so a PATH lookup would report
        # every just-installed tool as failed. eget lands each tool at
        # ~/.local/bin/<binary> (the global target, or the per-tool file-path
        # target which renames to that same path).
        if [[ -x "$HOME/.local/bin/${TOOL_BINARY[$name]}" ]]; then
            track_install "$name" ok
        else
            track_install "$name" fail
            any_missing=true
        fi
    done
    if [[ "$any_missing" == true ]]; then
        error "Some eget tools are missing after install (see summary)"
        return 1
    fi
    return 0
}

# ==============================================================================
# Tiered Installation Functions
# ==============================================================================

# bash tier: the non-sudo base. eget binaries to ~/.local/bin only — no apt,
# no root. git is assumed present (needed to clone this repo in the first place);
# we warn rather than install it, since installing would require the sudo this
# tier deliberately avoids.
install_bash_packages() {
    log "Installing bash tier packages..."

    command -v git >/dev/null 2>&1 || \
        warn "git not found — install it (sudo apt install git) for full functionality"

    install_eget_tools || return 1

    success "Bash tier installation complete"
}

# dev tier: first apt layer (sudo). Everything that needs root lives here or
# above — zsh, build toolchain, clipboard, and the tmux build deps that
# install-tmux.sh compiles against.
install_dev_packages() {
    log "Installing dev tier packages..."

    # PACKAGES values are intentionally space-separated lists meant to be
    # word-split into the array — the alternative (per-key arrays) would
    # bloat the data file. shellcheck flags this as SC2206; that's expected.
    # shellcheck disable=SC2206
    local packages=(${PACKAGES[core]} ${PACKAGES[development]} ${PACKAGES[languages]} ${PACKAGES[terminal]} ${PACKAGES[diagramming]})
    # shellcheck disable=SC2206
    is_wsl && packages+=(${PACKAGES[wsl]})

    if ! install_apt "dev" "${packages[@]}"; then
        [[ "${DRY_RUN:-false}" == "true" ]] || track_install zsh fail
        return 1
    fi
    if [[ "${DRY_RUN:-false}" != "true" ]]; then
        if command -v zsh >/dev/null 2>&1; then track_install zsh ok; else track_install zsh fail; return 1; fi
    fi

    log "Installing dev tier tools via scripts..."
    local failed=false
    run_installer "tmux" || failed=true
    run_installer "neovim" || failed=true
    [[ "$failed" == "false" ]] || return 1

    success "Dev tier installation complete"
}

# AI CLIs (Claude Code, Codex, opencode). Orthogonal to the tier chain —
# installed only when --ai/--full or a per-tool flag (--claude/--codex/
# --opencode) is passed. Which tools run is driven by setup.sh's AI_ALL /
# AI_TOOLS globals; AI_ALL expands to every AI-capability tool in the registry, so a
# new AI CLI is picked up automatically once registered. Kept separate so an
# org-managed install can be left untouched — each installer refuses to shadow
# an external binary already on PATH.
install_ai_packages() {
    local -a tools=()
    local failed=false
    if [[ "${AI_ALL:-false}" == "true" ]]; then
        readarray -t tools < <(tools_for_capability ai)
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
        run_installer "$t" || failed=true
    done

    [[ "$failed" == "false" ]] || return 1

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
    preserve_default_display_manager || { track_install "xrdp" fail; return 1; }

    # Deliberately not install_apt: we need a preseeded, fully non-interactive
    # apt run. DEBIAN_FRONTEND=noninteractive suppresses the dialog; DEBIAN_PRIORITY
    # =critical is a second guard so only critical questions could ever surface.
    # env, not a bare assignment, because sudo resets the environment.
    update_packages || { track_install "xrdp" fail; return 1; }
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
    run_installer "xrdp" || return 1

    success "RDP server installation complete"
}

docker_conflicting_packages() {
    local pkg
    for pkg in docker.io docker-doc docker-compose docker-compose-v2 docker-buildx podman-docker containerd runc; do
        dpkg -s "$pkg" >/dev/null 2>&1 && printf '%s\n' "$pkg"
    done
}

install_docker_engine() {
    if dpkg-query -W "${TOOL_APT_PACKAGE[docker]}" >/dev/null 2>&1; then
        log "Docker Engine package already installed"
        track_install docker skip
        return 0
    fi

    # An already usable non-Docker-CE installation belongs to its administrator.
    # Keep it and its daemon configuration untouched.
    if command -v docker >/dev/null 2>&1; then
        local endpoint
        endpoint="$(work_docker_endpoint)"
        if ! work_docker_endpoint_is_local "$endpoint"; then
            error "Existing Docker CLI uses a remote endpoint ($endpoint); it does not satisfy local Engine installation."
            error "Select a local context or resolve the external CLI before re-running setup."
            track_install docker fail
            return 1
        fi
        warn "Keeping externally managed Docker installation: $(command -v docker)"
        track_install docker skip
        return 0
    fi

    local -a conflicts=()
    readarray -t conflicts < <(docker_conflicting_packages)
    if (( ${#conflicts[@]} )); then
        error "Docker Engine migration required; conflicting packages are installed: ${conflicts[*]}"
        error "Review Docker's migration guidance and container data, remove conflicts manually, then re-run setup."
        track_install docker fail
        return 1
    fi

    ensure_docker_repo || { track_install docker fail; return 1; }
    # shellcheck disable=SC2206
    local packages=(${PACKAGES[docker]})
    install_apt docker "${packages[@]}" || { track_install docker fail; return 1; }
    if [[ "${DRY_RUN:-false}" != true ]]; then
        command -v docker >/dev/null 2>&1 \
            && track_install docker ok \
            || { track_install docker fail; return 1; }
    fi
}

ensure_account_group() {
    local group="$1" account state
    account="$(host_account)" || { warn "Cannot resolve the invoking account for $group membership"; return 0; }
    getent group "$group" >/dev/null 2>&1 || { warn "$group group is unavailable; host configuration remains incomplete"; return 0; }
    state="$(host_group_state "$group")"
    case "$state" in
        active) log "$account has active $group group membership" ;;
        pending) warn "$account has $group membership, but this process needs a new login" ;;
        *)
            log "Adding $account to $group group..."
            if safe_sudo usermod -aG "$group" "$account"; then
                warn "$group membership added; sign out and reconnect before verification"
            else
                warn "Could not add $account to $group (try: sudo usermod -aG $group $account)"
            fi
            ;;
    esac
}

configure_docker_host_access() {
    command -v docker >/dev/null 2>&1 || return 0
    local endpoint
    endpoint="$(work_docker_endpoint)"
    if [[ "$endpoint" == unix:///run/user/*/docker.sock ]]; then
        log "Rootless Docker endpoint detected; docker-group membership is unnecessary"
    else
        ensure_account_group docker
        warn "Membership in the docker group grants root-equivalent access to this host."
    fi
    if host_systemd_running && [[ "$endpoint" != unix:///run/user/*/docker.sock ]]; then
        safe_sudo systemctl enable --now docker || warn "Could not enable/start docker via systemd"
    fi
}

configure_work_host() {
    log "Configuring work-tier Docker and KVM access..."
    configure_docker_host_access
    if work_kvm_device_present || work_kernel_has_kvm; then
        ensure_account_group kvm
    else
        warn "KVM unavailable; enable hardware/nested virtualization outside this machine, then verify /dev/kvm"
    fi
    if ! work_kvm_device_present; then
        warn "/dev/kvm is missing; sbx is installed but local sandboxes cannot start"
    elif ! work_kvm_accessible; then
        warn "/dev/kvm permission denied; reconnect after kvm group membership is applied"
    fi
    host_systemd_running || warn "systemd is not managing this host; Docker service readiness must be handled manually"
    success "Work host configuration checked (package success and host readiness are reported separately)"
}

install_tail_packages() {
    log "Installing the optional Tailscale capability..."
    run_installer tailscale || return 1
    success "Tailscale capability installation complete"
}

install_cloud_capability() {
    local capability="$1" tool
    tool="$(tools_for_capability "$capability" | head -n1)"
    [[ -n "$tool" ]] || { error "No component registered for --$capability"; return 1; }
    run_installer "$tool"
}

install_work_packages() {
    log "Installing work tier packages..."
    local failed=false

    install_apt "work" python3-dev python3-venv || failed=true

    install_docker_engine || failed=true
    run_installer "sbx" || failed=true
    configure_work_host

    # Version managers (Python is handled by uv, installed in the shell tier)
    run_installer "nvm" || failed=true
    if [[ -d "$HOME/.nvm/default/bin" && ":$PATH:" != *":$HOME/.nvm/default/bin:"* ]]; then
        PATH="$HOME/.nvm/default/bin:$PATH"
        export PATH
    fi
    # Rust toolchain (userspace, no sudo). Non-critical: unlike node (which
    # underpins the AI CLIs), nothing else in setup depends on it.
    run_installer "rust" || failed=true

    [[ "$failed" == "false" ]] || return 1

    success "Work tier installation complete"
}
