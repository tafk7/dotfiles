#!/bin/bash
# Component observation: structured fields, no side effects for any registry
# component, and exit 3 when the observation cannot be made.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
export DOTFILES_TEST_PLATFORM=ubuntu DOTFILES_TEST_ARCH=x86_64 DOTFILES_TEST_OS_VERSION=24.04
source "$ROOT/lib/install.sh"

field() { observation_field "$1" <<< "$2"; }

# --- Nothing observed changes anything, for every component, in-process and
# through each installer's --observe.
mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\necho "eza - banner\nv0.23.4 [+git]"\n' > "$HOME/.local/bin/eza"
# Stand-ins for tools that write even for --version, with the real mkdir as
# the tools have. Like gh 2.100: a telemetry device id, unless DO_NOT_TRACK or
# GH_TELEMETRY=false.
cat > "$HOME/.local/bin/gh" <<'GH'
#!/bin/sh
if [ -z "${DO_NOT_TRACK:-}" ] && [ "${GH_TELEMETRY:-}" != false ]; then
    /bin/mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/gh" && echo id > "${XDG_STATE_HOME:-$HOME/.local/state}/gh/device-id"
fi
echo "gh version 2.100.0 (2026-09-03)"
GH
# Like Neovim 0.12: its state directory and log, unless NVIM_LOG_FILE. On the
# test's PATH, which the engine here and the installers share.
cat > "$TEST_ROOT/bin/nvim" <<'NVIM'
#!/bin/sh
if [ -z "${NVIM_LOG_FILE:-}" ]; then
    /bin/mkdir -p "${XDG_STATE_HOME:-$HOME/.local/state}/nvim" && : > "${XDG_STATE_HOME:-$HOME/.local/state}/nvim/log"
fi
echo "NVIM v0.12.5"
NVIM
# Like glow 2.1 (a default config and a log under XDG) and starship 1.24 (a
# cache under ~/.cache, whatever XDG_CACHE_HOME says, unless STARSHIP_CACHE).
cat > "$HOME/.local/bin/glow" <<'GLOW'
#!/bin/sh
/bin/mkdir -p "${XDG_CONFIG_HOME:-$HOME/.config}/glow" && : > "${XDG_CONFIG_HOME:-$HOME/.config}/glow/glow.yml"
echo "glow version 2.1.1 (d37e988)"
GLOW
cat > "$HOME/.local/bin/starship" <<'STARSHIP'
#!/bin/sh
/bin/mkdir -p "${STARSHIP_CACHE:-$HOME/.cache/starship}"
echo "starship 1.24.2"
STARSHIP
chmod +x "$HOME/.local/bin/eza" "$HOME/.local/bin/gh" "$TEST_ROOT/bin/nvim" "$HOME/.local/bin/glow" "$HOME/.local/bin/starship"
install_mutation_spies
# Service queries are reads; every other systemctl use is still a mutation.
printf '#!/bin/sh\ncase "$1" in is-active|is-enabled) exit 3 ;; esac\nprintf "systemctl\\t%%s\\n" "$*" >> "$DOTFILES_MUTATION_LOG"\nexit 97\n' \
    > "$TEST_ROOT/bin/systemctl"
before="$(fixture_managed_manifest)"
for name in $(printf '%s\n' "${!TOOL_BINARY[@]}" | LC_ALL=C sort); do
    rc=0
    observe_component "$name" > "$TEST_ROOT/observation" 2>/dev/null || rc=$?
    [[ $rc -eq 0 || $rc -eq 3 ]] || fail "$name observation exited $rc"
    for key in applicable path owner identity want runnable companions ready; do
        grep -q "^$key=" "$TEST_ROOT/observation" || fail "$name observation lacks $key"
    done
    if [[ -f "$ROOT/installers/install-$name.sh" ]]; then
        rc=0
        "$ROOT/installers/install-$name.sh" --observe > "$TEST_ROOT/installer-observation" 2>/dev/null || rc=$?
        [[ $rc -eq 0 || $rc -eq 3 ]] || fail "install-$name.sh --observe exited $rc"
        cmp -s "$TEST_ROOT/observation" "$TEST_ROOT/installer-observation" \
            || fail "install-$name.sh --observe differs from the engine's observation"
    fi
    # Checked per component, so a host tool that writes on --version is named.
    after="$(fixture_managed_manifest)"
    [[ "$after" == "$before" ]] \
        || fail "$name observation changed HOME or XDG state: $(diff <(printf '%s\n' "$before") <(printf '%s\n' "$after") | grep '^[<>]' | head -5)"
