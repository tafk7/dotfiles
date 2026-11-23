-- TAFK WezTerm configuration for Windows.
-- Copy to: %USERPROFILE%\.wezterm.lua
--
-- WezTerm owns top-level tabs, the Windows clipboard, and presentation.
-- Tmux owns remote sessions, windows, panes, layouts, and scrollback.

local wezterm = require 'wezterm'
local act = wezterm.action

local config = wezterm.config_builder()

-- This file's revision. With `SendEnv LC_TAFK_WEZTERM` in the Windows ssh
-- config's Host block, `dotfiles verify` on the host says when this copy is
-- out of date and needs copying again.
local CONFIG_REVISION = 'b77f26eccd08'
config.set_environment_variables = { LC_TAFK_WEZTERM = CONFIG_REVISION }

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
  -- ClearAllForwardings: forwards in the ssh config belong to the tab's
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
-- Downloads from the SSH host
-- ---------------------------------------------------------------------------

-- `dl FILE` on the host (bin/dl) stages a copy as ~/.cache/dl/<id>/<name> and
-- sets the user variable dl_fetch to "<id>/<name>"; this fetches it with scp
-- from the tab's SSH host into DL_DEST, never overwriting a file there. Only
-- that staging folder is fetched from, so output that sets the variable can't
-- reach any other file. Like the image paste, plain `ssh <host>` must
-- authenticate without a prompt.
local DL_DEST = nil -- nil: %USERPROFILE%\Downloads
local DL_REMOTE_DIR = '.cache/dl' -- relative to remote $HOME; bin/dl's STAGE_REL

local function staged_name(value)
  local id, name = (value or ''):match('^(%w+)/([%w%._%-]+)$')
  if not id or name:match('^%.+$') then
    return nil
  end
  return id .. '/' .. name, name
end

-- DIR\NAME, or DIR\STEM (n).EXT for the first n that is free.
local function free_path(dir, name)
  local stem, ext = name:match('^(.+)(%.[^.]+)$')
  if not stem then
    stem, ext = name, ''
  end
  local path, n = dir .. '\\' .. name, 1
  while true do
    local f = io.open(path, 'rb')
    if not f then
      return path
    end
    f:close()
    path = string.format('%s\\%s (%d)%s', dir, stem, n, ext)
    n = n + 1
  end
end

local function scp_staged(host, staged, dest)
  return wezterm.run_child_process {
    'scp', '-q', '-o', 'BatchMode=yes', host .. ':' .. DL_REMOTE_DIR .. '/' .. staged, dest,
  }
end

local function download_staged(window, pane, value)
  local staged, name = staged_name(value)
  if not staged then
    return
  end
  local host = ssh_host_of(pane) or PASTE_FALLBACK_HOST
  if not host then
    return window:toast_notification('dl', 'No SSH host for this tab (set PASTE_FALLBACK_HOST).', nil, 5000)
  end
  local dest = free_path(DL_DEST or (os.getenv('USERPROFILE') .. '\\Downloads'), name)
  local ok, _, err = scp_staged(host, staged, dest)
  if ok then
    window:toast_notification('dl', 'Saved ' .. dest, nil, 5000)
  else
    window:toast_notification('dl', 'Download from ' .. host .. ' failed: ' .. (err or ''):gsub('%s+$', ''), nil, 8000)
  end
end

-- Replacing this file with the SSH host's configs/wezterm.lua: from the
-- command palette, or `dl --wezterm` on the host, which stages it and sets the
-- user variable dl_config. A config is code that runs here, and any program
-- in a pane can set a user variable, so that way asks first. The previous
-- copy is kept as .bak, and WezTerm reloads the new one by itself.

-- Fetch the staged config to <config>.new; return its path and revision, or
-- nil and why not.
local function fetch_config(host, staged)
  local new = wezterm.config_file .. '.new'
  local ok, _, err = scp_staged(host, staged, new)
  local f = ok and io.open(new, 'rb')
  local text = f and f:read('a') or ''
  if f then
    f:close()
  end
  local revision = text:match("\nlocal CONFIG_REVISION = '(%x+)'\n")
  if revision then
    return new, revision
  end
  os.remove(new)
  if not ok then
    return nil, 'Download from ' .. host .. ' failed: ' .. (err or ''):gsub('%s+$', '')
  end
  return nil, 'The file from ' .. host .. ' has no CONFIG_REVISION stamp; kept the current one.'
end

