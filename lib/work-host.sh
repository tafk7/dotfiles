#!/bin/bash
# Read-only work-host readiness checks and the explicitly requested local sbx smoke
# test. This library never performs host configuration or enrollment.

[[ -n "${_DOTFILES_WORK_HOST_LOADED:-}" ]] && return 0
_DOTFILES_WORK_HOST_LOADED=1

host_timeout() {
    local seconds="$1"
    shift
    if command -v timeout >/dev/null 2>&1; then
        timeout --foreground "$seconds" "$@"
    else
        "$@"
    fi
}

host_account() {
    local account="${DOTFILES_TARGET_USER:-${SUDO_USER:-${USER:-}}}"
    [[ -n "$account" ]] || account="$(id -un 2>/dev/null || true)"
    [[ -n "$account" && "$account" != root ]] || return 1
    printf '%s\n' "$account"
}

host_systemd_running() {
    [[ "${DOTFILES_TEST_SYSTEMD_RUNNING:-}" == 1 ]] && return 0
    [[ "${DOTFILES_TEST_SYSTEMD_RUNNING:-}" == 0 ]] && return 1
    [[ -d /run/systemd/system ]] && command -v systemctl >/dev/null 2>&1
}

work_kernel_has_kvm() {
    [[ "${DOTFILES_TEST_KVM_KERNEL:-}" == 1 ]] && return 0
    [[ "${DOTFILES_TEST_KVM_KERNEL:-}" == 0 ]] && return 1
    [[ -d /sys/module/kvm ]] && return 0
    grep -Eq '^kvm(_intel|_amd|_arm64)? ' /proc/modules 2>/dev/null && return 0
    command -v modinfo >/dev/null 2>&1 && modinfo kvm >/dev/null 2>&1 && return 0
    grep -Eq '^CONFIG_KVM=(y|m)$' "/boot/config-$(uname -r)" 2>/dev/null && return 0
    command -v zgrep >/dev/null 2>&1 && zgrep -Eq '^CONFIG_KVM=(y|m)$' /proc/config.gz 2>/dev/null
}

work_kvm_device_present() {
    [[ "${DOTFILES_TEST_KVM_DEVICE:-}" == present ]] && return 0
    [[ "${DOTFILES_TEST_KVM_DEVICE:-}" == missing ]] && return 1
    [[ -c /dev/kvm ]]
}

work_kvm_accessible() {
    [[ "${DOTFILES_TEST_KVM_ACCESS:-}" == yes ]] && return 0
    [[ "${DOTFILES_TEST_KVM_ACCESS:-}" == no ]] && return 1
    [[ -r /dev/kvm && -w /dev/kvm ]]
}

# active, pending, absent, or unavailable
host_group_state() {
    local group="$1" account
    account="$(host_account)" || { printf 'unavailable\n'; return; }
    if id -nG 2>/dev/null | tr ' ' '\n' | grep -Fxq "$group"; then
        printf 'active\n'
    elif getent group "$group" 2>/dev/null | awk -F: -v user="$account" '
        { n=split($4, members, ","); for (i=1; i<=n; i++) if (members[i] == user) found=1 }
        END { exit found ? 0 : 1 }
    '; then
        printf 'pending\n'
    else
        printf 'absent\n'
    fi
}

work_docker_endpoint() {
    local context endpoint
    if [[ -n "${DOCKER_HOST:-}" ]]; then
        printf '%s\n' "$DOCKER_HOST"
        return
    fi
    context="$(host_timeout 5 docker context show 2>/dev/null || true)"
    [[ -n "$context" ]] || context=default
    endpoint="$(host_timeout 5 docker context inspect --format '{{.Endpoints.docker.Host}}' "$context" 2>/dev/null || true)"
    [[ -n "$endpoint" ]] && printf '%s\n' "$endpoint" || printf 'unix:///var/run/docker.sock\n'
}

work_docker_endpoint_is_local() {
    local endpoint="$1" uid
    uid="$(id -u)"
    case "$endpoint" in
        unix:///var/run/docker.sock|unix:///run/docker.sock|unix:///run/user/"$uid"/docker.sock) return 0 ;;
        *) return 1 ;;
    esac
}

work_docker_ready() {
    command -v docker >/dev/null 2>&1 || return 2
    local endpoint
    endpoint="$(work_docker_endpoint)"
    work_docker_endpoint_is_local "$endpoint" || return 3
    host_timeout 10 docker info >/dev/null 2>&1 || return 1
}

