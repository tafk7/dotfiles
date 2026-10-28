# Secure terminal-only visualization viewer with live reload

**Status:** first implementation on branch `viz-ssh`, 2026-10-28. Not yet
tried from the Windows laptop: see [still to verify](#still-to-verify). Created
2026-10-26 as an idea note; this revision records the decided design.

## User need

The user works on headless Linux through SSH/tmux from a Windows machine and
wants to view generated interactive HTML in the Windows browser. Frequent
iteration and automatic reload are essential. VS Code must not be required.

The user's words:

> I want frequent iteration and automatic reload. It would be nice if I didn't
> need to have VSS code open because its so fragile w/ its connection and annoying
> to bring up vs just a ssh connection in my terminal

Everyday workflow: ssh in from WezTerm and attach to tmux. Keep one bookmark,
`http://127.0.0.1:PORT/`. Agents publish with `viz open` and pass on the URL it
prints. Pages reload on change. A dropped tunnel leaves the page visible, and
polling recovers on reconnect.

## Decided design

```text
Windows browser --HTTP--> 127.0.0.1:PORT --ssh -L--> /run/user/UID/viz/http.sock --> bin/viz
                 cookie                 (Windows      (0700 dir, 0600 socket,        (stdlib Python)
                 viz-PORT               OpenSSH)       no TCP listener on Linux)
```

**Transport: a Unix socket, no TCP on Linux.** The server listens on
`$XDG_RUNTIME_DIR/viz/http.sock`. Without `XDG_RUNTIME_DIR` it uses
`/run/user/UID/viz`, and failing that `/tmp/viz-UID`, checked for owner and
mode the way tmux checks `/tmp/tmux-UID`. The directory is 0700. The socket is
created under umask 0177, so it is 0600 from the moment it exists. The kernel
then refuses every other account (except root) at `connect()`. sshd runs the
forward as the user, so the user's own forward gets through. Nothing listens on
a TCP port, so there is no port for two Linux accounts to collide on or squat.

**A browser secret as well.** The forwarded port on the laptop is open to every
process there, and the browser runs pages from other sites. The socket alone
cannot tell the user's browser from those. The server keeps one secret per
account in `~/.local/state/viz/token` (0600). It reaches a browser only as a
cookie:

- `viz login` asks the running server (over the socket, with the secret as a
  bearer token) for a single-use code, valid for 10 minutes, and prints
  `http://127.0.0.1:PORT/__viz/login?code=...`.
- Opening the link sets `viz-PORT=<secret>`: HttpOnly, SameSite=Lax, 400 days,
  then 303s to the gallery. The name carries the port because browsers share
  cookies across ports. Two forwards (two hosts) then keep separate sign-ins.
  This is Jupyter's `username-localhost-8888` pattern.
- The secret itself is never printed. `viz open` and `viz status` print nothing
  secret, so agent transcripts carry no credential. `viz login --reset` writes a
  new secret and restarts the server, which signs every browser out.

**Checks on every request, in order:**

1. The Host header is `localhost`, `127.0.0.1` or `[::1]` with any port, else
   421. This stops DNS rebinding.
2. `/__viz/login?code=` is the only unauthenticated route. Everything else
   needs the cookie or the bearer secret, else 403 with sign-in instructions.
3. For browser requests, Fetch Metadata: `Sec-Fetch-Site` must be
   `same-origin` or `none`, or the request must be a top-level `GET`
   navigation. Other origins, including other localhost ports, which count as
   same-site and get the Lax cookie, cannot load a viz file as a script, image,
   iframe or fetch.
4. Path: URL components are percent-decoded first, then any component starting
   with `.` is refused (`..`, `.git`, `.ff-profile`, `.env`). The realpath must
   lie under VIZ_DIR or a linked directory, and a hidden component below that
   root is refused even when a symlink leads there. GET, HEAD and the version
   endpoint share this code.
5. Response headers: `X-Content-Type-Options: nosniff`,
   `Cross-Origin-Resource-Policy: same-origin`,
   `Cross-Origin-Opener-Policy: same-origin`, `X-Frame-Options: SAMEORIGIN`,
   `Referrer-Policy: same-origin` and `Cache-Control: no-store`. viz's own pages
   (gallery, sign-in) get a strict CSP (`default-src 'none'; script-src
   'self'`...). Served files get `frame-ancestors 'self'` only. They are the
   user's pages, with inline scripts and CDNs, and a strict CSP would break them
   without stopping a hostile page.

**Publication.** The model is unchanged: VIZ_DIR, plus a file outside it
published by linking its directory into `VIZ_DIR/linked/`, so relative links
and reload on rebuild keep working. It is tightened:

- A linked directory is never `$HOME` or above it, the temp root, or a
  repository root. `viz open` refuses, and the server ignores such links if made
  by hand.
- Linked directories are not listed. Directory listings exist only inside
  VIZ_DIR, and the old SimpleHTTPRequestHandler auto-index is gone.
- The gallery lists linked files only after they have been opened (recorded in
  `~/.local/state/viz/opened`), not their siblings.
- Without VS Code, `viz open` also serves images.

**Reload.** An injected `<script src="/__viz/reload.js">` polls
`/__viz/version?path=` every second, starting at the `load` event. The server
records what each page loads, by the `Referer` its CSS, JS, images and fetches
send. A page's version covers the page and those files. Error responses and
failed fetches are skipped, so polling rides out a tunnel drop, a server
restart or a sign-out. After a server restart a page with assets reloads once,
because the asset list starts empty.

**Lifetime.** `viz open`, `viz start` and `viz login` start a detached server
on demand, as before:

- An flock serializes check-and-bind, so a second `viz serve` exits.
- A stale socket from a crash is replaced, after checking it is a socket.
- The server exits when its socket disappears or is replaced, for example when
  logind removes `/run/user/UID` at the last logout.
- `viz stop` signals only a process whose command line is `viz serve`.
- `viz stop` also ends the old 127.0.0.1 TCP server, through its pid file in
  `~/.local/state/viz/`. `viz status` warns while that server still runs.

**VS Code: kept where it fits, dropped where it can't work.**

- Kept: non-browser files (notebooks, Markdown, PNG) open as tabs in a
  connected window, and `viz diff` works.
- Kept, protected: `/__viz/diff`, which is POST only. It needs the cookie, an
  `Origin` exactly equal to `http://<Host>`, `Sec-Fetch-Site: same-origin`
  when sent, and an `X-Viz: 1` header, which a cross-origin page could only
  send after a CORS preflight that viz never grants. GET returns 405. Pages
  keep writing `<a href="/__viz/diff?left=..&right=..">`, and the injected
  script turns the click into that POST. Paths must be existing files under
  VIZ_DIFF_ROOTS, with no hidden components.
- Dropped: `code --openExternal` for browser files. VS Code forwards remote
  *TCP* ports. For a localhost URL it opens its own tunnel to the remote TCP
  port and rewrites the URL to whatever local port it got. With no TCP listener
  on Linux, that page would fail. `viz open` prints the URL instead. Inside VS
  Code's terminal, copy the URL into the browser rather than clicking it. VS
  Code Remote-SSH reads the same `~/.ssh/config`, so its connection can own the
  forward too.

**Why not TCP plus a secret?** An earlier draft considered it, and it is
weaker on a shared host:

- Anyone can bind `127.0.0.1:PORT` while viz is down. The user's VS Code or
  browser then sends the cookie to that impostor.
- Two accounts with the same `uid % 10000` collide.
- Every coworker's process can probe the server.

The socket removes all three. The secret is still needed for the laptop and the
browser, so viz keeps both layers. It has one transport.

## Prior art

A survey on 2026-10-27 checked primary sources (registries, release pages,
docs, source). No tool combines zero install, a private Unix socket, a token,
a Host check and live reload, so the decision was to keep the custom server
and borrow patterns.

| Tool | Latest release | Unix socket / token / Host check | Live reload | Gap |
|---|---|---|---|---|
| browser-sync | 3.0.4, 2025-04 | no / no / no | yes (socket.io) | Node, TCP, no auth |
| python-livereload | 2.7.1, 2024-12 | no / no / no | yes | websocket accepts any Origin |
| live-server / five-server | 1.2.2 (2022) / 0.5.0, 2026-05 | no / no / no | yes | unmaintained / CORS on by default |
| `python -m http.server` | stdlib 3.15 | no / no / no | no | serves dotfiles, follows symlinks, lists dirs |
| vercel `serve` | 14.2.6, 2026-03 | yes (`-l unix:`) / no / no | no | Node; dotfiles still served |
| Jupyter Server | 2.21.1, 2026-09 | yes (`--sock`, 0600) / yes / yes | no | reference design, not a file viewer |
| code-server / openvscode-server | 4.143.1 / 1.109.5 | yes / password or token / Origin | no | proxies TCP ports only; heavy |
| VS Code port forwarding | n/a | can't forward Unix sockets (vscode-remote-release #8950, closed) | n/a | rewrites localhost URLs to TCP tunnels |
| ttyd / gotty | 1.7.7 / 1.10.0 | ttyd yes / basic auth / origin | n/a | terminal sharing, not files |
| Caddy `file-server` | 2.11.7, 2026-10 | yes (`unix//path\|0600`) / no / yes | no | Go binary; dotfiles served unless hidden |
| agent-preview | 0.1.1, 2026-10 | no / yes (token to HttpOnly cookie) / ? | ? | built for public tunnels; Go |

Borrowed from Jupyter:

- the token-to-cookie flow;
- a port-qualified cookie name;
- a socket mode fixed before it can accept, and a stale path removed only if it
  is a socket;
- a loopback Host allowlist;
- printing the `ssh -L` line.

Not copied: Jupyter's `==` token compare (viz uses `hmac.compare_digest`).
Jupyter also sets no SameSite attribute; viz sends Lax.

## Threat model

**Assets:** what viz serves (agent output, often derived from project data),
the secret, and the ability to open VS Code diffs.

| Who | Can they... | Defense | Residual |
|---|---|---|---|
| Another account on the Linux host (coworker) | connect to the server? | 0700 directory and 0600 socket; no TCP listener; secret file 0600 | root and admins can read everything, as with any file of yours |
| Another account on the Linux host | squat the socket or `/tmp/viz-UID`? | runtime dir is per-user (systemd); the `/tmp` fallback is refused unless owned by you and 0700 | a squatter of `/tmp/viz-UID` can deny service (viz refuses to run) |
| Another local user or process on the laptop | read pages through the forwarded port? | every request needs the secret; the forward binds 127.0.0.1, never the LAN | admins and malware running as you; the login link sits in the browser history but is single-use and expires |
| Another laptop account racing for the port | impersonate viz and collect the cookie? | `127.0.0.1` binding (no IPv6 sibling); ssh prints `Address already in use`; the strict variant below exits instead | with the default config a warning can be missed; HTTPS would be needed to authenticate the server |
| LAN | reach the forward? | `LocalForward 127.0.0.1:PORT` (GatewayPorts off by default) | none known |
| A website in the user's browser | rebind DNS to read viz? | Host allowlist (421) | none known |
| A website or another localhost port | embed, frame or script viz files, or read them? | Fetch Metadata check, CORP, `frame-ancestors`, X-Frame-Options; cookie is Lax and HttpOnly | browsers without Fetch Metadata or CORP rely on the cookie and same-origin policy alone |
| A website or another localhost port | make viz do something (CSRF)? | no state-changing GET; diff needs POST, cookie, exact Origin, `X-Viz` | none known |
| A page served by viz | read other viz pages, request diffs? | **not defended: by design.** Pages are the user's and agents' output, trusted like their code | don't open untrusted or downloaded HTML through viz |
| Any request | escape the served roots? | traversal (plain and encoded), symlink escape and hidden paths refused for GET, HEAD and version | siblings of an opened file in a linked directory are fetchable by the signed-in browser (needed for relative links) |

Also residual:

- The server trusts that whatever reaches its socket came through the user's
  own ssh. That is true by filesystem permission, but every process running as
  the user (agents included) can also talk to it, and to VS Code.
- The secret persists across reboots on purpose, so the bookmark keeps working.
  Rotate it with `viz login --reset`.
- No HTTPS. Loopback HTTP between the browser and ssh is visible only to
  privileged software on the laptop.

## SSH setup (Windows client)

**Facts about the user's setup:**

- WezTerm runs PowerShell (`config.default_prog`), and the user runs Windows
  OpenSSH `ssh.exe` in it. `configs/wezterm.lua` finds the tab's host by
  looking for an `ssh.exe` foreground process.
- `configs/ssh_config` is deployed only on Linux, as a symlink to
  `~/.ssh/config` (`lib/config.sh`). The Windows client reads
  `%USERPROFILE%\.ssh\config`, which these dotfiles don't manage, like
  `wezterm.lua`, which is copied by hand.
- Windows OpenSSH has no ControlMaster, so each `ssh` is its own connection.
- `bin/ssh-bridge` is for the agent inside WSL and doesn't touch forwards.

`viz status` on the Linux host prints the exact lines for that host. The
default port is `20000 + uid % 10000`, the same as the old `VIZ_PORT`, so an
existing bookmark number stays. If you forward a different local port, set
`VIZ_PORT` in `~/.shell.env` so printed URLs match.

**Everyday setup:** add the forward to the host's existing block.

```
Host devbox
    HostName devbox.example.com
    LocalForward 127.0.0.1:21001 /run/user/1001/viz/http.sock
```

- The first `ssh devbox` owns the forward. Later sessions to the same host
  print `bind [127.0.0.1]:21001: Address already in use` / `Could not request
  local forwarding.` and carry on. Don't add `ExitOnForwardFailure yes` here:
  it would make those later sessions exit.
- `configs/wezterm.lua` now passes `ClearAllForwardings=yes` to its image-paste
  `ssh`, so pasting doesn't compete for the port. scp already clears forwards.
  Recopy the file to Windows.

**Strict variant,** for a laptop other people log into. A dedicated alias exits
when the port is taken instead of warning:

```
Host devbox-viz
    HostName devbox.example.com
    LocalForward 127.0.0.1:21001 /run/user/1001/viz/http.sock
    ExitOnForwardFailure yes
```

Run it in its own tab: `ssh -N devbox-viz`. Don't use `SessionType none` in the
file. It needs OpenSSH 8.7, and Windows 10 ships 8.1, which rejects the
unknown keyword and with it the whole config.

**One-off, no config:**
`ssh -L 127.0.0.1:21001:/run/user/1001/viz/http.sock devbox`.

**Bind to 127.0.0.1, not localhost.** `LocalForward localhost:PORT` binds both
`127.0.0.1` and `[::1]` (verified below). A browser asked for `localhost` tries
`[::1]` first, and someone who bound `[::1]:PORT` before you would get only a
warning from ssh. viz prints `127.0.0.1` URLs, and the forward binds exactly
that address.

**Server side:** the remote sshd must allow stream-local forwarding. It does by
default: `AllowStreamLocalForwarding yes`, no `DisableForwarding`, and no
`restrict` or `no-port-forwarding` on the key. Ubuntu's default `sshd_config`
sets none of these.

## Verification

**OpenSSH on this host,** 9.6p1 (Ubuntu 24.04), client and server. I ran an
unprivileged `sshd` on a random loopback port with scratch keys and
`UsePAM no`, and an `ssh -F` client config with its own known_hosts.
`~/.ssh` was untouched. Results:

- `-L 127.0.0.1:P:/…/viz/http.sock` works: no cookie gives 403; a rebinding
  `Host` gives 421; the login link gives 303 with a cookie; reusing the code
  gives 403; with the cookie the page arrives with the reload script.
- A second forward on a taken port: with `ExitOnForwardFailure=yes` it exits
  255. Without it, ssh warns and runs the command.
- `ClearAllForwardings=yes` silences a `LocalForward` from the config.
- `LocalForward localhost:P` binds `127.0.0.1:P` and `[::1]:P`.
  `127.0.0.1:P` binds IPv4 only.
- Stopping viz behind a live tunnel: requests fail (curl exit 56) and sshd logs
  `connect to /…/http.sock port -2 failed`. Restarting viz restores service
  without reconnecting ssh.

**Headless Chromium 153** (Playwright 1.64.1) through that tunnel passed 13 of
13 checks:

- Before sign-in: an unsigned page gets 403; the login link lands on the
  gallery; the cookie is `viz-P`, HttpOnly and Lax.
- Reload: a stylesheet edit and a page edit each reload the page.
- Diff: a `/__viz/diff` link becomes a same-origin POST that passes every
  check. It got 409 because no VS Code was connected.
- A page on another localhost port (same-site, so the cookie is sent) fails to
  load a viz `<script>` and `<img>`, cannot read a credentialed `fetch`, and
  gets an empty iframe.
- With the tunnel killed, the page stays. After reconnecting, an edit reloads
  it.

**Windows OpenSSH: source review, not run.**

- In PowerShell/openssh-portable `latestw_all`, the client path for
  `-L port:/remote/path` is upstream's, with no `WINDOWS` conditionals:
  - `readconf.c` `parse_fwd_field` treats any `/` as a path;
  - `ssh.c` only expands `%`/`~` in the path;
  - `channels.c` `channel_post_port_listener` opens a
    `direct-streamlocal@openssh.com` channel.
- Windows only listens on TCP. sshd on Linux connects to the socket.
- The known Win32-OpenSSH Unix-socket failures (#1564, #2321) are where the
  Windows side must itself open a socket path, which it treats as a named pipe:
  `-R` back to Windows, or sshd on Windows. That is not this direction.
- Inbox versions: Windows 10 has 8.1p1 (KB5003173). Windows 11 24H2 has 9.5p1
  according to community reports. Stream-local forwarding dates from OpenSSH
  6.7 (2014).
- Upstream `serverloop.c` `server_request_direct_streamlocal` permits the
  connect when `AllowStreamLocalForwarding` includes local, port forwarding is
  permitted for the key, and `DisableForwarding` is off.

**StreamLocalBindUnlink: not needed.** It applies only when ssh or sshd
*listens* on a Unix socket (`-L /local.sock:…` or `-R /remote.sock:…`). Here
the listening end is TCP on Windows, and viz replaces its own stale socket.

**`tests/viz.py`** covers, with temporary roots and no real credentials:

- the socket directory is 0700 and the socket 0600, owned by the user, with
  nothing on the TCP port;
- requests are refused without the secret, with a wrong cookie, with another
  port's cookie or with a wrong bearer, for GET, HEAD, version, ping and login
  mint;
- bad Host headers get 421;
- sign-in: one code, used once, never shown in `viz status`;
- containment: traversal (plain, encoded, through a symlinked directory),
  symlink escape and hidden paths, for GET, HEAD and version;
- Fetch Metadata outcomes;
- reload on page and asset changes;
- linked-directory rules: no listing, the gallery shows only opened files, and
  home and repository roots are refused;
- the diff endpoint's refusals;
- lifetime: single server, VIZ_DIR mismatch, `stop` sparing unrelated PIDs,
  crash recovery, exit when the socket is removed, the `/tmp` fallback refused
  when not private, and `login --reset`.

### Still to verify

On the laptop:

1. Check `ssh -V`.
2. Add the `LocalForward` and `ssh devbox`.
3. Open `http://127.0.0.1:PORT/`, run `viz login`, and open its link.
4. Edit a page and watch it reload.
5. Close and reopen the ssh tab.

Check the PDF viewers of Edge and Chrome on Windows too. Their internal fetches
were not exercised: headless Chromium has no PDF viewer.

## Decisions on the open questions

1. **Windows client:** Windows OpenSSH via WezTerm and PowerShell (from
   `wezterm.lua`). The direction we need has no Windows-specific code; to be
   confirmed on the laptop.
2. **Transport:** a private Unix socket, plus the browser secret. The secret
   isn't a second transport: it is required by the laptop and browser threats,
   which the socket can't see.
3. **Publication:** kept VIZ_DIR and linked directories rather than a registry
   of named publications, tightened as above. Siblings of an opened file in a
   linked directory stay fetchable. This trades the note's "single-file
   publication exposes no unregistered siblings" for working relative links.
   Only the user's browser can fetch them now.
4. **VS Code:** helpers kept. The browser diff endpoint is kept but protected,
   which departs from this note's draft criterion "HTTP requests cannot open
   editor windows": a same-origin viz page still can. To remove it, delete the
   `/__viz/diff` branch in `Handler._route`. `code --openExternal` is dropped.
5. **Migration:** existing links and pages keep their URLs (on the new port
   forward). `viz stop` ends the old TCP server. Nothing is deleted.
6. **Not done:** a systemd user service (on-demand start plus exit-on-socket-loss
   covers it), HTTPS, Range requests.

## Acceptance criteria

- [x] Transport settled: Unix socket and secret.
- [ ] Complete Windows workflow demonstrated (Linux side verified with OpenSSH
  9.6p1 and Chromium. Laptop pending).
- [x] Stable gallery and artifact URLs; reload on HTML and asset updates.
- [x] Tunnel disconnect and reconnect, and server restart, recover.
- [x] Another Linux account cannot connect (permissions; kernel-enforced).
- [ ] Single-file publication exposes no siblings. Decided against: see
  decision 3.
- [x] Hidden paths, traversal, encoded paths and escaping symlinks refused for
  every method.
- [ ] HTTP requests cannot open editor windows. A same-origin POST can open a
  diff by design: see decision 4.
- [x] Tests use temporary roots only.
- [x] Old whole-directory tests updated.
- [x] Windows setup, lifecycle commands and agent guidance documented (README,
  this note, the viz skill).
- [x] Migration of the old listener planned (`viz stop`).
