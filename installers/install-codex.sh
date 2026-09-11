#!/bin/bash
# Install or update the OpenAI Codex CLI with OpenAI's standalone installer.
#
# Codex is an "ai" tier tool (./setup.sh --ai, or --full). It is kept out of the
# shell-tier installers so an org-managed Codex install isn't shadowed by
# default. A normal rerun preserves a working standalone install; --force asks
# the official installer to update or repair it without deleting its launcher.
set -euo pipefail

INSTALLER_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(dirname "$INSTALLER_DIR")}"
export DOTFILES_DIR
source "$DOTFILES_DIR/lib/install.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

# The official standalone installer owns this launcher and the release tree
# under ~/.codex/packages/standalone. Dotfiles owns configuration, plugins and
# verification, but never rewrites the launcher itself.
CODEX_BIN="$HOME/.local/bin/codex"
CODEX_INSTALLER_URL="https://chatgpt.com/codex/install.sh"

# Provision the portable block in ~/.codex/config.toml. On first install the
# tracked file is copied whole. Later runs replace only the marked block, leaving
# Codex-owned project trust, hook trust, plugin state, and adapter selections
# untouched. Older unmarked configs are preserved and get a migration warning.
provision_codex_config() {
    local src="$DOTFILES_DIR/configs/codex.toml"
    local dest="$HOME/.codex/config.toml"
    local begin='# BEGIN DOTFILES-MANAGED CODEX CONFIG'
    local end='# END DOTFILES-MANAGED CODEX CONFIG'
    [[ -f "$src" ]] || return 0
    mkdir -p "$(dirname "$dest")"

    if [[ ! -e "$dest" ]]; then
        cp "$src" "$dest"
        chmod 600 "$dest"
        success "Provisioned portable ~/.codex/config.toml."
        return 0
    fi

    if ! grep -qxF "$begin" "$dest" || ! grep -qxF "$end" "$dest"; then
        warn "Existing $dest predates dotfiles-managed blocks; preserving it unchanged."
        warn "Migrate its portable settings once, then bracket them with:"
        warn "    $begin"
        warn "    $end"
        return 0
    fi

    local tmp
    tmp=$(mktemp "${dest}.tmp.XXXXXX")
    if ! awk -v src="$src" -v begin="$begin" -v end="$end" '
        function emit_source(   line, copying) {
            copying = 0
            while ((getline line < src) > 0) {
                if (line == begin) copying = 1
                if (copying) print line
                if (copying && line == end) break
            }
            close(src)
        }
        $0 == begin {
            emit_source()
            in_managed = 1
            replaced = 1
            next
        }
        in_managed && $0 == end {
            in_managed = 0
            next
        }
        !in_managed { print }
        END { if (!replaced || in_managed) exit 42 }
    ' "$dest" >"$tmp"; then
        rm -f "$tmp"
        error "Could not refresh the managed Codex config block in $dest"
        return 1
    fi

    chmod 600 "$tmp"
    if cmp -s "$tmp" "$dest"; then
        rm -f "$tmp"
        return 0
    fi
    mv "$tmp" "$dest"
    success "Refreshed portable settings in ~/.codex/config.toml."
}

# Install the agent-badge plugin (plugins/agent-badge) from this repo, which
# doubles as a plugin marketplace via .agents/plugins/marketplace.json.
#
# Same mechanism as the Claude side in install-claude.sh, and the same shared
# hooks/hooks.json: Codex auto-loads it by convention and expands
# ${CLAUDE_PLUGIN_ROOT} in the commands, so one file serves both harnesses.
#
# Registered as a local directory rather than tafk7/dotfiles so it tracks the
# working tree and needs no network. Both commands are idempotent.
#
# Never fatal: a badge is a convenience, not a reason to fail the Codex install.
provision_agent_badge_plugin() {
    [[ "${DOTFILES_AGENT_BADGE_ENABLED:-1}" == "1" ]] || {
        log "Agent-badge disabled; skipping plugin registration."
        return 0
    }
    local codex_cmd="${1:-}"
    [[ -n "$codex_cmd" && -x "$codex_cmd" ]] || codex_cmd="$(command -v codex 2>/dev/null || true)"
    [[ -n "$codex_cmd" ]] || return 0
    [[ -f "$DOTFILES_DIR/.agents/plugins/marketplace.json" ]] || return 0

    if ! "$codex_cmd" plugin marketplace add "$DOTFILES_DIR" >/dev/null 2>&1; then
        warn "Could not register $DOTFILES_DIR as a Codex plugin marketplace."
        return 0
    fi
    if "$codex_cmd" plugin add agent-badge@tafk7 >/dev/null 2>&1; then
        success "Plugin agent-badge installed (tmux window badges for agent sessions)."
        # Worth stating on every run. Codex gates hooks behind human review, and
        # an untrusted hook is skipped in SILENCE -- indistinguishable from a
        # broken config, and it has already caused one wrong diagnosis here.
        log "  Run /hooks inside Codex once to review and trust them."
        log "  Until you do, they are skipped silently and no badges appear."
    else
        warn "Could not install the agent-badge plugin; see plugins/agent-badge/README.md."
    fi
}

