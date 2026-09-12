#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/harness.sh"
fixture_init
trap fixture_cleanup EXIT
source "$ROOT/setup.sh"
command() {
    if [[ "$1" == -v && "$2" == jq ]]; then return 1; fi
    builtin command "$@"
}
calls=""
install_eget_tools() { calls+=" dependency:$1"; }
run_installer() { calls+=" cli:$1"; }
AI_TOOLS=(claude)
AGENT_BADGE_REQUEST=enabled
install_ai_packages >/dev/null
assert_eq "$calls" ' dependency:jq cli:claude' 'badge dependency missing from AI-only selection'
calls=""; AGENT_BADGE_REQUEST=disabled
install_ai_packages >/dev/null
assert_eq "$calls" ' cli:claude' 'disabled badge installed dependency'
calls=""; AGENT_BADGE_REQUEST=enabled; AI_TOOLS=(opencode)
install_ai_packages >/dev/null
assert_eq "$calls" ' cli:opencode' 'unsupported badge CLI installed dependency'
AI_TOOLS=(codex)
install_eget_tools() { return 73; }
if install_ai_packages >/dev/null; then fail 'dependency failure reported success'; fi
printf 'badge-dependency: ok\n'
