# Spec: git profiles — per-repo identity, auth, and signing

**Status:** implemented; on `main` since 2026-10-28. Not yet adopted on any
machine (§9.3). Where the implementation departs from the
proposal, the sections below describe what was built, and §8 lists each
deviation and why.
**Problem:** setup couples git identity to the install track (flags, a warning,
and historically a prompt on every run), supports only one global identity, and
the one multi-account helper (a machine-local clone function in
`~/.shell.local`) handles clone auth but not commit
identity or signing. Work machines routinely need a second account.
**Goal:** a machine has one default identity (`tafk7`), and specific repos opt
into another profile (e.g. `work`) with one command — covering clone, push,
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
  the agent "try keys until it hits work" does not work; the key must be pinned.
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
`core.sshCommand`, so normal SSH key order applies, and the default key must be
the first one ssh offers the host: `~/.ssh/id_ed25519` (what `add --default`
generates), the agent's key, or an `IdentityFile` for the host in
`~/.ssh/config.local`.

- Personal WSL: key custody is Bitwarden via `ssh-bridge`; `user.signingkey`
  points at an exported `.pub` of the Bitwarden key (`--ssh-key agent`).
- Native Linux / work: a local `~/.ssh/id_ed25519`.

### 2.2 Profiles

A profile is a small, untracked git config file. `git profile add work` writes:

```ini
# ~/.config/git/profiles/work.gitconfig
[user]
    email = you@work.example
    signingkey = ~/.ssh/id_ed25519_work.pub
[gpg]
    format = ssh
[commit]
    gpgsign = true
[gpg "ssh"]
    allowedSignersFile = ~/.config/git/allowed_signers
[core]
    sshCommand = ssh -i ~/.ssh/id_ed25519_work -o IdentitiesOnly=yes -o ControlMaster=no -o ControlPath=none
[profile]
    name = work
    ghUser = work-login
    host = github.com
```

The directory is `${XDG_CONFIG_HOME:-~/.config}/git/profiles`. Paths under
`HOME` are written `~/`-relative; git expands `~/` in `include.path`,
`user.signingkey`, and `allowedSignersFile`, and sh expands it in
`core.sshCommand`.

- **`core.sshCommand` pins the key per repo.** The remote stays a normal
  `git@github.com:` URL. This replaces per-account SSH host aliases: no
  `~/.ssh/config.local` alias block, no URL rewriting, and no
  `gh repo set-default` step, since gh recognizes a normal remote.
- **`ControlMaster=no ControlPath=none` is required.** `configs/ssh_config`
  multiplexes all hosts (`ControlPath ~/.ssh/sockets/%C`, `ControlPersist 600`),
  and `%C` is derived from host/port/user, not the key (verified, §7.5).
  Without this, a connection opened as `tafk7` within 10 minutes would be
  silently reused.
- **The `[profile]` section is ours, not git's.** Git accepts arbitrary sections
  and ignores these keys, so one file is both the declaration and the include
  target. `add --default` writes the same section into `~/.gitconfig.local`, so
  `git config profile.ghUser` resolves to the account in effect in any
  repository. Git has no native "profile" concept; everything else here is
  stock git (`include.path`, `includeIf`, `core.sshCommand`,
  `user.useConfigOnly`).
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
    path = ~/.config/git/profiles/work.gitconfig
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
                     [--user LOGIN] [--email EMAIL]
