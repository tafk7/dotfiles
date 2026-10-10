-- The review popup (bin/tmux-review open): a pane's history, read-only. Loaded
-- only when NVIM_REVIEW is set, so this nvim exists just for the popup and the
-- mappings can be global. E/S/D/F move like the arrows, as in tmux review; q
-- closes the popup. Yanks reach the clipboard through tmux, like any nvim yank.
for lhs, rhs in pairs({ e = 'k', s = 'h', d = 'j', f = 'l' }) do
  vim.keymap.set({ 'n', 'x', 'o' }, lhs, rhs)
end
vim.keymap.set('n', 'q', '<Cmd>qall!<CR>')
