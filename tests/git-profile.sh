#!/bin/bash
# git profile and gcl -p against a temporary HOME. gh, ssh, ssh-keygen, and
# ssh-add are stubs, so nothing reaches GitHub: gh keeps accounts, tokens,
# emails, and registered keys in files; ssh answers "Hi LOGIN!" for the first
# offered key an account has registered, and serves fetches and pushes from
# local bare repositories; ssh-keygen makes real unencrypted keys, so commits
# really sign.
# Quoted ~/ paths are the literal values git profile writes.
# shellcheck disable=SC2088
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_REPO_ROOT="$ROOT"
source "$ROOT/tests/lib/harness.sh"
trap fixture_cleanup EXIT
fixture_init
REAL_SSH="$(command -v ssh)"
REAL_SSH_KEYGEN="$(command -v ssh-keygen)"
# The default layout, so profile paths are written ~/-relative.
export XDG_CONFIG_HOME="$HOME/.config"
export GIT_CONFIG_NOSYSTEM=1 NO_COLOR=1 GH_STUB="$TEST_ROOT/gh" REMOTES="$TEST_ROOT/remotes"
unset GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL EMAIL \
    GH_TOKEN GITHUB_TOKEN SSH_AUTH_SOCK SSH_STUB_DEFAULT_KEY
export PATH="$TEST_ROOT/bin:$ROOT/bin:$TEST_SYSTEM_PATH"
mkdir -p "$GH_STUB/keys" "$GH_STUB/emails" "$GH_STUB/names" "$REMOTES" "$HOME/.ssh"

cat > "$TEST_ROOT/bin/gh" <<'STUB'
#!/bin/bash
# gh: accounts ("login<TAB>scopes"), the active login, display names, emails
# ("email<TAB>verified"), and keys ("title<TAB>type base64") under $GH_STUB.
set -euo pipefail
printf '%s | token=%s\n' "$*" "${GH_TOKEN:-}" >> "$GH_STUB/log"
group="$1"; shift
sub=""
case "$group" in auth|config) sub="$1"; shift ;; esac
user="" scopes="" method=GET endpoint="" title="" key="" jq=""
while (( $# )); do
    case "$1" in
        --hostname|--host) [[ "$2" == github.com ]] || { echo "gh stub: host $2" >&2; exit 2; }; shift ;;
        --user) user="$2"; shift ;;
        --scopes) scopes="$2"; shift ;;
        --json|--git-protocol) shift ;;
        --jq) jq="$2"; shift ;;
        --method) method="$2"; shift ;;
        -f) case "$2" in title=*) title="${2#title=}" ;; key=*) key="${2#key=}" ;; esac; shift ;;
        --paginate|--skip-ssh-key) ;;
        -*) echo "gh stub: unexpected flag $1" >&2; exit 2 ;;
        *) endpoint="$1" ;;
    esac
    shift
