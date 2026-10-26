# Supply-chain policy

All downloads require HTTPS, TLS 1.2 or newer, bounded connection/transfer
timeouts, and a non-empty response. Installer scripts are downloaded to a file
and checked for a shell shebang before execution; they are never piped directly
from the network into a shell and are never executed with `sudo`.

`versions.lock` is the one record of what dotfiles downloads itself: per
component and architecture, the wanted release, the artifact, its SHA-256, the
file extracted from it, and the installed identity (the extracted binary's
SHA-256, or the version it reports). Installers and checks read only the lock;
`lib/versions.sh` parses it and setup refuses a malformed one before a tier that
downloads.

| Component | Version policy | Authenticity / replacement contract |
|---|---|---|
| eget | pinned release (`versions.lock`) | release archive SHA-256 and extracted binary SHA-256 verified against the lock; staged executable check and atomic replacement |
| eget-managed CLI tools | tags in `eget.toml`; asset, archive SHA-256 and binary SHA-256 in `versions.lock` | exact asset by download URL (no GitHub API call), archive verified against the lock, extracted binary verified against the lock's identity; current only when the installed binary's SHA-256 is the lock's; staged executable check and atomic replacement |
| Neovim | pinned release (`versions.lock`) | release asset SHA-256 verified against the lock; archive-layout and executable checks; staged tree replacement |
| vim-plug | pinned commit (`versions.lock`) | installed when editor plugins are enrolled; `plug.vim` SHA-256 verified against the lock; a dotfiles-installed copy moves with the pin, any other is preserved |
| Neovim plugins | commit-pinned in `configs/init.vim` | cloned by vim-plug, then each checkout moved to its pinned commit (one with local changes is left alone); no post-install hooks, so the fzf plugin never downloads its own binary and uses the eget-pinned `fzf` on PATH |
| tmux | pinned release (`versions.lock`) | source archive SHA-256 verified against the lock; staged build and executable check before replacement |
| NVM | pinned installer (`versions.lock`) | installer `install.sh` SHA-256 verified against the lock before it runs; no shell-RC modification; prior tree retained on installer failure |
| Node | pinned release and its bundled npm (`versions.lock`) | installed by NVM, which checks the archive against nodejs.org's `SHASUMS256.txt`; the installed `node` binary's SHA-256 verified against the lock; an independently upgraded npm is restored to the bundled version; other releases and `.nvmrc` versions untouched |
| Rust | moving rustup installer; pinned default toolchain (`versions.lock`) | HTTPS-trusted installer file; toolchains verified by rustup against the channel manifest; the default moves only with the pin, set and read from `/` without `RUSTUP_TOOLCHAIN` or auto-install; recover with `rustup self uninstall` |
| Claude Code | moving official installer | HTTPS-trusted installer file; verified owned launcher after execution |
| Codex | moving official installer | HTTPS-trusted installer file; official `CODEX_NON_INTERACTIVE=1` mode; release layout preserves the prior launcher on failed migration |
| opencode | moving official installer | HTTPS-trusted installer file with `--no-modify-path`; verified owned binary and launcher |
| Pi | npm package | npm registry trust, isolated prefix, lifecycle scripts disabled, verified launcher; one exact known transitive `node-domexception@1.0.0` deprecation line is filtered while all other npm diagnostics remain visible |
| Ubuntu/Docker/Azure packages | APT | package-manager in-place transaction; Docker and Microsoft repository keys are fingerprint checked |
| Docker Sandboxes | Docker signed APT repository; version pinned in `versions.lock` and held | `docker-sbx`; executable check; sandbox state and credentials preserved |
| Tailscale | Tailscale signed APT repository | release-specific official keyring/list; no enrollment or auth-key handling |
| Google Cloud CLI | Google signed APT repository | official `google-cloud-cli` package; credentials preserved |
| AWS CLI v2 | pinned release (`versions.lock`) | versioned amd64/arm64 ZIP verified against the lock's SHA-256 and its detached signature with the AWS CLI Team key and pinned fingerprint; `/usr/local/aws-cli` ownership explicit |

The checksums in `versions.lock` pin the bytes first seen over HTTPS
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
