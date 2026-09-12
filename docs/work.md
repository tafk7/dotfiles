# Work tier: local Docker Sandboxes

The cumulative work tier prepares a native Ubuntu machine for ordinary Docker
development and local Docker Sandboxes:

```bash
./setup.sh --work
./setup.sh --work --claude --codex
./setup.sh --full
./setup.sh --full --tail
```

`work` includes the lower config, bash, and dev tiers, then adds NVM, Docker
Engine, `docker-sbx`, KVM/Docker host access, and Rust. Tailscale is independent:
`--tail` installs its package and service without selecting work or AI.
`--full` remains exactly `--work --ai`, so add `--tail` explicitly when wanted.

Work and `--tail` require sudo. Setup itself must run as the normal account; it
invokes sudo for repository, package, service, and group operations. Docker
group membership grants root-equivalent access to the host.

## Supported host and virtualization

Because local `sbx` is a work-tier requirement, work targets native Ubuntu
24.04 and 26.04 on amd64 or arm64. Config, bash, and dev retain Ubuntu 22.04
and WSL support. Tailscale independently supports repository-supported Ubuntu
22.04/24.04/26.04.

See the current vendor pages for [Docker Engine on Ubuntu](https://docs.docker.com/engine/install/ubuntu/),
[Docker Sandboxes installation](https://docs.docker.com/ai/sandboxes/install/),
and [Tailscale stable packages](https://pkgs.tailscale.com/stable/).

Local `sbx` execution requires hardware virtualization, kernel KVM support,
`/dev/kvm`, and active `kvm` group access. A cloud VM must expose nested
virtualization before setup runs. That is a provider/instance setting: setup
does not change the VM size, provider metadata, BIOS, kernel command line,
firewall, or device permissions, and it never fabricates `/dev/kvm`. Kernel
support may be built in, so verification does not rely only on `lsmod`.

Package installation and host readiness are separate results. Missing KVM or a
group change awaiting a new login does not turn a successful package install
into a package failure, but explicit work verification fails until local
sandbox execution is ready.

## Installation boundaries

Setup uses Docker's signed Ubuntu APT repository for both Docker Engine and the
`docker-sbx` package. Repository preparation never removes container packages.
If Docker CE conflicts with an existing container runtime, setup prints the
packages requiring migration and stops. It preserves externally managed Docker
installations and existing daemon configuration.

`--tail` uses Tailscale's signed stable Ubuntu repository. When systemd is
managing the host, setup enables and starts `tailscaled`. It does not run
`tailscale up`, consume an auth key, enable Tailscale SSH, advertise routes,
change routing, or modify firewall policy. Tailscale installation outcomes are
recorded in the component ledger, and a later `./setup.sh --config` never turns
those records into package installation.

## Authentication and ownership

Run `sbx login` interactively after installation. Docker currently uses browser
OAuth. On Linux with a Secret Service, sandbox credentials use the desktop
keyring. On a headless host without one, `sbx` falls back automatically to a
permission-protected file under `$XDG_CONFIG_HOME/com.docker.sandboxes`
(normally `~/.config/com.docker.sandboxes`). Treat that directory as sensitive.
See Docker's [credential documentation](https://docs.docker.com/ai/sandboxes/configuration/credentials/).

Sandbox settings, images, sessions, and credentials remain user-owned and are
preserved by `uninstall-tool sbx`. Tailscale identity/enrollment under
`/var/lib/tailscale` is also preserved. Setup never owns AI, GitHub, cloud, or
Tailscale credentials.

Host Claude, Codex, plugin, hook, and configuration state does not
automatically propagate into a sandbox. Future integration should pass only
explicitly selected, portable, allowlisted content.

## Verification and smoke test

```bash
./bin/verify --tier work
./bin/verify --tier work --diagnose
./bin/verify --tier work --tail
./bin/verify --tier work --smoke
```

Verification is read-only and bounded by timeouts unless `--smoke` is supplied.
It distinguishes package absence, KVM absence/access, active versus pending
group membership, rootless versus system Docker, remote Docker contexts,
stopped services, sandbox daemon health, and optional Tailscale
enrollment/connectivity. Rootless local Docker is valid without `docker` group
membership; a reachable remote context does not satisfy local readiness.
`--diagnose` runs bounded local `sbx diagnose` without `--upload`.

`--smoke` requires existing `sbx` authentication. It creates one uniquely named
local shell sandbox without a host workspace mount, runs `uname -a`, and removes
only that sandbox with `sbx rm --force`. Local is the default backend; the command
never supplies `--cloud`. Creation, execution, and cleanup have separate
timeouts and status messages. Cleanup runs after partial creation, failure, INT,
TERM, and normal exit while preserving the original failure. SIGKILL, host
failure, or power loss can prevent trap cleanup. Initial use can download images
and consume CPU, memory, disk, and network.

## Fresh personal server

Provision native Ubuntu 24.04 or 26.04 with nested virtualization exposed, then:

```bash
curl -fsSL https://raw.githubusercontent.com/tafk7/dotfiles/main/bootstrap.sh \
  | bash -s -- --full --tail
```

Bootstrap may install Git, clone or update the checkout, and run setup; it is
not side-effect-free merely because setup receives `--dry-run`.

Reconnect if group membership changed, enroll Tailscale with the intended
routing/SSH policy, run `sbx login`, authenticate GitHub and selected tools, and
run `./bin/verify --tier work --tail`. Use `--smoke` only when image downloads
and temporary resource use are acceptable.

## Cloud CLI compatibility

Fresh `--work` and `--full` installs no longer install Azure CLI. Use
`--work --azure` to retain that selection. Existing Azure installations remain;
their Azure DevOps helper moves into an optional portable Git include without
duplicate credential entries. Select Google Cloud with `--gcloud` and AWS CLI
v2 with `--aws`. Setup never selects a CLI from cloud-provider detection.

Microsoft's current APT support table covers Ubuntu 22.04 and 24.04, so explicit
`--azure` on 26.04 fails until Microsoft publishes support.

A real acceptance test remains manual on an authorized host: verify KVM
execution, optional Tailscale enrollment, a full logout/login, SSH disconnect
and reconnect, and reboot persistence. Hosted tests mock privileged operations
and cannot establish those lifecycle properties.
