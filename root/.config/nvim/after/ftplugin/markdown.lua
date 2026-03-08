-- Global settings in init.lua (like vim.opt.tabstop = 2) get overridden by
-- built-in filetype-specific indent scripts that load after your config during
-- filetype detection.
-- 
-- Neovim loads configs in this order:
--     init.lua (your global options)
--     Filetype detection (:help filetype)
--     runtime/indent/markdown.vim (sets tabstop=4, smartindent, etc. for markdown)
--     BufReadPost autocmd (but runs too early, before indent script)
-- 
-- The indent script ignores your globals and enforces its own values. Solution:
-- Use after/ftplugin/markdown.lua as recommended—it loads last via
-- runtimepath's after/ directory, overriding everything buffer-locally. See
-- :help ftplugin-override, :help runtimepath, :help after-directory.
-- 
-- Verify ordering with
-- :scriptnames          " Shows load sequence
-- :verbose set tabstop? " Reveals *where* option was last set (file:line)
--
vim.opt.tabstop = 2        -- Tab width
vim.opt.shiftwidth = 2     -- Indent width
vim.opt.softtabstop = 2    -- Soft tab width
vim.opt.expandtab = true   -- Use spaces instead of tabs
vim.opt.smartindent = true -- Smart autoindenting
vim.opt.autoindent = true  -- Copy indent from current line
vim.opt.breakindent = true -- Maintain indent when wrapping
vim.opt.wrap = true        -- Don't wrap lines
vim.opt.linebreak = true   -- Break at word boundaries if wrap enabled
vim.opt.textwidth = 0      -- Text width for formatting
vim.opt.foldlevel = 1
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
vim.opt.foldenable = true
vim.opt.conceallevel = 2
-- vim.opt.concealcursor = "nc"
vim.treesitter.start(vim.api.nvim_get_current_buf(), "markdown") -- Force reload TS parser

vim.keymap.set("n", "<leader>P", 'a<C-o>:set paste<cr>[<C-r>+](<C-r>+)<C-o>:set nopaste<cr>', { desc = "url paste" })
vim.keymap.set("n", "<leader>p", 'a<C-o>:set paste<cr>[](<C-r>+)<C-o>:set nopaste<cr><C-o>F]', { desc = "url paste w/desc" })

vim.api.nvim_create_user_command("ToMarkdownLink", function()
  vim.cmd.normal({ 'Ea)', bang = true })
  vim.cmd.normal({ 'Bi(', bang = true })
  vim.cmd.normal({ 'i[]', bang = true })
  vim.cmd.startinsert()
end, { desc = "convert raw url to title markdown link", nargs = 0 })

-- Enhance 'gf' to follow Markdown link from label/brackets/parentheses
vim.keymap.set("n", "gf", function()
  local line = vim.api.nvim_get_current_line()
  local col  = vim.api.nvim_win_get_cursor(0)[2] + 1 -- 1‑based
  -- Find the nearest "(" after any "[" on the line
  local open_paren = line:find("%b[]%b()", 1) and line:find("%(", col) or nil
  if not open_paren then
    -- fallback: just try <cfile> under cursor (e.g. bare paths)
    local file = vim.fn.expand("<cfile>")
    if file ~= "" then
      vim.cmd.edit(file)
    end
    return
  end
  -- Move cursor to just after "(" and use gf logic there
  vim.api.nvim_win_set_cursor(0, { vim.api.nvim_win_get_cursor(0)[1], open_paren })
  vim.cmd.normal({ args = { "gf" }, bang = false })
end, { buffer = true })

-- Strawman keymapping for markdown list items
local function in_markdown_list_item()
  local ts = vim.treesitter
  local bufnr = vim.api.nvim_get_current_buf()
  local lang = ts.language.get_lang(vim.bo[bufnr].filetype)
  if not lang then
    return false
  end

  local parser = ts.get_parser(bufnr, lang)
  if not parser then
    return false
  end

  local tree = parser:parse()[1]
  if not tree then
    return false
  end

  local root = tree:root()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  row = row - 1

  local node = root:named_descendant_for_range(row, col, row, col)
  while node do
    local t = node:type()
    if t == "list_item" or t == "tight_list_item" then
      return true
    end
    node = node:parent()
  end

  return false
end
vim.keymap.set("n", "<leader>t", function() -- strawman
  if in_markdown_list_item() then
    return "o- "
  else
    print("keybind false")
    return "o"
  end
end, { expr = true, silent = true, buffer = true })