git profile use NAME            # in a repo: add the include
git profile use --default       # in a repo: remove it
git profile clone NAME [GIT-CLONE-ARGS] URL [DIR]   # what gcl -p runs
git profile whoami              # effective identity, signing, ssh command + origin file
git profile list
git profile remove NAME         # local only; prints GitHub key titles to revoke
```

- `use` keeps one profile include per repository: it drops any other include
  of a file in the profiles directory, then adds this one. It warns when a
  setting read later (a repository `[user]` after the include) overrides the
  profile.
- `whoami` wraps `git config --show-origin --includes` for `profile.name`,
  `user.name`, `user.email`, `user.signingkey`, `gpg.format`, `commit.gpgsign`,
  `core.sshCommand`, and `profile.ghUser`. It also shows gh's active account
  (`gh config get user`, a local read) and says when it is not the profile's.
- `list` shows the default and each profile with email, login, and host, and
  stars the one in effect here.
- `git profile --help` is turned by git into `git help profile`, which looks
  for a manual page; `git profile -h` prints the usage.

### 3.2 `gcl -p PROFILE URL [DIR]`

`gcl` changes from an alias to a function in `shell/tools/git.sh`. Without `-p`
it is exactly `git clone "$@"`; `git clone` has no `-p` flag, so there is no
collision. With `-p` it runs `git profile clone`, which is one command:

```bash
gcl() {
    if [[ "${1:-}" == -p ]]; then
        shift
        git profile clone "$@"
    else
        git clone "$@"
    fi
}

