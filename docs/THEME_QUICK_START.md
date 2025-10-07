# Theme System Quick Start Guide

## 🎨 Switch Themes in 10 Seconds

### Interactive Mode (Recommended)
```bash
theme-switch
```
- Use ↑/↓ arrows to browse themes
- Press Enter to preview
- Press Enter again to apply
- Press Esc to cancel

### Direct Switch
```bash
# Switch to a specific theme
theme-switch nord
theme-switch tokyo-night
theme-switch kanagawa
theme-switch gruvbox
theme-switch catppuccin
```

### List Themes
```bash
themes
```

## 🔄 After Switching

Most applications update automatically, but:

- **Tmux**: Press `Ctrl-a r` to reload
- **Vim**: Theme applies to new vim sessions
- **Shell**: New terminals use new theme immediately

## 🎯 Theme Descriptions

| Theme | Best For | Vibe |
|-------|----------|------|
| **Nord** | Long coding sessions | Cool, professional, Arctic |
| **Tokyo Night** | Modern development | Vibrant, city lights, contemporary |
| **Kanagawa** | Focused work | Earthy, Japanese aesthetic, calming |
| **Gruvbox Material** | Retro feel | Warm, comfortable, nostalgic |
| **Catppuccin Mocha** | Gentle on eyes | Soft pastels, cozy, smooth |

## 🚀 Pro Tips

1. **Quick Preview**: The theme switcher shows a color preview in the selection menu

2. **Keyboard Shortcuts**: 
   - In theme switcher: `j/k` or arrows to navigate
   - `/` to search for a theme name

3. **Default Theme**: Gruvbox Material is the default if no theme is selected

4. **Check Current Theme**: 
   ```bash
   cat ~/.config/dotfiles/current-theme
   ```

## 🛠️ Troubleshooting

**Theme not showing?**
```bash
# Reinstall vim plugins
vim +PlugInstall +qall

# Reload shell
exec $SHELL
```

**Want to reset?**
```bash
rm ~/.config/dotfiles/current-theme
rm ~/.vim/theme.vim
rm ~/.tmux/theme.conf
rm ~/.config/dotfiles/theme.sh
```

Then run `theme-switch` to select a fresh theme.

---

For detailed documentation, see [Theme System Documentation](./theme-system.md)