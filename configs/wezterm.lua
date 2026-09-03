-- TAFK WezTerm configuration for Windows.
-- Copy to: %USERPROFILE%\.wezterm.lua
--
-- WezTerm owns top-level tabs, the Windows clipboard, and presentation.
-- Tmux owns remote sessions, windows, panes, layouts, and scrollback.

local wezterm = require 'wezterm'
local act = wezterm.action

local config = wezterm.config_builder()

-- ---------------------------------------------------------------------------
-- Rendering and terminal behavior
-- ---------------------------------------------------------------------------

config.term = 'xterm-256color'
config.automatically_reload_config = true
config.scrollback_lines = 5000 -- tmux keeps the long 50k-line history
config.enable_scroll_bar = false
config.audible_bell = 'Disabled'
config.window_close_confirmation = 'AlwaysPrompt'

-- Preserve a simple client tab layer; tmux handles all pane splitting.
config.enable_tab_bar = true
config.hide_tab_bar_if_only_one_tab = true
config.use_fancy_tab_bar = false
config.tab_max_width = 32

-- Shift bypasses application/tmux mouse reporting for native client selection.
-- Alt remains available to tmux for Alt+drag selection.
config.bypass_mouse_reporting_modifiers = 'SHIFT'
config.copy_on_select = false

-- Avoid client opacity or a default scheme overriding the dotfiles palette.
config.window_background_opacity = 1.0
config.text_background_opacity = 1.0
config.bold_brightens_ansi_colors = false

-- Gruvbox Material palette matching themes/gruvbox.
config.colors = {
  foreground = '#d4be98',
  background = '#282828',
  cursor_bg = '#d4be98',
  cursor_fg = '#282828',
  cursor_border = '#d4be98',
  selection_fg = '#d4be98',
  selection_bg = '#504945',
  scrollbar_thumb = '#504945',
  split = '#504945',

  ansi = {
    '#282828',
    '#ea6962',
    '#a9b665',
    '#d8a657',
    '#7daea3',
    '#d3869b',
    '#89b482',
    '#d4be98',
  },
  brights = {
    '#928374',
    '#ea6962',
    '#a9b665',
    '#d8a657',
    '#7daea3',
    '#d3869b',
    '#89b482',
    '#d4be98',
  },

  tab_bar = {
    background = '#1b1b1b',
    active_tab = {
      bg_color = '#3c3836',
      fg_color = '#d4be98',
      intensity = 'Bold',
    },
    inactive_tab = {
      bg_color = '#282828',
      fg_color = '#a89984',
    },
    inactive_tab_hover = {
      bg_color = '#504945',
      fg_color = '#d4be98',
    },
    new_tab = {
      bg_color = '#282828',
      fg_color = '#a89984',
    },
    new_tab_hover = {
      bg_color = '#504945',
      fg_color = '#d4be98',
    },
  },
}

-- ---------------------------------------------------------------------------
-- Keyboard
-- ---------------------------------------------------------------------------

-- Start from an explicit small client keymap. In particular, this prevents
-- WezTerm pane shortcuts and Ctrl+C/Ctrl+V from competing with tmux and TUIs.
config.disable_default_key_bindings = true

config.keys = {
  -- Top-level tabs: usually one per SSH machine.
  {
    key = 'a',
    mods = 'ALT',
    action = act.ActivateTabRelative(1),
  },
  {
    key = '1',
    mods = 'CTRL',
    action = act.ActivateTab(0),
  },
  {
    key = '2',
    mods = 'CTRL',
    action = act.ActivateTab(1),
  },
  {
    key = 'PageUp',
    mods = 'CTRL|SHIFT',
    action = act.MoveTabRelative(-1),
  },
  {
    key = 'PageDown',
    mods = 'CTRL|SHIFT',
    action = act.MoveTabRelative(1),
  },
  {
    key = 't',
    mods = 'CTRL|SHIFT',
    action = act.SpawnTab 'CurrentPaneDomain',
  },
  {
    key = 'n',
    mods = 'CTRL|SHIFT',
    action = act.SpawnWindow,
  },

  -- Native Windows clipboard. Ctrl+C/Ctrl+V remain available to applications.
  {
    key = 'Insert',
    mods = 'CTRL',
    action = act.CopyTo 'Clipboard',
  },
  {
    key = 'Insert',
    mods = 'SHIFT',
    action = act.PasteFrom 'Clipboard',
  },
  {
    key = 'c',
    mods = 'CTRL|SHIFT',
    action = act.CopyTo 'Clipboard',
  },
  {
    key = 'v',
    mods = 'CTRL|SHIFT',
    action = act.PasteFrom 'Clipboard',
  },

  -- Alt + the keyboard's physical Copy/Paste macros belongs to tmux.
  {
    key = 'Insert',
    mods = 'CTRL|ALT',
    action = act.SendString '\x1b[2;7~',
  },
  {
    key = 'Insert',
    mods = 'ALT|SHIFT',
    action = act.SendString '\x1b[2;4~',
  },

  -- Shift-cut transport. Bash/zsh map these virtual F13-F16 sequences to
  -- word/line cuts that publish the removed text to the tmux buffer.
  {
    key = 'Backspace',
    mods = 'CTRL|SHIFT',
    action = act.SendString '\x1b[1;2P',
  },
  {
    key = 'Delete',
    mods = 'CTRL|SHIFT',
    action = act.SendString '\x1b[1;2Q',
  },
  {
    key = 'Backspace',
    mods = 'ALT|SHIFT',
    action = act.SendString '\x1b[1;2R',
  },
  {
    key = 'Delete',
    mods = 'ALT|SHIFT',
    action = act.SendString '\x1b[1;2S',
  },

  -- Client utilities retained from the Windows Terminal surface.
  {
    key = 'p',
    mods = 'CTRL|SHIFT',
    action = act.ActivateCommandPalette,
  },
  {
    key = 'f',
    mods = 'CTRL|SHIFT',
    action = act.Search 'CurrentSelectionOrEmptyString',
  },
  {
    key = 'F11',
    mods = 'NONE',
    action = act.ToggleFullScreen,
  },
  {
    key = 'Enter',
    mods = 'ALT',
    action = act.ToggleFullScreen,
  },
  {
    key = '=',
    mods = 'CTRL',
    action = act.IncreaseFontSize,
  },
  {
    key = '+',
    mods = 'CTRL|SHIFT',
    action = act.IncreaseFontSize,
  },
  {
    key = '-',
    mods = 'CTRL',
    action = act.DecreaseFontSize,
  },
  {
    key = '0',
    mods = 'CTRL',
    action = act.ResetFontSize,
  },
}

return config