run_official_installer() {
    local installer_path="${DOTFILES_CODEX_INSTALLER_SCRIPT:-}"
    local downloaded=false

    # Private test seam: CI supplies a local stand-in so it can exercise
    # ownership behavior without executing a moving upstream installer.
    if [[ -n "$installer_path" ]]; then
        if [[ ! -f "$installer_path" ]]; then
            error "DOTFILES_CODEX_INSTALLER_SCRIPT does not exist: $installer_path"
            return 1
        fi
    else
        if ! command -v curl >/dev/null 2>&1; then
            error "curl is required to install Codex"
            return 1
        fi

        installer_path="$(mktemp)"
        downloaded=true
        if ! download_installer_script "$CODEX_INSTALLER_URL" "$installer_path"; then
            rm -f "$installer_path"
            error "Could not download the official Codex installer"
            return 1
        fi
    fi

    local rc=0
    sh "$installer_path" || rc=$?
    [[ "$downloaded" == true ]] && rm -f "$installer_path"
    if [[ "$rc" != 0 ]]; then
        error "The official Codex installer failed (exit $rc)"
        return "$rc"
    fi
}

# Config is independent of the binary — provision on every run so it lands even
# when the binary is already present (the early exits below).
provision_codex_config

# Never shadow an externally managed Codex, including under the repository-wide
# --force flag. Replacing another manager's binary must be a separate, explicit
# operation rather than a side effect of refreshing dotfiles.
EXTERNAL_CODEX="$(command -v codex 2>/dev/null || true)"
if [[ -n "$EXTERNAL_CODEX" && "$EXTERNAL_CODEX" != "$CODEX_BIN" ]]; then
    warn "Found an externally-managed codex on PATH: $EXTERNAL_CODEX"
    warn "Skipping install to avoid a shadow copy at $CODEX_BIN."
    provision_agent_badge_plugin "$EXTERNAL_CODEX"
    exit 2
fi

# A symlink at the standard path is owned by the standalone installer. Leave a
# working one alone on normal runs so setup remains fast and offline-friendly.
if [[ "$FORCE" != true && -L "$CODEX_BIN" && -x "$CODEX_BIN" ]] \
    && "$CODEX_BIN" --version >/dev/null 2>&1; then
    success "Codex already installed ($("$CODEX_BIN" --version 2>/dev/null | head -n1))."
    provision_agent_badge_plugin "$CODEX_BIN"
    exit 2
fi

# Migrate the previous dotfiles/eget installation, which was a regular binary at
# this same path, into the official release-managed layout. Do not delete it
# first: the official installer performs the replacement, and a failed download
# therefore leaves the working legacy binary intact.
if [[ "$FORCE" != true && -x "$CODEX_BIN" ]]; then
    warn "Found a legacy direct Codex binary at $CODEX_BIN."
    log "Migrating it to the official standalone installation..."
elif [[ "$FORCE" == true && -x "$CODEX_BIN" ]]; then
    log "Updating or repairing Codex with the official standalone installer..."
else
    log "Installing Codex with the official standalone installer..."
fi

if ! run_official_installer; then
    error "Codex installation failed"
    exit 1
fi

if [[ -x "$CODEX_BIN" ]] && "$CODEX_BIN" --version >/dev/null 2>&1; then
    success "Codex installed: $("$CODEX_BIN" --version 2>/dev/null | head -n1)"
    provision_agent_badge_plugin "$CODEX_BIN"
    exit 0
fi

error "Codex installer ran but $CODEX_BIN is not runnable"
exit 1
