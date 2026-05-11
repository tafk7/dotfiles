# Theme System Quick Start Guide

## 🎨 Switch Themes in 10 Seconds

### Interactive Mode (Recommended)
```bash
bin/theme-switcher
```
- Use ↑/↓ arrows to browse themes
- Type to fuzzy-search
- Enter to apply

### Direct Switch
```bash
bin/theme-switcher nord
bin/theme-switcher tokyo-night
bin/theme-switcher kanagawa
bin/theme-switcher gruvbox
bin/theme-switcher catppuccin
```

### List / Inspect
```bash
bin/theme-switcher --list        # all themes
bin/theme-switcher --current     # active theme
bin/theme-switcher --preview nord   # preview without applying
bin/theme-switcher --revert      # back to previous theme
```

## 🔄 After Switching

Most surfaces update on next launch, but some need a nudge:

- **Tmux**: `Ctrl-a r` to reload
- **Vim**: applies to new sessions
- **Shell**: applies to new terminals; `reload` for current
- **Bat**: cache is rebuilt automatically by the switcher when vendored themes change

## 🎯 Theme Descriptions

| Theme | Best For | Vibe |
|-------|----------|------|
| **gruvbox** | Retro feel | Warm, comfortable, nostalgic (default) |
| **nord** | Long coding sessions | Cool, professional, Arctic |
| **tokyo-night** | Modern development | Vibrant, city lights, contemporary |
| **kanagawa** | Focused work | Earthy, Japanese aesthetic, calming |
| **catppuccin** | Gentle on eyes | Soft pastels, cozy, smooth (Mocha) |

## 🚀 Pro Tips

1. **Quick aliases** in `~/.zshrc.local` or `~/.bashrc.local`:
   ```bash
   alias nord='bin/theme-switcher nord'
   alias tokyo='bin/theme-switcher tokyo-night'
   ```

2. **Default theme**: gruvbox if none is set.

3. **Check current theme**:
   ```bash
   bin/theme-switcher --current
   # or look at:
   grep DOTFILES_THEME generated/theme.sh
   ```

## 🛠️ Troubleshooting

**Theme partially applied?**
The theme switcher applies each surface independently. If one tool's vendored
file is missing, that tool is skipped (with a warning) but the others still
update. Run `./bin/verify` to see what's wired up.

**Reset everything:**
```bash
rm generated/theme.sh
rm generated/starship.toml generated/delta.gitconfig
rm ~/.config/nvim/theme.vim ~/.tmux/theme.conf
bin/theme-switcher gruvbox
```

**Vim plugin missing?**
```bash
nvim +PlugInstall +qall
```

**Reload current shell:**
```bash
exec $SHELL
```

---

For detailed documentation, see [Theme System Documentation](./theme-system.md).
