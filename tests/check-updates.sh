#!/bin/bash
# check-updates against recorded responses: every kind of pin compared with its
# source, advisories newer than the pin, JSON and records, and the exit codes.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT/tests/lib/harness.sh"
fixture_init
trap fixture_cleanup EXIT
export DOTFILES_FETCH_FIXTURES="$TEST_ROOT/responses" GITHUB_TOKEN=fixture
mkdir -p "$DOTFILES_FETCH_FIXTURES"
# record URL SUFFIX BODY: a recorded response (.json for the GitHub API).
record() { printf '%s' "$3" > "$DOTFILES_FETCH_FIXTURES/$(python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1], safe=""))' "$1")$2"; }
lockfield() { awk -F '\t' -v c="$1" -v n="$2" '$1 == c { print $n; exit }' "$ROOT/versions.lock"; }
check() { local rc=0; OUTPUT="$("$ROOT/bin/check-updates" "$@" 2>&1)" || rc=$?; RC=$rc; }
api=https://api.github.com/repos

fd_pin="$(lockfield fd 3)"
record "$api/sharkdp/fd/releases/latest" .json '{"tag_name": "v99.0.0"}'
record "$api/sharkdp/fd/releases/tags/$fd_pin" .json '{"published_at": "2026-01-01T00:00:00Z"}'
record "$api/sharkdp/fd/security-advisories?state=published&per_page=100" .json \
    '[{"ghsa_id": "GHSA-new1", "severity": "high", "summary": "a fix after the pin", "published_at": "2026-05-01T00:00:00Z"},
      {"ghsa_id": "GHSA-old1", "severity": "low", "summary": "fixed long ago", "published_at": "2025-01-01T00:00:00Z"}]'
check fd
[[ "$RC" == 0 && "$OUTPUT" == *"fd"*"github"*"$fd_pin"*"v99.0.0"*"update available"* && "$OUTPUT" == *"advisory: GHSA-new1 (high)"* \
   && "$OUTPUT" != *GHSA-old1* ]] || fail "fd ($RC): $OUTPUT"
check fd --outdated
assert_eq "$RC" 2 "an outdated pin with --outdated"
check fd --records
[[ "$OUTPUT" == *$'advisory\tUpstream\tfd\tv99.0.0 is available (pinned '"$fd_pin"')'* \
   && "$OUTPUT" == *$'health\tUpstream\tfd\tGHSA-new1 (high): a fix after the pin'* ]] || fail "fd records: $OUTPUT"

# Node: the newest LTS, and a security release newer than the pin on its line.
node_pin="$(lockfield node 3)"
record https://nodejs.org/dist/index.json '' "[{\"version\": \"v26.20.0\", \"lts\": false},
    {\"version\": \"v24.99.0\", \"lts\": \"Krypton\", \"security\": true},
    {\"version\": \"$node_pin\", \"lts\": \"Krypton\"}]"
check node --json
python3 -c 'import json, sys
r = json.loads(sys.argv[1])[0]
assert r["latest"] == "v24.99.0" and r["status"] == "outdated", r
assert r["advisories"] == ["security release v24.99.0 (Node 24)"], r' "$OUTPUT" || fail "node JSON: $OUTPUT"

# Rust, sbx, and a plugin commit, current; a failed lookup is exit 1.
record https://static.rust-lang.org/dist/channel-rust-stable.toml '' "date = \"2026-10-01\"
[pkg.rustc]
version = \"$(lockfield rust 3) (abc 2026-10-01)\""
check rust
[[ "$RC" == 0 && "$OUTPUT" == *"rust"*"up to date"* ]] || fail "rust: $OUTPUT"
sbx_pin="$(lockfield sbx 3)"
for arch in amd64 arm64; do
    record "https://download.docker.com/linux/ubuntu/dists/noble/stable/binary-$arch/Packages" '' \
        "Package: docker-sbx
Version: $sbx_pin-1~ubuntu.24.04~noble
"
done
check sbx
[[ "$OUTPUT" == *"sbx"*"up to date"* ]] || fail "sbx: $OUTPUT"
surround="$(sed -nE "s/^Plug 'tpope\/vim-surround', \{ 'commit': '([0-9a-f]{40})'.*/\1/p" "$ROOT/configs/init.vim")"
record "$api/tpope/vim-surround/commits/HEAD" .json "{\"sha\": \"$surround\"}"
check vim-surround
[[ "$OUTPUT" == *"vim-surround"*"commit"*"up to date"* ]] || fail "plugin: $OUTPUT"
check tmux
[[ "$RC" == 1 && "$OUTPUT" == *"check failed"* ]] || fail "a failed lookup ($RC): $OUTPUT"
check tmux --records
[[ "$RC" == 0 && "$OUTPUT" == $'incomplete\tUpstream\ttmux\trelease lookup failed' ]] || fail "failed lookup record: $OUTPUT"
check nothing-here
assert_eq "$RC" 1 "an unknown pin"

printf 'check-updates: ok\n'