done
[[ ! -s "$DOTFILES_MUTATION_LOG" ]] || fail "observation ran mutating commands: $(cat "$DOTFILES_MUTATION_LOG")"
export PATH="$TEST_SYSTEM_PATH"
rm -f "$TEST_ROOT"/bin/{mkdir,mv,rm,ln,cp,chmod,install,apt,apt-get,dpkg,tee,systemctl,sudo}

# --- Identity: an eget tool whose digest is versions.lock's identity is its
# locked tag; anything else is its digest.
obs="$(observe_component eza)"
assert_eq "$(field owner "$obs")" external "an unrecorded binary is not owned"
[[ "$(field identity "$obs")" == sha256:* ]] || fail "eget identity off the lock: $(field identity "$obs")"
assert_eq "$(field want "$obs")" "tag:$(versions_field eza want)" "eget want"
digest="$(sha256sum "$HOME/.local/bin/eza" | awk '{print $1}')"
awk -F '\t' -v OFS='\t' -v d="sha256:$digest" '$1 == "eza" && $2 == "x86_64" { $8 = d } 1' \
    "$ROOT/versions.lock" > "$TEST_ROOT/versions.lock"
DOTFILES_VERSIONS_LOCK="$TEST_ROOT/versions.lock"
ledger_record eza yes dotfiles installed v0.23.4 "$HOME/.local/bin/eza" "staged-release pin=v0.23.4 sha256=$digest"
obs="$(observe_component eza)"
assert_eq "$(field owner "$obs")/$(field identity "$obs")/$(field runnable "$obs")" "dotfiles/tag:v0.23.4/yes" "owned eget tool"
printf '#!/bin/sh\necho changed\n' >> "$HOME/.local/bin/eza"
[[ "$(field identity "$(observe_component eza)")" == sha256:* ]] || fail "a changed binary kept its tag identity"

# --- Absent, not applicable, external, and timed-out components.
obs="$(observe_component bat)"
assert_eq "$(field path "$obs")/$(field owner "$obs")/$(field ready "$obs")/$(field ready-reason "$obs")" "/none/no/not installed" "absent component"
obs="$(observe_component wsl2-ssh-agent)"
assert_eq "$(field applicable "$obs")" no "wsl-only component on native Ubuntu"
mkdir -p "$TEST_ROOT/usr/bin"
printf '#!/bin/sh\necho "fd 9.1.0"\n' > "$TEST_ROOT/usr/bin/fd"
printf '#!/bin/sh\nsleep 5\n' > "$TEST_ROOT/usr/bin/gdu"
chmod +x "$TEST_ROOT/usr/bin/fd" "$TEST_ROOT/usr/bin/gdu"
PATH="$TEST_ROOT/usr/bin:$PATH"
obs="$(observe_component fd)"
assert_eq "$(field owner "$obs")/$(field identity "$obs")" "external/sha256:$(sha256sum "$TEST_ROOT/usr/bin/fd" | awk '{print $1}')" "external eget tool"
rc=0
obs="$(DOTFILES_OBSERVE_TIMEOUT=1 observe_component gdu)" || rc=$?
assert_eq "$rc/$(field runnable "$obs")" "3/unknown" "a hung version probe"

# --- Node is NVM's default release, never a node on PATH; its identity
# carries the npm it has, so an independently upgraded npm is off the pin.
printf '#!/bin/sh\necho v18.0.0\n' > "$TEST_ROOT/usr/bin/node"
chmod +x "$TEST_ROOT/usr/bin/node"
node_dir="$HOME/.nvm/versions/node/v24.22.1"
mkdir -p "$node_dir/bin" "$node_dir/lib/node_modules/npm" "$HOME/.nvm/alias"
printf '#!/bin/sh\necho v24.22.1\n' > "$node_dir/bin/node"
chmod +x "$node_dir/bin/node"
printf '{\n  "version": "11.19.1"\n}\n' > "$node_dir/lib/node_modules/npm/package.json"
printf '24.22.1\n' > "$HOME/.nvm/alias/default"
awk -F '\t' -v OFS='\t' -v d="sha256:$(sha256sum "$node_dir/bin/node" | awk '{print $1}')" \
    '$1 == "node" && $2 == "x86_64" { $8 = d } 1' "$DOTFILES_VERSIONS_LOCK" > "$TEST_ROOT/versions.lock.node"
