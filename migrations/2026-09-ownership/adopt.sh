#!/bin/bash
# One-time, operator-confirmed adoption of installations predating the ledger.
# Delete this directory after the personal/work fleet has migrated.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "$ROOT/lib/registry.sh"
source "$ROOT/lib/state.sh"

usage() {
    cat <<'EOF'
Usage: migrations/2026-09-ownership/adopt.sh [--apply [--yes]] [COMPONENT ...]

Default: preview unknown/present ledger entries, with no writes or CLI execution.
Specify component names to select a subset. --apply requires typing 'adopt',
or --yes for an explicitly authorized unattended run. No packages are installed.

Only confirm installations you want dotfiles to manage, including future removal.
Paths and file checks establish eligibility, not historical installation provenance.
EOF
}

die() { printf 'Error: %s\n' "$*" >&2; }

# Check the conventional launcher AND its resolved target. Do not execute vendor
# CLIs or source nvm.sh: even a version query may create user configuration.
inspect_installation() {
    local name="$1" launcher active file resolved home_real companion
    PROBED_PATH="" PROBED_ID="" PROBED_NOTE="" REASON=""
    home_real="$(realpath -e "$HOME")" || return 1
    case "$name" in
        nvm) launcher="$HOME/.nvm/nvm.sh" ;;
        rust) launcher="$HOME/.cargo/bin/rustc" ;;
        *) launcher="$HOME/.local/bin/${TOOL_BINARY[$name]}" ;;
    esac
    local -a files=("$launcher")
    [[ "$name" != rust ]] || files+=("$HOME/.cargo/bin/cargo" "$HOME/.cargo/bin/rustup")
    for companion in ${TOOL_COMPANIONS[$name]:-}; do
        file="$HOME/.local/bin/$companion"
        if [[ -e "$file" || -L "$file" ]]; then
            files+=("$file")
        else
            PROBED_ID+="missing:$companion;"
            PROBED_NOTE+=" missing $companion (repair with its setup tier);"
        fi
    done
    for file in "${files[@]}"; do
        if [[ ! -f "$file" || ! -s "$file" || ! -O "$file" ]]; then
            REASON="missing, empty, or not user-owned: $file"; return 1
        fi
        if [[ "$name" != nvm && ! -x "$file" ]]; then
            REASON="not executable: $file"; return 1
        fi
        resolved="$(realpath -e -- "$file")" || return 1
        if [[ "$resolved" != "$home_real/"* ]] || ! tool_owned_path "$name" "$resolved"; then
            REASON="target outside the local installation roots: $resolved"; return 1
        fi
        [[ "$resolved" != *$'\t'* && "$resolved" != *$'\n'* && "$resolved" != *$'\r'* ]] || return 1
        PROBED_ID+="$resolved:$(sha256sum -- "$file" | cut -d ' ' -f1);"
    done
    PROBED_PATH="$(realpath -e -- "$launcher")"
    if [[ "$name" == nvm ]]; then
        PROBED_PATH="$(realpath -e "$HOME/.nvm")"
    else
        active="$(type -P "${TOOL_BINARY[$name]}" || true)"
        if [[ -n "$active" && "$(realpath -e -- "$active")" != "$PROBED_PATH" ]]; then
            # Match the existing ripgrep verifier: agent/editor-private rg is
            # incidental, while ~/.local/bin/rg is the durable installation.
            if [[ "$name" == ripgrep && ( "$active" == */.codex/* || "$active" == */.vscode*/extensions/* ) ]]; then
                PROBED_NOTE+=" (private rg on PATH ignored)"
            else
                REASON="another installation is active on PATH: $active"; return 1
            fi
        fi
    fi
}

confirm_adoption() {
    local answer
    [[ -t 0 ]] || { die 'Use --yes with --apply for an authorized noninteractive run.'; return 1; }
    read -r -p "Confirm these installations should be managed by dotfiles. Type 'adopt': " answer
    [[ "$answer" == adopt ]] || { die 'Adoption cancelled.'; return 1; }
}

apply_plan() (
    _state_lock_acquire || exit 1
    staged=""
    trap '[[ -z "$staged" ]] || rm -f -- "$staged"; _state_lock_release' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    journal_pending && { die 'Resolve the pending artifact transaction first.'; exit 1; }
    [[ "$(sha256sum "$DOTFILES_LEDGER_FILE")" == "$ledger_hash" ]] \
        || { die 'Ledger changed after preview; rerun the migration.'; exit 1; }
    local name row backup now
    for name in "${!adopt_paths[@]}"; do
        inspect_installation "$name" || { die "Recheck failed for $name: $REASON"; exit 1; }
        [[ "$PROBED_ID" == "${adopt_ids[$name]}" && "$PROBED_PATH" == "${adopt_paths[$name]}" ]] \
            || { die "$name changed after preview; rerun the migration."; exit 1; }
    done
    staged="$(mktemp "$DOTFILES_STATE_DIR/.ownership-ledger.XXXXXX")" || exit 1
    now="$(date +%s)"
    while IFS= read -r row || [[ -n "$row" ]]; do
        name="${row%%$'\t'*}"
        if [[ -n "${adopt_paths[$name]:-}" ]]; then
            printf '%s\tyes\tdotfiles\tinstalled\t%s\t%s\t%s\t%s\n' \
                "$name" "${adopt_versions[$name]}" "${adopt_paths[$name]}" \
                "${adopt_notes[$name]}; operator-adopted 2026-09" "$now" || exit 1
        else
            printf '%s\n' "$row" || exit 1
        fi
    done < "$DOTFILES_LEDGER_FILE" > "$staged" || exit 1
    _state_validate_file "$staged" ledger 8 || exit 1
    backup="$(mktemp "$DOTFILES_STATE_DIR/components.before-ownership-2026-09.tsv.XXXXXX")" || exit 1
    cp -- "$DOTFILES_LEDGER_FILE" "$backup" || exit 1
    printf 'Ledger backup: %s\n' "$backup"
    _state_commit_file "$staged" "$DOTFILES_LEDGER_FILE" || exit 1
    printf 'Adopted %s installation(s). No executables or configuration were changed.\n' "${#adopt_paths[@]}"
)

main() {
    local apply=false yes=false name line applicable owner status version path note timestamp
    local blocked=0 ledger_hash
    local -a names=()
    local -A adopt_paths=() adopt_ids=() adopt_versions=() adopt_notes=()
    while (( $# )); do
        case "$1" in
            --help|-h) usage; return ;;
            --apply) apply=true ;;
            --yes) yes=true ;;
            -*) usage >&2; die "Unknown option: $1"; return 64 ;;
            *) names+=("$1") ;;
        esac
        shift
    done
    [[ "$yes" == false || "$apply" == true ]] || { die '--yes requires --apply.'; return 64; }
    [[ -f "$DOTFILES_LEDGER_FILE" ]] || { die 'No component ledger; run setup.sh --config first.'; return 1; }
    _state_validate_file "$DOTFILES_LEDGER_FILE" ledger 8 || return 1
    awk -F '\t' 'NR > 1 && seen[$1]++ { exit 1 }' "$DOTFILES_LEDGER_FILE" \
        || { die 'Duplicate component records; repair the ledger first.'; return 1; }
    journal_pending && { die 'Resolve the pending artifact transaction first.'; return 1; }
    ledger_hash="$(sha256sum "$DOTFILES_LEDGER_FILE")"
    if (( ${#names[@]} == 0 )); then
        mapfile -t names < <(awk -F '\t' '$3 == "unknown" && $4 == "present" { print $1 }' "$DOTFILES_LEDGER_FILE" | sort)
    fi
    printf '%-18s %-7s %s\n' Component Action 'Resolved installation / reason'
    for name in "${names[@]}"; do
        if [[ ! "$name" =~ ^[a-z0-9-]+$ || -z "${TOOL_BINARY[$name]:-}" ]]; then
            printf '%-18s BLOCK   Unknown component\n' "$name"; blocked=$((blocked + 1)); continue
        fi
        line="$(ledger_line "$name" || true)"
        IFS=$'\t' read -r _ applicable owner status version path note timestamp <<< "$line"
        if [[ "$owner" == dotfiles || "$owner" == external || "$owner" == package-manager ]]; then
            printf '%-18s KEEP    Recorded ownership: %s\n' "$name" "$owner"; continue
        fi
        if [[ "$owner" != unknown || "$status" != present || "$applicable" != yes \
              || "${TOOL_METHOD[$name]}" == apt || "$name" == aws-cli ]]; then
            printf '%-18s BLOCK   Not an unclaimed local installation\n' "$name"; blocked=$((blocked + 1)); continue
        fi
        if ! inspect_installation "$name"; then
            printf '%-18s BLOCK   %s\n' "$name" "$REASON"; blocked=$((blocked + 1)); continue
        fi
        adopt_paths[$name]="$PROBED_PATH"; adopt_ids[$name]="$PROBED_ID"
        # A self-updated release may have moved since discovery. Do not attach
        # an old version string to that new artifact without executing the CLI.
        [[ "$path" == "$PROBED_PATH" ]] || version=-
        adopt_versions[$name]="$version"; adopt_notes[$name]="$note"
        printf '%-18s ADOPT   %s%s\n' "$name" "$PROBED_PATH" "$PROBED_NOTE"
    done
    (( blocked == 0 )) || { die 'Blocked entries found; correct them or select an eligible subset by name. Nothing adopted.'; return 1; }
    (( ${#adopt_paths[@]} )) || { printf 'Nothing to adopt.\n'; return 0; }
    [[ "$apply" == true ]] || { printf '\nPreview only. Rerun with --apply after reviewing the list.\n'; return 0; }
    [[ "$yes" == true ]] || confirm_adoption || return 1
    apply_plan
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then main "$@"; fi
