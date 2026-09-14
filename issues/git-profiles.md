# Spec: git profiles — per-repo identity, auth, and signing

**Status:** proposed — not implemented.
**Problem:** setup couples git identity to the install track (flags, a warning,
and historically a prompt on every run), supports only one global identity, and
the one multi-account helper (`gcl-amd`) handles clone auth but not commit
identity or signing. Work machines routinely need a second account.
**Goal:** a machine has one default identity (`tafk7`), and specific repos opt
into another profile (e.g. `amd`) with one command — covering clone, push,
commit email, and signing — without anything employer-specific in tracked files.

---

## 1. Mental model: what a "git identity" is

A full identity is seven independent pieces. They are checked at different times
by different parties, which is why fixing one (e.g. an SSH alias) does not fix
another (e.g. signing).

| # | Component | Answers | Lives in |
|---|---|---|---|
| 1 | Commit identity (`user.name`, `user.email`) | Who the commit *claims* wrote it | git config |
| 2 | Transport auth (SSH key, or HTTPS credential) | May this machine clone/push | `~/.ssh`, credential helper |
| 3 | Signing (`user.signingkey`, `gpg.format`, `commit.gpgsign`) | Proof the claim in (1) is genuine | git config + key |
| 4 | API/CLI auth (gh token) | Who I am for PRs, issues, API | `~/.config/gh/hosts.yml` |
| 5 | Server-side registration | Host links 2–3 to an account | GitHub/GHE account settings |
| 6 | Routing | Which set of 1–4 applies to this repo | repo `.git/config`, `includeIf`, gh active account |
| 7 | Key custody | Where private keys live | Bitwarden agent (personal WSL) or local `~/.ssh` (work) |

### When each is used

| Operation | Uses | Checked by server |
|---|---|---|
| `git clone` / `fetch` | SSH key → account | Read access |
| `git commit` | `user.email`, signing key | **Never** — fully local, no network |
| `git push` | SSH key → account | Write access; optional rules on commit email/signature |
| GitHub web view | Commit email + signature | Attributes commit by verified email; "Verified" if signature matches that account's signing key |

Facts the design depends on:

- **The SSH key alone selects the account.** Every GitHub SSH login is user
  `git`; a public key is registered to exactly one account, so the offered key
  determines who you are. Commit identity plays no part in clone or push.
- **The first recognized key wins.** SSH offers keys in order and stops at the
  first one GitHub accepts. GitHub authenticates first and authorizes second, so
  a registered `tafk7` key authenticates as `tafk7` and then fails with
  "repository not found" (private) or "permission denied" (public push). Letting
  the agent "try keys until it hits amd" does not work; the key must be pinned.
- **Pusher and author are unrelated.** A push checks only the pusher's write
  access. Commits carry whatever email was configured at commit time. Errors
  surface late: at a push rule (required signatures, author-email rulesets,
  email-privacy blocks) or as unverified/misattributed commits in the UI.
- **Commit identity is not signing identity.** The email is unverified text;
  the signature proves it. GitHub shows "Verified" only when the signing key is
  registered *as a signing key* on an account whose verified emails include the
  commit's email.
- **Public repos:** cloning as the wrong account is harmless (reads are open).
  Pushing is not: push re-authenticates with whichever key is offered first.

---

## 2. Design

### 2.1 Machine default (`tafk7`)

Plain `git clone` and `gcl` behave as today and authenticate with the default
key first. The default identity lives directly in the untracked
`~/.gitconfig.local`: email plus SSH signing with the default key. There is no
`core.sshCommand`, so normal SSH key order applies.

- Personal WSL: key custody is Bitwarden via `ssh-bridge`; `user.signingkey`
  points at an exported `.pub` of the Bitwarden key.
- Native Linux / work: a local `~/.ssh/id_ed25519`.

### 2.2 Profiles

A profile is a small, untracked git config file:

```ini
# ~/.config/git/profiles/amd.gitconfig
[user]
    email = you@amd.com
    signingkey = ~/.ssh/id_ed25519_amd.pub
[gpg]
    format = ssh
[commit]
    gpgsign = true
[core]
    sshCommand = ssh -i ~/.ssh/id_ed25519_amd -o IdentitiesOnly=yes -o ControlMaster=no -o ControlPath=none
[profile]
    ghUser = amd-login
    host = github.com
```

- **`core.sshCommand` pins the key per repo.** The remote stays a normal
  `git@github.com:` URL. This replaces the `github.com-amd` SSH alias: no
  `~/.ssh/config.local` alias block, no URL rewriting, and no
  `gh repo set-default` step, since gh recognizes a normal remote.
- **`ControlMaster=no ControlPath=none` is required.** `configs/ssh_config`
  multiplexes all hosts (`ControlPath ~/.ssh/sockets/%C`, `ControlPersist 600`),
  and `%C` is derived from host/port/user, not the key. Without this, a
  connection opened as `tafk7` within 10 minutes would be silently reused.
