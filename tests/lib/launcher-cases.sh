#!/bin/bash
# Shared standalone AI installer cases. Each uses its own home and ledger;
# the caller supplies a local release and its install function.
launcher_install_cases() {
    local component="$1" binary="$2" installer="$3" release_dir="$4" scenario failed=false
    local -a scenarios=(missing-bin-dir missing-bin-path eget-before-ai alias earlier-elf absent-path-elf
        unmarked-no-dir unmarked-ahead unmarked-after wrong-marker late-marker no-shebang bom execute-only empty
        marked-after marker-at-ten symlink-marked)
    scenarios+=(managed-elf-update)
    [[ "$component" != antigravity ]] || scenarios+=(managed-unmarked-update)
    for scenario in "${scenarios[@]}"; do
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
    unset DOTFILES_CALLER_PATH DOTFILES_CALLER_PATH_OWNER
    mkdir -p "$HOME" "$case_root/launcher"
    target="$HOME/.local/bin/$binary" entry="$case_root/launcher/$binary"
    printf '#!/bin/sh\n# dotfiles-launcher: %s\necho called >> "%s/calls"\nexit 97\n' "$binary" "$case_root" > "$entry"
    chmod +x "$entry"
    export PATH="$case_root/launcher:$TEST_SYSTEM_PATH"
    case "$scenario" in
        missing-bin-dir) [[ ! -d "$HOME/.local/bin" ]] || fail "fixture has a managed directory" ;;
        missing-bin-path) mkdir -p "$HOME/.local/bin" ;;
        marker-at-ten)
            { printf '#!/bin/sh\n'; printf '# padding\n%.0s' {1..8}; printf '# dotfiles-launcher: %s\nexit 97\n' "$binary"; } > "$entry"
            ;;
        symlink-marked)
            mv "$entry" "$case_root/launcher-script"
            ln -s ../launcher-script "$entry"
            ;;
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
        managed-elf-update|managed-unmarked-update)
            if [[ "$component" == antigravity ]]; then make_release 1.5.18; else make_release 19.2.1; fi
            export PATH="$HOME/.local/bin:$TEST_SYSTEM_PATH"
            "$installer" >/dev/null 2>&1 || fail "$binary update fixture install"
            if [[ "$scenario" == managed-elf-update ]]; then
                cp -- /bin/false "$entry"
            else
                sed -i '/^# dotfiles-launcher:/d' "$entry"
            fi
            export PATH="$case_root/launcher:$HOME/.local/bin:$TEST_SYSTEM_PATH"
            local rerun_rc=0 rerun_out expected
            rerun_out="$("$installer" 2>&1)" || rerun_rc=$?
            if [[ "$component" == antigravity ]]; then
                make_release 1.6.0
                expected='agy 1.6.0'
            else
                printf '19.2.2\n' > "$TEST_ROOT/next"
                expected='omp 19.2.2'
            fi
            out="$("$installer" --update 2>&1)" || rc=$?
            [[ $rc -eq 0 && "$(AGY_CLI_DISABLE_AUTO_UPDATE=true "$target" --version)" == "$expected" ]] \
                || fail "$binary $scenario: rc=$rc $out"
            [[ $rerun_rc -eq 2 && "$rerun_out" == *'already installed'* ]] \
                || fail "$binary $scenario rerun: rc=$rerun_rc $rerun_out"
            rc=0; out="$("$installer" --update 2>&1)" || rc=$?
            [[ $rc -eq 2 && "$out" == *'current'* ]] || fail "$binary $scenario current: rc=$rc $out"
            # Forced replacement still preserves the separate install, as omp
            # does; the bypass applies to retaining/updating a working copy.
            rc=0; out="$("$installer" --force 2>&1)" || rc=$?
            [[ $rc -eq 2 && "$out" == *"externally-managed $binary"* ]] \
                || fail "$binary $scenario force: rc=$rc $out"
            ;;
        unmarked-*|wrong-marker|late-marker|no-shebang|bom|execute-only|empty|marked-after)
            case "$scenario" in
                unmarked-*) sed -i '/^# dotfiles-launcher:/d' "$entry" ;;
                wrong-marker) sed -i 's/^# dotfiles-launcher:.*/# dotfiles-launcher: another-tool/' "$entry" ;;
                late-marker)
                    { printf '#!/bin/sh\n'; printf '# padding\n%.0s' {1..9}; printf '# dotfiles-launcher: %s\nexit 97\n' "$binary"; } > "$entry"
                    ;;
                no-shebang) sed -i '1d' "$entry" ;;
                bom) sed -i '1s/^/\xEF\xBB\xBF/' "$entry" ;;
                execute-only) sed -i '/^# dotfiles-launcher:/d' "$entry"; chmod 111 "$entry" ;;
                empty) : > "$entry" ;;
            esac
            case "$scenario" in
                unmarked-ahead)
                    mkdir -p "$HOME/.local/bin"
                    export PATH="$case_root/launcher:$HOME/.local/bin:$TEST_SYSTEM_PATH"
                    ;;
                unmarked-after|marked-after)
                    mkdir -p "$HOME/.local/bin"
                    export PATH="$HOME/.local/bin:$case_root/launcher:$TEST_SYSTEM_PATH"
                    ;;
            esac
            out="$("$installer" 2>&1)" || rc=$?
            [[ $rc -eq 2 && ! -e "$target" && "$out" == *"externally-managed $binary"* ]] \
                || fail "$binary $scenario installed an external script: rc=$rc $out"
            [[ "$out" == *"# dotfiles-launcher: $binary"* && "$out" == *'#!'* && "$out" == *'readable'* && "$out" == *'first 10 lines'* ]] \
                || fail "$binary $scenario refusal did not explain the declaration: $out"
            ;;
    esac
    if [[ "$scenario" == missing-bin-* || "$scenario" == marker-at-ten || "$scenario" == symlink-marked ]]; then
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
