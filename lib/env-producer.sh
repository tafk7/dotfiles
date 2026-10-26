#!/bin/bash
# The environment dotfiles manages, computed without a login shell. Run by
# env_produce (lib/environment.sh) as `bash --noprofile --norc` in a cleared
# environment: it sources the POSIX baseline (Part 1 of entry/profile.sh) and
# shell/env.sh, which ends with ~/.shell.env, and never direnv or any user
# startup file. Prints one line per managed variable, NAME<TAB>VALUE when set
# and -NAME when not, then PATH<TAB>SEGMENTS: the directories env.sh put in
# front of the base PATH it was given.
set -u
[[ -n "${DOTFILES_DIR:-}" && -f "$DOTFILES_DIR/shell/env.sh" ]] || { echo "env-producer: no checkout at ${DOTFILES_DIR:-?}" >&2; exit 1; }
base_path="$PATH"
unset _DOTFILES_BASE_ENV _DOTFILES_ENV_LOADED _PROFILE_LOADED
# Part 1 is POSIX shell between its heading and Part 2's.
eval "$(sed -n '/^# Part 1: POSIX baseline/,/^# Part 2:/p' "$DOTFILES_DIR/entry/profile.sh")"
# shellcheck source=../shell/env.sh
source "$DOTFILES_DIR/shell/env.sh"

for name in "$@"; do
    if [[ -n "${!name+x}" && "${!name}" != *$'\n'* ]]; then
        printf '%s\t%s\n' "$name" "${!name}"
    else
        printf -- '-%s\n' "$name"
    fi
done
segments="${PATH%"$base_path"}"
[[ "$segments" != "$PATH" ]] || segments=""
printf 'PATH\t%s\n' "${segments%:}"