- **The `[profile]` section is ours, not git's.** Git accepts arbitrary sections
  and ignores these keys, so one file is both the declaration and the include
  target. Git has no native "profile" concept; everything else here is stock
  git (`include.path`, `includeIf`, `core.sshCommand`, `user.useConfigOnly`).
- **Private, not secret.** Profiles hold emails, logins, and key paths; private
  keys stay in `~/.ssh` or Bitwarden, and tokens stay in gh. Profiles are never
  stored centrally. `git profile add` regenerates one in about a minute per
  machine, which also keeps work identity out of personal repositories.

### 2.3 Applying a profile to a repo

A repo opts in with one line in its local config, which links the profile rather
than copying it:

```ini
# <repo>/.git/config
[include]
    path = ~/.config/git/profiles/amd.gitconfig
```

Editing the profile updates every repo using it. `includeIf` rules
(`gitdir:` / `hasconfig:remote.*.url:`) remain available as optional automation
but are not the primary mechanism: per-repo choice is explicit and does not
depend on directory layout or URL shape.

---

## 3. Commands

### 3.1 `bin/git-profile`

Named `git-profile` so git exposes it as `git profile`. A `bin/` script, not
env vars in `~/.shell.local`: git, SSH, and IDEs never read shell variables, so
state must live in config files. Registration is a multi-step action that needs
error handling and tests, and `bin/cheatsheet commands` lists `bin/` scripts
automatically.

```
git profile add NAME [--default] [--ssh-key PATH|agent] [--hostname HOST]
git profile use NAME            # in a repo: add the include
git profile use --default       # in a repo: remove it
git profile whoami              # effective email / signing key / ssh command + origin file
git profile list
git profile remove NAME         # local only; prints GitHub key titles to revoke
```

`whoami` wraps `git config --show-origin --includes` for `user.email`,
`user.signingkey`, and `core.sshCommand`.

### 3.2 `gcl -p PROFILE URL [DIR]`

`gcl` changes from an alias to a function in `shell/tools/git.sh`. Without `-p`
it is exactly `git clone "$@"`; `git clone` has no `-p` flag, so there is no
collision.

```bash
gcl() {
    if [[ "${1:-}" != -p ]]; then
        git clone "$@"; return
    fi
    local profile="${2:?usage: gcl -p PROFILE URL [DIR]}" url="${3:?usage: gcl -p PROFILE URL [DIR]}"
    local dir="${4:-$(basename "${url%/}" .git)}"
    local ssh_cmd
    ssh_cmd="$(git config --file "$HOME/.config/git/profiles/$profile.gitconfig" core.sshCommand)" \
        || { echo "gcl: unknown profile '$profile'" >&2; return 1; }

    git clone -c core.sshCommand="$ssh_cmd" "$url" "$dir" || return
    git -C "$dir" config --local --unset core.sshCommand
    git -C "$dir" profile use "$profile" \
        || { echo "gcl: cloned, but applying profile '$profile' failed" >&2; return 1; }
}
```

- `git clone -c` writes config before the remote history is fetched, so a
  private amd repo clones with the amd key.
- The explicit `core.sshCommand` is passed instead of `-c include.path=…`
  because it is not verified that clone's transport honors an include added
  that way. The temporary value is removed once `use` adds the include.
- Clone failure and profile failure are reported separately.
- Passing extra clone flags (`--depth`, `-b`) in `-p` mode is a follow-up.

---

## 4. First-time setup: `git profile add NAME`

Each step checks before acting, so reruns repair a partial setup.

0. **Prerequisite:** gh (installed by `./setup.sh --bash`). `NAME` is a local
   label and does not need to match anything on GitHub.
1. **Authenticate the account with gh** (skipped if already present):
   ```bash
   gh auth login --hostname github.com --git-protocol ssh --skip-ssh-key \
     --scopes admin:public_key,admin:ssh_signing_key,user:email
   ```
   Login makes this account active; restore the previous one afterwards
   (`gh auth switch --user <previous>`).
2. **Identify the account without switching:**
   `GH_TOKEN="$(gh auth token --user LOGIN)"`, then `gh api user --jq .login`,
   and offer a choice from
   `gh api user/emails --jq '.[] | select(.verified) | .email'`. Nothing typed
   by hand is stored.
3. **Key:**
   - Local (default): `ssh-keygen -t ed25519 -C EMAIL -f ~/.ssh/id_ed25519_NAME`
     (with a passphrase; `AddKeysToAgent yes` is already in `configs/ssh_config`).
   - `--ssh-key agent`: select a key from `ssh-add -L` (Bitwarden) and write
     only its `.pub`.
   - One key per machine per profile, so each `<hostname>-NAME` entry on GitHub
     can be revoked independently.