DOTFILES_VERSIONS_LOCK="$TEST_ROOT/versions.lock.node"
obs="$(observe_component node)"
assert_eq "$(field path "$obs")" "$node_dir/bin/node" "Node path"
assert_eq "$(field identity "$obs")" "$(field want "$obs")" "the locked Node and npm"
assert_eq "$(field want "$obs")" "version:24.22.1 (npm 11.19.1)" "Node want"
printf '{\n  "version": "12.0.2"\n}\n' > "$node_dir/lib/node_modules/npm/package.json"
assert_eq "$(field identity "$(observe_component node)")" "version:24.22.1 (npm 12.0.2)" "an upgraded npm"
printf '#!/bin/sh\necho other build\n' > "$node_dir/bin/node"
[[ "$(field identity "$(observe_component node)")" == sha256:* ]] || fail "another Node build kept the locked identity"
mkdir -p "$HOME/.nvm/versions/node/v22.0.0/lib/node_modules/npm"
cp -r "$node_dir/bin" "$HOME/.nvm/versions/node/v22.0.0/"
printf '{\n  "version": "10.0.0"\n}\n' > "$HOME/.nvm/versions/node/v22.0.0/lib/node_modules/npm/package.json"
printf 'v22.0.0\n' > "$HOME/.nvm/alias/default"
assert_eq "$(field identity "$(observe_component node)")" "version:22.0.0 (npm 10.0.0)" "another Node release"

# --- Rust is rustup's default toolchain, asked from / without overrides, so a
# project toolchain or RUSTUP_TOOLCHAIN cannot answer and nothing installs.
mkdir -p "$HOME/.cargo/bin" "$TEST_ROOT/project"
printf '[toolchain]\nchannel = "nightly"\n' > "$TEST_ROOT/project/rust-toolchain.toml"
cat > "$HOME/.cargo/bin/rustup" <<'EOF'
#!/bin/sh
echo "$PWD|${RUSTUP_TOOLCHAIN-unset}|${RUSTUP_AUTO_INSTALL-unset}|$*" >> "$HOME/rustup.log"
[ -f rust-toolchain.toml ] && { echo "nightly-x86_64-unknown-linux-gnu (overridden)"; exit 0; }
echo "${FAKE_DEFAULT:-1.98.1}-x86_64-unknown-linux-gnu (default)"
EOF
printf '#!/bin/sh\necho "rustc 1.98.1"\n' > "$HOME/.cargo/bin/rustc"
chmod +x "$HOME/.cargo/bin/rustup" "$HOME/.cargo/bin/rustc"
obs="$(cd "$TEST_ROOT/project" && RUSTUP_TOOLCHAIN=nightly PATH="$HOME/.cargo/bin:$PATH" observe_component rust)"
assert_eq "$(field identity "$obs")/$(field want "$obs")" "version:1.98.1/version:$(versions_field rust want any)" "Rust from a project directory"
grep -Fxq "/|unset|0|default" "$HOME/rustup.log" || fail "rustup was not asked from / without overrides: $(<"$HOME/rustup.log")"
obs="$(FAKE_DEFAULT=stable PATH="$HOME/.cargo/bin:$PATH" observe_component rust)"
assert_eq "$(field identity "$obs")" toolchain:stable "a channel default"
rm "$HOME/rustup.log"
assert_eq "$(field want "$(observe_component aws-cli)")" "version:$(versions_field aws-cli want)" "AWS CLI want"

# --- Unreadable state makes the observation incomplete.
printf 'schema\t1\nbroken row\n' > "$DOTFILES_LEDGER_FILE"
rc=0
observe_component eza >/dev/null || rc=$?
assert_eq "$rc" 3 "an unreadable ledger"

printf 'observe: ok\n'
