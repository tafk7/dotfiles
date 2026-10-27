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

local M = {}

-- The last misspelled word before the cursor (row 0-based), within the 50
-- lines above: {row, byte column, word}.
local function last_misspelling(row, col)
  for r = row, math.max(0, row - 50), -1 do
    local line = vim.api.nvim_buf_get_lines(0, r, r + 1, false)[1]
    if r == row then
      line = line:sub(1, col)
    end
    local found, offset = nil, 0
    while true do
      local bad = vim.fn.spellbadword(line:sub(offset + 1))[1]
      local start = bad ~= '' and line:find(bad, offset + 1, true)
      if not start then
        break
      end
      found, offset = { r, start - 1, bad }, start - 1 + #bad
    end
    if found then
      return found
    end
  end
end

-- Replace the last misspelling before the cursor with Vim's first suggestion.
local function spell_fix(row, col)
  local found = last_misspelling(row, col)
  local suggestion = found and vim.fn.spellsuggest(found[3], 1)[1]
  if not suggestion then
    return false
  end
  local r, c, word = found[1], found[2], found[3]
  vim.api.nvim_buf_set_text(0, r, c, r, c + #word, { suggestion })
  if r == row then
    vim.api.nvim_win_set_cursor(0, { row + 1, col + #suggestion - #word })
  end
  return true
end

-- Harper marks that start before the cursor (row 0-based), latest first.
local function marks_before(row, col)
  local marks = {}
  for _, d in ipairs(vim.diagnostic.get(0)) do
    local before = d.lnum < row or (d.lnum == row and d.col < col)
    if before and d.source == 'Harper' and d.user_data and d.user_data.lsp then
      table.insert(marks, d)
    end
  end
  table.sort(marks, function(a, b) return a.lnum > b.lnum or (a.lnum == b.lnum and a.col > b.col) end)
  return marks
end

local function buffer_text()
  return table.concat(vim.api.nvim_buf_get_lines(0, 0, -1, false), '\n')
end

-- Apply Harper's first suggested edit at MARK; true if the text changed. A
-- mark already fixed but not yet cleared can still offer its old edit, which
-- changes nothing, so the caller moves on to the next mark.
local function harper_fix(mark)
  local at = mark.user_data.lsp.range.start
  local params = {
    textDocument = vim.lsp.util.make_text_document_params(0),
    range = { start = at, ['end'] = at },
    context = { diagnostics = {} },
  }
  local responses = vim.lsp.buf_request_sync(0, 'textDocument/codeAction', params, 1000) or {}
  for client_id, response in pairs(responses) do
    local client = vim.lsp.get_client_by_id(client_id)
    if client and client.name == 'harper_ls' then
      for _, action in ipairs(response.result or {}) do
        -- Replacements carry an edit; "add to dictionary" and "ignore" are commands.
        if action.edit then
          local text = buffer_text()
          vim.lsp.util.apply_workspace_edit(action.edit, client.offset_encoding)
          return buffer_text() ~= text
        end
      end
    end
  end
  return false
end

-- Ctrl+L in insert mode: fix the latest problem before the cursor with
-- Harper's suggestion (spelling or grammar), else Vim's first spelling
-- suggestion, and keep typing where you were.
function M.fix_last()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  row = row - 1
  local before = #vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1]
  for _, mark in ipairs(marks_before(row, col)) do
    if harper_fix(mark) then
      if mark.lnum == row then
        local after = #vim.api.nvim_buf_get_lines(0, row, row + 1, false)[1]
        vim.api.nvim_win_set_cursor(0, { row + 1, math.max(0, col + after - before) })
      end
      return
    end
  end
  spell_fix(row, col)
end

vim.keymap.set('i', '<C-l>', '<C-g>u<Cmd>lua require("dotfiles.prose").fix_last()<CR><C-g>u')

-- Grammar through the built-in LSP client (Neovim 0.11+). harper-ls runs in
-- its own session, and left by a Neovim that quits without waiting it can
-- linger for good (2.12.0): on quit Neovim waits up to half a second for it,
-- then stops it.
if vim.fn.executable('harper-ls') == 1 and vim.lsp.config and vim.lsp.enable then
  vim.lsp.config('harper_ls', { cmd = { 'harper-ls', '--stdio' }, filetypes = { 'markdown' }, exit_timeout = 500 })
  vim.lsp.enable('harper_ls')
end

local group = vim.api.nvim_create_augroup('dotfiles_prose', {})

-- Paste the draft into the target (send also submits it). On success the
-- draft is cleared and the pane stays open; on failure it is kept and the
-- reason shown.
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

-- A pull from the agent's prompt box (tmux-compose, through the --listen
-- socket) appended to the draft on disk: reread it and continue after the
-- pulled text.
function M.reread()
  vim.cmd('silent! checktime')
  local last = vim.api.nvim_buf_line_count(0)
  vim.api.nvim_win_set_cursor(0, { last, #vim.api.nvim_buf_get_lines(0, last - 1, last, false)[1] })
  return ''
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
  -- Claude's Ctrl+G adds its prompt box to the draft on disk and asks this
  -- nvim, through its --listen socket, to reread it; focus rereads it too.
  vim.bo[buf].autoread = true
  vim.api.nvim_create_autocmd({ 'FocusGained', 'BufEnter' }, {
    group = group,
    buffer = buf,
    command = 'silent! checktime',
  })
end

-- Quitting (:q, :wq, ZZ) puts the draft back in the agent's prompt box; :cq
-- keeps it here for next time.
if target and target ~= '' then
  vim.api.nvim_create_autocmd('VimLeavePre', {
    group = group,
    callback = function()
      local draft = vim.env.DOTFILES_COMPOSE_DRAFT
      if vim.v.exiting ~= 0 or not draft or draft == '' then
        return
      end
      -- Autosave has already written the draft; writing here ends nvim early.
      vim.fn.system({ compose, 'return', target, draft })
    end,
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

return M