done
accounts="$GH_STUB/accounts"
touch "$accounts"
has_account() { cut -f1 "$accounts" | grep -Fxq -- "$1"; }
scopes_of() { awk -F'\t' -v l="$1" '$1 == l { print $2 }' "$accounts"; }
set_scopes() { awk -F'\t' -v OFS='\t' -v l="$1" -v s="$2" '$1 == l { $2 = s } 1' "$accounts" > "$accounts.new"; mv "$accounts.new" "$accounts"; }
add_scopes() {
    local have="$1" scope
    for scope in ${2//,/ }; do [[ ", $have, " == *", $scope, "* ]] || have+=", $scope"; done
    printf '%s\n' "$have"
}
require_scope() {
    [[ ", $(scopes_of "$1"), " == *", $2, "* ]] || { echo "gh: HTTP 403: needs the $2 scope" >&2; exit 1; }
}
case "$group $sub" in
    "config get") [[ -s "$GH_STUB/active" ]] || exit 1; cat "$GH_STUB/active" ;;
    # As --jq '.hosts[][] | [.login, (.scopes // "")] | @tsv' prints it.
    "auth status") cat "$accounts" ;;
    "auth token") has_account "$user" || exit 1; echo "token-$user" ;;
    "auth login")
        login="$(cat "$GH_STUB/login-as")"
        has_account "$login" || printf '%s\t%s\n' "$login" "repo, read:org, gist" >> "$accounts"
        set_scopes "$login" "$(add_scopes "$(scopes_of "$login")" "$scopes")"
        echo "$login" > "$GH_STUB/active"
        ;;
    "auth switch") has_account "$user" || exit 1; echo "$user" > "$GH_STUB/active" ;;
    "auth refresh")
        login="$(cat "$GH_STUB/active")"
        set_scopes "$login" "$(add_scopes "$(scopes_of "$login")" "$scopes")"
        ;;
    "api ")
        [[ "${GH_TOKEN:-}" == token-* ]] || { echo "gh stub: api without an account token" >&2; exit 4; }
        login="${GH_TOKEN#token-}"
        case "$method $endpoint" in
            "GET user")
                if [[ "$jq" == .login ]]; then echo "$login"
                else printf '%s\t%s\n' "$login" "$(cat "$GH_STUB/names/$login" 2>/dev/null || true)"; fi
                ;;
            "GET user/emails") require_scope "$login" user:email; awk -F'\t' '$2 == "true" { print $1 }' "$GH_STUB/emails/$login" ;;
            "GET user/keys") require_scope "$login" admin:public_key; cut -f2 "$GH_STUB/keys/$login.authentication" 2>/dev/null || true ;;
            "GET user/ssh_signing_keys") require_scope "$login" admin:ssh_signing_key; cut -f2 "$GH_STUB/keys/$login.signing" 2>/dev/null || true ;;
            "POST user/keys")
                require_scope "$login" admin:public_key
                printf '%s\t%s\n' "$title" "$(awk '{ print $1 " " $2 }' <<< "$key")" >> "$GH_STUB/keys/$login.authentication" ;;
            "POST user/ssh_signing_keys")
                require_scope "$login" admin:ssh_signing_key
                printf '%s\t%s\n' "$title" "$(awk '{ print $1 " " $2 }' <<< "$key")" >> "$GH_STUB/keys/$login.signing" ;;
            *) echo "gh stub: unexpected request $method $endpoint" >&2; exit 2 ;;
        esac
        ;;
    *) echo "gh stub: unexpected command $group $sub" >&2; exit 2 ;;
esac
STUB

cat > "$TEST_ROOT/bin/ssh" <<'STUB'
#!/bin/bash
# ssh: offers -i's key, then $SSH_STUB_DEFAULT_KEY (an IdentityFile from the
# SSH config, or the default key order); the first key an account registered
# authenticates as that account. A repository with a .login file next to it
# is private to that login.
printf '%s\n' "$*" >> "$GH_STUB/ssh.log"
key="" target="" command=""
while (( $# )); do
    case "$1" in
        -i) key="$2"; shift ;;
        -o) shift ;;
        -*) ;;
        *) if [[ -z "$target" ]]; then target="$1"; else command="$1"; fi ;;
    esac
    shift
