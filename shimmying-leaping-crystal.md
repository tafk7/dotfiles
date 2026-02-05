# Tiered Dotfiles Installation System

## Overview

Restructure `setup.sh` to support tiered installation levels, from "symlinks only" to "full dev environment".

## Tier System

| Tier | Flag | What It Does | Requires Sudo |
|------|------|--------------|---------------|
| **config** | `--config` or `--sync` | Symlinks only. Zero installs. | No |
| **shell** | `--shell` | Config + modern CLI (starship, eza, bat, fd, ripgrep, fzf, zoxide) | Yes |
| **dev** | `--dev` | Shell + neovim, lazygit, tmux | Yes |
| **full** | `--full` or `--work` | Dev + NVM, pyenv, Docker, Azure CLI, Claude Code | Yes |

**Modifiers:**
- `--personal` - Adds media tools (ffmpeg, yt-dlp) to any tier

**Behaviors:**
- Tiers are cumulative (`--dev` includes `--shell` which includes `--config`)
- `--work` is alias for `--full` (backwards compatibility)
- Default with no flags: `--config` (safe, non-destructive)

## Files to Modify

### 1. setup.sh

**Flag parsing (lines 17-72):**
```bash
# Replace INSTALL_WORK with:
INSTALL_TIER="config"  # Default tier
```

**New argument cases:**
- `--config|--sync` → `INSTALL_TIER="config"`
- `--shell` → `INSTALL_TIER="shell"`
- `--dev` → `INSTALL_TIER="dev"`
- `--full|--work` → `INSTALL_TIER="full"`

**Add tier helper function:**
```bash
tier_includes() {
    local required="$1"
    case "$INSTALL_TIER" in
        full) return 0 ;;
        dev) [[ "$required" != "full" ]] ;;
        shell) [[ "$required" == "config" || "$required" == "shell" ]] ;;
        config) [[ "$required" == "config" ]] ;;
    esac
}
```

**Reorganize phase_install_packages():**
- Skip entirely if `INSTALL_TIER="config"`
- Call `install_shell_tier_packages` if tier >= shell
- Call `install_dev_tier_packages` if tier >= dev
- Call `install_full_tier_packages` if tier >= full

**Update phase_verify_system():**
- Soften Ubuntu requirement for config tier (warn instead of error)
- Skip locale generation for config tier (requires sudo)

**Update show_help():**
- Document all tiers with examples
- Explain cumulative behavior

**Update banner:**
- Show selected tier instead of "Base + Work + Personal"

### 2. lib.sh

**Add new tier installation functions:**

```bash
install_shell_tier_packages() {
    # APT: git, build-essential, zsh, bat, fd-find, ripgrep, fzf, httpie, htop, tree, python3-pip, pipx
    # WSL: socat, wslu (if detected)
    # Scripts: install-starship.sh, install-eza.sh, install-zoxide.sh
}

install_dev_tier_packages() {
    # Scripts: install-neovim.sh, install-lazygit.sh
    # APT: tmux (if not present)
}

install_full_tier_packages() {
    # Existing: install_work_packages (Azure CLI, python3-dev)
    # Scripts: install-nvm.sh, install-pyenv.sh, install-claude-code.sh
    # Function: install_docker
}
```

**Remove `install_base_packages`** - replaced by tier functions

## Key Design Decisions

1. **Default to `--config`**: Safest option, shell configs already handle missing tools via fallbacks

2. **No special handling for existing tools**: Running `--config` after `--full` is fine - configs detect available tools

3. **Backwards compatibility**: `--work` continues to work as alias for `--full`

4. **Graceful failures in shell/dev tiers**: Use `|| warn` instead of `|| exit 1` for non-critical tools

## Verification

After implementation, test:

```bash
# Test dry-run for each tier
./setup.sh --dry-run                    # Should show config-only actions
./setup.sh --shell --dry-run            # Should show shell tier packages
./setup.sh --dev --dry-run              # Should show dev tier additions
./setup.sh --full --dry-run             # Should show full tier additions
./setup.sh --full --personal --dry-run  # Should show everything

# Test backwards compatibility
./setup.sh --work --dry-run             # Should equal --full

# Test config tier on clean system (no sudo needed)
./setup.sh --config

# Verify symlinks created
ls -la ~/.bashrc ~/.zshrc ~/.gitconfig
```
