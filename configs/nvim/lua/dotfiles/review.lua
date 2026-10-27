-- The review popup (bin/tmux-review: prefix+o, and o in review): a conversation
-- or a pane's history, read-only. Loaded only when NVIM_REVIEW is set, so this
-- nvim exists just for the popup and the mappings can be global. The keys are
-- tmux review's (configs/tmux.conf, issues/scrollback-copy-compose.md §3.3):
--   e/s/d/f move like the arrows; E/S/D/F and Shift+arrows extend the
--     selection, starting one if needed; v starts or ends it
--   Ctrl+S/F and Ctrl+Left/Right move by word; Ctrl+E/D and Ctrl+Up/Down jump
--     to the previous or next prompt, the lines matching NVIM_REVIEW_PROMPT
--   / searches upward, ? downward, and n/N repeat in the search's direction
--   y or Copy (Ctrl+Insert) copies the selection and closes the popup; Esc
--     clears the selection, else closes; q closes
-- Yanks reach the clipboard through tmux, like any nvim yank.
local all = { 'n', 'x', 'o' }
local arrows = { e = 'k', s = 'h', d = 'j', f = 'l' }
for lhs, rhs in pairs(arrows) do
  vim.keymap.set(all, lhs, rhs)
  vim.keymap.set('n', lhs:upper(), 'v' .. rhs)
  vim.keymap.set('x', lhs:upper(), rhs)
end
for key, rhs in pairs({ Up = 'k', Left = 'h', Down = 'j', Right = 'l' }) do
  vim.keymap.set('n', '<S-' .. key .. '>', 'v' .. rhs)
  vim.keymap.set('x', '<S-' .. key .. '>', rhs)
end

vim.keymap.set(all, '<C-s>', 'b')
vim.keymap.set(all, '<C-f>', 'e')
vim.keymap.set(all, '<C-Left>', 'b')
vim.keymap.set(all, '<C-Right>', 'e')

local prompt = vim.env.NVIM_REVIEW_PROMPT or ''
local function jump(flags)
  return function()
    if prompt ~= '' then
      vim.fn.search(prompt, flags)
    end
  end
end
for _, lhs in ipairs({ '<C-e>', '<C-Up>' }) do
  vim.keymap.set({ 'n', 'x' }, lhs, jump('bW'))
end
for _, lhs in ipairs({ '<C-d>', '<C-Down>' }) do
  vim.keymap.set({ 'n', 'x' }, lhs, jump('W'))
end

vim.keymap.set({ 'n', 'x' }, '/', '?')
vim.keymap.set({ 'n', 'x' }, '?', '/')

vim.keymap.set('x', 'y', '"+y<Cmd>qall!<CR>')
vim.keymap.set('x', '<C-Insert>', '"+y<Cmd>qall!<CR>')
vim.keymap.set('n', '<Esc>', '<Cmd>qall!<CR>')
vim.keymap.set('n', 'q', '<Cmd>qall!<CR>')

vim.opt.linebreak = true
