# Spec: xrdp layer — RDP into the dotfiles environment

**Status:** implemented — `./setup.sh --rdp` (see `installers/install-xrdp.sh`).
This document is retained as the design rationale.
**Primary use case:** the work machine — RDP from the Windows host into a full
Linux desktop session running in WSL2 Ubuntu (where these dotfiles live).
**Secondary use case:** the same installer on a native Ubuntu box for remote
access (over VPN/Tailscale — never raw internet).

Related parked idea: `issues/moonlight-sunshine.md` (game-stream stack; revisit
if xrdp latency becomes a problem).

---

## 1. What gets installed

| Piece | Source | Why |
|---|---|---|
| `xrdp` | Ubuntu apt | The RDP listener/session broker. Ubuntu 24.04 ships 0.9.x/0.10.x — apt is the right channel (daemon + systemd unit + user/group wiring), not eget. |
| `xorgxrdp` | Ubuntu apt | Xorg backend module so sessions run a real X server (required for a usable desktop; without it you get only the deprecated VNC proxy path). |
| A desktop session | apt (`xfce4 xfce4-goodies`) | xrdp starts a session but ships none. This repo is CLI-first and installs no DE today, so the installer must provide one. XFCE is the de-facto xrdp pairing: light (~500 MB), no compositor fights with xrdp's rendering path, works headless. |

Everything is apt — **no version pinning needed or possible** (matches how the
repo already treats apt packages vs eget pins).

## 2. Integration into the installer stack

Mirror the `--ai` pattern exactly — an **orthogonal flag, not a tier**:

