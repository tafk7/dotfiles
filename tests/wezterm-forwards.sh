#!/bin/bash
# WezTerm's Ctrl+Alt+P against a fake wezterm module, run by Neovim's LuaJIT:
# the toggle query, the tunnel's command line and wait, and the user variable
# that `viz open` sets to open a page on a forwarded port, and only there.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NVIM_BIN="$(command -v nvim 2>/dev/null || true)"
[[ -n "$NVIM_BIN" ]] || { echo 'wezterm-forwards: skipped (nvim unavailable)'; exit 0; }

driver="$(mktemp)"
trap 'rm -f "$driver"' EXIT
cat > "$driver" <<'EOF'
local config_path = arg[1]
local calls, opened, toasts, background
local handlers, GLOBAL = {}, {}   -- GLOBAL outlives config reloads, as in WezTerm

local function reset(forwards_out, forwards_ok, port_ok)
  calls, opened, toasts, background = {}, {}, {}, nil
  package.loaded.wezterm = {
    GLOBAL = GLOBAL,
    config_builder = function() return {} end,
    action = setmetatable({}, { __index = function(_, name)
      return setmetatable({ name = name }, { __call = function(self, a) return { name = self.name, arg = a } end })
    end }),
    action_callback = function(fn) return { callback = fn } end,
    on = function(event, fn) handlers[event] = fn end,
    run_child_process = function(argv)
      table.insert(calls, argv)
      if argv[1] == 'ssh' then return forwards_ok, forwards_out, forwards_ok and '' or 'viz forward failed' end
      if argv[1] == 'powershell.exe' then return port_ok, '', '' end
      return false, '', 'unexpected'
    end,
    background_child_process = function(argv) background = argv end,
    open_with = function(url) table.insert(opened, url) end,
  }
  return dofile(config_path)
end

local function fail(msg) io.stderr:write('FAIL: ' .. msg .. '\n'); os.exit(1) end
local function has(list, value) for _, v in ipairs(list) do if v == value then return true end end return false end

local window = { toast_notification = function(_, title, msg) table.insert(toasts, msg) end }
local pane = { get_foreground_process_info = function()
  return { name = 'ssh.exe', argv = { 'ssh.exe', '-p', '22', 'devbox' } }
end }
local function press(config)
  for _, k in ipairs(config.keys) do
    if k.key == 'p' and k.mods == 'CTRL|ALT' then return k.action.callback(window, pane) end
  end
  fail('Ctrl+Alt+P is not bound')
end

-- Two tools: one tunnel with both forwards and a hold, then the pages that have a URL.
local config = reset('viz\t21001\t/run/user/1001/viz/http.sock\thttp://127.0.0.1:21001/__viz/login?code=x\r\n'
  .. 'other\t21002\tlocalhost:8080\t-\n', true, true)
press(config)
local query = calls[1]
if not (query[1] == 'ssh' and has(query, 'BatchMode=yes') and has(query, 'ClearAllForwardings=yes')
        and query[#query - 1] == 'devbox' and query[#query] == 'bash -lc "forwards toggle"') then
  fail('forwards query: ' .. table.concat(query, ' '))
end
if not background then fail('no tunnel started') end
if not (background[1] == 'cmd.exe' and has(background, '/s') and has(background, '/c')) then
  fail('tunnel not run through cmd /s /c: ' .. table.concat(background, ' '))
end
local line = background[#background]
for _, want in ipairs({ 'ssh -n -T ', 'ExitOnForwardFailure=yes', 'BatchMode=yes', 'ServerAliveInterval=15',
                        '-L 127.0.0.1:21001:/run/user/1001/viz/http.sock', '-L 127.0.0.1:21002:localhost:8080',
                        " devbox bash -lc 'forwards hold viz other' >NUL 2>&1" }) do
  if not line:find(want, 1, true) then fail('tunnel lacks ' .. want .. ': ' .. line) end
end
if line:find('"', 1, true) or line:find('ClearAllForwardings', 1, true) then fail('tunnel command: ' .. line) end
if not (calls[2] and calls[2][1] == 'powershell.exe' and calls[2][#calls[2]]:find('@(21001,21002)', 1, true)) then
  fail('no wait for both ports')
end
if #opened ~= 0 then fail('opening the tunnel opened ' .. table.concat(opened, ' ')) end
if not (toasts[1] or ''):find('devbox: viz 21001, other 21002', 1, true) then fail('toast: ' .. tostring(toasts[1])) end

-- `viz open` on the host: a page opens on a forwarded port, nothing else does.
local function viz_open(value, name)
  opened, toasts = {}, {}
  handlers['user-var-changed'](window, pane, name or 'viz_open', value)
end
viz_open('21001 /__viz/login?code=x&next=%2F2026-11-06%2Fa.html')
if opened[1] ~= 'http://127.0.0.1:21001/__viz/login?code=x&next=%2F2026-11-06%2Fa.html' then
  fail('viz open: ' .. table.concat(opened, ' '))
end
viz_open('9999 /')
if #opened ~= 0 or not (toasts[1] or ''):find('not forwarded', 1, true) then fail('opened an unforwarded port') end
for _, bad in ipairs({ '21001 //evil.example/', '21001 /a b', '21001 /x"&calc', '21001', 'x /' }) do
  viz_open(bad)
  if #opened ~= 0 then fail('opened ' .. opened[1] .. ' for ' .. bad) end
end
viz_open('21001 /', 'other_var')
if #opened ~= 0 then fail('acted on another user variable') end

-- Pressed while open: the host closed them; no tunnel, and no page opens there.
press(reset('closed\n', true, true))
if background or #opened ~= 0 or not (toasts[1] or ''):find('devbox: closed', 1, true) then
  fail('toggle off: ' .. tostring(toasts[1]))
end
viz_open('21001 /')
if #opened ~= 0 then fail('opened a page on a closed tunnel') end

-- A line with cmd.exe metacharacters is not a forward.
press(reset('viz\t21001\t/tmp/x&calc\thttp://127.0.0.1:21001/\n', true, true))
if background then fail('forwarded a target with & in it') end

-- One tool failing still forwards the rest, and the toast says what failed.
press(reset('viz\t21001\t/s\thttp://127.0.0.1:21001/\n', false, true))
if not background or not (toasts[1] or ''):find('viz forward failed', 1, true) then
  fail('partial failure: ' .. tostring(toasts[1]))
end

-- Nothing to forward: no tunnel, no page.
press(reset('', false, true))
if background or #opened ~= 0 or not (toasts[1] or ''):find('No forwards from devbox', 1, true) then
  fail('empty forwards: ' .. tostring(toasts[1]))
end

-- Ports that never answer: not recorded as forwarded.
GLOBAL.forwarded_ports = nil
press(reset('viz\t21001\t/s\thttp://127.0.0.1:21001/\n', true, false))
if not (toasts[1] or ''):find('did not come up', 1, true) then fail('dead tunnel: ' .. tostring(toasts[1])) end
viz_open('21001 /')
if #opened ~= 0 then fail('opened a page on a tunnel that never came up') end

-- The command palette lists it.
local entries = handlers['augment-command-palette'] and handlers['augment-command-palette']() or {}
if not (entries[1] and entries[1].brief:find('Ctrl+Alt+P', 1, true) and entries[1].action.callback) then
  fail('no command palette entry')
end
EOF

"$NVIM_BIN" --headless --clean -l "$driver" "$ROOT/configs/wezterm.lua"
echo 'wezterm-forwards: ok'
