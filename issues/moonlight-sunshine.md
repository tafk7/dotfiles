# Idea: Moonlight/Sunshine game-stream stack as a remote desktop alternative

**Status:** parked — revisit after the xrdp layer (see `xrdp-remote-desktop.md`) has been
in use for a while and its limitations are felt in practice.

## What it is

- **Sunshine** — self-hosted, open-source game-stream *host* (the server side).
  Runs on the machine being accessed. Encodes the desktop with hardware H.264/HEVC/AV1
  (NVENC, VAAPI, QSV) and speaks NVIDIA's GameStream protocol.
- **Moonlight** — the open-source *client* for that protocol. Clients exist for
  Windows, macOS, Linux, Android, iOS, and even a browser-adjacent Steam Link build.

Together they form a low-latency (~5–15 ms encode-to-decode on LAN) remote desktop
pipeline that treats the session like a video stream rather than a drawing protocol.

## Why it might beat xrdp for us later

| Dimension | xrdp | Sunshine/Moonlight |
|---|---|---|
| Latency / smoothness | OK for terminals + editors; chugs on video/scroll | Near-local; 60–120 fps capable |
| GPU use | Software rendering path by default | Hardware encode + decode end to end |
| Session model | Own login session (headless-friendly) | Mirrors an existing logged-in desktop¹ |
| Client on locked-down Windows | mstsc.exe is preinstalled — zero friction | Moonlight must be installed² |
| Protocol/firewall | One TCP port (3389), well-known to IT | Several TCP+UDP ports, unusual to IT |
| Audio/mic/clipboard | Mature in RDP | Audio yes; clipboard/file transfer weaker |

¹ Sunshine can run as a service with a virtual display on headless boxes, but it's
more setup than xrdp's "log in and get a session".
² Moonlight ships a portable .exe that runs without admin rights — install
restrictions are usually surmountable, but it's still a foreign binary an org
might flag; mstsc never is.

## When to actually pick this up

Trigger conditions — any of:
- xrdp latency/repaint becomes a real annoyance (e.g. GUI-heavy work, video, high-DPI).
- We want to stream a GPU-accelerated desktop (CUDA/GL work, gaming on the home box).
- The client machine stops being install-restricted (personal laptop, or org policy allows Moonlight).

## Sketch if/when we do it

- `installers/install-sunshine.sh` — Sunshine ships a `.deb` via GitHub releases, so
  it fits the existing `github_latest_version` + apt/dpkg pattern; pin the version
  like everything else. Needs udev rules + `setcap` for KMS capture, and a systemd
  user service.
- Gate behind an orthogonal flag (e.g. `--stream`), same pattern as `--ai` / the
  proposed `--rdp`: hardware-specific, opt-in, never implied by a tier.
- Client side is out of scope for the dotfiles (Windows/Android installs), but the
  Moonlight portable .exe needs no admin — document it in the runbook.
- Ports: 47984/47989/48010 TCP, 47998–48000 UDP (default range) — document for
  firewall/Tailscale ACLs.
- Pairing is PIN-based on first connect; no accounts or cloud dependency.

## References

- https://github.com/LizardByte/Sunshine
- https://github.com/moonlight-stream
- Moonlight portable client: https://github.com/moonlight-stream/moonlight-qt/releases
