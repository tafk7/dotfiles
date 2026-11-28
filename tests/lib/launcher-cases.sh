#!/bin/bash
# Shared standalone AI installer cases. Each uses its own home and ledger;
# the caller supplies a local release and its install function.
launcher_install_cases() {
    local component="$1" binary="$2" installer="$3" release_dir="$4" scenario failed=false
    for scenario in missing-bin-dir missing-bin-path eget-before-ai alias earlier-elf absent-path-elf; do
        if (launcher_install_case "$component" "$binary" "$installer" "$scenario" "$release_dir"); then
            printf 'launcher case: %s %s ok\n' "$binary" "$scenario"
        else
            failed=true
        fi
    done
    [[ "$failed" == false ]] || fail "$binary launcher cases failed"
}

launcher_install_case() {
    local component="$1" binary="$2" installer="$3" scenario="$4" release_dir="$5"
    local case_root="$TEST_ROOT/launcher-cases/$binary/$scenario" rc=0 out target entry
    export HOME="$case_root/home" XDG_STATE_HOME="$case_root/state"
    export XDG_CONFIG_HOME="$case_root/config" XDG_DATA_HOME="$case_root/data" XDG_CACHE_HOME="$case_root/cache"
    unset DOTFILES_CALLER_PATH
    mkdir -p "$HOME" "$case_root/launcher"
    target="$HOME/.local/bin/$binary" entry="$case_root/launcher/$binary"
    printf '#!/bin/sh\necho called >> "%s/calls"\nexit 97\n' "$case_root" > "$entry"
    chmod +x "$entry"
    export PATH="$case_root/launcher:$TEST_SYSTEM_PATH"
    case "$scenario" in
        missing-bin-dir) [[ ! -d "$HOME/.local/bin" ]] || fail "fixture has a managed directory" ;;
        missing-bin-path) mkdir -p "$HOME/.local/bin" ;;
        eget-before-ai)
            mkdir -p "$HOME/.local/bin"
            export PATH="$case_root/launcher:$HOME/.local/bin:$TEST_SYSTEM_PATH"
            # Run the real setup dispatch, narrowly selected to avoid packages.
            # A local eget stand-in copies the verified eza artifact.
            printf '#!/bin/sh\necho "eza 1.0"\n' > "$case_root/eza"
            export EGET_CASE_ARTIFACT="$case_root/eza"
            cat > "$HOME/.local/bin/eget" <<'EOF'
#!/bin/sh
if [ "${1:-}" = --version ]; then echo 'eget 1.3.4'; exit 0; fi
while [ "$#" -gt 0 ]; do
    if [ "$1" = --to ]; then cp "$EGET_CASE_ARTIFACT" "$2"; exit; fi
    shift
done
exit 98
EOF
            chmod +x "$HOME/.local/bin/eget"
            export DOTFILES_VERSIONS_LOCK="$case_root/versions.lock"
            local digest
            digest="$(sha256sum "$case_root/eza" | awk '{print $1}')"
            awk -F '\t' -v OFS='\t' -v identity="sha256:$digest" '$1 == "eza" { $8 = identity } { print }' \
                "$ROOT/versions.lock" > "$DOTFILES_VERSIONS_LOCK"
            if [[ "$component" == antigravity ]]; then
                export DOTFILES_ANTIGRAVITY_MANIFEST_URL="file://$release_dir/manifest.json"
            else
                export DOTFILES_OMP_RELEASE_DIR="$release_dir"
            fi
            out="$("$ROOT/setup.sh" --bash "--$component" --only "eza,$component" \
                --no-agent-badge --no-hooks --no-theme 2>&1)" || rc=$?
            [[ $rc -eq 0 && -f "$target" && -f "$HOME/.local/bin/eza" ]] \
                || fail "$binary $scenario: rc=$rc $out"
            ;;
        alias)
            export PATH="$HOME/.local/bin:$TEST_SYSTEM_PATH"
            "$installer" >/dev/null 2>&1 || fail "$binary alias fixture install"
            ln -s .local/bin "$HOME/bin"
            export PATH="$HOME/bin:$HOME/.local/bin:$TEST_SYSTEM_PATH"
            if [[ "$component" == antigravity ]]; then
                make_release 1.5.19
                out="$("$installer" --update 2>&1)" || rc=$?
            else
                out="$("$installer" --force 2>&1)" || rc=$?
            fi
            [[ $rc -eq 0 ]] || fail "$binary alias install/upgrade: rc=$rc $out"
            ;;
        earlier-elf|absent-path-elf)
            cp -- /bin/false "$entry"
            if [[ "$scenario" == earlier-elf ]]; then
                mkdir -p "$HOME/.local/bin"
                export PATH="$case_root/launcher:$HOME/.local/bin:$TEST_SYSTEM_PATH"
            else
                [[ ! -d "$HOME/.local/bin" ]] || fail "fixture has a managed directory"
            fi
            out="$("$installer" 2>&1)" || rc=$?
            [[ $rc -eq 2 && ! -e "$target" && "$out" == *"externally-managed $binary"* ]] \
                || fail "$binary $scenario: rc=$rc $out"
            ;;
    esac
    if [[ "$scenario" == missing-bin-* ]]; then
        out="$("$installer" 2>&1)" || rc=$?
        [[ $rc -eq 0 && -f "$target" ]] || fail "$binary $scenario: rc=$rc $out"
    fi
    [[ ! -e "$case_root/calls" ]] || fail "$binary $scenario ran the launcher"
    if [[ -f "$target" ]]; then
        local recorded
        recorded="$(awk -F '\t' -v name="$component" '$1 == name { print $3 "/" $6 }' "$XDG_STATE_HOME/dotfiles/components.tsv")"
        assert_eq "$recorded" "dotfiles/$target" "$binary $scenario ledger"
    fi
}
