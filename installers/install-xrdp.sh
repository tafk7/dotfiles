#!/bin/bash
# Configure the xrdp RDP server. Packages (xrdp, xorgxrdp, xfce4) are apt-installed
# by install_rdp_packages before this runs; this script owns everything after:
# TLS group, xrdp.ini port/security, ~/.xsession, the polkit colord fix, and the
# systemd service. All /etc/xrdp state lives here, not CONFIG_MAP — the symlink
# engine is (correctly) restricted to $HOME.
#
# xrdp is an "rdp" tool (./setup.sh --rdp): opt-in per machine, never implied by
# a tier or --full, because installing it opens a network listener. Idempotent;
# re-run with --force to reapply configuration.
set -euo pipefail

source "${DOTFILES_DIR:-$HOME/dotfiles}/lib/install.sh"

FORCE=false
[[ "${1:-}" == "--force" ]] && FORCE=true

XRDP_INI="/etc/xrdp/xrdp.ini"
STARTWM="/etc/xrdp/startwm.sh"
POLKIT_PKLA="/etc/polkit-1/localauthority/50-local.d/45-xrdp-colord.pkla"
POLKIT_RULE="/etc/polkit-1/rules.d/45-xrdp-colord.rules"

# WSL listens on 3390: the Windows host commonly owns 3389 itself (Remote
# Desktop enabled on work machines), and WSL2 localhost-forwarding would
# collide. Native installs keep the standard port.
RDP_PORT=3389
is_wsl && RDP_PORT=3390

# Session command launched on RDP login. Defaults to XFCE; override for a
# machine whose preferred desktop is already installed, e.g.
# RDP_XSESSION="gnome-session" ./setup.sh --rdp --force
RDP_XSESSION="${RDP_XSESSION:-startxfce4}"

# Write our ~/.xsession (carries a marker so re-runs recognize their own file).
write_xsession() {
    cat > "$HOME/.xsession" <<EOF
# Written by dotfiles installers/install-xrdp.sh — xrdp session entry point.
# Executed by /etc/X11/Xsession for RDP logins.
exec ${RDP_XSESSION}
EOF
    success "Wrote ~/.xsession (session: ${RDP_XSESSION})"
}

# xrdp is a systemd service; without systemd there is nothing to manage.
if is_wsl && [[ ! -d /run/systemd/system ]]; then
    error "xrdp requires systemd, which is not running in this WSL distro."
    error "Enable it in /etc/wsl.conf:"
    error "    [boot]"
    error "    systemd=true"
    error "then run 'wsl --shutdown' from Windows and re-run: ./setup.sh --rdp"
    exit 1
fi

if ! command -v xrdp >/dev/null 2>&1 || [[ ! -f "$XRDP_INI" ]]; then
    error "xrdp not installed — run via ./setup.sh --rdp (installs the apt packages first)"
    exit 1
fi

# Preflight: is the target port already held by something that ISN'T xrdp? A
# stray listener (another RDP server, a leftover process, or a conflicting
# service) would make xrdp fail to bind at start with an opaque error — catch it
# here with an actionable message. A re-run where xrdp is already the listener
# is fine and passes through.
if command -v ss >/dev/null 2>&1 \
   && ss -Hltn "sport = :${RDP_PORT}" 2>/dev/null | grep -q . \
   && ! systemctl is-active --quiet xrdp 2>/dev/null; then
    error "Port ${RDP_PORT} is already in use, and xrdp is not the listener."
    error "Identify it with: sudo ss -ltnp 'sport = :${RDP_PORT}'"
    if is_wsl; then
        error "On WSL a stale session can hold it — try 'wsl --shutdown' from Windows, then retry."
    else
        error "Stop the conflicting service, or change xrdp's port in ${XRDP_INI}."
    fi
    exit 1
fi

