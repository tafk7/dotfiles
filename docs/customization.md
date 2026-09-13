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
| Shell entrypoints | `entry/{bash.sh,zsh.sh,profile.sh}`     | Symlinked to `~/.bashrc`, `~/.zshrc`, `~/.profile`. Resolve the checkout from the symlink or XDG state, load Layer 0, then interactive layers. |
| Shell startup    | `shell/env.sh`, `shell/init.sh`, `shell/tools/*.sh`, `shell/platform/*.sh` | PATH composition, tool-init, domain-grouped functions/aliases. |
| Themes           | `themes/<name>/`                         | One directory per theme. `bin/theme-switcher` writes runtime files.                  |

## Adding a New APT Package

Edit `lib/config.sh` and add the package to the appropriate `PACKAGES` group:

```bash
declare -A PACKAGES=(
    [core]="git build-essential"
    [development]="zsh ... lsof psmisc your-package"  # add here
    ...
)
```

Tier-owned APT packages start at dev, while orthogonal Tailscale/RDP/cloud
selections can require APT independently. The bash tier remains sudo-free
(eget only). Groups are mapped to selections in `lib/install.sh`:

- `install_bash_packages`  → (no apt; eget binaries only, plus a git-present check)
- `install_dev_packages`   → core + development + languages + terminal + diagramming (+ wsl on WSL); then tmux + neovim installers
- `install_work_packages`  → NVM/node, Docker, sbx/KVM host access, and Rust
- `install_ai_packages`    → selected Claude, Codex, opencode, and Pi installers
- `install_rdp_packages`   → rdp (then runs the xrdp config installer)
- `install_tail_packages` → optional Tailscale package/service without enrollment

## Adding a New Binary Tool (eget)

1. Add a release block to `eget.toml`:
   ```toml
   ["owner/repo"]
   tag = "v1.2.3"
   asset_filters = [".tar.gz", "gnu"]
   ```

2. Register the tool in `lib/registry.sh`:
   ```bash
   TOOL_BINARY[mytool]=mytool
   TOOL_METHOD[mytool]=eget
   TOOL_TIER[mytool]=bash      # bash|dev|work; omit for capability-only tools
   TOOL_PLATFORM[mytool]=ubuntu
   TOOL_ARCHES[mytool]='x86_64,aarch64'
   TOOL_OWNERSHIP_ROOTS[mytool]="$HOME/.local/bin"
   TOOL_UPDATE_CONTRACT[mytool]=staged-release
   TOOL_COMPANIONS[mytool]='helper'  # only when the release includes one
   ```

   Put entries into the existing tables/default loops. Capability-only tools
   also need `TOOL_CAPABILITIES`; omit their cumulative tier. Companion names
   automatically participate in verification and removal. Use `TOOL_EGET_REPO`
   when the short tool name differs from the repository basename.

3. Run `./setup.sh --bash` to install through selection, staging, and the ledger.
4. `bin/verify` and `bin/uninstall-tool` automatically pick up the new tool.

## Adding a New Tool With a Custom Installer

For tools that need more than `eget`:

1. Create `installers/install-mytool.sh`. Follow the existing pattern:
   - `set -euo pipefail`
   - Source `lib/install.sh` if needed
   - Exit `0` on install/update, `2` if already up-to-date, `1` on failure
   - **Never let a vendor installer edit shell rc files.** `~/.bashrc`/`~/.zshrc`
     are dotfiles symlinks, so an installer that appends a PATH/init block writes
     straight through into the tracked repo. Suppress it and manage PATH yourself
     (`~/.local/bin` is already on PATH via `shell/env.sh`, or symlink the binary
     there like `bat`/`fd`/`opencode`). Suppression varies by tool:
     `--no-modify-path` (opencode), `PROFILE=/dev/null` (nvm), or install to a
     dir already on PATH so the installer skips the edit (claude). When a vendor
     installer offers **no** suppression at all — Pi's `pi.dev/install.sh`
     interactively appends a PATH line and has no opt-out — don't use it: drive
     the underlying package manager yourself into a controlled prefix and
     symlink the result (see `installers/install-pi.sh`). Either way, end the
     installer with the `git diff -- entry/ shell/` safety net the AI installers
     use, so a write-through is caught rather than assumed impossible.
2. Register in `lib/registry.sh`:
   ```bash
   TOOL_BINARY[mytool]=mytool
   TOOL_METHOD[mytool]=installer
   TOOL_TIER[mytool]=dev
   TOOL_PATHS[mytool]="$HOME/.local/bin/mytool"
   TOOL_OWNERSHIP_ROOTS[mytool]="$HOME/.local/bin"
   TOOL_UPDATE_CONTRACT[mytool]=staged-release
   ```
3. Call it from the appropriate `install_*_packages` function in `lib/install.sh`:
   ```bash
   run_installer "mytool" || failed=true
   ```
   The caller propagates `failed` as a nonzero return; requested installation
   failures make setup incomplete. A function called through `if`, `!`, or `||`
   cannot rely on `set -e` internally: check each required mutation explicitly.
   The runner records outcomes; standalone staged helpers record committed
   artifacts. Never claim ownership merely because a skipped tool is local.

## Adding a New Config File

Edit `lib/config.sh` and add to `CONFIG_MAP`:

```bash
declare -A CONFIG_MAP=(
    ...
    [your-config]="$HOME/.your-config:symlink:"
    [config/your-app]="${XDG_CONFIG_HOME:-$HOME/.config}/your-app:symlink:your-app"
)
```

