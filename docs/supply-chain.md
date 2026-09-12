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
| Codex | moving official installer | HTTPS-trusted installer file; official `CODEX_NON_INTERACTIVE=1` mode; release layout preserves the prior launcher on failed migration |
| opencode | moving official installer | HTTPS-trusted installer file with `--no-modify-path`; verified owned binary and launcher |
| Pi | npm package | npm registry trust, isolated prefix, lifecycle scripts disabled, verified launcher; one exact known transitive `node-domexception@1.0.0` deprecation line is filtered while all other npm diagnostics remain visible |
| Ubuntu/Docker/Azure packages | APT | package-manager in-place transaction; Docker and Microsoft repository keys are fingerprint checked |
| Docker Sandboxes | Docker signed APT repository | `docker-sbx`; executable check; sandbox state and credentials preserved |
| Tailscale | Tailscale signed APT repository | release-specific official keyring/list; no enrollment or auth-key handling |
| Google Cloud CLI | Google signed APT repository | official `google-cloud-cli` package; credentials preserved |
| AWS CLI v2 | signed AWS distribution | amd64/arm64 ZIP plus detached signature verified with the AWS CLI Team key and pinned fingerprint; `/usr/local/aws-cli` ownership explicit |

Some upstream projects do not publish stable checksums or signatures for every
asset. This repository records that limitation instead of embedding hashes from
an unauthenticated source or implying a guarantee the upstream process does not
provide. A failed staged replacement leaves the previous dotfiles-owned binary
or tree runnable. APT and vendor-managed in-place updates may leave partial
upstream state; rerun the same setup selection after correcting the reported
cause.

APT runs noninteractively and waits a bounded 120 seconds for package-manager
locks (`DOTFILES_APT_LOCK_TIMEOUT` overrides this). The dev tier installs
`locales` before generating `en_US.UTF-8`, which keeps minimal Ubuntu images
from failing an early `locale-gen` call. Lock files are never deleted.

Repository configuration and package migration are separate. Adding Docker's
repository for `sbx` never removes existing container runtimes. Docker Engine
conflicts produce a manual migration diagnostic. The bundled AWS CLI Team key
and fingerprint must be reviewed together when AWS rotates its signing key.
As checked on 2026-09-11, AWS's current install page and current detached ZIP
signature still use `FB5DB77FD5C118B80511ADA8A6310ACC4672475C`; `gpgv`
validated that day's artifact even though the key's displayed expiration is
2026-07-07. Treat any signer change or verification failure as a hard stop.