work_sbx_daemon_ready() {
    command -v sbx >/dev/null 2>&1 || return 2
    host_timeout 10 sbx daemon status >/dev/null 2>&1
}

tail_state() {
    command -v tailscale >/dev/null 2>&1 || { printf 'missing\n'; return; }
    local output
    output="$(host_timeout 10 tailscale status --json 2>/dev/null || true)"
    [[ -n "$output" ]] || { printf 'stopped-or-denied\n'; return; }
    local backend
    backend="$(printf '%s\n' "$output" | sed -n 's/.*"BackendState"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -n1)"
    case "$backend" in
        Running) printf 'connected\n' ;;
        NeedsLogin) printf 'needs-login\n' ;;
        Stopped) printf 'stopped\n' ;;
        *) printf 'not-connected\n' ;;
    esac
}

# Callers provide check_pass/check_warn/check_fail. Required work verification
# treats every missing local execution prerequisite as an error.
work_verify_checks() {
    local required="${1:-true}" group_state endpoint rc
    local fail_fn=check_fail
    [[ "$required" == true ]] || fail_fn=check_warn

    if host_systemd_running; then
        check_pass "systemd is managing the host"
    else
        "$fail_fn" "systemd unavailable (work services cannot be managed persistently)"
    fi

    if command -v sbx >/dev/null 2>&1; then
        if host_timeout 10 sbx version >/dev/null 2>&1; then check_pass "sbx executable health";
        else "$fail_fn" "sbx package present but executable health failed"; fi
    else
        "$fail_fn" "sbx package missing (run: ./setup.sh --work)"
    fi

    work_kernel_has_kvm && check_pass "kernel KVM support" \
        || "$fail_fn" "KVM kernel support unavailable (enable provider nested virtualization or BIOS virtualization)"
    if ! work_kvm_device_present; then
        "$fail_fn" "KVM unavailable (/dev/kvm missing)"
    elif work_kvm_accessible; then
        check_pass "/dev/kvm access"
    else
        "$fail_fn" "/dev/kvm permission denied"
    fi
    group_state="$(host_group_state kvm)"
    case "$group_state" in
        active) check_pass "kvm group membership active" ;;
        pending) "$fail_fn" "kvm group membership pending; sign out and reconnect" ;;
        absent) "$fail_fn" "kvm group membership absent (sudo usermod -aG kvm $(host_account 2>/dev/null || printf USER))" ;;
        *) "$fail_fn" "cannot resolve kvm account membership" ;;
    esac

    rc=0
    work_docker_ready || rc=$?
    case "$rc" in
        0) check_pass "local Docker daemon access" ;;
        2) "$fail_fn" "Docker package missing (run: ./setup.sh --work)" ;;
        3) endpoint="$(work_docker_endpoint)"; "$fail_fn" "Docker context is remote ($endpoint); local daemon access is required" ;;
        *) "$fail_fn" "local Docker daemon unavailable or permission denied" ;;
    esac
    if command -v docker >/dev/null 2>&1; then
        endpoint="$(work_docker_endpoint)"
        if [[ "$endpoint" == unix:///run/user/*/docker.sock ]]; then
            check_pass "rootless Docker access (docker group not required)"
        else
            group_state="$(host_group_state docker)"
            case "$group_state" in
                active) check_pass "docker group membership active" ;;
                pending) "$fail_fn" "docker group membership pending; sign out and reconnect" ;;
                absent) "$fail_fn" "docker group membership absent; Docker socket access may be denied" ;;
                *) "$fail_fn" "cannot resolve docker account membership" ;;
            esac
            if host_systemd_running; then
                host_timeout 5 systemctl is-enabled --quiet docker 2>/dev/null \
                    && check_pass "docker service enabled" || "$fail_fn" "docker service disabled"
                host_timeout 5 systemctl is-active --quiet docker 2>/dev/null \
                    && check_pass "docker service active" || "$fail_fn" "docker service stopped"
            fi
        fi
    fi

    if command -v sbx >/dev/null 2>&1; then
        work_sbx_daemon_ready && check_pass "sandbox daemon status" \
            || "$fail_fn" "sandbox daemon stopped or unreachable"
        if [[ "${WORK_DIAGNOSE:-false}" == true ]]; then
            host_timeout 30 sbx diagnose >/dev/null 2>&1 \
                && check_pass "bounded local sbx diagnostics" \
                || "$fail_fn" "sbx diagnostics failed (rerun 'sbx diagnose'; no upload was requested)"
        fi
    fi

}

