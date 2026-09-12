# September 2026 refinement — adoption review

Status: implemented and validated in an isolated clone; not adopted into the
live checkout. Baseline: `ce7ddf2270875ed141125bae70ee0ef8b7aaa066`.

## Changes

- Installation helpers explicitly propagate replacement, backup, download, and
  state-write failures, including when invoked through conditional shell calls.
  Recovery retains the journal on failure and verifies its actual target.
- Skipped local binaries no longer acquire ownership from their location alone.
  Native installers preserve external tools before looking up releases.
- The registry describes companion executables: uv and uvx are both staged,
  checked, installed, verified, and included in removal paths.
- Git integration follows installed tools. First environment initialization
  selects an available editor using shell builtins; inherited initialization
  keeps its existing fast path.
- Neovim, bat, fd, and btop configuration respects XDG paths. The explicit
  `install-editor-plugins` command bootstraps pinned vim-plug; editor startup
  remains offline. Existing plugin trees are retained when moving to XDG data.
- Supported agent selections with badges enabled install missing jq without
  sudo. Standalone plugin installs declare the dependency and report its absence.
- Update checks preserve upstream errors and return correct empty JSON results.
- Theme rendering uses the per-theme Starship palette directly. Twenty-four
  unused/duplicated `colors.sh` and `tmux.conf` files are removed; pane tints live
  with semantic palettes. All Starship palette values match the baseline.
- Current maintenance instructions replace historical approval/status prose;
  the original implementation plan is preserved under `docs/history/`.

## Performance

The baseline and candidate were measured side by side on the current x86_64
Ubuntu/WSL host. Each of 28 cases has 50 samples per revision after warm-up,
with interleaved execution. The matrix covers Bash/Zsh first initialization,
inherited initialization, interactive startup, and Bash snapshot replay, with
themes enabled/disabled and controlled/installed tools. The test suite and
download checks were finished before timing started.

Interactive startup with installed direnv, Starship, uv, fzf, and zoxide:

| Shell | Theme | Median, base → candidate | p95, base → candidate |
|---|---|---|---|
| Bash | enabled | 82.94 → 82.25 ms | 87.07 → 85.81 ms |
| Zsh | enabled | 43.31 → 43.24 ms | 44.87 → 45.35 ms |
| Bash | disabled | 69.41 → 69.66 ms | 74.47 → 72.32 ms |
| Zsh | disabled | 31.45 → 31.25 ms | 33.62 → 33.08 ms |

Across all cases, the largest median increase was **0.29 ms** and the largest
p95 increase was **0.51 ms**. The largest percentage increase was 9.4% on a
roughly 1.2 ms snapshot-replay case, an absolute change of about 0.11 ms.
No case crossed the existing joint 10 ms / 15% median regression threshold
or the two-second catastrophic limit. Installed-tool inherited initialization
with themes enabled measured 9.09 → 9.09 ms for Bash and 3.32 → 3.28 ms for Zsh.

These results support adoption from a startup-performance perspective. They
do not establish statistical equivalence or measure first prompt rendering,
Windows interop, network-mounted PATH entries, or remote-host latency. Prompt
refresh and lazy NVM loading were not changed. The owner retains the adoption
decision, including acceptance of changes below the automated threshold.

Raw samples and per-case medians:

- [Controlled tools, theme enabled](2026-09/startup-fixture-enabled.json)
- [Controlled tools, theme disabled](2026-09/startup-fixture-disabled.json)
- [Installed tools, theme enabled](2026-09/startup-installed-enabled.json)
- [Installed tools, theme disabled](2026-09/startup-installed-disabled.json)

## Validation and limits

All 36 shell test scripts, six benchmark unit tests, theme contrast checks,
structured-file checks, documentation-link checks, and ShellCheck pass. Tests
use temporary HOME/XDG roots and separate tmux servers. Failure probes cover
failed binary/tree moves, ledger writes, incomplete downloads, skipped ownership,
companion loss, dependency selection, and update lookup errors.

An additional isolated check downloaded the actual pinned jq and uv releases
through Eget and ran jq 1.8.1, uv 0.10.0, and uvx 0.10.0. It did not install
anything into the operator's HOME. The full Neovim plugin download is covered by
a fake download/manager fixture; actual cloud, APT, RDP, KVM, and ARM runtime
acceptance remain outside this validation.

## Adoption and deferred decisions

Review the candidate before integrating into the live symlink-target checkout.
Configuration reconciliation and package/plugin installation are separate rollout
actions; follow [maintenance](../maintenance.md). The candidate has not changed
live symlinks, preferences, plugin caches, services, or installed executables.

Keep legacy state readers until all personal/work machines are accounted for.
Older ledger ownership cannot be reconstructed automatically. The meaning of
`--work`/`--full`, including sbx/KVM, remains unchanged pending the separate
[sandbox selection decision](../../issues/work-tier-sandbox-boundary.md).
