#!/bin/bash
# versions.lock: rows by component and architecture, validation of malformed,
# duplicate, missing, and mixed rows, and setup refusing an invalid lock
# before a tier that downloads.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
unset DOTFILES_OPERATION
export NO_COLOR=1 DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_OS_VERSION=24.04
source "$ROOT/lib/install.sh"

# The repository's lock is valid.
problems="$(versions_problems)"
[[ -z "$problems" ]] || fail "versions.lock is invalid: $problems"

sha() { printf '%064d' 0 | tr 0 "$1"; }
lock="$TEST_ROOT/versions.lock"
DOTFILES_VERSIONS_LOCK="$lock"
row() { local IFS=$'\t'; printf '%s\n' "$*"; }
{
    printf '# comment\n\n'
    row demo x86_64 v1 example/demo demo-amd64.tar.gz "$(sha a)" demo-dir/demo "sha256:$(sha b)"
    row demo arm64 v1 example/demo demo-arm64.tar.gz "$(sha c)" - "sha256:$(sha d)"
    row script any 2.0 example/script install.sh "$(sha e)" - version:2.0
} > "$lock"

# Rows: per-arch (amd64/arm64 read as x86_64/aarch64) and arch-independent.
assert_eq "$(versions_field demo artifact x86_64)" demo-amd64.tar.gz "x86_64 row"
assert_eq "$(versions_field demo artifact amd64)" demo-amd64.tar.gz "amd64 is x86_64"
assert_eq "$(versions_field demo member aarch64)" - "aarch64 row from arm64"
assert_eq "$(versions_field demo identity)" "sha256:$(sha b)" "this machine's architecture by default"
assert_eq "$(DOTFILES_TEST_ARCH=aarch64 versions_field demo want)" v1 "the test architecture"
assert_eq "$(versions_field script sha256 aarch64)" "$(sha e)" "an any row serves every architecture"
if versions_row missing >/dev/null; then fail "a missing component had a row"; fi
if versions_field demo nonsense >/dev/null 2>&1; then fail "an unknown field was read"; fi

# problems_for ROWS...: versions_problems for a lock of just these rows, with
# no registry tools and the bootstrap components excused.
problems_for() {
    printf '%s\n' "$@" > "$lock"
    versions_problems | grep -Ev '^(neovim|tmux|eget|nvm|vim-plug|sbx|node|npm|rust|aws-cli) has no row for ' || true
}
declare -A saved_method=()
for name in "${!TOOL_METHOD[@]}"; do saved_method[$name]="${TOOL_METHOD[$name]}"; done
TOOL_METHOD=()

good="$(row demo x86_64 v1 example/demo a.tar.gz "$(sha a)" - "sha256:$(sha b)")"
assert_eq "$(problems_for "$good")" "" "a valid row"
[[ "$(problems_for "$(printf 'demo\tx86_64\tv1')")" == *"3 fields, expected 8"* ]] || fail "a short row passed"
[[ "$(problems_for "$(row demo sparc v1 example/demo a "$(sha a)" - -)")" == *"unknown arch sparc"* ]] || fail "an unknown arch passed"
[[ "$(problems_for "$(row demo x86_64 - example/demo a "$(sha a)" - -)")" == *"no wanted version"* ]] || fail "a row without a version passed"
[[ "$(problems_for "$(row demo x86_64 v1 example/demo a ABC - -)")" == *"sha256 is malformed"* ]] || fail "a malformed sha256 passed"
[[ "$(problems_for "$(row demo x86_64 v1 example/demo a "$(sha a)" - md5:abc)")" == *"identity is malformed"* ]] || fail "a malformed identity passed"
[[ "$(problems_for "$good" "$good")" == *"duplicate demo x86_64"* ]] || fail "a duplicate row passed"
[[ "$(problems_for "$good" "$(row demo amd64 v1 example/demo a "$(sha a)" - -)")" == *"duplicate demo x86_64"* ]] \
    || fail "amd64 and x86_64 rows for one component passed"
[[ "$(problems_for "$good" "$(row demo any v1 example/demo a "$(sha a)" - -)")" == *"both an arch-independent row and per-arch rows"* ]] \
    || fail "mixed any and per-arch rows passed"

# Every eget tool needs a row for each architecture it supports.
TOOL_METHOD=(['demo']=eget)
TOOL_ARCHES=(['demo']='x86_64,aarch64')
[[ "$(problems_for "$good")" == *"demo has no row for aarch64"* ]] || fail "a missing architecture passed"

TOOL_METHOD=()
for name in "${!saved_method[@]}"; do TOOL_METHOD[$name]="${saved_method[$name]}"; done

# setup.sh refuses an invalid lock before a tier that downloads, and only
# warns for the config tier, which downloads nothing.
cp "$ROOT/versions.lock" "$lock"
printf 'broken\trow\n' >> "$lock"
export DOTFILES_VERSIONS_LOCK="$lock"
rc=0
output="$("$ROOT/setup.sh" --bash --dry-run 2>&1)" || rc=$?
(( rc != 0 )) || fail "setup --bash accepted an invalid lock"
[[ "$output" == *"versions.lock is invalid"*"2 fields, expected 8"* && "$output" != *"Would install eget"* ]] \
    || fail "setup --bash did not stop on the invalid lock: $output"
output="$("$ROOT/setup.sh" --config --dry-run --no-hooks --no-theme 2>&1)" || fail "setup --config failed on an invalid lock: $output"
[[ "$output" == *"versions.lock is invalid (not needed for the config tier)"* ]] || fail "setup --config did not warn: $output"

printf 'versions-lock: ok\n'
