# Theme System Documentation

The dotfiles theme system provides a unified way to switch color schemes across vim, tmux, and shell environments with a single command.

## Overview

The theme system allows you to:
- Switch between multiple color schemes instantly
- Preview themes before applying them
- Maintain consistent colors across all terminal applications
- Easily add new themes

## Available Themes

### 1. **Nord** (`nord`)
A arctic, north-bluish clean and elegant theme based on the Nord color palette.
- Cool, muted colors with excellent readability
- Blue-grey tones with subtle accent colors
- Great for long coding sessions

### 2. **Kanagawa** (`kanagawa`)
Inspired by the famous painting "The Great Wave off Kanagawa" by Katsushika Hokusai.
- Warm, earthy tones with Japanese aesthetic
- Dark background with cream-colored text
- Distinctive purple and green accents

### 3. **Tokyo Night** (`tokyo-night`)
A clean, dark theme inspired by the lights of Tokyo at night.
- Modern dark theme with vibrant colors
- Purple and blue tones with pink accents
- Popular among modern developers

### 4. **Gruvbox Material** (`gruvbox-material`)
A modified version of Gruvbox with softer contrast.
- Retro groove colors with material design principles
- Warm color temperature
- Less aggressive than original Gruvbox

### 5. **Catppuccin Mocha** (`catppuccin-mocha`)
A soothing pastel theme with a dark background.
- Soft, pastel colors
- Excellent syntax highlighting
- Part of the Catppuccin family (other variants can be added)

## Usage

### Quick Start

1. **Switch themes interactively:**
   ```bash
   theme-switch
   ```
   This opens an interactive menu where you can:
   - Use arrow keys to navigate
   - Press Enter to preview a theme
   - Press Enter again to apply it
   - Press Esc to cancel

2. **List available themes:**
   ```bash
   themes
   ```

3. **Switch directly to a theme:**
   ```bash
   ~/dotfiles/scripts/theme-switcher.sh nord
   ```

### How It Works

When you switch themes, the system:
1. Creates/updates symlinks in your config directories:
   - `~/.vim/theme.vim` → Selected theme's vim configuration
   - `~/.tmux/theme.conf` → Selected theme's tmux configuration
   - `~/.config/dotfiles/theme.sh` → Selected theme's shell colors
2. Updates the theme preference in `~/.config/dotfiles/current-theme`
3. Automatically reloads configurations where possible

### Integration Points

#### Vim
- Theme is loaded dynamically from `~/.vim/theme.vim`
- Falls back to gruvbox-material if no theme is set
- All theme plugins are pre-installed via vim-plug
- Airline theme updates automatically

#### Tmux
- Theme is loaded from `~/.tmux/theme.conf`
- Includes status bar styling and pane borders
- Run `Ctrl-a r` to reload tmux config after switching

#### Shell (Bash/Zsh)
- Colors are loaded from `~/.config/dotfiles/theme.sh`
- Affects:
  - Command prompt colors
  - Git status indicators
  - Error/success symbols
  - Welcome message
- New shells automatically use the selected theme

#### FZF
- Each theme includes FZF color definitions
- Affects fuzzy finder appearance in all commands

## Adding New Themes

To add a new theme:

1. **Create theme directory:**
   ```bash
   mkdir -p ~/dotfiles/configs/themes/my-theme
   ```

2. **Create required files:**

   **vim.vim** - Vim configuration:
   ```vim
   " Set colorscheme
   try
       colorscheme my-theme
       let g:airline_theme='my_theme'
   catch
       colorscheme desert
   endtry
   ```

   **tmux.conf** - Tmux styling:
   ```bash
   # Status bar colors
   set -g status-style 'bg=#color1 fg=#color2'
   set -g window-status-current-style 'bg=#color3 fg=#color4 bold'
   # ... more styling
   ```

   **shell.sh** - Shell colors:
   ```bash
   # Export color variables for prompts
   export PROMPT_COLOR_USER='\[\e[38;5;108m\]'
   export PROMPT_COLOR_HOST='\[\e[38;5;214m\]'
   # ... more colors
   
   # FZF colors
   export FZF_DEFAULT_OPTS="$FZF_DEFAULT_OPTS \
   --color=bg+:#color1,bg:#color2,spinner:#color3"
   
   # Theme name for display
   export DOTFILES_THEME="My Theme"
   ```

   **colors.sh** - Preview colors (optional):
   ```bash
   # RGB values for theme preview
   export THEME_BG_R=30 THEME_BG_G=30 THEME_BG_B=30
   export THEME_FG_R=220 THEME_FG_G=220 THEME_FG_B=220
   # ... more color definitions
   ```

3. **Update theme-switcher.sh:**
   Add your theme to the `THEMES` array in the script.

4. **Install vim plugin (if needed):**
   Add to vimrc's plugin section:
   ```vim
   Plug 'author/my-theme-vim'
   ```

## Troubleshooting

### Theme not applying in vim
- Run `:PlugInstall` to ensure theme plugin is installed
- Check `:colorscheme` to see current theme
- Verify `~/.vim/theme.vim` exists and is readable

### Tmux colors not updating
- Reload tmux config: `Ctrl-a r`
- For full update: exit and restart tmux

### Shell prompt colors not changing
- Source your shell config: `source ~/.bashrc` or `source ~/.zshrc`
- Start a new shell session

### FZF colors not updating
- FZF colors are loaded when FZF starts
- Try a new FZF command or restart shell

## Technical Details

### File Structure
```
configs/themes/
├── nord/
│   ├── vim.vim      # Vim colorscheme and settings
│   ├── tmux.conf    # Tmux status bar and colors
│   ├── shell.sh     # Shell prompt and FZF colors
│   └── colors.sh    # RGB values for preview
├── kanagawa/
│   └── ...
└── .../

scripts/
└── theme-switcher.sh  # Main theme switching script
```

### Configuration Paths
- Current theme: `~/.config/dotfiles/current-theme`
- Vim theme: `~/.vim/theme.vim`
- Tmux theme: `~/.tmux/theme.conf`
- Shell theme: `~/.config/dotfiles/theme.sh`

### Dependencies
- `fzf` - For interactive theme selection
- `tput` - For terminal color preview
- Standard unix tools: `ln`, `mkdir`, `source`

## Tips

1. **Preview without applying:**
   In the theme switcher, press Enter once to preview, Esc to cancel

2. **Quick theme toggle:**
   Create aliases for your favorite themes:
   ```bash
   alias nord='theme-switch nord'
   alias tokyo='theme-switch tokyo-night'
   ```

3. **Match system theme:**
   Set theme based on system dark/light mode or time of day

4. **Per-project themes:**
   Use `.vimrc.local` to override theme for specific projects

## See Also

- [Vim Configuration](./vim-config.md)
- [Tmux Configuration](./tmux-config.md)
- [Shell Configuration](./shell-config.md)