tail_verify_checks() {
    local required="${1:-true}" state
    local fail_fn=check_fail
    [[ "$required" == true ]] || fail_fn=check_warn

    if ! command -v tailscale >/dev/null 2>&1; then
        "$fail_fn" "Tailscale package missing (run: ./setup.sh --tail)"
    else
        check_pass "Tailscale installed"
        if host_systemd_running; then
            host_timeout 5 systemctl is-enabled --quiet tailscaled 2>/dev/null \
                && check_pass "tailscaled enabled" || "$fail_fn" "tailscaled service disabled"
            host_timeout 5 systemctl is-active --quiet tailscaled 2>/dev/null \
                && check_pass "tailscaled active" || "$fail_fn" "tailscaled service stopped"
        fi
        state="$(tail_state)"
        case "$state" in
            connected) check_pass "Tailscale enrolled and connected" ;;
            needs-login) "$fail_fn" "Tailscale enrollment required (run: sudo tailscale up)" ;;
            stopped) "$fail_fn" "Tailscale is enrolled but stopped" ;;
            *) "$fail_fn" "Tailscale status unavailable or not connected" ;;
        esac
    fi
}

work_sbx_name_exists() {
    local name="$1"
    host_timeout 10 sbx ls --quiet 2>/dev/null | grep -Fxq "$name"
}

work_smoke_test() {
    local name="${DOTFILES_SBX_SMOKE_NAME:-dotfiles-smoke-$(id -u)-$(date +%s)-$$-${RANDOM:-0}}"
    local created=false primary_rc=0 cleanup_rc=0

    command -v sbx >/dev/null 2>&1 || { error "sbx package missing"; return 1; }
    work_kvm_device_present || { error "KVM unavailable: /dev/kvm is missing"; return 1; }
    work_kvm_accessible || { error "KVM permission denied: activate kvm group membership and retry"; return 1; }
    if ! host_timeout "${DOTFILES_SBX_DIAGNOSE_TIMEOUT:-30}" sbx diagnose >/dev/null 2>&1; then
        error "sbx diagnostics failed; authenticate with 'sbx login' and run 'sbx diagnose' for details"
        return 1
    fi
    if work_sbx_name_exists "$name"; then
        error "Smoke-test sandbox name collision: $name"
        return 1
    fi

    _work_smoke_cleanup() {
        local signal_rc="${1:-0}"
        if [[ "$created" != true ]] && work_sbx_name_exists "$name"; then
            created=true
        fi
        if [[ "$created" == true ]]; then
            log "Smoke cleanup: removing $name"
            cleanup_rc=0
            host_timeout "${DOTFILES_SBX_CLEANUP_TIMEOUT:-60}" sbx rm --force "$name" || cleanup_rc=$?
            if (( cleanup_rc != 0 )); then
                error "Smoke cleanup failed; sandbox may remain: $name"
            else
                created=false
                success "Smoke cleanup complete"
            fi
        fi
        (( signal_rc == 0 )) || return "$signal_rc"
        (( primary_rc != 0 )) && return "$primary_rc"
        return "$cleanup_rc"
    }
    trap 'primary_rc=130; _work_smoke_cleanup 130; exit 130' INT
    trap 'primary_rc=143; _work_smoke_cleanup 143; exit 143' TERM

    log "Smoke create: local mountless shell sandbox $name"
    # Local is the default backend. Never add the global --cloud flag.
    if host_timeout "${DOTFILES_SBX_CREATE_TIMEOUT:-300}" sbx create --name "$name" shell; then
        created=true
        success "Smoke create complete"
    else
        primary_rc=$?
        (( primary_rc == 0 )) && primary_rc=1
        # Creation can fail after allocating the named resource.
        work_sbx_name_exists "$name" && created=true
        error "Smoke create failed"
    fi

    if (( primary_rc == 0 )); then
        log "Smoke exec: uname -a"
        if host_timeout "${DOTFILES_SBX_EXEC_TIMEOUT:-60}" sbx exec "$name" uname -a; then
            success "Smoke exec complete"
        else
            primary_rc=$?
            (( primary_rc == 0 )) && primary_rc=1
            error "Smoke exec failed"
        fi
    fi

    _work_smoke_cleanup 0
    local rc=$?
    trap - INT TERM
    return "$rc"
}
