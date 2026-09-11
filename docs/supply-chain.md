# Supply-chain policy

All downloads require HTTPS, TLS 1.2 or newer, bounded connection/transfer
timeouts, and a non-empty response. Installer scripts are downloaded to a file
and checked for a shell shebang before execution; they are never piped directly
from the network into a shell and are never executed with `sudo`.

| Component | Version policy | Authenticity / replacement contract |
|---|---|---|
| eget | pinned release | HTTPS-trusted release asset; staged executable check and atomic replacement |
| eget-managed CLI tools | pinned in `eget.toml` | eget native architecture selection; staged executable check and atomic replacement |
| Neovim | latest compatible release (0.10.4 fallback for old glibc) | HTTPS-trusted release asset; archive-layout and executable checks; staged tree replacement |
| tmux | latest release | HTTPS-trusted source archive; staged build and executable check before replacement |
| NVM | pinned installer v0.40.4 | HTTPS-trusted installer file; no shell-RC modification; prior tree retained on installer failure |
| Rust | moving rustup installer | HTTPS-trusted installer file; in-place upstream mutation; recover with `rustup update`/`rustup self uninstall` |
| Claude Code | moving official installer | HTTPS-trusted installer file; verified owned launcher after execution |
| Codex | moving official installer | HTTPS-trusted installer file; official release layout preserves the prior launcher on failed migration |
| opencode | moving official installer | HTTPS-trusted installer file with `--no-modify-path`; verified owned binary and launcher |
| Pi | npm package | npm registry trust, isolated prefix, lifecycle scripts disabled, verified launcher |
| Ubuntu/Docker/Azure packages | APT | package-manager in-place transaction; Docker and Microsoft repository keys are fingerprint checked |

Some upstream projects do not publish stable checksums or signatures for every
asset. This repository records that limitation instead of embedding hashes from
an unauthenticated source or implying a guarantee the upstream process does not
provide. A failed staged replacement leaves the previous dotfiles-owned binary
or tree runnable. APT and vendor-managed in-place updates may leave partial
upstream state; rerun the same setup selection after correcting the reported
cause.
