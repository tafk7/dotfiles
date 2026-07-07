# Dotfiles Customization Guide

This guide explains how to customize and extend the dotfiles system. The repo
is data-driven: you almost never edit `setup.sh` directly. You add an entry to
a declarative table in `lib/config.sh` or `lib/registry.sh`, and the existing
machinery picks it up.

## Architecture in One Page

| Layer            | File(s)                                  | Purpose                                                                              |
| ---------------- | ---------------------------------------- | ------------------------------------------------------------------------------------ |
| Declarative data | `lib/config.sh`, `lib/registry.sh`       | `PACKAGES`, `CONFIG_MAP`, `TOOL_*` arrays. No side effects. Read by every other layer. |
| Runtime helpers  | `lib/runtime.sh`                         | `log`, `success`, `warn`, `error`, `is_wsl`, `command_exists`. Safe everywhere.      |
| Install helpers  | `lib/install.sh`                         | `install_apt`, `safe_sudo`, `run_installer`, `track_install`. Sourced ONLY by `setup.sh` and installers. |
| Tool installers  | `installers/install-<tool>.sh`           | One script per non-apt tool (neovim, tmux, nvm, …). Exit 0 = installed, 2 = up-to-date, 1 = failed. |
| Shell entrypoints | `entry/{bash.sh,zsh.sh,profile.sh}`     | Symlinked to `~/.bashrc`, `~/.zshrc`, `~/.profile`. Source `generated/bridge.sh` then `shell/init.sh`. |
| Shell startup    | `shell/env.sh`, `shell/init.sh`, `shell/tools/*.sh`, `shell/platform/*.sh` | PATH composition, tool-init, domain-grouped functions/aliases. |
| Themes           | `themes/<name>/`                         | One directory per theme. `bin/theme-switcher` writes runtime files.                  |

## Adding a New APT Package

Edit `lib/config.sh` and add the package to the appropriate `PACKAGES` group:

```bash
declare -A PACKAGES=(
    [core]="git build-essential"
    [development]="zsh direnv ... lsof psmisc your-package"  # add here
    [modern]="bat fd-find ripgrep"
    ...
)
```

Groups are mapped to tiers in `lib/install.sh`:

- `install_shell_packages` → core + development + modern + languages + terminal (+ wsl on WSL)
- `install_dev_packages`   → diagramming
- `install_work_packages`  → docker
- `install_ai_packages`    → (no apt packages; runs the claude + codex installers)

## Adding a New Binary Tool (eget)

1. Add a release block to `eget.toml`:
   ```toml
   ["owner/repo"]
   tag = "v1.2.3"
   asset_filters = [".tar.gz", "gnu"]
   ```

2. Register the tool in `lib/registry.sh` (all five arrays):
   ```bash
   TOOL_BINARY[mytool]=mytool
   TOOL_METHOD[mytool]=eget
   TOOL_TIER[mytool]=shell      # shell|dev|work|ai
   ```

3. Run `./setup.sh --shell` (or just `eget --download-all`) to install.
4. `bin/verify` and `bin/uninstall-tool` automatically pick up the new tool.

## Adding a New Tool With a Custom Installer

For tools that need more than `eget`:

1. Create `installers/install-mytool.sh`. Follow the existing pattern:
   - `set -euo pipefail`
   - Source `lib/install.sh` if needed
   - Exit `0` on install/update, `2` if already up-to-date, `1` on failure
2. Register in `lib/registry.sh`:
   ```bash
   TOOL_BINARY[mytool]=mytool
   TOOL_METHOD[mytool]=installer
   TOOL_TIER[mytool]=dev
   TOOL_PATHS[mytool]="\$HOME/.local/bin/mytool"   # for bin/uninstall-tool
   ```
3. Call it from the appropriate `install_*_packages` function in `lib/install.sh`:
   ```bash
   run_installer "mytool"           # non-critical; warn-only on failure
   run_installer "mytool" true      # critical; abort setup on failure
   ```

## Adding a New Config File

Edit `lib/config.sh` and add to `CONFIG_MAP`:

```bash
declare -A CONFIG_MAP=(
    ...
    [your-config]="$HOME/.your-config:symlink"
    [config/your-app]="$HOME/.config/your-app:symlink"
)
```

- Source path is resolved by `config_source_path()`:
  - `bash.sh|zsh.sh|profile.sh|bash_profile` → `entry/`
  - everything else → `configs/`
- Place the file at the resolved source path, then run `./setup.sh --config`.
- Type `gitconfig` is special-cased for template processing (`{{GIT_NAME}}`,
  `{{GIT_EMAIL}}`).

