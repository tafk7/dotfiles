#!/bin/bash
# Per-run setup logs for auditing installs. Each run writes the full transcript,
# without color codes, between a header (command, checkout, host) and a footer
# (exit status and the component ledger changes the run made). Set
# DOTFILES_SETUP_LOG=0 to turn logging off.

[[ -n "${_DOTFILES_SETUP_LOG_LOADED:-}" ]] && return 0
_DOTFILES_SETUP_LOG_LOADED=1

DOTFILES_LOG_DIR="$DOTFILES_STATE_DIR/logs"
DOTFILES_LOG_KEEP="${DOTFILES_LOG_KEEP:-30}"
SETUP_LOG=""

# Drop escape sequences and keep the last frame of carriage-return redraws.
_setup_log_clean() {
    sed -u -e 's/\x1b\[[0-9;?]*[A-Za-z]//g' -e 's/\x1b\][^\x07\x1b]*\(\x07\|\x1b\\\)//g' \
        -e 's/\r$//' -e 's/.*\r//'
}

# Up to ~2s for a log process to drain. A daemon a step started can inherit
# the transcript pipe and hold it open; the log must not wait on it.
_setup_log_drain() {
    local pid i
    for pid in "$@"; do
        for ((i = 0; i < 20; i++)); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
    done
}

_setup_log_checkout() {
    local rev branch dirty
    rev="$(git -C "$DOTFILES_DIR" rev-parse --short HEAD 2>/dev/null)" || { printf '%s (not a git checkout)' "$DOTFILES_DIR"; return; }
    branch="$(git -C "$DOTFILES_DIR" symbolic-ref --short -q HEAD 2>/dev/null || printf 'detached')"
    dirty="$(git -C "$DOTFILES_DIR" status --porcelain 2>/dev/null | wc -l)"
    printf '%s @ %s (%s' "$DOTFILES_DIR" "$rev" "$branch"
    (( dirty > 0 )) && printf ', %s uncommitted' "$dirty"
    printf ')'
}

# Ledger rows without the timestamp, so only real outcome changes diff.
_setup_log_ledger_rows() {
    [[ -f "$1" ]] || return 0
    awk -F '\t' -v OFS='\t' 'NR > 1 && NF { NF = 7; print }' "$1" | LC_ALL=C sort
}

setup_log_start() {
    [[ "${DOTFILES_SETUP_LOG:-1}" != 0 ]] || return 0
    local stamp mode="" os=""
    stamp="$(date -u +%Y%m%dT%H%M%SZ)"
    [[ "${DRY_RUN:-false}" == true ]] && mode="-dry-run"
    if ! (umask 077 && mkdir -p "$DOTFILES_LOG_DIR" && chmod 700 "$DOTFILES_LOG_DIR" \
            && : > "$DOTFILES_LOG_DIR/setup-$stamp$mode.log"); then
        warn "Could not create a setup log in $DOTFILES_LOG_DIR; continuing without one."
        return 0
    fi
    SETUP_LOG="$DOTFILES_LOG_DIR/setup-$stamp$mode.log"
    ln -sfn "${SETUP_LOG##*/}" "$DOTFILES_LOG_DIR/latest.log"
    find "$DOTFILES_LOG_DIR" -maxdepth 1 -name 'setup-*.log' -printf '%f\n' | LC_ALL=C sort -r \
        | tail -n +"$((DOTFILES_LOG_KEEP + 1))" | while IFS= read -r old; do rm -f -- "$DOTFILES_LOG_DIR/$old"; done

    _setup_log_started="$SECONDS"
    _setup_log_before="$(_setup_log_ledger_rows "$DOTFILES_LEDGER_FILE")"
    [[ -r /etc/os-release ]] && os="$(. /etc/os-release && printf '%s' "${PRETTY_NAME:-}")"
    {
        printf '# dotfiles setup log\n'
        printf 'started:  %s\n' "$(date -u +%FT%TZ)"
        printf 'command:  ./setup.sh%s\n' "$(printf ' %q' "$@")"
        printf 'checkout: %s\n' "$(_setup_log_checkout)"
        printf 'host:     %s, %s, %s\n' "$(uname -n)" "${os:-unknown OS}" "$(uname -rm)"
        printf '\n'
    } >> "$SETUP_LOG"

    # stdout and stderr each pass through tee into one cleaning process, so the
    # terminal keeps them apart and the log keeps their order.
    exec {_setup_log_tty_out}>&1 {_setup_log_tty_err}>&2
    exec {_setup_log_fd}> >(_setup_log_clean >> "$SETUP_LOG")
    _setup_log_cleaner=$!
    exec > >(tee "/dev/fd/$_setup_log_fd") ; _setup_log_tee_out=$!
    exec 2> >(tee "/dev/fd/$_setup_log_fd" >&2) ; _setup_log_tee_err=$!
    trap setup_log_finish EXIT
}

setup_log_finish() {
    local rc=$? after changes
    [[ -n "$SETUP_LOG" ]] || return "$rc"
    trap - EXIT
    exec 1>&"$_setup_log_tty_out"
    exec 2>&"$_setup_log_tty_err"
    _setup_log_drain "$_setup_log_tee_out" "$_setup_log_tee_err"

    after="$(_setup_log_ledger_rows "$DOTFILES_LEDGER_FILE")"
    changes="$(diff <(printf '%s\n' "$_setup_log_before") <(printf '%s\n' "$after") \
        | sed -n 's/^< /- /p; s/^> /+ /p' || true)"
    {
        printf '\n# finished: %s (exit %s, %ss)\n' "$(date -u +%FT%TZ)" "$rc" "$((SECONDS - _setup_log_started))"
        if [[ -n "$changes" ]]; then
            printf '# ledger changes (- before, + after; timestamps omitted):\n%s\n' "$changes"
        else
            printf '# ledger changes: none\n'
        fi
    } >&"$_setup_log_fd"
    exec {_setup_log_fd}>&-
    _setup_log_drain "$_setup_log_cleaner"
    printf 'Setup log: %s\n' "$SETUP_LOG" >&2
    return "$rc"
}
