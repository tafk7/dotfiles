# Customization

Most extensions are table entries in `lib/config.sh` or `lib/registry.sh`;
`setup.sh`, `bin/verify`, `bin/uninstall-tool`, and `bin/cheatsheet` read those
tables, so they pick up a new entry without code changes. See
[architecture](architecture.md) for how the pieces fit together.

## Adding an APT package

Add it to the appropriate `PACKAGES` group in `lib/config.sh`. The bash tier is
sudo-free, so tier-owned APT packages start at dev. Groups map to selections in
`lib/install.sh`:

- `install_dev_packages`: core, development, languages, terminal, diagramming
  (plus wsl on WSL), then the tmux and Neovim installers
- `install_work_packages`: NVM/Node, Docker, sbx/KVM host access, Rust
- `install_ai_packages`: the named AI CLI installers
- `install_rdp_packages`: rdp, then the xrdp configuration installer
- `install_tail_packages`: Tailscale package/service without enrollment

## Adding a binary tool (eget)

1. Add a pinned release block to `eget.toml`:
   ```toml
   ["owner/repo"]
   tag = "v1.2.3"
   asset_filters = [".tar.gz", "gnu"]
   ```
   Filters must leave exactly one asset for each supported architecture. Refresh
   the recorded asset lists with `tests/eget-selection.py --refresh`.
2. Register the tool in `lib/registry.sh`:
   ```bash
   TOOL_BINARY[mytool]=mytool
   TOOL_METHOD[mytool]=eget
   TOOL_TIER[mytool]=bash      # bash|dev|work; omit for capability-only tools
   ```
   Add it to the ownership-root/update-contract loop for `~/.local/bin` tools.
   Capability-only tools use `TOOL_CAPABILITIES` instead of a tier. Use
   `TOOL_EGET_REPO` when the tool name differs from the repository basename,
   and `TOOL_COMPANIONS` when the release ships extra executables.
3. Run `./setup.sh --bash` so selection, staging, and ownership recording apply.
   Direct `eget --download-all` bypasses all three.

## Adding a tool with a custom installer

1. Create `installers/install-mytool.sh` with `set -euo pipefail`. Exit `0` when
   installed or updated, `2` when already current, and `1` on failure.

   **Never let a vendor installer edit shell rc files.** `~/.bashrc` and
   `~/.zshrc` are symlinks into this checkout, so an appended PATH block writes
   into the tracked repo. Suppress the edit (`--no-modify-path` for opencode,
   `PROFILE=/dev/null` for NVM, or install into a directory already on PATH as
   for Claude). If the vendor offers no suppression, drive the underlying package
   manager into a controlled prefix instead, as `installers/install-pi.sh` does.
   Take `rc_before="$(rc_snapshot)"` before the vendor step and end with
   `warn_if_rc_changed "$rc_before"`, as the AI installers do.
2. Register it in `lib/registry.sh` with `TOOL_METHOD=installer`, its
   `TOOL_OWNERSHIP_ROOTS`, `TOOL_UPDATE_CONTRACT`, and any `TOOL_PATHS` that
   uninstall may remove.
3. Call it from the appropriate `install_*_packages` function:
   ```bash
   run_installer "mytool" || failed=true
   ```
   Functions called through `if`, `!`, or `||` run without `set -e`, so check
   each required mutation explicitly. The runner records outcomes; never record
   ownership merely because a skipped tool is already present locally.

Host mutations (groups, services) belong in `lib/install.sh`. Read-only
KVM/service/group probes belong in `lib/work-host.sh`, which verification also
uses. Neither is loaded during shell startup.

## Adding an orthogonal capability

Capabilities such as `--tail` or `--aws` compose with any tier. Add a row to
`CAPABILITIES` in `setup.sh` (name, requirements, installer, label) and give the
registry components the capability in `TOOL_CAPABILITIES`. The `--NAME` flag,
preflight checks, install dispatch, banner, and summary all come from the row;
the installer function receives the capability name. Document the flag in
`show_help`.

## Adding a config file

Add the source file, then an entry to `CONFIG_MAP` in `lib/config.sh`:

```bash
[your-config]="$HOME/.your-config:symlink:"
[config/your-app]="${XDG_CONFIG_HOME:-$HOME/.config}/your-app:symlink:your-app"
```

The value is `target:type:owner`. Shell rc sources live in `entry/`, everything
else in `configs/`. An empty owner means the config is always linked; a named
owner links it only when that tool is present. Run `./setup.sh --config`.

