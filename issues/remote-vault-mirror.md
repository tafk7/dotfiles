# Edit a remote Markdown vault from the laptop over ssh

**Status:** open, design proposal (2026-11-23). Nothing is built. The Ctrl+Alt+P
change for password-only hosts it relies on is drafted (below, [Auth](#auth-key-or-password)).

## User need

Work happens on headless Linux hosts over ssh from a Windows laptop, with
Markdown notes kept on the hosts: a knowledge base, a project's record, generated
vaults. The goal is a rich Markdown editor with a graph view (Obsidian) on the
laptop, on files that live on the host, without installing drivers on the laptop
and without handing credentials to an editor plugin. Some hosts accept an ssh
key; others accept only a password (a directory login with no key registered).

## What exists, and why not

- **Obsidian has no server mode.** It is a closed desktop app on local files.
  Its own headless client (2026) only syncs with the paid Obsidian Sync, and its
  CLI needs the desktop app running.
- **A network drive (SSHFS-Win).** Needs the WinFsp kernel driver on the laptop,
  which a managed machine may block. Obsidian does not support network drives
  (no file watching).
- **The community plugin "Remote SSH"** does this live, by patching Obsidian's
  internal file adapter. We want our own instead, built to the security
  requirements below.
- **Obsidian on the host in a container, shown in the browser** (linuxserver's
  image, Selkies). Works with nothing on the laptop. But it streams a desktop,
  and on a host without a usable GPU, Obsidian draws on one CPU core (a
  2,800-note graph lags). It is a separate tool; see [Alternatives](#alternatives).
- **git** (a clone on the laptop, Obsidian Git). Every pull asks for the password
  on a password-only host. Generated vaults are not repositories, and a sync on a
  timer makes commits nobody meant.

## Proposed design

Obsidian on the laptop works on a **local mirror** of the remote vault. A small
plugin of ours keeps the mirror in sync with a small helper of ours on the host,
through the tunnel Ctrl+Alt+P already opens. The plugin never sees a credential.

```text
laptop                                              host
Obsidian ─ local mirror folder                      remote-vault serve (stdlib Python, the user's account)
   └─ plugin ─HTTP+token─► 127.0.0.1:PORT ═ssh -L═► $XDG_RUNTIME_DIR/remote-vault/http.sock (0700 dir, 0600)
                                                       └─ registered vaults only, with their write rules
```

**A mirror, not live remote files.** Obsidian reads every file at startup to
build its graph, backlinks and search, so serving files lazily saves little. And
replacing Obsidian's file layer means patching undocumented internals, which any
Obsidian update can break. A mirror is an ordinary folder:
- every Obsidian feature runs locally, at native speed;
- it keeps working with the tunnel down;
- the plugin uses only the public API: vault events, and `app.vault` for writes.

Large attachments (PDFs) can be left out by pattern, or fetched on first open.

### The helper on the host: `bin/remote-vault`

One stdlib Python script, built like `bin/viz`: HTTP over a Unix socket, no TCP
listener.

- `remote-vault add NAME PATH [--write GLOB]...`, `remove`, `list`: the
  registry, in `~/.config/remote-vault/vaults.toml`.
  - A vault is read-only unless `--write` names the paths the laptop may change
    (`notes/**`).
  - Generated content stays read-only, and so do files with another writer.
- `remote-vault forward`: prints its line for `forwards` (`NAME\tPORT\tSOCKET\t-`)
  and starts the server if it is not running. That is how Ctrl+Alt+P carries it.
- `remote-vault pair`: prints a one-time code, valid for 10 minutes. The plugin
  exchanges it for a token, stored hashed on the host. `remote-vault revoke`
  drops tokens.
- The API, all under the token:
  - `GET /vaults`;
  - `GET /tree` (path, size, mtime, sha256);
  - `GET /file`;
  - `PUT /file` with `If-Match: <sha256>`, answering 409 on a conflict;
  - `POST /rename`;
  - `DELETE /file` (moves the file to the vault's trash, never unlinks it);
  - `GET /changes?since=CURSOR`, a long poll that answers when something changes.
- **Lifetime.** Started by `forward` (or a user unit). It exits after a set idle
  time with no client, and when the last tunnel hold ends.

### The plugin on the laptop

- **Settings:**
  - the forwarded port;
  - pairing (paste the code from `remote-vault pair`);
  - which remote vault this local vault mirrors;
  - exclude patterns (always `.obsidian/**` and the trash);
  - the attachment policy;
  - a status in the status bar (connected, syncing, conflicts, offline).
- **Sync:**
  - **First,** a full copy.
  - **Then both directions:** the helper's change feed brings remote changes;
    Obsidian's create, modify, rename and delete events send local ones, only
    under paths the vault makes writable.
  - **On a conflict** (the remote file changed since the copy the edit started
    from), keep both: the local version is saved beside it as
    `NAME (conflict YYYY-MM-DD HHMM).md`, never overwritten.
  - **Offline edits** queue and replay on reconnect, through the same check.
- **The plugin never stores a password,** opens no ssh connection, starts no
  process, and never evaluates fetched content as code.

## Auth: key or password

ssh does all authentication, and the plugin reaches only the forwarded port, so
the helper and the plugin work the same whichever way the host is reached.

- **A host that takes a key:**
  - Ctrl+Alt+P as today: a background ssh with `BatchMode=yes` asks `forwards`
    for the list, then opens the tunnel without a console;
  - an agent-held key with a passphrase works through the Windows ssh-agent.
- **A password-only host** (or keyboard-interactive, or 2FA): the background ssh
  answers "Permission denied", so Ctrl+Alt+P opens the tunnel in a WezTerm tab of
  its own, where ssh prompts as usual.
  - **Which ports:** the tab uses the last list the host gave, sent by `forwards`
    as a WezTerm user variable and kept in `~/.wezterm-forwards.tsv`.
  - **Once the ports are up,** the hold in that tab says so (`forwards_open`),
    and WezTerm switches back to the tab the user was in.
  - **Ctrl+Alt+P again** closes the tab.
  - **Hosts with a key** are unchanged.
  - **Status:** drafted on a scratch branch, with `tests/forwards.sh` and
    `tests/wezterm-forwards.sh` extended and passing; not yet run on Windows.
  - **Left to do:** when there is no list yet, let the first press learn it
    instead of asking the user to run `forwards` once.
- **Without WezTerm,** `forwards` prints the `-L` arguments for a plain
  `ssh -N -L … HOST`, which prompts for whatever the host asks.

## Security requirements

Each is a property the design must keep, including on a shared host.

1. **No credentials in the editor.** No password, passphrase or private key
   reaches the plugin; host keys are checked by OpenSSH's `known_hosts`, as for
   any ssh.
2. **Other accounts on the host can't reach it.** The socket sits in a 0700
   directory and is created 0600; no TCP listener. Owner and mode are checked at
   start, as viz does.
3. **Other programs on the laptop can't use the port.** The forwarded port is
   open to every local process and to pages in the browser. Every request needs
   the token; pairing uses a one-time code; tokens are stored hashed, revocable,
   and scoped to the registered vaults. No CORS headers; only `GET` without a
   token reaches `/health`.
4. **It stays in the vault.** Every path is opened with `openat2`
   `RESOLVE_BENEATH | RESOLVE_NO_MAGICLINKS`, relative to the vault's directory
   descriptor, so `..`, absolute paths and symlinks pointing out are refused by
   the kernel. Where `openat2` is missing (Linux before 5.6), it falls back to a
   `realpath` check on each component and refuses symlinks.
5. **Writes only where allowed.** Write rules per vault are checked on the host,
   whatever the plugin sends. Writes are atomic (temporary file and rename in the
   same directory). Deletes go to the trash.
6. **No code from the host.** `.obsidian/` is never mirrored in either direction:
   plugins, themes and settings stay local to the laptop.
7. **No downloads, no auto-update.**
   - **The helper** is a script in dotfiles, run by the user's Python.
   - **The plugin** is built from this repository with pinned, checked dependencies
     (`obsidian` types, `esbuild`, `typescript`; nothing at run time).
   - **The built `main.js`** is committed with its sha256 and a reproducible build
     script, and installed by copying it (with `dl`). It is not in the community
     store.
8. **Bounded.** Size caps per file and per request. The change feed is
   rate-limited. The server exits when idle.
9. **Logs** hold paths and errors, never contents or tokens.

## Plan

1. **Ctrl+Alt+P for password-only hosts.** Land the drafted change, plus the
   first press learning the list, then check it on the laptop.
2. **The helper.** `bin/remote-vault` with its registry, pairing, the API and
   `forward`; added to `forwards` TOOLS.
   - **Tests in `tests/remote-vault.sh`:**
     - confinement: `..`, absolute paths, symlink out, a symlink swapped in during
       a request;
     - write rules, the token, socket modes, conflicts (409), the trash;
     - change-feed ordering.
3. **The plugin.** `plugins/remote-vault-obsidian/`: the sync engine with a fake
   helper in tests (first copy, both directions, conflicts, an offline queue,
   excludes); settings and pairing; the status bar; the build script and the
   committed `main.js` with its hash.
4. **On the laptop:**
   - install Obsidian, copy the plugin, pair, mirror a vault of about 3,000 notes;
   - edit on both sides;
   - force a conflict, cut the tunnel mid-edit, reconnect.

   Once through a key host, once through a password-only host.

## Acceptance

- A ~3,000-note vault mirrors in under a minute through the tunnel. The graph
  and search run at local speed.
- An edit on either side shows on the other within a few seconds while connected.
  An edit made offline arrives on reconnect, or becomes a conflict copy; it is
  never lost.
- With the tunnel up, another account on the host can't connect to the socket.
  A process on the laptop without the token gets 401. A request for `../x`, an
  absolute path or a path through a symlink out of the vault is refused.
- The same steps work with a key host (Ctrl+Alt+P, no prompt) and with a
  password-only host (Ctrl+Alt+P, the password in the tunnel tab).

## Open questions

- Whether a managed laptop may run Obsidian: it installs per-user without admin
  rights, as far as known. Check the employer's policy.
- Whether a local copy of the vault on the laptop is acceptable for the content
  in question.
- Attachments: mirror everything up to a size, or fetch on first open (Obsidian
  shows a placeholder until then)?
- Whether the plugin should also offer search on the host (a command that queries
  a host-side index through the helper) or leave search to Obsidian's own index
  of the mirror.
- Whether other editors (VS Code, any folder-based Markdown tool) should use the
  same helper through a small CLI sync client instead of the Obsidian plugin.

## Alternatives

- **Obsidian on the host in a container, in the browser** (an `obsidian-box`
  tool).
  - **Strengths:** nothing on the laptop; one copy of the files.
  - **Weaknesses:** a streamed desktop; CPU drawing without a GPU; a third-party
    image to pin and trust; its web desktop has a terminal with root inside the
    container.
  - **If built:** no network, served only on a socket in the runtime directory
    (its nginx can listen there), the image pinned by digest, restricted mode
    on. It complements the mirror for machines where Obsidian can't be
    installed.
- **Live remote files** (the community plugin's approach). Rejected above: it
  patches Obsidian's internals, gains little, and breaks offline.
- **A static site** of the vault (Quartz or a viz page): read-only, but a graph,
  search and backlinks with nothing installed. Useful beside the mirror; not a
  replacement for editing.