# ------------------------------------------------------------------------------
# Desired-state checks (each maps to one config step below)
# ------------------------------------------------------------------------------
# ssl-cert: satisfied if xrdp is a member, OR the group doesn't exist (nothing
# we can do — TLS cert access just won't be available on such a minimal system).
group_ok()        { id -nG xrdp 2>/dev/null | grep -qw ssl-cert || ! getent group ssl-cert >/dev/null 2>&1; }
port_ok()         { grep -q "^port=${RDP_PORT}$" "$XRDP_INI"; }
tls_ok()          { grep -q "^security_layer=tls$" "$XRDP_INI"; }
xsession_is_ours() { [[ -f "$HOME/.xsession" ]] && grep -q "install-xrdp.sh" "$HOME/.xsession"; }
xsession_ok()     { xsession_is_ours && grep -q "^exec ${RDP_XSESSION}$" "$HOME/.xsession"; }
# A session will launch on login if ours is wired OR the user maintains their own
# non-empty ~/.xsession (custom DE / tiling WM) — we must not hijack the latter.
session_wired()   { xsession_ok || { [[ -s "$HOME/.xsession" ]] && ! xsession_is_ours; }; }
polkit_ok()       { [[ -f "$POLKIT_PKLA" || -f "$POLKIT_RULE" ]]; }
service_ok()      { systemctl is-active --quiet xrdp 2>/dev/null; }

if [[ "$FORCE" != true ]] && group_ok && port_ok && tls_ok && session_wired && polkit_ok && service_ok; then
    success "xrdp already configured and running (port $RDP_PORT)"
    exit 2
fi

ini_changed=false

# 1. TLS certificate access. xrdp reads the snakeoil key via the ssl-cert
#    group; without membership it silently falls back to weaker RDP security.
if ! id -nG xrdp 2>/dev/null | grep -qw ssl-cert; then
    if getent group ssl-cert >/dev/null 2>&1; then
        safe_sudo adduser xrdp ssl-cert
    else
        warn "ssl-cert group absent — skipping TLS cert group membership."
        warn "(RDP may use weaker security; install the 'ssl-cert' package to enable TLS.)"
    fi
fi

# 2. xrdp.ini: port + TLS layer. One backup before the first edit, so the
#    pristine package config is always recoverable.
if ! port_ok || ! tls_ok; then
    safe_sudo cp "$XRDP_INI" "${XRDP_INI}.dotfiles-bak-$(date +%Y%m%d-%H%M%S)"
    if ! port_ok; then
        if grep -q "^port=3389$" "$XRDP_INI"; then
            safe_sudo sed -i "s/^port=3389$/port=${RDP_PORT}/" "$XRDP_INI"
        else
            # Port is neither the package default nor our target — a manual
            # customization we must not clobber.
            warn "xrdp.ini port is customized ($(grep '^port=' "$XRDP_INI" | head -1)); leaving it alone."
            warn "Expected port=${RDP_PORT} — adjust manually if the connect instructions don't match."
        fi
    fi
    if ! tls_ok; then
        safe_sudo sed -i 's/^security_layer=.*/security_layer=tls/' "$XRDP_INI"
    fi
    ini_changed=true
fi

# 3. Session wiring: ~/.xsession → the chosen session. /etc/xrdp/startwm.sh
#    defers to /etc/X11/Xsession, which executes ~/.xsession — so the stock
#    startwm.sh is left untouched and apt upgrades never conflict.
#
#    A machine may already have a full desktop (GNOME/KDE) or a hand-written
#    ~/.xsession. We must not silently hijack a session the user maintains, and
#    we shouldn't assume XFCE is wanted when another desktop is present.
if xsession_ok; then
    :  # our session file is already in place
elif [[ -s "$HOME/.xsession" ]] && ! xsession_is_ours; then
    # A pre-existing ~/.xsession we didn't write — respect the user's choice.
    if [[ "$FORCE" == true ]]; then
        backup="$HOME/.xsession.dotfiles-bak-$(date +%Y%m%d-%H%M%S)"
        log "--force: backing up existing ~/.xsession -> $backup"
        mv "$HOME/.xsession" "$backup"
        write_xsession
    else
        warn "Keeping your existing ~/.xsession — RDP will use it as-is."
        warn "To replace it with '${RDP_XSESSION}', re-run with --force (or set RDP_XSESSION)."
    fi
