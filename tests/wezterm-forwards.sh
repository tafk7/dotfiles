#!/bin/bash
# WezTerm's Ctrl+Alt+P against a fake wezterm module, run by Neovim's LuaJIT:
# the forwards query, the tunnel's arguments, the wait, and what it opens.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
NVIM_BIN="$(command -v nvim 2>/dev/null || true)"
[[ -n "$NVIM_BIN" ]] || { echo 'wezterm-forwards: skipped (nvim unavailable)'; exit 0; }

driver="$(mktemp)"
trap 'rm -f "$driver"' EXIT
cat > "$driver" <<'EOF'
local config_path = arg[1]
local calls, opened, toasts, background, palette

local function reset(forwards_out, forwards_ok, port_ok)
  calls, opened, toasts, background = {}, {}, {}, nil
  package.loaded.wezterm = {
    config_builder = function() return {} end,
    action = setmetatable({}, { __index = function(_, name)
      return setmetatable({ name = name }, { __call = function(self, a) return { name = self.name, arg = a } end })
    end }),
    action_callback = function(fn) return { callback = fn } end,
    on = function(event, fn) if event == 'augment-command-palette' then palette = fn end end,
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

-- Two tools: one tunnel with both forwards, then the pages that have a URL.
local config = reset('viz\t21001\t/run/user/1001/viz/http.sock\thttp://127.0.0.1:21001/__viz/login?code=x\r\n'
  .. 'other\t21002\tlocalhost:8080\t-\n', true, true)
press(config)
local query = calls[1]
if not (query[1] == 'ssh' and has(query, 'BatchMode=yes') and has(query, 'ClearAllForwardings=yes')
        and query[#query - 1] == 'devbox' and query[#query] == 'bash -lc "forwards --open"') then
  fail('forwards query: ' .. table.concat(query, ' '))
end
if not background then fail('no tunnel started') end
local tunnel = table.concat(background, ' ')
for _, want in ipairs({ '-N', 'ExitOnForwardFailure=yes', 'BatchMode=yes', 'ServerAliveInterval=15',
                        '127.0.0.1:21001:/run/user/1001/viz/http.sock', '127.0.0.1:21002:localhost:8080' }) do
  if not has(background, want) then fail('tunnel lacks ' .. want .. ': ' .. tunnel) end
end
if has(background, 'ClearAllForwardings=yes') then fail('the tunnel clears its own forwards: ' .. tunnel) end
if background[#background] ~= 'devbox' then fail('tunnel host: ' .. tunnel) end
if not (calls[2] and calls[2][1] == 'powershell.exe' and calls[2][#calls[2]]:find('@(21001,21002)', 1, true)) then
  fail('no wait for both ports')
end
if #opened ~= 1 or opened[1] ~= 'http://127.0.0.1:21001/__viz/login?code=x' then
  fail('opened: ' .. table.concat(opened, ' '))
end
if not (toasts[1] or ''):find('devbox: viz 21001, other 21002', 1, true) then fail('toast: ' .. tostring(toasts[1])) end

-- One tool failing still forwards the rest, and the toast says what failed.
press(reset('viz\t21001\t/s\thttp://127.0.0.1:21001/\n', false, true))
if not background or #opened ~= 1 or not (toasts[1] or ''):find('viz forward failed', 1, true) then
  fail('partial failure: ' .. tostring(toasts[1]))
end

-- Nothing to forward: no tunnel, no page.
press(reset('', false, true))
if background or #opened ~= 0 or not (toasts[1] or ''):find('No forwards from devbox', 1, true) then
  fail('empty forwards: ' .. tostring(toasts[1]))
end

-- Ports that never answer: no page.
press(reset('viz\t21001\t/s\thttp://127.0.0.1:21001/\n', true, false))
if #opened ~= 0 or not (toasts[1] or ''):find('did not come up', 1, true) then
  fail('dead tunnel: ' .. tostring(toasts[1]))
end

-- The command palette lists it.
local entries = palette and palette() or {}
if not (entries[1] and entries[1].brief:find('Ctrl+Alt+P', 1, true) and entries[1].action.callback) then
  fail('no command palette entry')
end
EOF

"$NVIM_BIN" --headless --clean -l "$driver" "$ROOT/configs/wezterm.lua"
echo 'wezterm-forwards: ok'