## Adding aliases, functions, and commands

Every `shell/tools/*.sh` file is sourced by `shell/init.sh`; add to the matching
domain file or create a new domain. WSL-only code goes in
`shell/platform/wsl.sh`. Add a row to `shell/shortcuts-index.tsv` so `cheat`
can find it.

`bin/` scripts put a one-line description on line 2. `cheat commands` lists
that line, and most scripts print their header comment as `--help`. Source
`lib/runtime.sh` for `log`/`warn`/`error`, `is_wsl`, `command_exists`,
`verify_binary`, `get_arch`, and `version_gte`. Commit the script executable.

## Local overrides

These untracked files keep machine-specific settings out of the repo:

- `~/.shell.local`: sourced near the end of interactive startup in both shells.
  Gate shell-specific syntax on `$ZSH_VERSION` or `$BASH_VERSION`.
- `~/.shell.local.d/*.sh`: sourced in filename order after `~/.shell.local`.
  They run again on `reload`, so keep them idempotent.
- `~/.gitconfig.local`: included last, so it overrides the tracked Git config.
  Azure DevOps organization hosts go here too ([work](work.md#cloud-clis)).
- `~/.ssh/config.local`: included first, so its values win. Named files in
  `~/.ssh/config.d/*.conf` follow it.

```bash
# ~/.shell.local
export PROJECTS_DIRS="$HOME/work/acme:$HOME/projects"
export CODEX_DEFAULT_PROFILE=work     # an explicit -p/--profile still wins
```

These are interactive hooks. Services, desktop applications, and plain
non-interactive shells do not read them.

Employer- or account-specific helpers, such as a clone function pinned to a
second GitHub account, belong in `~/.shell.local` until
[git profiles](../issues/git-profiles.md) provides a tracked mechanism.

### Git identity and signing

Setup renders the portable Git config to
`${XDG_CONFIG_HOME:-~/.config}/dotfiles/gitconfig` and includes it from your
existing `~/.gitconfig`, which it never replaces. Identity and signing go in
`~/.gitconfig.local`. Signing is machine-local because it only works where the
key exists:

```ini
[user]
    email = you@work.example
    signingkey = ~/.ssh/id_ed25519.pub
[gpg]
    format = ssh
[commit]
    gpgsign = true
```

### Secrets

The repo tracks no secrets and has no in-repo encryption. Keep credentials in
the untracked files above. To sync them across machines, use a password manager
or `age`/`sops` from `~/.shell.local`; don't commit encrypted blobs here.

### SSH keys: personal vs work

**Personal WSL machine (vault-backed key, nothing on disk).** A password manager
such as Bitwarden serves the Windows `openssh-ssh-agent` pipe, and
`wsl2-ssh-agent` bridges it into WSL as a systemd user service, so every shell,
tmux pane, and agent snapshot sees it from boot.

1. In Windows, enable Bitwarden's SSH agent and disable the Windows "OpenSSH
   Authentication Agent" service. Check with `ssh-add.exe -l`.
2. In WSL, run `./bin/ssh-bridge enable` (or `touch ~/.ssh/use-windows-agent`,
   then `./setup.sh --bash`). Check with `ssh-add -l`.
3. If the relay drops, for example because the vault locked, run
   `ssh-bridge restart`.

The unit is conditional on the marker file, so deleting the marker disables it.
Without systemd, `shell/platform/wsl.sh` starts the bridge from shell startup
instead.

**Work machine (local keys).** Leave the marker absent. The bridge is not
installed and `SSH_AUTH_SOCK` is untouched. Put work host settings in
`~/.ssh/config.local`:

```
Host github.com
    IdentityFile ~/.ssh/work_ed25519
    IdentitiesOnly yes
```

## Adding a theme

See [adding a complete theme](theme-system.md#adding-a-complete-theme).

## Checking changes

```bash
bash -n path/to/script.sh
./setup.sh --dry-run --bash
./bin/verify
```

For the full suite and its isolation rules, see [testing](testing.md). Develop
in a separate checkout, not the live one (see [maintenance](maintenance.md)).

## Conventions

- `setup.sh` orchestrates. Put logic in `lib/`, `installers/`, or `shell/`.
- Set `EDITOR` only in `shell/env.sh`; `bin/verify` checks this.
- Keep install libraries out of shell startup.
- Pin tool versions and bump them explicitly.