-- Put NEW in place of the config, keeping the old one as .bak.
local function swap_config(new, revision)
  local target = wezterm.config_file
  local bak = target .. '.bak'
  os.remove(bak)
  if not os.rename(target, bak) then
    os.remove(new)
    return 'Could not move the current config aside to ' .. bak .. '.'
  end
  if not os.rename(new, target) then
    os.rename(bak, target)
    return 'Could not put the new config in place; kept the current one.'
  end
  return 'Updated ' .. CONFIG_REVISION .. ' -> ' .. revision .. '; the previous copy is ' .. bak .. '.'
end

local function install_config(window, pane, host, staged, ask)
  local function say(msg)
    window:toast_notification('WezTerm config', msg, nil, 8000)
  end
  local new, revision = fetch_config(host, staged)
  if not new then
    return say(revision)
  end
  if revision == CONFIG_REVISION then
    os.remove(new)
    return say('Already current (' .. revision .. ').')
  end
  if not ask then
    return say(swap_config(new, revision))
  end
  window:perform_action(act.InputSelector {
    title = 'WezTerm config from ' .. host,
    description = string.format(
      '%s sent its WezTerm config (%s). Replace %s (%s) with it? The current copy is kept as .bak.',
      host, revision, wezterm.config_file, CONFIG_REVISION
    ),
    choices = {
      { id = 'yes', label = 'Replace it with ' .. host .. "'s (" .. revision .. ')' },
      { id = 'no', label = 'Keep this one' },
    },
    action = wezterm.action_callback(function(_, _, id)
      if id == 'yes' then
        say(swap_config(new, revision))
      else
        os.remove(new)
        say('Kept the current config (' .. CONFIG_REVISION .. ').')
      end
    end),
  }, pane)
end

-- `dl --wezterm` on the host: dl_config names the staged configs/wezterm.lua.
local function offer_config(window, pane, value)
  local staged, name = staged_name(value)
  if not staged or name ~= 'wezterm.lua' then
    return
  end
  local host = ssh_host_of(pane) or PASTE_FALLBACK_HOST
  if not host then
    return window:toast_notification('WezTerm config', 'No SSH host for this tab (set PASTE_FALLBACK_HOST).', nil, 8000)
  end
  install_config(window, pane, host, staged, true)
end

-- Command palette: the palette is the confirmation, so no question.
-- `dl --wezterm-config` on the host stages the file and prints its name.
local function update_config_from_host(window, pane)
  local host = ssh_host_of(pane) or PASTE_FALLBACK_HOST
  if not host then
    return window:toast_notification('WezTerm config', 'No SSH host for this tab (set PASTE_FALLBACK_HOST).', nil, 8000)
  end
  local ok, out, err = wezterm.run_child_process {
    'ssh', '-o', 'BatchMode=yes', '-o', 'ClearAllForwardings=yes', host, 'bash -lc "dl --wezterm-config"',
  }
  -- A login shell may print first; the staged name is the last line.
  local staged = staged_name((out or ''):match('([^\r\n]+)[\r\n]*$'))
  if not ok or not staged then
    return window:toast_notification('WezTerm config',
      'Could not stage it on ' .. host .. ': ' .. (err or ''):gsub('%s+$', ''), nil, 8000)
  end
  install_config(window, pane, host, staged, false)
end

-- ---------------------------------------------------------------------------
-- Uploads to the SSH host
-- ---------------------------------------------------------------------------

-- `up [WINPATH [DEST]]` on the host (bin/up) makes a private slot
-- ~/.cache/up/<id> and sets the user variable up_request to
-- "<id>\n<WINPATH>\n<host:DEST>". Any program in a pane can set it, so nothing
-- leaves this computer unless you confirm the file shown, or pick one. Then
-- this scps it into the slot, and last a .status file (ok, cancel or
-- "fail: why") that up waits for before moving the file to DEST.
local UP_SOURCE = nil -- nil: %USERPROFILE%\Downloads, for bare names and the picker
local UP_REMOTE_DIR = '.cache/up' -- relative to remote $HOME; bin/dl's UP_REL

local function up_source_dir()
  return UP_SOURCE or (os.getenv('USERPROFILE') .. '\\Downloads')
end

