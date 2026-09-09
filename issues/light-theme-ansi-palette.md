# Light themes and ANSI-colored output

**Status:** resolved inside tmux 3.3 or newer; documented fallback elsewhere.

The original report identified two separate failures correctly:

1. tmux set a light pane background without a matching default foreground;
2. ANSI-colored programs still used the terminal's dark-oriented 16-color
   palette, even though truecolor previews looked correct.

Capability verification for this change found tmux 3.7b installed. Its manual
documents `pane-colours[]`, and the upstream changelog places the option in the
3.2a-to-3.3 release. The Linux environment does not contain a WezTerm binary,
so no runtime WezTerm behavior was assumed; the tracked `configs/wezterm.lua`
was inspected and still deliberately leaves `colors` unset.

The foreground/background pair was fixed in every theme. The remaining claim
that “tmux cannot fix this” was true for older tmux releases, but is no longer
true for the installed tmux 3.7b. Tmux 3.3 introduced the `pane-colours[]`
pane option, with entries 0–255 and normal window/pane inheritance.

## Implemented behavior

The theme switcher now applies ANSI entries 0–15 at window scope. Existing
panes inherit the window palette and new splits inherit it automatically. All
splits share the window's full theme, as intended; their backgrounds may still
use independent subtle tints. Different windows can retain different palettes
without changing terminal-global state. The palette is applied after SSH or
local programs emit ANSI color indices, so it works regardless of whether the
underlying terminal is WezTerm, Windows Terminal, or another compatible client.

This avoids OSC palette mutation entirely. No terminal-global state is changed,
so switching one session/window cannot silently recolor another tab, client,
remote host, or standalone shell. Clearing an override simply reapplies the
inherited window palette.

Every light theme uses deliberately dark ANSI entries against its canvas.
Automated contrast checks require every ANSI 0–15 entry to reach 4.5:1 against
the actual theme background.

## Remaining limitation

Tmux versions before 3.3 have no `pane-colours[]` option. They still receive the
correct default foreground/background and truecolor styling, but ANSI colors
come from the terminal palette. Standalone shells outside tmux have the same
terminal-owned limitation. The implementation does not attempt unverified OSC
sequences or rewrite `configs/wezterm.lua`, because either approach is global
to a terminal context and breaks independent window/session isolation.

`theme-switcher diagnose` prints real default-color, ANSI 0–15, and truecolor
samples. In tmux it also reports whether the scoped palette is active. This
catches the integration gap that the old truecolor-only preview hid.
