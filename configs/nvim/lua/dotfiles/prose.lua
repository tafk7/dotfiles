-- Prose profile for the compose pane (bin/tmux-compose). Loaded only when
-- NVIM_PROSE is set, after the rest of the config, so ordinary nvim and
-- `git commit` are unchanged. Spelling, soft wrap, Markdown, grammar marks
-- from harper-ls when it is installed, and, with a target pane, the compose
-- keys. Dictionaries stay untracked: nvim's spellfile and Harper's own.
local target = vim.env.DOTFILES_COMPOSE_TARGET
local compose = (vim.env.DOTFILES_DIR or '') .. '/bin/tmux-compose'

vim.opt.spell = true
vim.opt.spelllang = 'en_us'
vim.opt.wrap = true
vim.opt.linebreak = true
vim.opt.textwidth = 0
vim.opt.number = false
vim.opt.relativenumber = false

-- Ctrl+L fixes the most recent misspelling and returns to where you were typing.
vim.keymap.set('i', '<C-l>', '<C-g>u<Esc>[s1z=`]a<C-g>u')

-- Grammar through the built-in LSP client (Neovim 0.11+).
if vim.fn.executable('harper-ls') == 1 and vim.lsp.config and vim.lsp.enable then
  vim.lsp.config('harper_ls', { cmd = { 'harper-ls', '--stdio' }, filetypes = { 'markdown' } })
  vim.lsp.enable('harper_ls')
end

local group = vim.api.nvim_create_augroup('dotfiles_prose', {})

-- Paste the draft into the target (send also submits it). On success the
-- draft is cleared; on failure it is kept and the reason shown.
local function deliver(action)
  vim.cmd('silent write')
  local output = vim.fn.system({ compose, action, target, vim.api.nvim_buf_get_name(0) })
  if vim.v.shell_error ~= 0 then
    vim.notify(vim.trim(output), vim.log.levels.ERROR)
    return
  end
  vim.api.nvim_buf_set_lines(0, 0, -1, false, {})
  vim.cmd('silent write')
end

local function forward(key)
  return function() vim.fn.system({ compose, 'forward', target, key }) end
end

local function compose_keys(buf)
  local map = function(modes, lhs, rhs)
    vim.keymap.set(modes, lhs, rhs, { buffer = buf, nowait = true })
  end
  map({ 'n', 'i' }, '<C-s>', function() deliver('send') end)
  -- Stage: paste without submitting. Ctrl+Shift+S needs the terminal to report
  -- it apart from Ctrl+S; configs/wezterm.lua sends it explicitly.
  map({ 'n', 'i' }, '<C-S-s>', function() deliver('stage') end)
  map('n', '<leader>s', function() deliver('stage') end)
  map({ 'n', 'i' }, '<PageUp>', forward('PPage'))
  map({ 'n', 'i' }, '<PageDown>', forward('NPage'))
  map({ 'n', 'i' }, '<C-Home>', forward('C-Home'))
  map({ 'n', 'i' }, '<C-End>', forward('C-End'))
  -- Autosave, so a killed pane loses nothing.
  vim.api.nvim_create_autocmd({ 'TextChanged', 'TextChangedI', 'InsertLeave' }, {
    group = group,
    buffer = buf,
    command = 'silent! update',
  })
end

vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufNewFile' }, {
  group = group,
  callback = function(args)
    vim.bo[args.buf].filetype = 'markdown'
    vim.b[args.buf].ale_enabled = 0
    if target and target ~= '' then
      compose_keys(args.buf)
    end
  end,
})

vim.api.nvim_create_autocmd('VimEnter', {
  group = group,
  once = true,
  callback = function()
    vim.cmd('normal! G')
    vim.cmd('startinsert!')
  end,
})
