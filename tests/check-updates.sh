#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/harness.sh"
fixture_init
trap fixture_cleanup EXIT
source "$ROOT/bin/check-updates"
resolve_github_auth() { GH_AUTH_SOURCE=fixture; }
emit_other_contracts() { :; }
parse_eget_toml() { printf 'cli/cli|v1\n'; }
gh_latest_tag() { return 1; }
ONLY_OUTDATED=true
if output="$(main)"; then fail "failed lookup returned success"; fi
[[ "$output" == *'check failed'* && "$output" != *'up to date'* ]] || fail "failed check concealed"
assert_eq "$(short_name cli/cli)" gh
gh_latest_tag() { printf 'v1\n'; }
JSON_OUTPUT=true
output="$(main)"
[[ "$(printf '%s' "$output" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)))')" == 0 ]] || fail "empty JSON result is not []"
gh_latest_tag() { printf 'v2\n'; }
rc=0
main >/dev/null || rc=$?
assert_eq "$rc" 2 "outdated exit status"
printf 'check-updates: ok\n'