4. **Register the key twice** (separate entries on GitHub), skipping any already
   listed by `gh ssh-key list`:
   ```bash
   gh ssh-key add KEY.pub --title "$(hostname)-NAME"
   gh ssh-key add KEY.pub --title "$(hostname)-NAME-signing" --type signing
   ```
5. **SSO authorization, if the org enforces SAML:** manual. GitHub → Settings →
   SSH keys → Configure SSO → Authorize. There is no API or gh command; print the
   link and wait for confirmation.
6. **Write the profile file** (§2.2) with `git config --file`. With `--default`,
   write email and signing settings into `~/.gitconfig.local` instead, with no
   `core.sshCommand`.
7. **Verify transport:** this should print `Hi LOGIN!` and records the host key
   on first connect.
   ```bash
   ssh -i KEY -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new -T git@HOST
   ```
8. **Optional local signature verification:** append `EMAIL KEY.pub` to
   `~/.config/git/allowed_signers` and set `gpg.ssh.allowedSignersFile`.

GHE on another hostname: `--hostname` flows into steps 1, 4, and 7 and is stored
as `profile.host`.

---

## 5. Touch points

1. **`bin/git-profile`** — new (§3.1, §4). Sources `lib/runtime.sh`, uses the
   repo's usage/`log`/`error` conventions.
2. **`shell/tools/git.sh`** — `gcl` alias → function (§3.2). `gcl-amd` removed,
   or reduced to `gcl -p amd "$@"` during transition.
3. **`shell/shortcuts-index.tsv`** — replace the `gcl-amd` row; document
   `gcl -p`.
4. **`configs/ssh_config`** — disable multiplexing for git hosts, which also
   protects plain `git` and `ssh` usage:
   ```
   Host github.com ssh.dev.azure.com gitlab.com
       ControlMaster no
   ```
   Keep `ControlMaster=no` in profile `sshCommand` too, for GHE hosts not listed
   here.
5. **`configs/gitconfig`** — add `user.useConfigOnly = true`, so a repo with no
   resolvable identity refuses to commit instead of guessing from
   username@hostname.
6. **`lib/install.sh` `process_git_config`** — remove the
   `DOTFILES_GIT_NAME`/`DOTFILES_GIT_EMAIL` writes and the identity warning.
   Setup keeps rendering the portable config and adding both includes; delta,
   the theme include, and Azure credential integration depend on these, and
   `bin/verify:256` fails without the Azure include.
7. **`setup.sh`** — remove `--git-name` / `--git-email` and the env vars from
   parsing and help. Fix stale comments claiming an interactive identity prompt
   exists (`setup.sh:65` and the `--no-git` help text); the current code never
   prompts.
8. **`bin/verify`** — keep the git-user check as warn-only, pointing at
   `git profile add NAME --default`.
9. **`docs/customization.md`** — replace the `gcl-amd` / `GH_AMD_USER` section
   and fold the signing example into a profiles section linking here.
10. **Tests** — `git-profile use`/`whoami`/`list` against a temp `HOME`, with
    gh and ssh stubbed; `gcl -p` with a stubbed `git clone`; profile parsing;
    `setup.sh` argument tests updated for removed flags.

---

## 6. Limits and non-goals

- **gh after clone uses the active account.** Profiles pin git transport and
  identity, not gh's account for later `gh pr` / `gh issue` in that repo.
- **Azure DevOps key upload is manual.** gh cannot register keys there; `add`
  prints the public key and settings URL. HTTPS remotes continue to use
  `git-credential-azdo`.
- **SSO authorization is manual** (§4 step 5).
- **No central profile storage.** Regenerate per machine. A private companion
  repo or Bitwarden-rendered profiles are possible later, but not warranted for
  about three values per profile.
- **Setup never runs `git profile add`.** Identity stays off the install track
  permanently.

## 7. Open questions

1. **Naming:** `git-profile` (exposed as `git profile`) vs `setup-git`.
2. **Per-repo gh account:** direnv (already in the bash tier) could export
   `GH_TOKEN="$(gh auth token --user LOGIN)"` from an untracked `.envrc` listed
   in `.git/info/exclude`. Worth it, or leave gh global?
3. **Transition for `gcl-amd`:** keep a wrapper for a release, or remove it
   outright?
4. **`user.useConfigOnly` on fresh machines:** commits fail until
   `git profile add NAME --default` runs. Intended, but should setup's final
   summary say so?
5. **Unverified assumptions to check during implementation:** whether
   `git clone -c include.path=…` is honored by clone's own fetch (§3.2 avoids
   depending on it), and that `%C` collides for aliased and unaliased
   `github.com` connections (§2.2 disables multiplexing regardless).