else
    # Absent, empty, or a stale copy of ours with a different session command.
    if [[ "$RDP_XSESSION" == "startxfce4" ]] \
       && { command -v gnome-session >/dev/null 2>&1 || command -v startplasma-x11 >/dev/null 2>&1; }; then
        log "A full desktop (GNOME/KDE) is already installed; the RDP session will still use XFCE."
        log "To use it instead: RDP_XSESSION=\"gnome-session\" ./setup.sh --rdp --force"
    fi
    write_xsession
fi

# Our ~/.xsession only takes effect if startwm.sh still routes through Xsession.
# A pre-existing xrdp install may have hard-coded a desktop in startwm.sh, which
# would bypass ~/.xsession entirely — flag it so the session choice isn't a mystery.
if [[ -r "$STARTWM" ]] && ! grep -qE 'Xsession|\.xsession' "$STARTWM"; then
    warn "${STARTWM} looks customized and may not read ~/.xsession;"
    warn "your RDP desktop could be dictated by that file instead of ~/.xsession."
fi

# 4. Polkit colord fix. Without it every RDP login throws an "Authentication
#    required to create a color managed device" dialog. polkit <= 0.105
#    (Ubuntu <= 22.04) only reads .pkla localauthority files; >= 106 (Ubuntu
#    24.04+) uses JS rules — detect via the version scheme (0.x vs 12x).
if ! polkit_ok; then
    pk_ver="$(pkaction --version 2>/dev/null | grep -oE '[0-9]+(\.[0-9]+)*' | head -1 || true)"
    if [[ "${pk_ver:-0.105}" == 0.* ]]; then
        safe_sudo install -d -m 755 "$(dirname "$POLKIT_PKLA")"
        safe_sudo tee "$POLKIT_PKLA" > /dev/null << 'EOF'
[Allow colord for active sessions (xrdp)]
Identity=unix-user:*
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
ResultAny=no
ResultInactive=no
ResultActive=yes
EOF
    else
        # Duktape polkit is ES5: no startsWith — use indexOf.
        safe_sudo tee "$POLKIT_RULE" > /dev/null << 'EOF'
// Written by dotfiles installers/install-xrdp.sh: suppress the colord
// authentication dialog in xrdp sessions.
polkit.addRule(function(action, subject) {
    if (action.id.indexOf("org.freedesktop.color-manager.") === 0 &&
        subject.active) {
        return polkit.Result.YES;
    }
});
EOF
    fi
    success "Polkit colord rule installed"
fi

# 5. Service: enable + start, restarting to pick up any xrdp.ini change.
safe_sudo systemctl enable --now xrdp
[[ "$ini_changed" == true ]] && safe_sudo systemctl restart xrdp

if ! service_ok; then
    error "xrdp service is not active after enable/start — check: systemctl status xrdp"
    exit 1
fi

if is_wsl; then
    success "xrdp ready — connect from the Windows host: mstsc -> localhost:${RDP_PORT}"
else
    success "xrdp ready on port ${RDP_PORT}"
    warn "xrdp listens on all interfaces. Keep it behind a VPN/Tailscale or a firewall,"
    warn "or set address=127.0.0.1 in ${XRDP_INI} and tunnel over SSH."
    warn "If ufw is active, allow the port on trusted networks: sudo ufw allow ${RDP_PORT}/tcp"
fi

# Same-user console + RDP collision: the Xorg backend can't open a second
# session for a user already logged in on the physical console. Note it so a
# "black screen / immediate disconnect" isn't a surprise.
if ! is_wsl; then
    log "Note: if you're logged in locally as this user, log out of the console before"
    log "connecting over RDP — xorgxrdp can't run two X sessions for the same user."
fi
exit 0
