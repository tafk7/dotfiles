# Secure terminal-only visualization viewer with live reload

**Status:** proposed; design discussion incomplete. Implementation is deferred to
a separate session. Created 2026-10-26.

## User need

The user works on headless Linux through SSH/tmux from a Windows machine and
wants to view generated interactive HTML in the Windows browser. Frequent
iteration and automatic reload are essential. VS Code must not be required.

The user's words:

> I want frequent iteration and automatic reload. It would be nice if I didn't
> need to have VSS code open because its so fragile w/ its connection and annoying
> to bring up vs just a ssh connection in my terminal

The user then asked to discuss the design before implementation, and requested
this local issue for another session. Do not treat the proposals below as an
approved final design.

## Existing implementation and findings

Start with:

- [`bin/viz`](../bin/viz): the standalone Python tool. The Claude plugin is an
  instruction wrapper, not a runtime dependency.
- [`plugins/viz-claude/skills/viz/SKILL.md`](../plugins/viz-claude/skills/viz/SKILL.md)
  and its [README](../plugins/viz-claude/README.md).
- [`tests/viz.py`](../tests/viz.py): existing containment, directory-linking,
  reload and no-VS-Code fallback tests.
- [`docs/testing.md`](../docs/testing.md) for repository checks.

The inspected `bin/viz` revision is `a8832e6f86608d9042a4784009330b79ac88512f`
("Open side-by-side diffs from viz"). Recheck the current tree before changing it.

Current behavior:

- A localhost TCP server serves `VIZ_DIR` (default `~/viz`). The default port is
  `20000 + uid % 10000`, overridable with `VIZ_PORT`.
- `viz open` searches for a connected VS Code window and uses its remote CLI to
  open/forward a browser URL. Without VS Code it prints forwarding instructions.
- HTML gets a browser-side reload script polling `/__viz/version` once a second.
- An external file's whole parent directory is linked into `~/viz/linked/`.
- `/__viz/diff` can request a VS Code diff through HTTP GET.

Security findings, observed 2026-10-26:

- The TCP listener is restricted to `127.0.0.1`, but has no authentication.
  Other accounts on the Linux host can connect without using the owner's SSH
  tunnel. SSH secures the tunnel; it does not authenticate local HTTP clients.
- Whole-directory linking exposes siblings of the requested file.
- Hidden paths are not excluded from HTTP serving. A HEAD request to
  `/.ff-profile/` returned HTTP 200 without authentication. No profile contents
  or credentials were inspected. The gallery hiding dotfiles is not access control.
- Realpath containment exists, but its allowed roots include every linked
  directory. Narrowing publication is therefore necessary as well as transport
  protection.

No implementation, server migration or security fix was performed in the
discussion that produced this issue. Recheck any running server before deployment.

## Desired everyday workflow

1. Connect through a normal terminal SSH session and attach to tmux.
2. Open a stable Windows bookmark such as `http://localhost:23526/`.
3. An agent or human publishes a page and receives a stable, clickable URL.
4. The page reloads after its HTML or published assets change.
5. Disconnecting SSH leaves the current page visible. Reconnecting the tunnel
   lets reload checks recover without changing the URL or restarting the agent.

One SSH connection owns the local forward. Additional SSH sessions should not
need competing forwards. A remote shell need only print the URL; automatically
launching Windows applications is not required.

Keep the useful `viz path` / `viz open` interface where practical. Prefer a small
extension or replacement of the existing tool over a new visualization platform.
The workflow should work from Codex, Claude and an ordinary shell.

## Proposed design to evaluate

### Transport

The preferred candidate is a private Unix-domain HTTP socket on Linux, reached
through SSH forwarding from a TCP port on Windows:

```text
Windows browser -> localhost TCP port -> SSH -> private Linux socket -> publications
```

Use a user-only socket directory and restrictive socket permissions. This would
reuse SSH and filesystem access control without distributing browser tokens.
**Windows SSH client compatibility has not been verified.** First establish which
client the user runs and test local-TCP-to-remote-Unix forwarding with that client.

The alternative is localhost TCP protected by an access token. If selected,
design token storage, browser bootstrap, reconnect behavior and rotation explicitly;
keep tokens out of tracked files and routine logs. Do not ship both transports
by default merely to avoid deciding.

### Publication and browsing

- Serve only explicitly registered publications, with stable names independent
  of source paths, for example `/project-overview/`.
- `viz open FILE` should publish that file, without implicitly exporting its
  parent or siblings. Multi-file pages need an explicit directory publication.
- Decide how an HTML file declares or includes assets and how directory
  publication is limited. Reject broad accidental exports of a home, repository
  root or temporary-directory root.
- Exclude hidden files and directories at every path component; prevent encoded
  traversal and symlink escapes for GET, HEAD and reload/version requests alike.
- Make the HTTP interface read-only: published files, gallery and reload metadata.
  Remove the browser-triggered VS Code diff operation from this interface.
- Consider Host/Origin validation appropriate to the chosen local transport.
  Do not claim generated HTML is sandboxed untrusted code: it runs JavaScript in
  the browser. The trust model should be stated clearly.

### Reload and lifetime

- Keep reload checking in the browser. Simple version polling every second or
  two is sufficient for a small set of pages; no AI polling or broker is needed.
- Include published CSS, JavaScript, images and data changes in the version.
  Handle atomic file replacement and transient writes without getting stuck.
- Recover from tunnel loss, server restart and temporary fetch errors.
- Use a user service for the server, independent of the SSH/tmux session. Keep
  lifecycle commands/status simple and identify stale state safely.
- Keep manifests, sockets and authentication state outside served publications.

## Decisions still open

1. Which Windows SSH client is used, and does its Unix-socket forwarding work?
2. Private Unix socket or authenticated localhost TCP?
3. Exact single-file versus explicit-directory publication and asset semantics?
4. Retain any VS Code helpers as explicit optional CLI commands, or remove them?
5. How are old links migrated and publications revoked without deleting sources?

## Acceptance criteria

- [ ] Discuss and settle the transport with the user before implementation.
- [ ] Demonstrate the complete Windows-terminal SSH/browser workflow with no
  connected VS Code window or VS Code server dependency.
- [ ] Stable gallery and artifact URLs; reload on HTML and asset updates.
- [ ] Tunnel disconnect/reconnect and server restart recover cleanly.
- [ ] Another Linux account cannot fetch publications without authorization.
- [ ] Single-file publication exposes no unregistered siblings.
- [ ] Hidden paths (including browser profiles and `.git`), traversal, encoded
  paths and escaping symlinks are refused through all relevant HTTP methods.
- [ ] HTTP requests cannot open editor windows or invoke host commands.
- [ ] Tests use temporary roots and do not read real credentials, browser
  profiles, SSH configuration or unrelated files.
- [ ] Update the existing tests that currently expect whole-directory exports.
- [ ] Provide concise Windows SSH setup instructions, Linux lifecycle commands,
  and agent guidance for generating/publishing pages.
- [ ] Plan migration of the existing listener and links; preserve preexisting
  source files, browser profiles and other user data.

Keep this issue local to the repository unless the user asks to publish it.
