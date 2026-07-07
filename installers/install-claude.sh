#!/bin/bash
# Install Claude Code via the official native installer (claude.ai/install.sh).
#
# Claude Code self-updates in the background by design, so this script only
# ensures the binary is present — it does NOT pin or manage versions. Re-run
# with --force to reinstall (e.g. to repair a broken binary). To stop the
# background auto-update, set DISABLE_AUTOUPDATER=1 in ~/.claude/settings.json.
set -euo pipefail

source "${DOTFILES_DIR:-$HOME/dotfiles}/lib/install.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

# The native installer writes the binary here. Verify by absolute path: on a
# fresh machine ~/.local/bin is not guaranteed to be on the installer process's
# PATH (the same reason install_eget_tools resolves eget by absolute path).
CLAUDE_BIN="$HOME/.local/bin/claude"

if [[ "$FORCE" != true && -x "$CLAUDE_BIN" ]] && "$CLAUDE_BIN" --version >/dev/null 2>&1; then
    success "Claude Code already installed ($("$CLAUDE_BIN" --version 2>/dev/null | head -n1)); it self-updates."
    exit 2
fi

# Don't shadow an externally-managed Claude. On org-managed machines the AI CLI
# is provided elsewhere on PATH; installing our own copy at ~/.local/bin/claude
# would silently override it (shell/env.sh prepends ~/.local/bin). Skip unless
# forced. The shell wrapper resolves whatever `claude` is on PATH either way.
EXTERNAL_CLAUDE="$(command -v claude 2>/dev/null || true)"
if [[ "$FORCE" != true && -n "$EXTERNAL_CLAUDE" && "$EXTERNAL_CLAUDE" != "$CLAUDE_BIN" ]]; then
    warn "Found an externally-managed claude on PATH: $EXTERNAL_CLAUDE"
    warn "Skipping install to avoid a shadow copy at $CLAUDE_BIN."
    warn "Re-run with --force to install the dotfiles-managed copy anyway."
    exit 2
fi

log "Installing Claude Code via claude.ai/install.sh..."

# ~/.local/bin is already on PATH (shell/env.sh), so the installer should detect
# that and skip editing shell rc files. Those rc files are dotfiles symlinks, so
# if it edits them anyway it writes through into the tracked repo — warn if so.
if ! curl -fsSL https://claude.ai/install.sh | bash; then
    error "Claude Code installation failed"
    exit 1
fi

if [[ -d "$DOTFILES_DIR/.git" ]] && ! git -C "$DOTFILES_DIR" diff --quiet -- entry/ shell/ 2>/dev/null; then
    warn "The Claude installer modified a shell rc file that is symlinked into the repo."
    warn "Review with: git -C \"$DOTFILES_DIR\" diff entry/ shell/   (revert if unwanted — PATH is already set by shell/env.sh)"
fi

if [[ -x "$CLAUDE_BIN" ]] && "$CLAUDE_BIN" --version >/dev/null 2>&1; then
    success "Claude Code installed: $("$CLAUDE_BIN" --version 2>/dev/null | head -n1)"
    exit 0
fi

error "Claude Code installer ran but $CLAUDE_BIN is not runnable"
exit 1