- Most machines should never run an RDP server; it's a per-machine opt-in like
  `--ai`, and it must not ride along with `--dev`/`--work`/`--full`.
  (Deliberate difference from `--ai`: `--full` does **not** imply `--rdp` —
  "everything" shouldn't silently open a listening service.)
- Requires sudo (apt + systemd + `/etc/xrdp` edits), so it composes with any
  tier but does real system mutation. `--config --rdp` is allowed and simply
  does the rdp part.

### Touch points (all follow existing patterns)

1. **`setup.sh`**
   - `INSTALL_RDP=false`; `--rdp` sets it (parse_arguments).
   - `phase_install_packages`: `[[ "$INSTALL_RDP" == "true" ]] && install_rdp_packages`
     after the tier chain, alongside the `install_ai_packages` call.
   - Help text: new "SERVICES (orthogonal)" entry; banner line like the AI one.
   - Post-install "Next Steps": print the connect string (see §5) and, on WSL,
     the systemd requirement warning.

2. **`lib/install.sh`** — `install_rdp_packages()`:
   ```
   install_apt "rdp" ${PACKAGES[rdp]}     # xrdp xorgxrdp xfce4 xfce4-goodies
   run_installer "xrdp"                   # config + service, see §3
   ```

3. **`lib/config.sh`** — `PACKAGES[rdp]="xrdp xorgxrdp xfce4 xfce4-goodies"`.

4. **`lib/registry.sh`**
   - `TOOL_BINARY[xrdp]=xrdp`, `TOOL_METHOD[xrdp]=installer`, `TOOL_TIER[xrdp]=rdp`.
   - `TOOL_VERIFY[xrdp]='systemctl is-active --quiet xrdp'` — the binary existing
     is not the success condition; the service running is.
   - Removal instructions: `sudo apt remove xrdp xorgxrdp; sudo rm -rf /etc/xrdp.d-backups`.

5. **`bin/verify`** — add `rdp` to the tier loop with warn-not-fail semantics
   (same treatment as `ai`/`work`: opt-in ⇒ absence is not an error).

6. **NOT `CONFIG_MAP`.** All xrdp config lives under `/etc/xrdp/`, and
   `assert_safe_home_target()` (correctly) refuses destructive ops outside
   `$HOME`. System files are therefore owned by the installer script
   (idempotent edits + timestamped backups), not the symlink engine. The only
   `$HOME` artifact is `~/.xsession`, and even that is better written by the
   installer than symlinked: it's machine-specific opt-in, not a config every
   machine should get.

## 3. `installers/install-xrdp.sh` — behavior spec

Standard contract: exit 0 installed/changed, 2 already-configured, 1 failed;
`--force` reapplies config. Sources `lib/install.sh`, uses `safe_sudo`.

Steps, each idempotent:

1. **Guard: WSL without systemd.** On WSL, if `[[ ! -d /run/systemd/system ]]`,
   error out with the fix (`/etc/wsl.conf` → `[boot] systemd=true`, then
   `wsl --shutdown`) rather than half-installing. Native Ubuntu: proceed.
2. **Packages** are already present (installed by `install_rdp_packages` via
   `install_apt`); verify `command -v xrdp`.
3. **TLS cert access:** `adduser xrdp ssl-cert` (xrdp reads the snakeoil key to
   offer TLS; without this it silently falls back to weaker RDP security).
4. **Port (WSL only):** switch `port=3389` → `port=3390` in `/etc/xrdp/xrdp.ini`.
   The Windows host may itself listen on 3389 (Remote Desktop enabled on work
   machines is common), and WSL2 localhost-forwarding would collide/confuse.
   3390 is the established convention for xrdp-in-WSL. Native installs keep 3389.
5. **Quality settings** in `xrdp.ini`: `security_layer=tls`, `max_bpp=32`,
   leave the GFX/H.264 section at package defaults (0.10.x enables it when the
   client negotiates it — mstsc does).
6. **Session wiring:** write `~/.xsession` containing `startxfce4` (backup any
   existing non-matching file via the standard backup dir). This keeps
   `/etc/xrdp/startwm.sh` stock — it already honors `~/.xsession` — so apt
   upgrades never conflict.
7. **Polkit quirk fix:** drop `/etc/polkit-1/localauthority/50-local.d/45-xrdp-colord.pkla`
   (or the newer `rules.d` JS equivalent depending on polkit version) allowing
   `org.freedesktop.color-manager.create-device` for active sessions. Without
   it, every login throws an "Authentication required to create a color
   managed device" popup.
8. **Service:** `systemctl enable --now xrdp`, then assert
   `systemctl is-active xrdp`. Print the connect target.
9. **Bind scope decision (see Open Questions):** default config listens on all
   interfaces. On WSL this is effectively private (WSL2 NAT + Windows
   firewall), but on native installs the installer should print a loud
   reminder: reachable ⇒ put it behind VPN/Tailscale, or set
   `address=127.0.0.1` in `xrdp.ini` and tunnel over SSH.

## 4. WSL2-specific realities (the primary target)

- **systemd is mandatory** — xrdp is a systemd service. Modern WSL supports it
  but it's off on older installs; the installer guard (§3.1) handles this.
- **Connect to `localhost:3390`** from the Windows host. WSL2's localhost
  forwarding makes the Linux listener reachable without knowing the VM IP.
- **Session ≠ WSLg.** The RDP desktop is a separate X session from WSLg's
  Wayland surface; both coexist. GUI apps launched in the RDP session render
  through xorgxrdp (software) — fine for desktops/editors, not for GPU work.
- **No suspend/resume weirdness**: if `wsl --shutdown` happens, the session
  dies; reconnecting after WSL restart gets a fresh login. Document, don't fix.
- **A second machine can reach it** only via Windows-side port proxy
  (`netsh interface portproxy`) or mirrored networking mode — out of scope for
  the installer; note it in docs.

## 5. Client on the work machine — recommendation

**Use `mstsc.exe` (Microsoft Remote Desktop Connection). Full stop.**

Rationale against install restrictions:
- **Zero install, zero admin** — ships in every Windows edition work laptops
  use (Pro/Enterprise); it's in `System32`, already allowlisted, and IT
  departments use it themselves. There is no approval to seek.
- **Protocol fit** — mstsc negotiates TLS + the GFX pipeline (H.264) with
  xrdp ≥ 0.10, so quality/latency is as good as xrdp offers.
- Saved `.rdp` profiles cover the ergonomics: `localhost:3390`, 32-bit color,
  "reconnect if dropped", clipboard on, drive redirection if wanted.

Alternatives, in order, if mstsc is somehow unavailable:
1. **"Windows App"** (Microsoft Store, the rebranded Remote Desktop client) —
   nicer multi-connection UI, but Store access is often blocked on managed
   machines; needs no admin if the Store works.
2. **Remmina** — only relevant if the client is itself Linux.

Non-options under restrictions: anything requiring an MSI/admin install from
outside vendor channels (Royal TS, mRemoteNG, etc.) — capability duplicates
mstsc anyway.

## 6. Security posture

- Auth is the Linux user's password (PAM). Enforce: no exposure beyond
  localhost/VPN; TLS layer on (§3.3/3.5); never port-forward 3389/3390 from a
  router.
- Work-machine primary case is inherently localhost-only (WSL2 NAT).
- Native/remote case: document Tailscale/VPN as the transport;
  `address=127.0.0.1` + SSH tunnel as the zero-extra-infra fallback.

## 7. Open questions — resolved at implementation

1. **DE choice** — XFCE always. Simpler, known-good with xrdp; a machine with
   GNOME can hand-edit `~/.xsession` afterwards (the installer backs up any
   existing file rather than clobbering it).
2. **Bind default on native installs** — all interfaces + loud warning at the
   end of the install (VPN/Tailscale or `address=127.0.0.1` + SSH tunnel).
   WSL: all interfaces (effectively private behind WSL2 NAT).
3. **Flag name** — `--rdp`. A future moonlight/sunshine layer would be
   `--stream`, so no name collision.
4. **`--full` scope** — does *not* imply `--rdp`; enforced in
   `phase_install_packages` and documented in help/README.

## 9. Coexistence with an existing display/RDP stack

Installing onto a machine that already has some of the desktop/RDP stack is the
common work-VM case. How each pre-existing condition is handled (all in
`install_rdp_packages` / `installers/install-xrdp.sh`):

| Pre-existing condition | Handling |
|---|---|
| A display manager (gdm3) | Preseed `shared/default-x-display-manager` to the current DM before apt — no prompt, no switch (§8 / `preserve_default_display_manager`). |
| xrdp already fully configured | Idempotent: desired-state checks pass → exit 2, nothing rewritten. |
| Custom `port=` in `xrdp.ini` | Left alone with a warning (only the package default 3389 is rewritten). |
| Something else on the target port | Preflight `ss` check: if the port is held and xrdp isn't the listener, fail early with the diagnosing command instead of an opaque bind error at service start. |
| A hand-written `~/.xsession` | Respected — not overwritten. `--force` (or `RDP_XSESSION`) replaces it, backing up first. |
| A full desktop already installed (GNOME/KDE) | Still defaults to XFCE for the RDP session, but detects it and prints how to reuse it: `RDP_XSESSION="gnome-session" ./setup.sh --rdp --force`. |
| Customized `/etc/xrdp/startwm.sh` | Warn that it may bypass `~/.xsession`, so the session source isn't a mystery. |
| `ssl-cert` group absent | Skip the group step with a warning instead of erroring on `adduser`. |
| ufw active (native) | Print the `ufw allow` hint (don't auto-open — security). |
| Same user logged in on the console | Note the xorgxrdp single-session-per-user limitation (black screen / instant disconnect otherwise). Not fixable in the installer. |

`RDP_XSESSION` (env) overrides the session command written to `~/.xsession`
(default `startxfce4`).

Not special-cased (benign): a Wayland console session — xrdp always spins up
its own Xorg session via `xorgxrdp`, independent of the console's display server.

## 8. Implementation notes (deltas from the spec above)

- apt install uses a dedicated `env DEBIAN_FRONTEND=noninteractive apt-get`
  call rather than `install_apt`: xfce4's Recommends pulls a display manager
  whose debconf dialog would block an interactive install. xrdp doesn't use a
  display manager, so the noninteractive default answer is irrelevant. `env`
  is required because sudo strips `DEBIAN_FRONTEND`.
- Dry-run is honored in-process by `install_rdp_packages` (setup.sh does not
  export `DRY_RUN`, so installer subprocesses can't see it).
- If `xrdp.ini` has a port that is neither the package default (3389) nor our
  target, the installer warns and leaves it alone instead of clobbering a
  manual customization.
- polkit backend detection: version `0.x` (`pkaction --version`) → `.pkla`
  localauthority file (Ubuntu ≤ 22.04); otherwise a JS rule in `rules.d`
  (Ubuntu 24.04+, duktape ES5 — hence `indexOf`, not `startsWith`).