-- The full path WINPATH names, or nil and why not: C:\x or C:/x as is, ~\x in
-- the home folder, anything else in UP_SOURCE. Never a network or device path
-- (opening one would already reach out), and no . or .. so what the question
-- shows is the file sent.
local function up_resolve(src)
  local p = src:gsub('/', '\\')
  if p:match('^\\\\') then
    return nil, 'Network and device paths are not uploaded: ' .. src
  end
  if p == '~' or p:match('^~\\') then
    p = os.getenv('USERPROFILE') .. p:sub(2)
  elseif not p:match('^%a:\\') then
    if p:match('^\\') or p:match('^%a:') then
      return nil, 'Give a full path, like C:\\Users\\you\\file: ' .. src
    end
    p = up_source_dir() .. '\\' .. p
  end
  p = p:gsub('\\+', '\\')
  for seg in p:gmatch('[^\\]+') do
    if seg == '.' or seg == '..' then
      return nil, 'No . or .. in the path: ' .. src
    end
  end
  return p
end

local function file_size(path)
  local f = io.open(path, 'rb')
  local size = f and f:seek('end')
  if f then
    f:close()
  end
  return size
end

local function human_size(n)
  for _, unit in ipairs { 'B', 'KB', 'MB', 'GB' } do
    if n < 1024 or unit == 'GB' then
      return (unit == 'B' and '%d %s' or '%.1f %s'):format(n, unit)
    end
    n = n / 1024
  end
end

-- What up reads last: TEXT as <slot>/.status on HOST.
local function up_status(host, id, text)
  local tmp = (os.getenv('TEMP') or os.getenv('USERPROFILE')) .. '\\wezterm-up-' .. id .. '.status'
  local f = io.open(tmp, 'wb')
  if not f then
    return
  end
  f:write(text)
  f:close()
  wezterm.run_child_process {
    'scp', '-q', '-o', 'BatchMode=yes', tmp, host .. ':' .. UP_REMOTE_DIR .. '/' .. id .. '/.status',
  }
  os.remove(tmp)
end

-- Up to 200 file names in DIR, newest first.
local function newest_files(dir)
  local ok, out = wezterm.run_child_process {
    'powershell.exe', '-NoProfile', '-NonInteractive', '-Command',
    '[Console]::OutputEncoding = [Text.Encoding]::UTF8; Get-ChildItem -File -LiteralPath '
      .. "'" .. dir:gsub("'", "''") .. "'"
      .. ' | Sort-Object LastWriteTime -Descending | Select-Object -First 200 -ExpandProperty Name',
  }
  local names = {}
  for line in ((ok and out) or ''):gmatch('[^\r\n]+') do
    table.insert(names, line)
  end
  return names
end

local function upload_requested(window, pane, value)
  local id, src, dest = (value or ''):match('^(%w+)\n([^\n]*)\n([^\n]*)$')
  if not id or #id ~= 12 then
    return
  end
  local function say(msg)
    window:toast_notification('up', msg, nil, 8000)
  end
  local host = ssh_host_of(pane) or PASTE_FALLBACK_HOST
  if not host then
    return say('No SSH host for this tab (set PASTE_FALLBACK_HOST); up times out.')
  end
  dest = dest:gsub('%c', ''):sub(1, 200)
  local function fail(why)
    up_status(host, id, 'fail: ' .. why)
    say(why)
  end
  local function send(path)
    local name = (path:match('([^\\]+)$') or ''):gsub('[^%w%._%-]', '_'):gsub('%.+$', '')
    local ok, _, err = wezterm.run_child_process {
      'scp', '-q', '-o', 'BatchMode=yes', path,
      host .. ':' .. UP_REMOTE_DIR .. '/' .. id .. '/' .. (name ~= '' and name or 'file'),
    }
    if not ok then
      return fail('Upload to ' .. host .. ' failed: ' .. (err or ''):gsub('%s+$', ''))
    end
    up_status(host, id, 'ok')
    say('Sent ' .. path .. ' to ' .. dest)
  end
  local function cancel()
    up_status(host, id, 'cancel')
  end

  if src == '' then
    local dir = up_source_dir()
    local choices = {}
    for _, name in ipairs(newest_files(dir)) do
      table.insert(choices, { id = name, label = name })
    end
    if #choices == 0 then
      return fail('No files in ' .. dir .. '.')
    end
    return window:perform_action(act.InputSelector {
      title = 'Upload to ' .. dest,
      description = 'Pick a file from ' .. dir .. ' to send to ' .. dest .. '. Esc cancels.',
      fuzzy = true,
      choices = choices,
      action = wezterm.action_callback(function(_, _, picked)
        if picked then
          send(dir .. '\\' .. picked)
        else
          cancel()
        end
      end),
    }, pane)
  end

  local path, why = up_resolve(src)
  local size = path and file_size(path)
  if not size then
    return fail(why or ('No such file: ' .. path))
  end
  window:perform_action(act.InputSelector {
    title = 'Upload to ' .. host,
    description = ('Send %s (%s) to %s?'):format(path, human_size(size), dest),
    choices = {
      { id = 'yes', label = 'Send it' },
      { id = 'no', label = 'Cancel' },
    },
    action = wezterm.action_callback(function(_, _, answer)
      if answer == 'yes' then
        send(path)
      else
        cancel()
      end
    end),
  }, pane)