- Source path is resolved by `config_source_path()`:
  - `bash.sh|zsh.sh|zshenv|zprofile|profile.sh|bash_profile` → `entry/`
  - everything else → `configs/`
- Place the file at the resolved source path, then run `./setup.sh --config`.
- Type `gitconfig` renders portable behavior and includes it from the user's
  existing global file. Identity remains in `~/.gitconfig.local`; missing
  Neovim/Delta integrations are omitted according to tool availability.

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

For WSL-specific code, use `shell/platform/wsl.sh`. Additional platform adapters
require an explicit loading condition in `shell/init.sh`.

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

For the `gcl-amd` helper, set the GitHub login associated with the AMD account
after authenticating it with `gh`:

```bash
# ~/.shell.local
GH_AMD_USER=your-amd-github-login
```

`gcl-amd OWNER/REPO [DIRECTORY]` clones through the machine-local
`github.com-amd` SSH alias and records the repository's real `github.com`
identity for GitHub CLI commands. It uses the AMD token only during that setup
and does not change the globally active `gh` account.

### Per-machine git identity and commit signing

Setup renders the tracked portable base to
`${XDG_CONFIG_HOME:-~/.config}/dotfiles/gitconfig` and adds an include to the
existing `~/.gitconfig`; it never replaces that user-owned file. Put identity
and signing in the final `~/.gitconfig.local` include. Example (SSH signing):

```ini
# ~/.gitconfig.local
[user]
    email = you@work.example
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

The relay runs as a **systemd user service** (`wsl2-ssh-agent.service`, installed by
`setup.sh` on opt-in WSL machines) so it is up at **boot** — visible to every shell,
tmux pane, and captured environment (e.g. an editor/agent that snapshots the shell),
and it survives reboots. The old shell-startup `eval` remains only as a *fallback* in
`shell/platform/wsl.sh`, for hosts without systemd or when the marker is added after
install.

1. Windows: enable the SSH agent in Bitwarden, disable the Windows *"OpenSSH
   Authentication Agent"* service (so Bitwarden owns the pipe), store/generate
   your key. Verify with `ssh-add.exe -l`.
2. WSL: opt in with the marker, then run setup — it installs `wsl2-ssh-agent` (eget)
   **and** the boot-time service (`systemctl --user enable --now` + linger):
   ```bash
   touch ~/.ssh/use-windows-agent
   ./setup.sh --bash        # installs the relay + enables wsl2-ssh-agent.service
   ssh-add -l                # should list your Bitwarden key
   ```
   The unit carries `ConditionPathExists=%h/.ssh/use-windows-agent`, so removing the
   marker disables it cleanly. If the relay ever drops mid-session (e.g. Bitwarden was
   locked), run **`ssh-bridge restart`** to restart it.
3. Git signing (optional): paste Bitwarden's WSL signing snippet into
   `~/.gitconfig.local`.

**Work machine — local on-disk keys (the bridge stays off).** Leave the
`~/.ssh/use-windows-agent` marker absent (the default): `setup.sh` does not install
the `wsl2-ssh-agent.service`, `shell/platform/wsl.sh` skips the bridge, and
`SSH_AUTH_SOCK` is left alone — so the local `ssh-agent` and your work's `~/.ssh`
key files work normally.

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
run_installer "name" || failed=true # runs installers/install-name.sh
track_install "name" ok|skip|fail   # contributes to the summary
```

Work-host mutations, including group and service changes, belong in
`lib/install.sh`. Shared KVM/service/group/daemon observations belong in
`lib/work-host.sh`, which is safe for verification commands. Do not add these
probes to shell startup.

Available everywhere (sourced by `lib/runtime.sh`):

```bash
is_wsl                # 0 if on WSL
command_exists git
verify_binary nvim    # exists AND --version works
get_arch              # x86_64 | aarch64
version_gte "$a" "$b" # 0 if a >= b
```

## Adding a Theme

See [`docs/theme-system.md`](./theme-system.md). Short version: create
`themes/<name>/` with `meta.sh`, `palette.sh`, `vim.vim`, `shell.sh`
plus the per-tool palette files (`bat/<name>.tmTheme`, `starship.palette.toml`,
`delta.gitconfig`, `btop.theme`, `lazygit.yml`). The theme is auto-discovered
on next `bin/theme-switcher` invocation.

## Testing Your Changes

```bash
./bin/verify              # reports configs / tools / env health
bash -n shell/env.sh      # syntax check any modified shell script
./setup.sh --dry-run --bash     # preview install without making changes
```

For theme changes, use the isolated automated checks. They create a temporary
HOME and a named tmux server, so they do not switch the live theme:

```bash
tests/theme-contrast.py
tests/theme-system.sh
```

## Best Practices

- **Don't put business logic in `setup.sh`** — it's an orchestrator. Add to
  `lib/`, `installers/`, or `shell/`.
- **Don't `set EDITOR` outside `shell/env.sh`** — it's the single source of
  truth (verified by `bin/verify`).
- **Keep install libraries out of shell startup.** Runtime helpers are used by
  commands; the shell entry chain loads the environment layers directly.
- **Use the installer runner** so outcomes and ownership are recorded consistently.
- **Pin tool versions in `eget.toml`** — bump explicitly, not implicitly.

## Getting Help

- `./bin/verify` shows what's broken.
- `./setup.sh --help` lists tier flags.
- `./bin/theme-switcher --help` lists theme commands.
- See `lib/runtime.sh` and `lib/install.sh` for the full helper surface.
