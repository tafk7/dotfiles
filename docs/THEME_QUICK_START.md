# Theme quick start

```bash
# Global theme (also used outside tmux)
bin/theme-switcher github-light

# Current tmux session and window
bin/theme-switcher --session
bin/theme-switcher --window
bin/theme-switcher -s              # short form
bin/theme-switcher -w vim          # choose a Vim override for this window
bin/theme-switcher set --session default catppuccin
bin/theme-switcher set --window default everforest

# Independent tools in the current window
bin/theme-switcher set --window vim gruvbox
bin/theme-switcher set --window tmux catppuccin

# Inspect the result and its source
bin/theme-switcher explain --window
```

The cascade checks window tool/group/default, session tool/group/default, then
global tool/group/default. Clear a value to restore inheritance:

```bash
bin/theme-switcher clear --window vim
bin/theme-switcher reset --window
bin/theme-switcher reset --session
```

Existing shells refresh at the next prompt. New Neovim instances inherit the
resolved theme; use `:ThemeReload` in an existing instance. Restart btop and
lazygit. Tmux canvas, status entries, borders, and the ANSI palette update
immediately.

Useful diagnostics:

```bash
bin/theme-switcher --list
bin/theme-switcher --preview gruvbox-light-soft
bin/theme-switcher diagnose
bin/theme-switcher show --window
```

See [theme-system.md](./theme-system.md) for stable ids, linked windows,
persistence, tmux version limits, and adding themes.