## Adding Custom Aliases or Functions

Shell tooling is grouped by domain in `shell/tools/`:

```
shell/tools/
├── claude.sh    # Claude Code helpers
├── docker.sh    # docker / compose aliases
├── fzf.sh       # fzf-* functions and bindings
├── general.sh   # ll, la, reload, ...
├── git.sh       # git aliases beyond gitconfig
├── nav.sh       # cdl, mkcd, proj, add_to_path
├── node.sh      # npm/yarn/pnpm shortcuts
├── process.sh   # killport, pidof helpers
├── python.sh    # venv helpers
├── tmux.sh      # tmux session helpers
├── vim.sh       # vim wrappers
└── vscode.sh    # code/cdiff/cf/cproj
```

Add to an existing file when your function fits a domain. Create a new
`shell/tools/<domain>.sh` only when there's a clear new domain (e.g. `kube.sh`).
All `*.sh` in `shell/tools/` are sourced automatically by `shell/init.sh`.

For WSL-specific code, use `shell/platform/wsl.sh` (only sourced when
`is_wsl` is true). For Linux-specific (non-WSL), use `shell/platform/linux.sh`.

## Adding a `bin/` Utility Command

The small maintainer/runtime commands in `bin/` (`verify`, `diff-config`,
`check-updates`, `ssh-bridge`, …) follow one convention so they stay
**self-documenting and self-cataloging** — there is no hand-maintained list to
keep in sync.

Every `bin/` script:

1. **Line 2 is a one-line `# description`** (right after the shebang). This is
   the single source of truth for "what does this do".
2. **Prints its own header as `--help`** via `usage() { sed -n '2,Np' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; }`.
3. **Sources `lib/runtime.sh`** for `log`/`success`/`warn`/`error`, colors, and
   helpers (`is_wsl`, `command_exists`, `verify_binary`).
4. Is committed executable (`git update-index --chmod=+x bin/<name>`).

Skeleton:

```bash
#!/bin/bash
# One-line description of what this command does.   # <- line 2, the catalog entry
#
# Usage:
#   <name> [args]    ...
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="${DOTFILES_DIR:-$(dirname "$SCRIPT_DIR")}"
source "$DOTFILES_DIR/lib/runtime.sh"
usage() { sed -n '2,5p' "${BASH_SOURCE[0]}" | sed 's/^# \?//'; }
# ...
```

**Tracking — it's automatic.** `bin/cheatsheet commands` scans `bin/` and prints
every script with its line-2 description, so a new utility shows up the moment
it lands — no registry edit, no doc edit. `cheat commands` (and the interactive
`cheat`) surface the same list. That's the catalog; this section is just the
recipe.

## Local Overrides (Per-Machine, Untracked)

Keep machine-specific tweaks out of git via `*.local`:

- `~/.shell.local` — sourced at the end of `shell/init.sh` for both bash and
  zsh. The single override hook for aliases, exports, secrets, and tweaks.
  Gate shell-specific syntax with `[[ -n "$ZSH_VERSION" ]]` /
  `[[ -n "$BASH_VERSION" ]]` blocks if needed.
- `~/.gitconfig.local` — included last by the templated `~/.gitconfig`, so its
  values override everything in the tracked config. Use it for per-machine git
  identity (e.g. a work email) and commit signing — neither belongs in the repo.

These are gitignored.

### Per-machine git identity and commit signing

The tracked `~/.gitconfig` sets a baseline; layer machine-specific identity and
signing on top via `~/.gitconfig.local`. Example (SSH signing):

```ini
# ~/.gitconfig.local
[user]
    email = you@work.example          # override the baseline identity per machine
    signingkey = ~/.ssh/id_ed25519.pub
[gpg]
    format = ssh
[commit]
    gpgsign = true
[tag]
    gpgsign = true
```

Signing lives here — not in the tracked config — because it only works on
machines that actually hold the key. Enabling `gpgsign` globally would break
commits anywhere the key is missing.

### Secrets: keep them out of the repo

This repo deliberately tracks **no secrets** and provides no in-repo encryption.
Tokens, keys, and credentials go in the untracked override files above
(`~/.shell.local`, `~/.gitconfig.local`), which are gitignored and never leave
the machine.

