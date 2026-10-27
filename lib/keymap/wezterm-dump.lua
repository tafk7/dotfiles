-- Run configs/wezterm.lua under `nvim -l` with a stand-in `wezterm` module and
-- print config.keys as MODS<TAB>KEY<TAB>ACTION lines (to stderr, as nvim -l does).
local act = setmetatable({}, {
  __index = function(_, name)
    return setmetatable({ __act = name }, {
      __call = function(_, arg) return { __act = name, arg = arg } end,
    })
  end,
})
local anything = setmetatable({}, {
  __index = function() return function() return {} end end,
  __call = function() return {} end,
})
local stub = setmetatable({
  action = act,
  config_builder = function() return {} end,
  action_callback = function() return { __act = 'callback' } end,
  on = function() end,
  target_triple = 'x86_64-pc-windows-msvc',
  home_dir = '/home/user',
}, { __index = function() return anything end })
package.preload.wezterm = function() return stub end

local config = dofile(arg[1])

local function show(a)
  if type(a) ~= 'table' then return tostring(a) end
  local s = a.__act or '?'
  if type(a.arg) == 'string' then
    s = s .. '(' .. string.format('%q', a.arg):gsub('\\\n', '\\n') .. ')'
  elseif type(a.arg) == 'table' and a.arg.key then
    s = s .. '(' .. (a.arg.mods or '') .. '+' .. a.arg.key .. ')'
  elseif a.arg ~= nil then
    s = s .. '(' .. vim.inspect(a.arg):gsub('%s+', ' ') .. ')'
  end
  return s
end

for _, k in ipairs(config.keys or {}) do
  print(('%s\t%s\t%s'):format(k.mods or 'NONE', k.key, show(k.action)))
end
print('disable_default_key_bindings\t' .. tostring(config.disable_default_key_bindings))