end

-- ---------------------------------------------------------------------------
-- Port forwards for the remote shell tools
-- ---------------------------------------------------------------------------

-- Ctrl+Alt+P (P for ports) toggles a tunnel to the tab's SSH host for the
-- ports its shell tools serve (`forwards` on the host lists them; viz
-- today). tmux's ⇅ is lit while it is open, and `viz open` on the host opens
-- pages through it (below). The tunnel runs in the background, without a
-- console, and outlives WezTerm. A LocalForward for the same port in the
-- Windows ssh config stops it from starting. The host comes from the tab, as
-- for image paste, with the same PASTE_FALLBACK_HOST.
local FORWARD_WAIT_SECONDS = 8

-- The client ports Ctrl+Alt+P's tunnels forward, by host: the only ports a
-- page may be opened on. Kept across config reloads.
local function forwarded_ports()
  wezterm.GLOBAL.forwarded_ports = wezterm.GLOBAL.forwarded_ports or {}
  return wezterm.GLOBAL.forwarded_ports
end

local function forward_shell_tools(window, pane)
  local function fail(msg)
    window:toast_notification('Forward ports', msg, nil, 5000)
  end

  local host = ssh_host_of(pane) or PASTE_FALLBACK_HOST
  if not host then
    return fail('No SSH host for this tab (set PASTE_FALLBACK_HOST).')
  end
  -- The tunnel's command line goes through cmd.exe, so every part of it is
  -- checked against cmd's metacharacters.
  if not host:match('^[%w%.%-_@]+$') then
    return fail('Unexpected characters in the SSH host: ' .. host)
  end

  -- A login shell puts the dotfiles' bin on PATH. toggle closes open forwards
  -- and prints "closed", or lists them.
  local ok, out, err = wezterm.run_child_process {
    'ssh', '-o', 'BatchMode=yes', '-o', 'ClearAllForwardings=yes', host, 'bash -lc "forwards toggle"',
  }
  if ok and (out or ''):match('^closed') then
    forwarded_ports()[host] = nil
    return window:toast_notification('Forward ports', host .. ': closed', nil, 3000)
  end
  local forwards = {}
  for line in (out or ''):gmatch('[^\r\n]+') do
    local name, port, target = line:match('^([%w%-]+)\t(%d+)\t([%w%._%-/:]+)\t[^\t]+$')
    if name then
      table.insert(forwards, { name = name, port = port, target = target })
    end
  end
  if #forwards == 0 then
    return fail('No forwards from ' .. host .. ': ' .. (err or ''):gsub('%s+$', ''))
  end

  local tunnel = {
    'ssh', '-n', '-T', '-o', 'BatchMode=yes', '-o', 'ExitOnForwardFailure=yes',
    '-o', 'ServerAliveInterval=15', '-o', 'ServerAliveCountMax=3',
  }
  local ports, names, held = {}, {}, {}
  for _, f in ipairs(forwards) do
    table.insert(tunnel, '-L 127.0.0.1:' .. f.port .. ':' .. f.target)
    table.insert(ports, f.port)
    table.insert(names, f.name .. ' ' .. f.port)
    table.insert(held, f.name)
  end
  -- ssh joins the words after the host into the remote command. No double
  -- quotes: Windows quotes this argument for cmd.exe in a way cmd doesn't read.
  table.insert(tunnel, host .. " bash -lc 'forwards hold " .. table.concat(held, ' ') .. "' >NUL 2>&1")
  wezterm.background_child_process { 'cmd.exe', '/d', '/s', '/c', table.concat(tunnel, ' ') }

  -- Report once every port answers.
  local wait = table.concat({
    '$deadline = (Get-Date).AddSeconds(' .. FORWARD_WAIT_SECONDS .. ')',
    'foreach ($p in @(' .. table.concat(ports, ',') .. ')) { while ($true) {',
    '$c = New-Object Net.Sockets.TcpClient',
    "try { if ($c.ConnectAsync('127.0.0.1', $p).Wait(250)) { break } } catch {} finally { $c.Close() }",
    'if ((Get-Date) -gt $deadline) { exit 1 }',
    'Start-Sleep -Milliseconds 200 } }',
  }, '; ')
  if not wezterm.run_child_process { 'powershell.exe', '-NoProfile', '-NonInteractive', '-Command', wait } then
    return fail('The tunnel to ' .. host .. ' did not come up within ' .. FORWARD_WAIT_SECONDS .. ' s.')
  end
  forwarded_ports()[host] = ports
  local note = ok and '' or ('; ' .. (err or ''):gsub('%s+$', ''))
  window:toast_notification('Forward ports', host .. ': ' .. table.concat(names, ', ') .. note, nil, 4000)