If you ever need to *sync* secrets across machines, do **not** commit them here —
even encrypted blobs invite mistakes. Reach for a purpose-built tool instead:
[`age`](https://github.com/FiloSottile/age)/[`sops`](https://github.com/getsops/sops)
for encrypted files, or a password manager (1Password, Bitwarden, `pass`) fetched
at shell-init time into `~/.shell.local`. Managers like `chezmoi`/`yadm` exist
largely to solve this; the untracked-override model here sidesteps it by design.

### SSH keys across machines (personal vs work)

The repo supports two SSH key models per machine, switched without editing any
tracked file:

**Personal machine — vault-backed key via the Windows agent (no keys on disk).**
A password manager (e.g. Bitwarden) holds the key and serves the standard
`\\.\pipe\openssh-ssh-agent` Windows pipe; `wsl2-ssh-agent` bridges that pipe into
WSL. One agent then serves Windows, WSL, and VS Code.

1. Windows: enable the SSH agent in Bitwarden, disable the Windows *"OpenSSH
   Authentication Agent"* service (so Bitwarden owns the pipe), store/generate
   your key. Verify with `ssh-add.exe -l`.
2. WSL: `./setup.sh --shell` installs `wsl2-ssh-agent` (eget). Enable the bridge
   with the marker file, then reload:
   ```bash
   touch ~/.ssh/use-windows-agent && reload
   ssh-add -l            # should list your Bitwarden key
   ```
3. Git signing (optional): paste Bitwarden's WSL signing snippet into
   `~/.gitconfig.local`.

**Work machine — local on-disk keys (the bridge stays off).** Leave the
`~/.ssh/use-windows-agent` marker absent (the default): `shell/platform/wsl.sh`
skips the bridge and leaves `SSH_AUTH_SOCK` alone, so the local `ssh-agent` and
your work's `~/.ssh` key files work normally.

- Put work-specific host config in **`~/.ssh/config.local`** (untracked, included
  first by `ssh_config` so it wins):
  ```
  # ~/.ssh/config.local
  Host github.com
      IdentityFile ~/.ssh/work_ed25519
      IdentitiesOnly yes
  ```
- Put work git identity/signing in `~/.gitconfig.local`.

The two markers are independent and untracked, so the same dotfiles checkout
behaves correctly on both machines with zero per-pull edits.

## Framework Helpers Available

In `installers/install-*.sh` and `lib/install.sh`-context only:

```bash
log "Info message"
success "OK"
warn "Heads up"
error "Failure"
wsl_log "WSL-specific message"

safe_sudo apt-get install -y foo    # honors DRY_RUN, logs the command
install_apt "label" pkg1 pkg2 ...   # idempotent, batches missing pkgs
run_installer "name" [critical]     # runs installers/install-name.sh
track_install "name" ok|skip|fail   # contributes to the summary
```

Available everywhere (sourced by `lib/runtime.sh`):

```bash
is_wsl                # 0 if on WSL
command_exists git
verify_binary nvim    # exists AND --version works
get_arch              # x86_64 | aarch64
get_glibc_version     # 2.35
version_gte "$a" "$b" # 0 if a >= b
```

## Adding a Theme

See [`docs/theme-system.md`](./theme-system.md). Short version: create
`themes/<name>/` with `meta.sh`, `vim.vim`, `tmux.conf`, `shell.sh`, `colors.sh`
plus the per-tool palette files (`bat/<name>.tmTheme`, `starship.palette.toml`,
`delta.gitconfig`, `btop.theme`, `lazygit.yml`). The theme is auto-discovered
on next `bin/theme-switcher` invocation.

## Testing Your Changes

```bash
./bin/verify              # reports configs / tools / env health
bash -n shell/env.sh      # syntax check any modified shell script
./setup.sh --dry-run --shell    # preview install without making changes
```

For theme changes, cycle every theme to make sure your wiring works:

```bash
for t in nord tokyo-night kanagawa catppuccin gruvbox; do
    ./bin/theme-switcher "$t"
done
```

## Best Practices

- **Don't put business logic in `setup.sh`** — it's an orchestrator. Add to
  `lib/`, `installers/`, or `shell/`.
- **Don't `set EDITOR` outside `shell/env.sh`** — it's the single source of
  truth (verified by `bin/verify`).
- **Don't add side effects to `lib/runtime.sh` or `lib/config.sh`** — they're
  sourced on every shell start.
- **Use `track_install`** in installers so the install summary stays accurate.
- **Pin tool versions in `eget.toml`** — bump explicitly, not implicitly.

## Getting Help

- `./bin/verify` shows what's broken.
- `./setup.sh --help` lists tier flags.
- `./bin/theme-switcher --help` lists theme commands.
- See `lib/runtime.sh` and `lib/install.sh` for the full helper surface.
