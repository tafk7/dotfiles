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
config.default_prog = { 'powershell.exe', '-NoLogo' } -- instead of cmd.exe
-- The new-tab menu (right-click +) lists domains, where a tab runs (local,
-- WSL, SSH hosts); PowerShell is what the local one starts, so it gets an
-- entry of its own there.
config.launch_menu = {
  { label = 'PowerShell', args = { 'powershell.exe', '-NoLogo' } },
}
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

-- Shift bypasses application/tmux mouse reporting and invokes WezTerm's
-- default native-selection bindings. Those bindings copy completed selections
-- to ClipboardAndPrimarySelection, including words on double-click and lines
-- on triple-click. Alt remains available to tmux for its selection gestures.
config.bypass_mouse_reporting_modifiers = 'SHIFT'

-- Deliberately leave colors unset. WezTerm supplies its normal client palette,
-- while remote shells, tmux, editors, and other applications emit their own
-- ANSI/truecolor styling.

-- ---------------------------------------------------------------------------
-- Image paste over SSH
-- ---------------------------------------------------------------------------

-- An SSH session carries only text, and remote TUIs (Claude Code's Ctrl+V)
-- read the server's clipboard, so a Windows clipboard image never arrives.
-- Ctrl+Alt+V bridges it (Alt+V is tmux's compose pane): save the clipboard
-- image to a temp PNG, copy it to the tab's SSH host, and paste the remote
-- path, which Claude Code attaches as an image. The host is read from the
-- tab's foreground `ssh` command line; PASTE_FALLBACK_HOST covers tabs where
-- that fails. Uploads run with BatchMode, so plain `ssh <host>` must already
-- authenticate without a prompt.
local PASTE_FALLBACK_HOST = nil -- e.g. 'moonspawn'
local PASTE_REMOTE_DIR = '.cache/wezterm-paste' -- relative to remote $HOME
local PASTE_KEEP_DAYS = 7

-- ssh options that consume the following argument.
local SSH_VALUE_OPTS = 'BbcDEeFIiJLlmOoPpQRSWw'

local function ssh_host_of(pane)
  local info = pane:get_foreground_process_info()
  if not info or not info.argv then
    return nil
  end
  local name = (info.name or ''):lower()
  if name ~= 'ssh.exe' and name ~= 'ssh' then
    return nil
  end
  local argv, i = info.argv, 2
  while i <= #argv do
    local arg = argv[i]
    if arg == '--' then
      return argv[i + 1]
    elseif arg:sub(1, 1) == '-' then
      -- Flags may be bundled (-tA). A value-taking flag consumes the rest of
      -- the word, or the next argument when it ends the word (-p 22).
      for j = 2, #arg do
        if SSH_VALUE_OPTS:find(arg:sub(j, j), 1, true) then
          if j == #arg then
            i = i + 1
          end
          break
        end
      end
    else
      return arg
    end
    i = i + 1
  end
  return nil
end

local function paste_clipboard_image(window, pane)
  local function fail(msg)
    window:toast_notification('Image paste', msg, nil, 5000)
  end

  local host = ssh_host_of(pane) or PASTE_FALLBACK_HOST
  if not host then
    return fail('No SSH host for this tab (set PASTE_FALLBACK_HOST).')
  end

  local name = os.date('clip-%Y%m%d-%H%M%S-') .. math.random(1000, 9999) .. '.png'
  local local_path = os.getenv('TEMP') .. '\\' .. name
  local save = table.concat({
    'Add-Type -AssemblyName System.Windows.Forms, System.Drawing',
    '$img = [System.Windows.Forms.Clipboard]::GetImage()',
    'if ($null -eq $img) { exit 3 }',
    "$img.Save('" .. local_path:gsub("'", "''") .. "', [System.Drawing.Imaging.ImageFormat]::Png)",
  }, '; ')
  if not wezterm.run_child_process {
    'powershell.exe', '-NoProfile', '-NonInteractive', '-STA', '-Command', save,
  } then
    return fail('Clipboard has no image.')
  end

  -- Private upload dir; prune old pastes; print the absolute path to paste.
  -- ClearAllForwardings: the host's LocalForward (viz) belongs to the tab's
  -- session, not to this command (scp clears forwards by itself).
  local ok, remote_dir, err = wezterm.run_child_process {
    'ssh', '-o', 'BatchMode=yes', '-o', 'ClearAllForwardings=yes', host,
    string.format(
      'umask 077 && mkdir -p %s && find %s -type f -mtime +%d -delete && cd %s && pwd',
      PASTE_REMOTE_DIR, PASTE_REMOTE_DIR, PASTE_KEEP_DAYS, PASTE_REMOTE_DIR
    ),
  }
  remote_dir = (remote_dir or ''):gsub('%s+$', '')
  if ok and remote_dir ~= '' then
    local remote_path = remote_dir .. '/' .. name
    ok, _, err = wezterm.run_child_process {
      'scp', '-q', '-o', 'BatchMode=yes', local_path, host .. ':' .. remote_path,
    }
    if ok then
      pane:paste(remote_path)
    end
  end
  os.remove(local_path)
  if not ok then
    fail('Upload to ' .. host .. ' failed: ' .. (err or ''):gsub('%s+$', ''))
  end
end

-- ---------------------------------------------------------------------------
-- Keyboard
-- ---------------------------------------------------------------------------

-- Start from an explicit small client keymap. In particular, this prevents
-- WezTerm pane shortcuts and Ctrl+C/Ctrl+V from competing with tmux and TUIs.
config.disable_default_key_bindings = true

config.keys = {
  -- Top-level tabs: usually one per SSH machine, rarely more than a few, so
  -- one key cycles them (with two, it toggles). Alt is tmux's.
  {
    key = 'a',
    mods = 'CTRL|SHIFT',
    action = act.ActivateTabRelative(1),
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
    -- Always a local PowerShell tab, even from a tab opened on an SSH domain.
    action = act.SpawnTab 'DefaultDomain',
  },
  {
    key = 'n',
    mods = 'CTRL|SHIFT',
    action = act.SpawnWindow,
  },

  -- Native Windows clipboard. Ctrl+C/Ctrl+V remain available to applications.
  -- Mouse selections already copy on release, so the Copy key only copies a
  -- WezTerm selection made otherwise. With none, it goes to tmux, which copies
  -- its copy-mode selection or hands the key to Claude.
  {
    key = 'Insert',
    mods = 'CTRL',
    action = wezterm.action_callback(function(window, pane)
      if window:get_selection_text_for_pane(pane) ~= '' then
        window:perform_action(act.CopyTo 'Clipboard', pane)
      else
        window:perform_action(act.SendKey { key = 'Insert', mods = 'CTRL' }, pane)
      end
    end),
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
  -- Clipboard image -> upload to the tab's SSH host -> paste its remote path.
  {
    key = 'v',
    mods = 'CTRL|ALT',
    action = wezterm.action_callback(paste_clipboard_image),
  },

  -- Ctrl+Shift+S as an extended key (xterm modifyOtherKeys), so it reaches
  -- applications apart from Ctrl+S: the compose pane stages a prompt with it.
  {
    key = 's',
    mods = 'CTRL|SHIFT',
    action = act.SendString '\x1b[27;6;83~',
  },
  -- Ctrl+Shift+E/D/F likewise: in tmux review, Ctrl+Shift+E/S/D/F extend the
  -- selection by a prompt or a word. WezTerm's own search is gone from
  -- Ctrl+Shift+F: under tmux it sees only the screen, and review searches the
  -- whole conversation.
  {
    key = 'e',
    mods = 'CTRL|SHIFT',
    action = act.SendString '\x1b[27;6;69~',
  },
  {
    key = 'd',
    mods = 'CTRL|SHIFT',
    action = act.SendString '\x1b[27;6;68~',
  },
  {
    key = 'f',
    mods = 'CTRL|SHIFT',
    action = act.SendString '\x1b[27;6;70~',
  },
  -- Ctrl+Shift+Tab likewise, for the program in the pane (OpenCode's previous
  -- session tab), not WezTerm's tabs.
  {
    key = 'Tab',
    mods = 'CTRL|SHIFT',
    action = act.SendString '\x1b[27;6;9~',
  },

  -- Shift + Copy: tmux copies the agent's last reply (prefix+y).
  {
    key = 'Insert',
    mods = 'CTRL|SHIFT',
    action = act.SendString '\x1b[2;6~',
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

  -- ScrollLock and Pause, by Windows key code: WezTerm has no names for them,
  -- but offers every key to its bindings by code before it names it.
  -- ScrollLock reviews the pane (Shift+F5 to tmux), with Shift reviews and
  -- searches (Shift+F7); Pause, the Break key, stops whatever runs (Shift+F9).
  -- Shift+F keys, clear of the Shift+F1-F4 cut transport above.
  {
    key = 'raw:145',
    mods = 'NONE',
    action = act.SendString '\x1b[15;2~',
  },
  {
    key = 'raw:145',
    mods = 'SHIFT',
    action = act.SendString '\x1b[18;2~',
  },
  {
    key = 'raw:19',
    mods = 'NONE',
    action = act.SendString '\x1b[20;2~',
  },

  -- Client utilities retained from the Windows Terminal surface.
  {
    key = 'p',
    mods = 'CTRL|SHIFT',
    action = act.ActivateCommandPalette,
  },
  {
    key = 'F11',
    mods = 'NONE',
    action = act.ToggleFullScreen,
  },
  -- Fullscreen and font size on Ctrl+Shift, WezTerm's modifier, so Alt+Enter,
  -- Ctrl+- and Ctrl+0 reach the programs. Physical keys, so Shift keeps the
  -- digit and the punctuation from turning into ) _ +.
  {
    key = 'Enter',
    mods = 'CTRL|SHIFT',
    action = act.ToggleFullScreen,
  },
  {
    key = 'phys:Equal',
    mods = 'CTRL|SHIFT',
    action = act.IncreaseFontSize,
  },
  {
    key = 'phys:Minus',
    mods = 'CTRL|SHIFT',
    action = act.DecreaseFontSize,
  },
  {
    key = 'phys:0',
    mods = 'CTRL|SHIFT',
    action = act.ResetFontSize,
  },
}

return config
