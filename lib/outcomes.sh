#!/bin/bash
# Outcome records: what every check reports, and how commands exit on them.
#
# A record is one line, CLASS<TAB>SECTION<TAB>SUBJECT<TAB>MESSAGE. Classes:
#   ok           a check passed (shown with -v)
#   convergence  apply has work to do, or failed to do it
#   health       apply cannot fix it; needs the operator
#   incomplete   the check could not be made
#   advisory     informational
# Checkers print records; no command parses another command's display text.

[[ -n "${_DOTFILES_OUTCOMES_LOADED:-}" ]] && return 0
_DOTFILES_OUTCOMES_LOADED=1

# outcome CLASS SECTION SUBJECT MESSAGE: print one record.
outcome() {
    local class="$1" section="$2" subject="$3" message="${4:-}"
    case "$class" in
        ok|convergence|health|incomplete|advisory) ;;
        *) printf 'outcome: invalid class: %s\n' "$class" >&2; return 2 ;;
    esac
    section="${section//[$'\t\n\r']/ }"
    subject="${subject//[$'\t\n\r']/ }"
    message="${message//[$'\t\n\r']/ }"
    printf '%s\t%s\t%s\t%s\n' "$class" "$section" "$subject" "$message"
}

# outcome_exit COMMAND < RECORDS: the exit status for COMMAND. Every finding is
# printed regardless; the status is the first class present, in the command's
# order of precedence.
outcome_exit() {
    local command="$1" order
    case "$command" in
        verify) order="convergence:1 incomplete:3 health:2" ;;
        apply|update|profile) order="convergence:1 incomplete:3" ;;
        refresh) order="incomplete:3" ;;
        *) printf 'outcome_exit: unknown command: %s\n' "$command" >&2; return 2 ;;
    esac
    awk -F '\t' -v order="$order" '
        { seen[$1] = 1 }
        END {
            n = split(order, pairs, " ")
            for (i = 1; i <= n; i++) {
                split(pairs[i], pair, ":")
                if (pair[1] in seen) { print pair[2]; exit }
            }
            print 0
        }'
}

# outcome_converged < RECORDS: converged means every check completed and none
# found convergence work.
outcome_converged() {
    ! awk -F '\t' '$1 == "convergence" || $1 == "incomplete" { found = 1 } END { exit !found }'
}

# outcome_render [-v] < RECORDS: group records by section, in first-seen order.
# Passing checks are listed only with -v; a section with nothing to show is
# omitted.
outcome_render() {
    local verbose=0
    [[ "${1:-}" == -v ]] && verbose=1
    awk -F '\t' -v verbose="$verbose" '
        function symbol(class) {
            if (class == "ok") return "ok  "
            if (class == "convergence") return "fix "
            if (class == "health") return "warn"
            if (class == "incomplete") return "??  "
            return "note"
        }
        $1 == "ok" && !verbose { next }
        {
            if (!($2 in count)) order[++sections] = $2
            line = sprintf("  %s %s", symbol($1), $3)
            if ($4 != "") line = line ": " $4
            lines[$2, ++count[$2]] = line
        }
        END {
            for (s = 1; s <= sections; s++) {
                name = order[s]
                if (s > 1) print ""
                print name
                for (i = 1; i <= count[name]; i++) print lines[name, i]
            }
        }'
}

# outcome_summary < RECORDS: one line of counts per class.
outcome_summary() {
    awk -F '\t' '
        { n[$1]++ }
        END {
            printf "%d ok, %d to converge, %d health, %d incomplete, %d advisory\n", \
                n["ok"], n["convergence"], n["health"], n["incomplete"], n["advisory"]
        }'
}