end

-- `viz open` on the host sets the user variable viz_open to "PORT PATH" (a
-- sign-in path that lands on the page). Any program in a visible pane can
-- set one, so WezTerm builds the URL itself, from a port Ctrl+Alt+P forwards
-- and a path of URL characters only.
wezterm.on('user-var-changed', function(window, pane, name, value)
  if name == 'dl_fetch' then
    return download_staged(window, pane, value)
  end
  if name == 'dl_config' then
    return offer_config(window, pane, value)
  end
  if name == 'up_request' then
    return upload_requested(window, pane, value)
  end
  if name ~= 'viz_open' then
    return
  end
  local port, path = (value or ''):match('^(%d+) (/[%w%-%._~/%%?=&+:@!$,;]*)$')
  if path and path:sub(2, 2) == '/' then
    port = nil
  end
  local known = false
  for _, ports in pairs(forwarded_ports()) do
    for _, p in ipairs(ports) do
      known = known or p == port
    end
  end
  if not known then
    return window:toast_notification('viz', 'Port ' .. tostring(port) .. ' is not forwarded: press Ctrl+Alt+P.', nil, 5000)
  end
  wezterm.open_with('http://127.0.0.1:' .. port .. path)
end)

wezterm.on('augment-command-palette', function()
  return {
    { brief = 'Toggle the port forwards for shell tools (Ctrl+Alt+P)', action = wezterm.action_callback(forward_shell_tools) },
    { brief = "Update this WezTerm config from the tab's SSH host", action = wezterm.action_callback(update_config_from_host) },
  }
end)

-- ---------------------------------------------------------------------------
-- Keyboard
-- ---------------------------------------------------------------------------

-- Start from an explicit small client keymap. In particular, this prevents
-- WezTerm pane shortcuts and Ctrl+C/Ctrl+V from competing with tmux and TUIs.
config.disable_default_key_bindings = true

config.keys = {
  -- Top-level tabs: usually one per SSH machine, rarely more than a few, so
  -- one key cycles them (with two, it toggles); Ctrl+Shift+1..9, after this
  -- table, go to one by number. Alt is tmux's.
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
  -- Ctrl+Alt chords match the physical key, whatever the layout maps it to.
  {
    key = 'phys:V',
    mods = 'CTRL|ALT',
    action = wezterm.action_callback(paste_clipboard_image),
  },
  -- Toggle the tunnel for the tab's SSH host's shell tool ports.
  {
    key = 'phys:P',
    mods = 'CTRL|ALT',
    action = wezterm.action_callback(forward_shell_tools),
  },

  -- Ctrl+Shift+S as an extended key (xterm modifyOtherKeys), so it reaches
  -- applications apart from Ctrl+S: the compose pane stages a prompt with it.
  {
    key = 's',
    mods = 'CTRL|SHIFT',
    action = act.SendString '\x1b[27;6;83~',
  },
  -- Ctrl+Shift+E/D/F likewise: in tmux review, Ctrl+Shift+E/S/D/F extend the
  -- selection by a prompt or a word.
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

  -- ScrollLock and Pause, by Windows key code (WezTerm has no names for them).
  -- ScrollLock is tmux's review key (Shift+F5; with Shift, Shift+F7), off for
  -- now (configs/tmux-review.conf); Pause, the Break key, stops whatever runs
  -- (Shift+F9).
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

  -- Client utilities: the command palette, fullscreen and font size.
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

-- Ctrl+Shift+1..9 go straight to tab 1..9, by physical key like Ctrl+Shift+0
-- above. Ctrl+Shift+A still cycles.
for i = 1, 9 do
  table.insert(config.keys, {
    key = 'phys:' .. i,
    mods = 'CTRL|SHIFT',
    action = act.ActivateTab(i - 1),
  })
end

return config
