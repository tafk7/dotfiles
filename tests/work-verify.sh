#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/lib/runtime.sh"; source "$ROOT/lib/work-host.sh"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

docker_mode=rootless
docker() {
    case "$1 ${2:-}" in
        "context show") echo rootless ;;
        "context inspect") [[ "$docker_mode" == rootless ]] && echo "unix:///run/user/1000/docker.sock" || echo "ssh://remote.example" ;;
        "info ") return 0 ;;
        *) return 0 ;;
    esac
}
id() { case "${1:-}" in -u) echo 1000 ;; -un) echo tester ;; -nG) echo users ;; *) command id "$@" ;; esac; }
USER=tester
host_timeout() { shift; "$@"; }
docker_mode=rootless; work_docker_ready || fail "rootless Docker was rejected"
docker_mode=remote; rc=0; work_docker_ready || rc=$?; [[ $rc -eq 3 ]] || fail "remote Docker context counted as local"

getent() { [[ "$1" == group && "$2" == kvm ]] && echo 'kvm:x:108:tester'; }
[[ "$(host_group_state kvm)" == pending ]] || fail "pending-login group state not detected"
DOTFILES_TEST_KVM_KERNEL=1 DOTFILES_TEST_KVM_DEVICE=present DOTFILES_TEST_KVM_ACCESS=yes
work_kernel_has_kvm && work_kvm_device_present && work_kvm_accessible || fail "KVM test overrides failed"

printf 'work-verify: ok\n'