# bin/git-profile, after checking that the profile exists:
exec git clone -c "include.path=~/.config/git/profiles/$name.gitconfig" "$@"
```

- `git clone -c` writes config before the remote history is fetched, and the
  fetch reads an include added that way (verified, §7.5), so a private work
  repo clones with the work key, and the clone keeps the include.
- There is no temporary `core.sshCommand` to remove and no second step that can
  fail after the clone succeeded, so the clone's own exit status is the result.
  A refused clone leaves no directory.
- Extra clone flags (`--depth`, `-b`) pass through to `git clone`.
- `shell/tools/git.sh` runs `unalias gcl` first: a shell that still has the old
  alias would expand it inside the function definition.

---

## 4. First-time setup: `git profile add NAME`

Each step checks before acting, so reruns repair a partial setup. A rerun
starts from what the profile records (host, login, email, key), so
`git profile add work` asks nothing the second time.

0. **Prerequisites:** gh (installed by `./setup.sh --bash`), ssh, and
   ssh-keygen. `NAME` is a local label and does not need to match anything on
   GitHub. Tokens in the environment (`GH_TOKEN` and the like) are unset, so gh
   acts only through accounts it stores.
1. **The account in gh.** An account gh already holds is used without a new
   login: `--user LOGIN`, the login the profile records, or else an account
   whose login equals `NAME`. Its token needs `admin:public_key`,
   `admin:ssh_signing_key`, and `user:email`; when `gh auth status` reports
   fewer, `gh auth refresh --scopes …` adds them (switching to the account
   first, and back afterwards, when it is not the active one). Otherwise:
   ```bash
   gh auth login --hostname github.com --git-protocol ssh --skip-ssh-key \
     --scopes admin:public_key,admin:ssh_signing_key,user:email
   ```
   Login makes the new account active; the previous one is restored
   (`gh auth switch --user <previous>`).
2. **Identify the account without switching:** every API call runs as
   `GH_TOKEN="$(gh auth token --user LOGIN)" gh api --hostname HOST …`.
   `gh api user` must return `LOGIN`; its display name is kept for step 6. The
   email is one of `gh api user/emails --jq '.[] | select(.verified) | .email'`:
   `--email` if verified, else the recorded one while still verified, else the
   only one, else a numbered choice on stdin. Nothing typed by hand is stored.
3. **Key:**
   - Local (default): `ssh-keygen -t ed25519 -C EMAIL -f ~/.ssh/id_ed25519_NAME`
     (with a passphrase; `AddKeysToAgent yes` is already in `configs/ssh_config`).
     With `--default` the file is `~/.ssh/id_ed25519`, which ssh offers
     unasked. An existing key is reused.
   - `--ssh-key agent`: select a key from `ssh-add -L` (Bitwarden) and write
     only its public half, to `~/.ssh/id_agent_NAME.pub`. The profile pins it
     by that file (`ssh -i KEY.pub -o IdentitiesOnly=yes` offers only the agent
     key that matches).
   - `--ssh-key PATH`: an existing key, private or `.pub`.
   - One key per machine per profile, so each `<hostname>-NAME` entry on GitHub
     can be revoked independently (`<hostname>` is `uname -n` up to its first
     dot).
4. **Register the key twice** (separate entries on GitHub), skipping a list that
   already has it under any title:
   ```bash
   gh api --method POST user/keys -f title="<hostname>-NAME" -f key="$(cat KEY.pub)"
   gh api --method POST user/ssh_signing_keys -f title="<hostname>-NAME-signing" -f key="$(cat KEY.pub)"
   ```
5. **SSO authorization, if the org enforces SAML:** manual. GitHub → Settings →
   SSH keys → Configure SSO → Authorize. There is no API or gh command. When
   step 4 registered a key, `add` prints the link and, on a terminal, waits for
   Enter.
6. **Write the profile file** (§2.2) with `git config --file`, changing only
   values that differ. With `--default`, write email and signing settings into
   `~/.gitconfig.local` instead, with no `core.sshCommand`, plus `user.name`
   (the account's display name, else its login) when no global name resolves:
   `user.useConfigOnly` refuses commits without one, and setup no longer sets
   it. It warns when `~/.gitconfig` does not include `~/.gitconfig.local`, or
   when a value set in `~/.gitconfig` after its includes overrides the one
   written.
7. **Local signature verification:** add `EMAIL KEYTYPE KEY` to
   `~/.config/git/allowed_signers` (replacing a line for the same key) and set
   `gpg.ssh.allowedSignersFile`, so `git log --show-signature` reports "Good".
8. **Verify transport:** SSH to the host the way git will for this identity —
   the profile's `core.sshCommand`, or plain `ssh` for the default — with
   `-o StrictHostKeyChecking=accept-new -T git@HOST`, which records the host
   key on first connect. The reply must be `Hi LOGIN!` for this account; any
   other login fails the command (exit 1) with the reason: a refused profile
   key lets ssh fall back to an `IdentityFile` from `~/.ssh/config.local`, and
   for the default, ssh offering another key first. Everything else is already
   written, so fixing the cause and rerunning finishes.

GHE on another hostname: `--hostname` flows into steps 1, 2, 4, and 8 and is
stored as `profile.host`.

---

## 5. Touch points

All done on the branch.

1. **`bin/git-profile`** — new (§3.1, §4). Sources `lib/runtime.sh`, uses the
   repo's usage/`log`/`error` conventions; line 2 is its `cheat commands`
   description.
2. **`shell/tools/git.sh`** — `gcl` alias → function (§3.2). A machine-local
   clone helper in `~/.shell.local` can be deleted once `gcl -p` is in use;
   tracked files never touch that file.
3. **`shell/shortcuts-index.tsv`** — documents `gcl -p` and `git profile`.
4. **`configs/ssh_config`** — disables multiplexing for git hosts, which also
   protects plain `git` and `ssh` usage. Placed before `Host *`, since ssh
   takes the first value it reads:
   ```
   Host github.com ssh.dev.azure.com gitlab.com
       ControlMaster no
       ControlPath none
   ```
   Profile `sshCommand` keeps both options too, for GHE hosts not listed here.
5. **`configs/gitconfig`** — `user.useConfigOnly = true`, so a repo with no
   resolvable identity refuses to commit instead of guessing from
   username@hostname.
6. **`lib/install.sh` `process_git_config`** — the
   `DOTFILES_GIT_NAME`/`DOTFILES_GIT_EMAIL` writes and the identity warning are
   gone. Setup keeps rendering the portable config and its include; delta and
   the theme include depend on it.
7. **`setup.sh`** — `--git-name` / `--git-email` and the env vars are gone from
   parsing and help, and the stale comments about an identity prompt are fixed.
   The retired flags fail (exit 64) with a pointer to
   `git profile add NAME --default` instead of "Unknown option". While no
   global identity resolves (and `--no-git` is not given), the Next Steps say
   how to set one.
8. **`bin/verify`** — the git-user check stays warn-only and points at
   `git profile add NAME --default`.
9. **Docs** — `docs/customization.md` has a Git profiles section in place of the
   clone-helper note and the signing example; `README.md` (after setup),
   `docs/architecture.md`, and `docs/work.md` point at it.
10. **Tests** — `tests/git-profile.sh` (§9.1); the setup tests drop the removed
    flags; `tests/argument-parsing.sh` covers the retired flags,
    `tests/verify-profiles.sh` the warning and an identity in
    `~/.gitconfig.local`, and the setup-selection snapshot the help and Next
    Steps. CI's installer runs drop the flags.

---

## 6. Limits and non-goals

- **gh after clone uses the active account.** Profiles pin git transport and
  identity, not gh's account for later `gh pr` / `gh issue` in that repo.
  `whoami` says when the two differ.
- **A refused profile key falls back.** ssh offers `-i`'s key first and then
  any `IdentityFile` the SSH config names for the host (verified, §7.5). If
  GitHub refuses the profile's key (deleted from the account, or a passphrase
  that cannot be asked for), a pinned default key in `~/.ssh/config.local`
  authenticates as the default account, and the work repo reports "repository
  not found". `add` catches this when it runs (step 8); later, `ssh -T` with
  the profile's command shows who answers.
- **Submodules are not covered.** A repository's include does not reach the
  fetch of a submodule clone: `gcl -p … --recurse-submodules` fetches
  submodules with the default key (verified). A command-line include does:
  `git -c include.path=~/.config/git/profiles/work.gitconfig submodule update
  --init`, then `git -C SUB profile use work` for later fetches.
- **A profile include can dangle.** `remove` cannot know which repositories
  include the profile; git ignores a missing include file, so those
  repositories fall back to the default identity without a message. `remove`
  says so.
- **Only gh hosts.** `add` registers keys through gh, so it needs github.com or
  a GHE host gh can log in to. Azure DevOps key upload is manual: create the
  key, upload it in the Azure DevOps user settings, and write the profile with
  `git config --file` (§2.2); `use` and `clone` work with any profile file.
  HTTPS remotes can use the parked `git-credential-azdo` snippet
  (`docs/work.md`).
- **SSO authorization is manual** (§4 step 5).
- **No central profile storage.** Regenerate per machine. A private companion
  repo or Bitwarden-rendered profiles are possible later, but not warranted for
  about three values per profile.
- **Setup never runs `git profile add`.** Identity stays off the install track
  permanently.

## 7. Decisions (formerly open questions)

1. **Naming:** `git-profile`, exposed as `git profile`.
2. **Per-repo gh account:** gh stays global. Follow-up, not built: direnv
   (already in the bash tier) could export the account's token from an
   untracked `.envrc` listed in `.git/info/exclude`. Since `profile.ghUser`
   resolves per repository (§2.2), the line is the same in every repo:
   `export GH_TOKEN="$(gh auth token --user "$(git config profile.ghUser)")"`.
3. **Transition for the clone helper:** it stays in `~/.shell.local`, which
   nothing tracked edits; delete it there once `gcl -p` is in use.
4. **`user.useConfigOnly` on fresh machines:** set. Commits fail until
   `git profile add NAME --default` runs (or `user.name` and `user.email` are
   set in `~/.gitconfig.local`); setup's Next Steps say so while no global
   identity resolves, and `dotfiles verify` warns. Checked against what could
   break:
   - Setup itself never commits. `bootstrap.sh` and `dotfiles update` pull with
     `--ff-only`, and reflog entries do not need an identity (useConfigOnly
     only applies where git requires one, verified with `git checkout -b`).
   - CI runs setup and then `bin/verify --tier bash`; the missing identity is a
     warning, which does not change verify's exit status.
   - Tests: every commit made under a setup-rendered config exports
     `GIT_AUTHOR_*`/`GIT_COMMITTER_*` (`dotfiles-update.sh`, `update-e2e.sh`,
     `editor-plugins.sh`), passes `-c user.*` (`install-ai.sh`), or sets a
     repository identity (`git-hooks.sh`). An identity from the environment or
     `-c` satisfies useConfigOnly (verified).
5. **The unverified assumptions, checked** with git 2.43.0 and OpenSSH 9.6p1,
   offline: a stub `ssh` on `PATH` that logs its argv and exits non-zero, a
   temporary `HOME`, and the fake URL `git@github.com:x/y.git`.

   | Check | Result |
   |---|---|
   | `git clone -c core.sshCommand=STUB …` | Clone's own fetch runs `STUB` |
   | `git clone -c include.path=PROFILE …` (profile sets `core.sshCommand`) | Clone's own fetch runs the profile's command, also with `include.path=~/…` |
   | `git -c include.path=PROFILE clone …` | Same; not persisted in the clone |
   | Successful clone through a stub serving `git-upload-pack` | `.git/config` keeps `[include] path = ~/…`; `user.email` resolves from the profile |
   | `ssh -G` for `github.com` and for an alias with `HostName github.com` | Same `%C` ControlPath: they collide |
   | `ssh -G -i OTHER github.com` | Same ControlPath: the key is not part of `%C` |
   | `ssh -G -i KEY -o IdentitiesOnly=yes` with an `IdentityFile` for the host in the config | Identity list is `KEY`, then the config's file |
   | `-o IdentityFile=none` | Adds a `none` entry; does not clear the config's files |
   | `ssh -v -o ControlMaster=no -o ControlPath=SOCK`, a listening socket at `SOCK` | The client contacts `SOCK` ("master hello exchange"); with `ControlPath=none` it does not. Hence `ControlPath none` |
   | `--recurse-submodules` with a profile include | The submodule's fetch uses the default command |

## 8. Deviations from the proposal

1. **`gcl -p` runs `git profile clone`, which clones with
   `-c include.path=…`.** The proposal passed a temporary `core.sshCommand`
   because it was not known whether clone's fetch honors an include added with
   `-c`; it does (§7.5). One command means nothing to undo after the clone, no
   separate "profile failed" state, clone flags pass through (the proposal's
   follow-up), the profile path lives in one place, and the logic is a tested
   `bin/` command instead of shell startup code.
2. **`--user LOGIN`, the name match, and `--email EMAIL` were added to `add`.**
   "Skipped if already present" needs the login before any login happens:
   `--user` names it, a rerun reads `profile.ghUser`, and otherwise an account
   whose login equals `NAME` is used, so `git profile add tafk7 --default`
   works on a machine where gh already holds `tafk7`. `--email` picks among the
   verified emails without a prompt and is refused if not verified.
3. **Scopes are refreshed for an account gh already holds.** The proposal only
   requested scopes at login. An account logged in before profiles lacks
   `admin:ssh_signing_key` and `user:email` (this machine's `tafk7` token has
   `admin:public_key, gist, read:org, repo`), so step 4's signing key and step
   2's email list would fail.
4. **Keys are listed and registered with `gh api` and the account's own
   token,** not `gh ssh-key list/add`, which act on the active account and
   print a table. With `GH_TOKEN` from `gh auth token --user`, no step but
   login and refresh changes gh's active account, and the listing is exact.
5. **The default identity's generated key is `~/.ssh/id_ed25519`.** It has no
   `sshCommand`, so a key ssh does not offer unasked would never be used.
6. **Allowed signers are written before the SSH check, and the check compares
   the login.** The check is last so that its failure leaves a complete
   profile; it must match the account, not merely succeed, because of the
   fallback in §6. For the default it runs plain `ssh` (as git will), with
   `ControlPath=none`.
7. **`configs/ssh_config` also sets `ControlPath none`** for the git hosts.
   `ControlMaster no` alone still joins a master opened earlier at the same
   path, such as one `Host *` opened before this change, for up to
   `ControlPersist` (600 s).
8. **`[profile]` records `name`, and `add --default` writes `[profile]` into
   `~/.gitconfig.local`,** so `whoami`, `list`, and the direnv follow-up can
   ask git which account is in effect.
9. **`add --default` writes `user.name` when none resolves,** from the
   account's display name. Profiles leave the name to the default identity.
10. **The SSO step waits only when it matters:** after a new registration, and
    only on a terminal, so reruns and non-interactive runs do not stop.
11. **The retired setup flags fail with a pointer** to `git profile add`
    rather than as unknown options.
12. **No Azure DevOps path in `add`** (§6 lists it as manual). The proposal had
    `add` print the key and settings URL; without gh there is no account to
    check the key against, and the profile is two `git config --file` lines.

## 9. Verification and adoption

### 9.1 Tests

`tests/git-profile.sh` runs against a temporary `HOME` with stubs for gh, ssh,
ssh-keygen, and ssh-add; nothing reaches GitHub or this machine's keys. The gh
stub keeps accounts, scopes, tokens, emails, and registered keys in files and
refuses API calls without an account token or scope. The ssh stub answers
`Hi LOGIN!` for the first offered key an account registered (the `-i` key,
then a configured fallback) and serves fetches and pushes from local bare
repositories, one of them private to the work account. ssh-keygen makes real
unencrypted keys, so commits really sign. It covers:

- usage errors, and `add` without gh;
- useConfigOnly refusing a commit with no identity;
- `add --default` for an account gh holds under the profile's name: a scope
  refresh without login or switch, both registrations and their titles,
  `~/.gitconfig.local`, allowed signers, the transport check, and a signed
  commit; the warning when `~/.gitconfig` overrides it;
- `add work`: login, the active account restored, every API call made with the
  work token, the email choice, key generation, the profile file; a rerun that
  asks and changes nothing; an unverified `--email` refused; a default key
  order that reaches another account refused;
- `--ssh-key agent` with `--user`: the chosen public half written and pinned,
  no account changes, and a rerun that does not ask the agent;
- `use` (outside a repository, idempotent, replacing, `--default`, unknown and
  default names), `whoami`, and `list`;
- `gcl -p` in Bash and Zsh over a leftover `gcl` alias: the fetch and the push
  use the profile's key, the clone keeps the include and no bare
  `core.sshCommand`, a commit signs as the profile; plain `gcl` keeps the
  default key and is refused by the private repository; unknown profiles and
  bare `-p` fail and leave no directory;
- `remove`: revocation titles, key files kept, the allowed signer dropped, and
  a repository falling back to the default;
- `ssh -G` on the shipped `ssh_config`: no multiplexing for `github.com`,
  unchanged for other hosts.

Each of nine deliberate breakages (no `ControlPath=none` in the profile, clone
without the include, no switch back, any login accepted, API calls as the
active account, `use` keeping the old include, `remove` keeping the signer,
`gcl` without `unalias`, `ssh_config` without `ControlPath none`) fails the
test.

### 9.2 What was not exercised

Real GitHub: `gh auth login`/`refresh` device flows, the REST endpoints'
responses (the stub reproduces the fields used: `login`, `name`, `email`,
`verified`, `key`), SSO authorization, and a real `Hi LOGIN!`. Git older than
2.43: Ubuntu 22.04 ships 2.34, which has `clone -c` and `git config
--fixed-value`, but clone's fetch reading an include added with `-c` was seen
only on 2.43. A passphrase-protected key, and an agent-held key signing a
commit.

### 9.3 Adopting on this machine (by hand, not done)

1. Merge the branch and apply it (`dotfiles update`, or `./setup.sh --config`),
   so the portable config gains `useConfigOnly`. `~/.ssh/config` is a link into
   the checkout and picks up the git-host block directly.
2. `git profile add tafk7 --default --ssh-key ~/.ssh/tafk7_github`. gh holds
   `tafk7`, so there is no login, but its token lacks
   `admin:ssh_signing_key` and `user:email`: expect a browser refresh. The key
   is probably registered for authentication already and is added for signing.
   `~/.ssh/config.local` pins it for `github.com`, so the SSH check passes.
3. `~/.gitconfig` sets `user.email` and `user.name` itself, after its includes,
   so they override `~/.gitconfig.local`; `add` warns about any that differ.
   Moving them into `~/.gitconfig.local` keeps the default in one file.
4. From then on every commit is signed (`commit.gpgsign = true`), including in
   this repository.
5. A work account: `git profile add work` on the machine that needs it, then
   `git profile use work` in existing clones, or `gcl -p work URL` for new
   ones.
