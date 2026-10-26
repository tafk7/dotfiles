# Customization

Most extensions are table entries in `lib/config.sh` or `lib/registry.sh`;
`setup.sh`, `bin/verify`, `bin/uninstall-tool`, and `bin/cheatsheet` read those
tables, so they pick up a new entry without code changes. Setup installs the
selected entries of the registry's install order (`_REGISTRY_ORDER`), so a new
component also needs a place there, after everything its `needs` names; the
help text's tool lists come from the same tables. See
[architecture](architecture.md) for how the pieces fit together.

## Adding an APT package

Add it to the appropriate `PACKAGES` group in `lib/config.sh`. The bash tier is
sudo-free, so tier-owned APT packages start at dev. A tier's groups install as
its package set (`install_package_set` in `lib/install.sh`; the `packages:dev`
and `packages:work` entries of the install order):

- `dev`: core, development, languages, terminal, diagramming (plus wsl on WSL),
  before the components that need them (zsh, tmux)
- `work`: the Python headers and venv module
- the rdp group installs with xrdp (`install_rdp_packages`), which preseeds
  the display-manager answer first

## Adding a binary tool (eget)

1. Add a pinned release block to `eget.toml`:
   ```toml
   ["owner/repo"]
   tag = "v1.2.3"
   asset_filters = [".tar.gz", "gnu"]
   ```
   Filters must leave exactly one asset for each supported architecture. Then
   run `python3 tests/eget-selection.py --refresh` (after any tag bump too): it
   records the release's asset lists and writes the tool's `versions.lock`
   rows: the exact asset, its SHA-256, the file to extract, and that file's
   SHA-256 per architecture. Setup downloads exactly that without asking the
   GitHub API, and treats the tool as current only while its binary's SHA-256
   matches. Commit all three.
2. Add one row to the core table in `lib/registry.sh`, and the name to the
   install order among the other eget tools:
   ```text
   # name   binary  method  tier  capabilities  platform  arches  ubuntu  apt  verify
   mytool   -       eget    bash  -             -         -       -       -    -
   ```
   `-` takes the documented default; eget tools are owned under `~/.local/bin`
   with the staged-release contract automatically. Capability-only tools put
   `-` in the tier column and name their capability instead. Add an override
   line (`mytool eget-repo owner/repo`, `mytool companions extra`) only when
   the tool name differs from the repository basename or the release ships
   extra executables.
3. Run `./setup.sh --bash` so selection, staging, and ownership recording apply.
   Direct `eget --download-all` bypasses all three.

## Adding a tool with a custom installer

1. Create `installers/install-mytool.sh` with `set -euo pipefail`. Exit `0` when
   installed or updated, `2` when already current, and `1` on failure. Right
   after sourcing `lib/install.sh`, branch on `--observe` to
   `observe_component mytool` and exit, before any provisioning: observation
   reports what is installed and must change nothing.

   **Never let a vendor installer edit shell rc files.** `~/.bashrc` and
   `~/.zshrc` are symlinks into this checkout, so an appended PATH block writes
   into the tracked repo. Suppress the edit (`--no-modify-path` for opencode,
   `PROFILE=/dev/null` for NVM, or install into a directory already on PATH as
   for Claude). If the vendor offers no suppression, drive the underlying package
   manager into a controlled prefix instead, as `installers/install-pi.sh` does.
   Take `rc_before="$(rc_snapshot)"` before the vendor step and end with
   `warn_if_rc_changed "$rc_before"`, as the AI installers do.
2. Add a core-table row in `lib/registry.sh` with method `installer`, and
   override lines for its `ownership-roots`, `update-contract`, and any `paths`
   that uninstall may remove. Use verify `runs` when a present launcher can
   still be broken. Name what must come first with `needs` (another component
   or a package set), and set `policy` when versions are not the pin's
   (`vendor` for a self-updating CLI).
3. Add it to the install order after everything it needs. Setup then runs the
   installer whenever the component is selected, skips it where it does not
   apply, and does not attempt it after one of its needs failed in the same
   run. Host configuration that belongs with it (groups, services) goes in
   `configure` override functions, which run after the install step whatever it
   did. Functions called through `if`, `!`, or `||` run without `set -e`, so
   check each required mutation explicitly. The runner records outcomes; never
   record ownership merely because a skipped tool is already present locally.

Host mutations (groups, services) belong in `lib/install.sh`. Read-only
KVM/service/group probes belong in `lib/work-host.sh`, which verification also
uses. Neither is loaded during shell startup.

## Adding an orthogonal capability

Capabilities such as `--tail` or `--aws` compose with any tier. Add a row to
the capability table in `lib/registry.sh` (name, requirements, label, help) and
give the registry components the capability in the core table. The `--NAME`
flag, preflight checks, install selection, help, banner, and summary all come
from the row.

## Adding a config file

Add the source file, then an entry to `CONFIG_MAP` in `lib/config.sh`:

```bash
[your-config]="$HOME/.your-config:symlink:"
[config/your-app]="${XDG_CONFIG_HOME:-$HOME/.config}/your-app:symlink:your-app"
```

The value is `target:type:owner`. Shell rc sources live in `entry/`, everything
else in `configs/`. An empty owner means the config is always linked; a named
owner links it only when that tool is present. Run `./setup.sh --config`.

To stop managing a config, delete its entry (and source). Setup records each
config it deploys in `deployed.tsv`, and retires one whose entry is gone: a
link that still points where setup pointed it is removed, a rendered file that
still has the content setup wrote is moved aside, each with a backup. A target
changed since then is kept and reported once. `bin/diff-config` and
`dotfiles verify` list retirements before setup makes them.

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

- `~/.shell.env`: environment only, read by every shell that reads Layer 0,
  including agents' non-interactive shells. It overrides the repo defaults
  for `EDITOR`, `PROJECTS_DIRS`, `RIPGREP_CONFIG_PATH`, `PAGER`, and `LESS`;
  an allowed `.envrc` overrides it in turn. Keep it to plain `export`
  lines: it runs in startup-critical, non-interactive shells.
- `~/.shell.local`: sourced near the end of interactive startup in both shells.
  Gate shell-specific syntax on `$ZSH_VERSION` or `$BASH_VERSION`.
- `~/.shell.local.d/*.sh`: sourced in filename order after `~/.shell.local`.
  They run again on `reload`, so keep them idempotent.
- `CLAUDE_FLAGS`: a stable extension point. The `claude` wrapper
  (`shell/tools/claude.sh`) injects it as separate arguments, so a fragment in
  `~/.shell.local.d/` can export extra flags such as `--plugin-dir`.
- `~/.gitconfig.local`: included last, so it overrides the tracked Git config.
  So does the parked Azure DevOps credential snippet ([work](work.md#cloud-clis)).
- `~/.tmux.local.conf`: sourced at the end of the tmux config, so it
  overrides it. `<prefix> r` reloads it.
- `~/.ssh/config.local`: included first, so its values win. Named files in
  `~/.ssh/config.d/*.conf` follow it.

```bash
# ~/.shell.env
export PROJECTS_DIRS="$HOME/work/acme:$HOME/projects"

# ~/.shell.local
export CODEX_DEFAULT_PROFILE=work     # an explicit -p/--profile still wins
```

The rule: what a program or agent needs goes in `~/.shell.env`; what only a
prompt needs goes in `~/.shell.local`. Secrets stay in `~/.shell.local` unless
agents should have them. `~/.shell.local` and its fragments are interactive
hooks; services, desktop applications, and plain non-interactive shells do not
read them. Plain `bash -c` reads neither file.

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

See [adding a theme](theme-system.md#adding-a-theme).

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