done
login=""
for offered in "$key" "${SSH_STUB_DEFAULT_KEY:-}"; do
    [[ -n "$offered" ]] || continue
    [[ "$offered" == *.pub ]] || offered="$offered.pub"
    [[ -f "$offered" ]] || continue
    blob="$(awk '{ print $1 " " $2 }' "$offered")"
    for registered in "$GH_STUB"/keys/*.authentication; do
        if [[ -f "$registered" ]] && cut -f2 "$registered" | grep -Fxq -- "$blob"; then
            login="$(basename "$registered" .authentication)"
            break 2
        fi
    done
done
[[ -n "$login" ]] || { echo "$target: Permission denied (publickey)." >&2; exit 255; }
case "$command" in
    "") echo "Hi $login! You've successfully authenticated, but GitHub does not provide shell access." >&2; exit 1 ;;
    "git-upload-pack '"*|"git-receive-pack '"*)
        repo="${command#* \'}"; repo="$REMOTES/${repo%\'}"
        if [[ -f "${repo%.git}.login" && "$(cat "${repo%.git}.login")" != "$login" ]]; then
            echo "ERROR: Repository not found." >&2; exit 1
        fi
        exec "${command%% *}" "$repo"
        ;;
esac
echo "ssh stub: unexpected command $command" >&2
exit 2
STUB

# ssh-keygen: generation gets no passphrase; git's signing calls pass through.
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$GH_STUB/ssh-keygen.log"\ncase " $* " in *" -t "*) exec %s -q -N "" "$@" ;; esac\nexec %s "$@"\n' \
    "$REAL_SSH_KEYGEN" "$REAL_SSH_KEYGEN" > "$TEST_ROOT/bin/ssh-keygen"
printf '#!/bin/sh\nprintf "%%s\\n" "$*" >> "$GH_STUB/ssh-add.log"\n[ "$1" = -L ] && [ -s "$GH_STUB/agent-keys" ] && exec cat "$GH_STUB/agent-keys"\necho "The agent has no identities." >&2\nexit 1\n' \
    > "$TEST_ROOT/bin/ssh-add"
chmod +x "$TEST_ROOT/bin/gh" "$TEST_ROOT/bin/ssh" "$TEST_ROOT/bin/ssh-keygen" "$TEST_ROOT/bin/ssh-add"

# tafk7 is held and active, with gh's default scopes plus admin:public_key
# (as on a machine set up before profiles); work-login is what the browser
# picks when add logs in.
printf 'tafk7\tadmin:public_key, gist, read:org, repo\n' > "$GH_STUB/accounts"
echo tafk7 > "$GH_STUB/active"
echo work-login > "$GH_STUB/login-as"
echo 'Thomas Fixture' > "$GH_STUB/names/tafk7"
printf 'tafk7@example.com\ttrue\nold@example.com\tfalse\n' > "$GH_STUB/emails/tafk7"
printf 'dev@work.example\ttrue\ndev2@work.example\ttrue\nunverified@work.example\tfalse\n' > "$GH_STUB/emails/work-login"
# seed_remote OWNER/REPO: a bare repository with one empty commit on main.
seed_remote() {
    local remote="$REMOTES/$1.git" tree
    git init -q --bare "$remote"
    git --git-dir="$remote" symbolic-ref HEAD refs/heads/main
    tree="$(git --git-dir="$remote" mktree < /dev/null)"
    git --git-dir="$remote" update-ref refs/heads/main \
        "$(git --git-dir="$remote" -c user.name=seed -c user.email=seed@example.invalid commit-tree -m seed "$tree")"
}
seed_remote acme/app && echo work-login > "$REMOTES/acme/app.login"
seed_remote tafk7/dots

# The portable Git config as setup renders it, with its two includes.
source "$ROOT/lib/runtime.sh"
source "$ROOT/lib/config.sh"
mkdir -p "$XDG_CONFIG_HOME/dotfiles"
render_portable_gitconfig "$ROOT/configs/gitconfig" > "$XDG_CONFIG_HOME/dotfiles/gitconfig"
git config --global --add include.path "$XDG_CONFIG_HOME/dotfiles/gitconfig"
git config --global --add include.path "$HOME/.gitconfig.local"

run() { local rc=0; OUT="$("$@" 2>&1)" || rc=$?; RC=$rc; }
host="$(uname -n)"; host="${host%%.*}"
scopes="admin:public_key,admin:ssh_signing_key,user:email"

# --- Usage.
run git profile; assert_eq "$RC" 0 "bare git profile"; [[ "$OUT" == *"git profile use NAME"* ]] || fail "usage: $OUT"
run git profile bogus; assert_eq "$RC" 64 "unknown command"
run git profile add; assert_eq "$RC" 64 "add without a name"
run git profile add 'two words'; assert_eq "$RC" 64 "a name with a space"
run git profile add work --ssh-key; assert_eq "$RC" 64 "--ssh-key without a value"
mkdir -p "$TEST_ROOT/nogh"
ln -s "$(command -v dirname)" "$TEST_ROOT/nogh/dirname"
OUT="$(PATH="$TEST_ROOT/nogh" "$ROOT/bin/git-profile" add work 2>&1)" && fail "add ran without gh"
[[ "$OUT" == *"gh is required (./setup.sh --bash installs it)"* ]] || fail "missing gh: $OUT"

# --- useConfigOnly: no identity, no commit.
scratch="$TEST_ROOT/scratch"
git init -q "$scratch"
run git -C "$scratch" commit -q --allow-empty -m nobody
[[ "$RC" != 0 && "$OUT" == *"auto-detection is disabled"* ]] || fail "a commit guessed an identity: $OUT"

# --- The machine default, from an account gh already holds under the profile's
# name and a key ~/.ssh/config.local would pin: missing scopes are refreshed
# without switching (tafk7 is active), nothing is logged into, and
# ~/.gitconfig.local gets the identity and signing without an sshCommand.
"$REAL_SSH_KEYGEN" -q -t ed25519 -N '' -C tafk7 -f "$HOME/.ssh/tafk7_github"
export SSH_STUB_DEFAULT_KEY="$HOME/.ssh/tafk7_github"
run git profile add tafk7 --default --ssh-key "$HOME/.ssh/tafk7_github" < /dev/null
assert_eq "$RC" 0 "default add: $OUT"
gh_calls="$(cat "$GH_STUB/log")"
[[ "$gh_calls" == *"auth refresh --hostname github.com --scopes $scopes"* ]] || fail "missing scopes not refreshed: $gh_calls"
[[ "$gh_calls" != *"auth login"* && "$gh_calls" != *"auth switch"* ]] || fail "default add logged in or switched: $gh_calls"
assert_eq "$(cut -f1 "$GH_STUB/keys/tafk7.authentication")" "$host-tafk7" "authentication key title"
assert_eq "$(cut -f1 "$GH_STUB/keys/tafk7.signing")" "$host-tafk7-signing" "signing key title"
local_config() { git config --file "$HOME/.gitconfig.local" --get "$1" || true; }
assert_eq "$(local_config user.email)/$(local_config user.name)" "tafk7@example.com/Thomas Fixture" "default identity"
assert_eq "$(local_config user.signingkey)/$(local_config gpg.format)/$(local_config commit.gpgsign)" \
    "~/.ssh/tafk7_github.pub/ssh/true" "default signing"
assert_eq "$(local_config profile.name)/$(local_config profile.ghUser)/$(local_config profile.host)" "tafk7/tafk7/github.com" "default record"
assert_eq "$(local_config core.sshCommand)" "" "the default pinned a key"
grep -Fxq "tafk7@example.com $(cut -d' ' -f1,2 "$HOME/.ssh/tafk7_github.pub")" "$XDG_CONFIG_HOME/git/allowed_signers" \
    || fail "default key not an allowed signer"
last_ssh="$(tail -n1 "$GH_STUB/ssh.log")"
[[ "$last_ssh" == *"ControlPath=none"*"StrictHostKeyChecking=accept-new -T git@github.com" && "$last_ssh" != *"-i "* ]] \
    || fail "default transport check: $last_ssh"
[[ "$OUT" == *"SSH to github.com authenticates as tafk7"* ]] || fail "default transport result: $OUT"
git -C "$scratch" commit -q --allow-empty -m default
assert_eq "$(git -C "$scratch" log -1 --format='%an <%ae> %G?')" "Thomas Fixture <tafk7@example.com> G" "default commit identity and signature"

# A user.email set in ~/.gitconfig after its includes overrides the default.
git config --global user.email stale@example.com
run git profile add tafk7 --default < /dev/null
[[ "$OUT" == *"user.email comes from ~/.gitconfig, which overrides ~/.gitconfig.local"* ]] || fail "override not reported: $OUT"
git config --global --unset user.email

# --- A second account: gh logs in (the browser picks work-login), the active
# account is restored, the operator picks one of two verified emails, and the
# key is generated once.
: > "$GH_STUB/log"
run git profile add work <<< 2
assert_eq "$RC" 0 "work add: $OUT"
gh_calls="$(cat "$GH_STUB/log")"
[[ "$gh_calls" == *"auth login --hostname github.com --git-protocol ssh --skip-ssh-key --scopes $scopes"* ]] \
    || fail "work add did not log in: $gh_calls"
[[ "$gh_calls" == *"auth switch --hostname github.com --user tafk7"* ]] || fail "active account not restored: $gh_calls"
assert_eq "$(cat "$GH_STUB/active")" tafk7 "active gh account after add"
grep -F 'api' "$GH_STUB/log" | grep -Fv 'token=token-work-login' && fail "an API call went out as another account"
[[ "$OUT" == *"1) dev@work.example"*"2) dev2@work.example"* && "$OUT" != *unverified@* ]] || fail "email choice: $OUT"
[[ "$(cat "$GH_STUB/ssh-keygen.log")" == *"-t ed25519 -C dev2@work.example -f $HOME/.ssh/id_ed25519_work"* ]] \
    || fail "work key not generated: $(cat "$GH_STUB/ssh-keygen.log")"
work_file="$XDG_CONFIG_HOME/git/profiles/work.gitconfig"
work_config() { git config --file "$work_file" --get "$1" || true; }
assert_eq "$(work_config user.email)/$(work_config user.signingkey)" "dev2@work.example/~/.ssh/id_ed25519_work.pub" "work identity"
assert_eq "$(work_config core.sshCommand)" \
    "ssh -i ~/.ssh/id_ed25519_work -o IdentitiesOnly=yes -o ControlMaster=no -o ControlPath=none" "work sshCommand"
assert_eq "$(work_config profile.ghUser)/$(work_config user.name)" "work-login/" "work record"
assert_eq "$(cut -f1 "$GH_STUB/keys/work-login.authentication" "$GH_STUB/keys/work-login.signing" | paste -sd ' ')" \
    "$host-work $host-work-signing" "work key titles"
[[ "$(tail -n1 "$GH_STUB/ssh.log")" == "-i $HOME/.ssh/id_ed25519_work -o IdentitiesOnly=yes -o ControlMaster=no -o ControlPath=none "* ]] \
    || fail "work transport check: $(tail -n1 "$GH_STUB/ssh.log")"
[[ "$OUT" == *"SSH to github.com authenticates as work-login"* && "$OUT" == *"Configure SSO"* ]] || fail "work add result: $OUT"

# A rerun asks nothing and changes nothing; an unverified email is refused.
before="$(sha256sum "$work_file" "$XDG_CONFIG_HOME/git/allowed_signers")"
: > "$GH_STUB/log"; : > "$GH_STUB/ssh-keygen.log"
run git profile add work < /dev/null
assert_eq "$RC" 0 "work rerun: $OUT"
grep -Eq 'auth (login|switch|refresh)|POST' "$GH_STUB/log" && fail "rerun changed gh: $(cat "$GH_STUB/log")"
[[ ! -s "$GH_STUB/ssh-keygen.log" ]] || fail "rerun generated a key"
assert_eq "$(sha256sum "$work_file" "$XDG_CONFIG_HOME/git/allowed_signers")" "$before" "rerun rewrote the profile"
run git profile add work --email unverified@work.example < /dev/null
[[ "$RC" == 1 && "$OUT" == *"unverified@work.example is not a verified email of work-login"* ]] || fail "unverified email: $OUT"

# The default identity now resolves to another account's key first: refused.
SSH_STUB_DEFAULT_KEY="$HOME/.ssh/id_ed25519_work" run git profile add tafk7 --default < /dev/null
[[ "$RC" == 1 && "$OUT" == *"authenticates as work-login, not tafk7: ssh offers another key first"* ]] \
    || fail "default key order mismatch: $OUT"

# --- A key the SSH agent holds, for an account gh holds (--user): only its
# public half is written, and the profile pins it by that file.
mkdir -p "$TEST_ROOT/vault"
for k in one two; do "$REAL_SSH_KEYGEN" -q -t ed25519 -N '' -C "vault-$k" -f "$TEST_ROOT/vault/$k"; done
cat "$TEST_ROOT/vault/one.pub" "$TEST_ROOT/vault/two.pub" > "$GH_STUB/agent-keys"
: > "$GH_STUB/log"
run git profile add bw --user tafk7 --ssh-key agent <<< 2
assert_eq "$RC" 0 "agent add: $OUT"
cmp -s "$HOME/.ssh/id_agent_bw.pub" "$TEST_ROOT/vault/two.pub" || fail "the chosen agent key was not written"
assert_eq "$(git config --file "$XDG_CONFIG_HOME/git/profiles/bw.gitconfig" core.sshCommand)" \
    "ssh -i ~/.ssh/id_agent_bw.pub -o IdentitiesOnly=yes -o ControlMaster=no -o ControlPath=none" "agent sshCommand"
grep -Eq 'auth (login|switch|refresh)' "$GH_STUB/log" && fail "agent add touched gh's accounts: $(cat "$GH_STUB/log")"
[[ "$OUT" == *"SSH to github.com authenticates as tafk7"* ]] || fail "agent transport: $OUT"
: > "$GH_STUB/ssh-add.log"
run git profile add bw < /dev/null
assert_eq "$RC" 0 "agent rerun: $OUT"
[[ ! -s "$GH_STUB/ssh-add.log" ]] || fail "agent rerun asked the agent again"

# --- use: one profile include per repository, ~/-relative; --default drops it.
run git -C "$TEST_ROOT" profile use work
[[ "$RC" == 1 && "$OUT" == *"not in a Git repository"* ]] || fail "use outside a repository: $OUT"
cd "$scratch"
git profile use work >/dev/null
git profile use work >/dev/null
assert_eq "$(git config --local --get-all include.path)" "~/.config/git/profiles/work.gitconfig" "work include"
assert_eq "$(git config --show-origin --get user.email)" "file:$work_file"$'\t'"dev2@work.example" "effective work email"
git profile use bw >/dev/null
assert_eq "$(git config --local --get-all include.path)" "~/.config/git/profiles/bw.gitconfig" "use replaced the profile"
git profile use --default >/dev/null
assert_eq "$(git config --local --get-all include.path || true)" "" "use --default"
assert_eq "$(git config --get user.email)" "tafk7@example.com" "default email after use --default"
run git profile use nope; [[ "$RC" == 1 && "$OUT" == *"no profile 'nope'"* ]] || fail "unknown profile: $OUT"
run git profile use tafk7; [[ "$RC" == 1 && "$OUT" == *"'tafk7' is the default identity"* ]] || fail "default by name: $OUT"
git profile use work >/dev/null

# --- whoami and list say which identity is in effect, and from where.
run git profile whoami
[[ "$OUT" == *"user.email       dev2@work.example  (~/.config/git/profiles/work.gitconfig)"* \
   && "$OUT" == *"user.name        Thomas Fixture  (~/.gitconfig.local)"* \
   && "$OUT" == *"core.sshCommand  ssh -i ~/.ssh/id_ed25519_work"* \
   && "$OUT" == *"gh account       tafk7  (active on github.com)"* \
   && "$OUT" == *"gh commands here act as tafk7, not work-login"* ]] || fail "whoami in a work repository: $OUT"
run git profile list
grep -Eq '^\* work +dev2@work\.example +work-login +github\.com$' <<< "$OUT" || fail "list in a work repository: $OUT"
grep -Eq '^  tafk7 +tafk7@example\.com +tafk7 +github\.com +\(default\)$' <<< "$OUT" || fail "list's default: $OUT"
cd "$TEST_ROOT"
run git profile whoami
[[ "$OUT" == "Outside a repository"* && "$OUT" == *"user.email       tafk7@example.com  (~/.gitconfig.local)"* ]] \
    || fail "whoami outside a repository: $OUT"
grep -Eq '^\* tafk7 ' <<< "$(git profile list)" || fail "list outside a repository"

# --- gcl -p clones with the profile's key from the first fetch, and the clone
# keeps the profile: its commits sign as the profile, its pushes use the key.
# Plain gcl keeps the default key, which this private repository refuses.
for test_shell in bash zsh; do
    # An alias from before gcl became a function must not break re-sourcing.
    "$test_shell" -c '
        [[ -z "${BASH_VERSION:-}" ]] || shopt -s expand_aliases
        alias gcl="git clone"
        source "$DOTFILES_DIR/shell/tools/git.sh"
        cd "$1"
        gcl -p work git@github.com:acme/app.git "app-$2" >/dev/null 2>&1 || exit 1
        gcl -p nope git@github.com:acme/app.git nope >/dev/null 2>&1 && exit 2
        gcl -p >/dev/null 2>&1 && exit 3
        gcl git@github.com:acme/app.git plain >/dev/null 2>&1 && exit 4
        gcl git@github.com:tafk7/dots.git "dots-$2" >/dev/null 2>&1 || exit 5
        exit 0
    ' _ "$TEST_ROOT" "$test_shell" || fail "$test_shell gcl (exit $?)"
done
[[ ! -e "$TEST_ROOT/nope" && ! -e "$TEST_ROOT/plain" ]] || fail "a refused clone left a directory"
app="$TEST_ROOT/app-bash"
grep -F "git-upload-pack 'acme/app.git'" "$GH_STUB/ssh.log" | grep -Fq -- "-i $HOME/.ssh/id_ed25519_work -o IdentitiesOnly=yes -o ControlMaster=no -o ControlPath=none" \
    || fail "gcl -p did not fetch with the profile's key: $(cat "$GH_STUB/ssh.log")"
grep -F "git-upload-pack 'tafk7/dots.git'" "$GH_STUB/ssh.log" | grep -Fq -- "-i " && fail "plain gcl pinned a key"
assert_eq "$(git -C "$app" config --local --get-all include.path)" "~/.config/git/profiles/work.gitconfig" "clone's include"
assert_eq "$(git -C "$app" config --local --no-includes --get core.sshCommand || true)" "" "clone kept a bare sshCommand"
git -C "$app" commit -q --allow-empty -m "work change"
assert_eq "$(git -C "$app" log -1 --format='%an <%ae> %G?')" "Thomas Fixture <dev2@work.example> G" "work commit identity and signature"
git -C "$app" push -q origin HEAD:main 2>/dev/null || fail "push with the profile's key"
grep -F "git-receive-pack 'acme/app.git'" "$GH_STUB/ssh.log" | grep -Fq -- "-i $HOME/.ssh/id_ed25519_work" \
    || fail "push did not use the profile's key"
assert_eq "$(git -C "$TEST_ROOT/dots-zsh" config --get user.email)" "tafk7@example.com" "plain clone's identity"

# --- remove: local only; the keys to revoke are named, the key files stay,
# and a repository that included it falls back to the default identity.
run git profile remove work
assert_eq "$RC" 0 "remove: $OUT"
[[ ! -e "$work_file" && -f "$HOME/.ssh/id_ed25519_work" ]] || fail "remove deleted the wrong things"
[[ "$OUT" == *"Revoke its keys on work-login: https://github.com/settings/keys"* \
   && "$OUT" == *"$host-work "*"$host-work-signing"* ]] || fail "remove's revocation list: $OUT"
grep -Fq dev2@work.example "$XDG_CONFIG_HOME/git/allowed_signers" && fail "removed key is still an allowed signer"
grep -Fq tafk7@example.com "$XDG_CONFIG_HOME/git/allowed_signers" || fail "remove dropped another allowed signer"
assert_eq "$(git -C "$app" config --get user.email)" "tafk7@example.com" "fallback after remove"
[[ "$(git profile list)" != *work* ]] || fail "list after remove"

# --- Multiplexing never spans git hosts; other hosts keep it.
sed "s|~/.ssh|$HOME/.ssh|g" "$ROOT/configs/ssh_config" > "$TEST_ROOT/ssh_config"
github="$("$REAL_SSH" -G -F "$TEST_ROOT/ssh_config" github.com 2>/dev/null)"
other="$("$REAL_SSH" -G -F "$TEST_ROOT/ssh_config" example.com 2>/dev/null)"
[[ "$github" == *$'\ncontrolmaster false\n'* && "$github" != *$'\ncontrolpath '* ]] || fail "github.com multiplexes"
[[ "$other" == *$'\ncontrolmaster auto\n'* && "$other" == *$'\ncontrolpath '* ]] || fail "other hosts lost multiplexing"

printf 'git-profile: ok\n'
