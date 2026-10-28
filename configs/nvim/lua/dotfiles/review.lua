-- The review popup (bin/tmux-review: prefix+o, and o in review): a conversation
-- or a pane's history, read-only. Loaded only when NVIM_REVIEW is set, so this
-- nvim exists just for the popup and the mappings can be global. The keys are
-- tmux review's (configs/tmux.conf, issues/scrollback-copy-compose.md §3.3):
--   e/s/d/f move like the arrows
--   Ctrl+S/F and Ctrl+Left/Right move by word; Ctrl+E/D and Ctrl+Up/Down jump
--     to the previous or next prompt, the lines matching NVIM_REVIEW_PROMPT
--   Home/End go to the ends of the line, Ctrl+Home/End to the ends of the text
--   Shift added to any of those moves selects as it goes, starting a selection
--     if needed, and a move without Shift drops it, as in a Windows text box;
--     h instead starts a selection that plain moves extend, until h or Esc
--   Shift+PgUp/PgDn scroll a few lines (tmux's @scroll-lines, default 3)
--   / searches upward, ? downward, and n/N repeat in the search's direction
--   y or Copy (Ctrl+Insert) copies the selection and closes the popup; Esc
--     clears the selection, else closes; q closes
-- Yanks reach the clipboard through tmux, like any nvim yank.
local prompt = vim.env.NVIM_REVIEW_PROMPT or ''
local function jump(flags)
  return function()
    if prompt ~= '' then
      vim.fn.search(prompt, flags)
    end
  end
end
vim.keymap.set({ 'n', 'x', 'o' }, '<Plug>(review-prompt-up)', jump('bW'))
vim.keymap.set({ 'n', 'x', 'o' }, '<Plug>(review-prompt-down)', jump('W'))

-- A selection h started; plain moves extend it rather than drop it.
local toggled = false
vim.api.nvim_create_autocmd('ModeChanged', {
  callback = function()
    if not vim.v.event.new_mode:match('^[vV\22]') then
      toggled = false
    end
  end,
})
vim.keymap.set('n', 'h', function()
  toggled = true
  return 'v'
end, { expr = true })
vim.keymap.set('x', 'h', '<Esc>')

-- {plain, shifted, motion, shifted motion if not the same}
local moves = {
  { 'e', 'E', 'k' }, { 's', 'S', 'h' }, { 'd', 'D', 'j' }, { 'f', 'F', 'l' },
  { '<Up>', '<S-Up>', 'k' }, { '<Left>', '<S-Left>', 'h' },
  { '<Down>', '<S-Down>', 'j' }, { '<Right>', '<S-Right>', 'l' },
  { '<C-s>', '<C-S-s>', 'b' }, { '<C-f>', '<C-S-f>', 'e' },
  { '<C-Left>', '<C-S-Left>', 'b' }, { '<C-Right>', '<C-S-Right>', 'e' },
  { '<C-e>', '<C-S-e>', '<Plug>(review-prompt-up)' }, { '<C-d>', '<C-S-d>', '<Plug>(review-prompt-down)' },
  { '<C-Up>', '<C-S-Up>', '<Plug>(review-prompt-up)' }, { '<C-Down>', '<C-S-Down>', '<Plug>(review-prompt-down)' },
  { '<Home>', '<S-Home>', '0' }, { '<End>', '<S-End>', '$', 'g_' },
  { '<C-Home>', '<C-S-Home>', 'gg' }, { '<C-End>', '<C-S-End>', 'G' },
}
for _, m in ipairs(moves) do
  local plain, shifted, motion = m[1], m[2], m[3]
  local extend = m[4] or motion -- a selection to the end of the line stops short of its line break
  local remap = motion:match('^<Plug>') ~= nil
  vim.keymap.set({ 'n', 'o' }, plain, motion, { remap = remap })
  vim.keymap.set('x', plain, function()
    return (toggled and '' or '<Esc>') .. motion
  end, { expr = true, remap = remap })
  vim.keymap.set('n', shifted, function()
    toggled = false
    return 'v' .. extend
  end, { expr = true, remap = remap })
  vim.keymap.set('x', shifted, extend, { remap = remap })
end

local ok, setting = pcall(vim.fn.system, { 'tmux', 'show', '-gqv', '@scroll-lines' })
local lines = ok and tonumber(vim.trim(setting)) or 3
vim.keymap.set({ 'n', 'x' }, '<S-PageUp>', lines .. '<C-y>')
vim.keymap.set({ 'n', 'x' }, '<S-PageDown>', lines .. '<C-e>')

vim.keymap.set({ 'n', 'x' }, '/', '?')
vim.keymap.set({ 'n', 'x' }, '?', '/')

vim.keymap.set('x', 'y', '"+y<Cmd>qall!<CR>')
vim.keymap.set('x', '<C-Insert>', '"+y<Cmd>qall!<CR>')
vim.keymap.set('n', '<Esc>', '<Cmd>qall!<CR>')
vim.keymap.set('n', 'q', '<Cmd>qall!<CR>')

vim.opt.linebreak = true
