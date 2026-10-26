#!/bin/bash
# agent-badge needs jq: it is selected with Claude Code or Codex while the
# badge is enabled, installed before them, and its failure fails the run.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/harness.sh"
fixture_init
trap fixture_cleanup EXIT
source "$ROOT/setup.sh"
calls=""
install_eget_tools() { calls+=" eget[$*]"; }
run_installer() { calls+=" $1"; }
select_ai() { SELECTED_CAPABILITIES=() SELECTED_AI_TOOLS=(); calls=""; parse_arguments "$@"; }
badge() { AGENT_BADGE_REQUEST="$1"; }

badge enabled; select_ai --claude
install_selection >/dev/null
assert_eq "$calls" ' eget[jq] claude' 'badge dependency missing from an AI-only selection'
badge disabled; select_ai --claude
install_selection >/dev/null
assert_eq "$calls" ' claude' 'a disabled badge installed its dependency'
badge enabled; select_ai --opencode
install_selection >/dev/null
assert_eq "$calls" ' opencode' 'a CLI without the badge installed its dependency'
install_eget_tools() { return 73; }
select_ai --codex
if install_selection >/dev/null 2>&1; then fail 'dependency failure reported success'; fi
printf 'badge-dependency: ok\n'
