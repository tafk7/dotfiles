# Supply-chain policy

All downloads require HTTPS, TLS 1.2 or newer, bounded connection/transfer
timeouts, and a non-empty response. Installer scripts are downloaded to a file
and checked for a shell shebang before execution; they are never piped directly
from the network into a shell and are never executed with `sudo`.

| Component | Version policy | Authenticity / replacement contract |
|---|---|---|
| eget | pinned release | HTTPS-trusted release asset; staged executable check and atomic replacement |
| eget-managed CLI tools | pinned in `eget.toml`; asset locked in `eget.lock` | exact asset by download URL (no GitHub API call), SHA-256 verified against the lock; staged executable check and atomic replacement |
| Neovim | pinned release (`lib/config.sh`) | release asset SHA-256 verified against the pin; archive-layout and executable checks; staged tree replacement |
| vim-plug | commit `88e31471818e9a29a8a20a0ee61360cfd7bdc1cd` | explicit `install-editor-plugins` action; HTTPS-trusted immutable source; existing manager preserved |
| tmux | pinned release (`lib/config.sh`) | source archive SHA-256 verified against the pin; staged build and executable check before replacement |
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

The `eget.lock`, Neovim and tmux checksums pin the bytes first seen over HTTPS
when the version was bumped, cross-checked with the SHA-256 digest GitHub
publishes for the asset where it has one. They make every later install
identical and detect a release asset that changes afterwards; they do not vouch
for the release itself.

Some upstream projects do not publish stable checksums or signatures for every
asset. This repository records that limitation instead of embedding hashes from
an unauthenticated source or implying a guarantee the upstream process does not
provide. Download/validation failures preserve the working artifact; see
[recovery](maintenance.md#recovery) for replacement and ledger failures. APT and
vendor-managed in-place updates may leave partial upstream state; rerun the same
setup selection after correcting the reported cause.

APT runs noninteractively and waits a bounded 120 seconds for package-manager
locks (`DOTFILES_APT_LOCK_TIMEOUT` overrides this). The dev tier installs
`locales` before generating `en_US.UTF-8`, which keeps minimal Ubuntu images
from failing an early `locale-gen` call. Lock files are never deleted.

Repository configuration and package migration are separate. Adding Docker's
repository for `sbx` never removes existing container runtimes. Docker Engine
conflicts produce a manual migration diagnostic. The bundled AWS CLI Team key
and fingerprint (`FB5DB77FD5C118B80511ADA8A6310ACC4672475C`) must be reviewed
together when AWS rotates its signing key. The key's displayed expiration
(2026-07-07) has passed, but AWS still signs with it and `gpgv` accepts the
signatures (last checked 2026-09-11). Treat any signer change or verification
failure as a hard stop.
