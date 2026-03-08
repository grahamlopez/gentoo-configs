-- TODO: list {{{
--  better highlighting/colors for listchars
--  fuzzy searching: buffer, file, grep, help pages
--  lsp-autocompletion
--    https://www.reddit.com/r/neovim/comments/1pig7ed/does_anyone_have_working_code_for_builtin/
--    'ins-autocompletion', 'autocomplete', 'complete', 'completeopt'
--  cmdline-autocompletion
--  undo-tree
-- }}}

-- Keybindings, Abbreviations {{{
-- For modes, see `:help map-modes`
--     To see mappings:
--     - :help [keys] for built-in keymappings
--     - :map [keys] for user-defined keymappings (with file:line location of defn)

-- Set <space> as the leader key
vim.g.mapleader = " "
vim.g.maplocalleader = " "

vim.keymap.set("n", "<leader>co", function() vim.cmd.edit(vim.fn.stdpath("config") .. "/init.lua") end, { desc = "Edit Neovim config" })
vim.keymap.set({ "n" }, "<esc>", ":nohl<cr>", { silent = true })                       -- cancel highlighting
vim.keymap.set("n", "k", "v:count == 0 ? 'gk' : 'k'", { expr = true, silent = true }) -- deal with line wrap
vim.keymap.set("n", "j", "v:count == 0 ? 'gj' : 'j'", { expr = true, silent = true }) -- deal with line wrap
vim.keymap.set("n", "]q", ":cnext<cr>zv", {})
vim.keymap.set("n", "[q", ":cprev<cr>zv", {})
vim.keymap.set("n", "zh", "zM zv", { desc = "fold everywhere but here" })
vim.keymap.set({ "n" }, "<leader>R", "<cmd>restart<cr>", { silent = true })
vim.keymap.set({ "n" }, "<C-b>", ":buffers<CR>:b<Space>", { silent = true })

vim.cmd("cabbrev vh vert help")
-- }}}

-- Options {{{
-- intro comments {{{
--[[
    These are some options that I've been carring around
    See :help vim.o and :help vim.opt
    and Vhyrro's YT vid: https://www.youtube.com/watch?v=Cp0iap9u29c&t=334s

    each table can contain both variables and/or options. variables are essentially
    "scoped" to a buffer, window, tab, or globally. Options may apply to one of
    these but not another. Note that 'id' numbers are optional, and default to
    the current buffer/window/tab

    variables         options
    ---------         ---------
    vim.b[id]         vim.bo[id]
    vim.w[id]         vim.wo[id]
    vim.t[id]         vim.to[id]
    vim.g             vim.o
                      vim.opt
                      vim.opt_local
                      vim.opt_global

    'vim.o' automatically detects the scope(s) of an option and uses it. If the
    option is only local or only global, sets that option. If the option is
    global-local, sets both versions of the variable. Only returns the bare
    variable; not helper functions.

    'vim.opt' will set both _global and _local versions, or whichever one is
    available if it isn't a global-local variable.

    Note that for checking option values (e.g. if vim.o[pt].background == "dark")
    that vim.o.* returns the option value as a Lua primitive, while vim.opt.*
    treats each option as a special object (metatable) with methods for list
    manipulation and advanced operations, such as vim.opt.background:get().

    ':set all' to see all possible settings and their current values
    ':help options' to get to the options part of the manual
--]]
-- }}}
-- General settings {{{
vim.opt.autoindent = true                             -- Copy indent from current line
vim.opt.autoread = true
vim.opt.autowrite = true                              -- Auto-write before running commands
-- vim.opt.backup = false -- No backup files
vim.opt.breakindent = true                            -- Maintain indent when wrapping
vim.opt.clipboard:append { "unnamed", "unnamedplus" } -- requires wl-clipboard
-- vim.opt.cmdheight = 0 -- docs say "experimental" - causes hit_enter events e.g. with :Todos
vim.opt.colorcolumn = ""
vim.cmd.colorscheme('default')
vim.opt.cursorline = true
vim.opt.cursorlineopt = "number"
vim.opt.completeopt = { "fuzzy", "menu", "menuone", "noselect", "noinsert" }
vim.opt.diffopt:append("linematch:60") -- Better diffs
vim.opt.expandtab = true
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
vim.opt.foldlevel = 99
vim.opt.foldenable = true
vim.opt.foldcolumn = "0" -- enable minimal foldcolumn for mouse interaction
vim.opt.fillchars:append({ fold = " " })
vim.opt.hidden = true
vim.opt.history = 1000    -- More command history
vim.opt.hlsearch = true   -- Set highlight on search
vim.opt.ignorecase = true -- Case-insensitive searching UNLESS \C or capital in search
vim.opt.inccommand = "split"
vim.opt.laststatus = 3
vim.opt.lazyredraw = true -- Don't redraw during macros
vim.opt.linebreak = true  -- Break at word boundaries if wrap enabled
vim.opt.listchars = { tab = "→ ", trail = "·", nbsp = "○", extends = "▸", precedes = "◂", }
vim.g.loaded_perl_provider = 0
vim.g.loaded_python_provider = 0
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0 -- Disable some providers for faster startup
vim.loader.enable()            -- Enable faster Lua module loading
vim.opt.number = false
-- vim.opt.mouse = "nv" -- Disable mouse for speed
vim.opt.pumblend = 10  -- Popup menu transparency
vim.opt.pumheight = 15 -- Maximum items in popup menu
vim.opt.relativenumber = false
vim.opt.scrolloff = 5
vim.opt.sessionoptions = { "buffers", "curdir", "folds", "help", "tabpages", "winsize", "winpos", "terminal", "globals", }
vim.opt.shiftwidth = 2
vim.opt.shortmess:append("c")
vim.opt.sidescrolloff = 5 -- Keep columns left/right of cursor
vim.opt.signcolumn = "auto"
vim.opt.smartcase = true
vim.opt.smartindent = true
vim.opt.softtabstop = 2
vim.opt.spell = false
vim.opt.spelllang = { "en_us" }
vim.opt.spellfile = vim.fn.stdpath("config") .. "/spell/en.utf-8.add"
vim.opt.splitbelow = true
vim.opt.splitright = true
-- vim.opt.swapfile = false
vim.opt.tabstop = 2                    -- Tab width
vim.opt.termguicolors = true
vim.opt.textwidth = 80                 -- Text width for formatting
vim.opt.timeoutlen = 500               -- More lenient keybindings vs. faster which-key popup
vim.opt.ttyfast = true                 -- Fast terminal connection
vim.opt.undofile = true                -- Persistent undo
vim.opt.updatetime = 250               -- Faster completion (4000ms default)
vim.opt.virtualedit = "block"
vim.opt.wildmode = "longest:full,full" -- Command completion mode
vim.opt.wildignore:append({ "*.o", "*.obj", ".git", "node_modules", "*.pyc" })
vim.opt.wildignorecase = true
vim.opt.wildoptions:append({ "fuzzy" }) -- FIXME: menu disappears with next keypress
vim.opt.winheight = 5
vim.opt.winminheight = 5
vim.opt.winminwidth = 5
vim.opt.winwidth = 5
vim.opt.wrap = true -- visually wrap lines when needed
-- vim.opt.writebackup = false -- No backup before overwriting
-- Configure clipboard for different environments {{{
if vim.fn.has("wsl") == 1 then
  vim.g.clipboard = {
    name = "WslClipboard",
    copy = {
      ["+"] = "clip.exe",
      ["*"] = "clip.exe",
    },
    paste = {
      ["+"] = 'powershell.exe -c [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))',
      ["*"] = 'powershell.exe -c [Console]::Out.Write($(Get-Clipboard -Raw).tostring().replace("`r", ""))',
    },
    cache_enabled = 0,
  }
end
-- }}}
-- WSL2/tmux terminal background detection fix {{{
if vim.fn.has("wsl") == 1 then
  -- Query Windows registry for current theme (light=1, dark=0)
  local is_dark = vim.fn.system(
        "powershell.exe -NoProfile -Command '[int](Get-ItemProperty -Path \"HKCU:\\Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize\" -Name AppsUseLightTheme).AppsUseLightTheme'")
      :match("0")
  vim.o.background = is_dark == "0" and "dark" or "light"
end
-- }}}
-- }}}
-- }}}

-- LSP, diagnostics, completion {{{
-- see lsp-quickstart, lsp-config, lsp-defaults
vim.lsp.config['lua_ls'] = {
  -- Command and arguments to start the server.
  cmd = { 'lua-language-server' },
  -- Filetypes to automatically attach to.
  filetypes = { 'lua' },
  root_markers = { { '.luarc.json', '.luarc.jsonc' }, '.git' },
  -- Specific settings to send to the server. The schema is server-defined.
  -- Example: https://raw.githubusercontent.com/LuaLS/vscode-lua/master/setting/schema.json
  settings = {
    Lua = {
      runtime = {
        version = 'LuaJIT',
      },
      workspace = {
        library = { vim.env.VIMRUNTIME }, -- Expose Neovim runtime API
        checkThirdParty = false,          -- Skip third-party checks
      },
    }
  }
}
vim.lsp.enable({ 'lua_ls' })
-- Configure diagnostic display - see diagnostic-quickstart
vim.diagnostic.config({
  virtual_text = {
    prefix = '●',
    source = "if_many",
  },
  float = {
    source = true,
    border = "rounded",
  },
  signs = false,
  underline = true,
  update_in_insert = false,
  severity_sort = true,
})
-- }}}

-- Utilities (lightweight plugins) {{{
-- fuzzy-file-picker and TODO: live-grep {{{
local filescache = {} -- Files cache (per-process)
-- Helper to (re)build the cache from the current directory
local function build_files_cache()
  local files = vim.fn.globpath('.', '**', true, true) -- globpath('.', '**', 1, 1)
  -- filter out directories: !isdirectory(v:val)
  files = vim.tbl_filter(function(path)
    return vim.fn.isdirectory(path) == 0
  end, files)
  -- fnamemodify(v:val, ':.') to make paths relative to cwd
  files = vim.tbl_map(function(path)
    return vim.fn.fnamemodify(path, ':.')
  end, files)
  filescache = files
end
-- This is the function used by 'findfunc'
local function Find(arg, _)
  if #filescache == 0 then
    build_files_cache()
  end
  if arg == '' then
    return filescache
  end
  return vim.fn.matchfuzzy(filescache, arg)
end
-- Expose it under a global name so 'findfunc' can see it
_G.Find = Find
-- Tell :find to use this function
vim.o.findfunc = 'v:lua.Find'
-- Clear cache on CmdlineEnter :
vim.api.nvim_create_autocmd('CmdlineEnter', {
  pattern = ':',
  callback = function()
    filescache = {}
  end,
})
-- }}}

-- TODO and friends {{{
-- grep todo keywords and add to quickfix
if vim.fn.executable('rg') then -- FIXME: redundant: this is already the default
  vim.opt.grepprg = "rg --vimgrep --no-hidden --no-heading"
end
vim.api.nvim_create_user_command("Todos", function()
  vim.cmd.vimgrep({ '/\\(TODO\\|FIXME\\|IDEA\\|TRACK\\):/', '**/*' })
  --vim.cmd.copen()
  vim.cmd("CopenSmart 25")
end, { desc = "vimgrep TODO and friends to quickfix", nargs = 0 })

-- highlight todo keywords
vim.api.nvim_create_autocmd({ "ColorScheme", "OptionSet", "VimEnter", "WinNew", "WinEnter" }, {
  callback = function()
    vim.api.nvim_set_hl(0, "darkTodoPattern", { fg = "#ffaf00", bold = true })
    vim.api.nvim_set_hl(0, "lightTodoPattern", { fg = "#cd4848", bold = true })
    vim.fn.clearmatches()
    if vim.o.background == "dark" then
      vim.fn.matchadd("darkTodoPattern", "\\(TODO\\|FIXME\\|IDEA\\|TRACK\\):")
    else
      vim.fn.matchadd("lightTodoPattern", "\\(TODO\\|FIXME\\|IDEA\\|TRACK\\):")
    end
  end
})

local function qf_open_smart(max_height, min_height)
  max_height = max_height or 15
  min_height = min_height or 1

  local qf_list = vim.fn.getqflist()
  local n_items = #qf_list

  if n_items == 0 then return end

  local h = math.min(n_items, max_height)
  h = math.max(h, min_height)

  vim.cmd(h .. "copen")

  vim.wo.winfixheight = true
end

vim.api.nvim_create_user_command("CopenSmart", function(opts)
  -- optional: allow :CopenSmart 20
  local maxh = tonumber(opts.args) or 15
  qf_open_smart(maxh, 1)
end, { nargs = "?", desc = "Open quickfix sized to contents with max height" })

-- Auto-size quickfix after typical quickfix commands
vim.api.nvim_create_autocmd("QuickFixCmdPost", {
  pattern = { "make", "grep", "vimgrep", "lvimgrep" },
  callback = function()
    qf_open_smart(20, 3) -- max 15 lines, min 3
  end,
})
-- }}}

-- background transparency {{{
local transparent_enabled = true  -- startup default
local saved_hls = {}
local groups = {
  'Normal',
  'NormalNC',
  'NormalFloat',
  'FloatBorder',
  'SignColumn',
  'WinSeparator',
  -- 'Folded',
  -- 'FoldColumn',
}
local function save_current_hls()
  for _, name in ipairs(groups) do
    -- get current definition from global namespace
    saved_hls[name] = vim.api.nvim_get_hl(0, { name = name, link = false })
  end
end
local function apply_saved_hls()
  for _, name in ipairs(groups) do
    local def = saved_hls[name]
    if def then
      vim.api.nvim_set_hl(0, name, def)
    end
  end
end
local function apply_transparent()
  for _, name in ipairs(groups) do
    vim.api.nvim_set_hl(0, name, { bg = 'none' })
  end
end
function _G.ToggleTransparent()
  if transparent_enabled then
    apply_saved_hls()
    transparent_enabled = false
  else
    -- on first enable, capture scheme defaults
    if next(saved_hls) == nil then
      save_current_hls()
    end
    apply_transparent()
    transparent_enabled = true
  end
end

vim.api.nvim_create_autocmd({'VimEnter', 'ColorScheme'}, {
  pattern = '*',
  callback = function()
    saved_hls = {} -- clear cache; next toggle will re-save
    if transparent_enabled then
      save_current_hls()
      apply_transparent()
    end
  end,
})
vim.api.nvim_create_user_command("TransparentToggle", function()
  ToggleTransparent()
end, { desc = "Toggle background transparency", nargs = 0 })
vim.keymap.set('n', '<leader>ut', ToggleTransparent, { desc = 'Toggle transparent background' })
-- }}}

-- listchars display {{{
-- Show listchars
vim.opt.listchars = {
  tab = "▸ ",
  trail = "·",
  space = "·",
  extends = "⟩",
  precedes = "⟨",
}

-- Color all listchars whitespace
vim.api.nvim_create_autocmd({ "ColorScheme", "OptionSet", "VimEnter", "WinNew", "WinEnter" }, {
  callback = function()
    vim.api.nvim_set_hl(0, "Whitespace", {
      fg = "#d70000",      -- red visible on dark/light
      ctermfg = 160,       -- 256‑color terminals
    })
    -- Optionally tweak others that may be involved
    vim.api.nvim_set_hl(0, "NonText",  { fg = "#444444" })
    vim.api.nvim_set_hl(0, "SpecialKey", { fg = "#5f5f5f" })
  end
})
-- }}}
-- }}}

-- Filetype specifics {{{
-- This autocmd is to fix the problem of '--' indentation being right-shifted by
-- two spaces only after lines with foldmarkers like '\{\{\{'
-- these stay here; timing is wrong if these are moved to 'after/ftplugin/lua.lua'
vim.api.nvim_create_autocmd("FileType", {
  pattern = "lua",
  callback = function()
    vim.opt_local.indentexpr = "v:lua.lua_indent(v:lnum)"
  end,
})
-- This autocmd defines the function to fix the '--' indentation problem
-- addressed by the previous autocmd
vim.api.nvim_create_autocmd("VimEnter", {
  callback = function()
    _G.lua_indent = function(lnum)
      local line = vim.fn.getline(lnum)
      if line:match("^%s*--%s*") then -- On comment lines/spaces after --, match prev comment indent
        local prev = vim.fn.prevnonblank(lnum - 1)
        if prev > 0 then
          return vim.fn.indent(prev)
        end
      end
      return vim.fn.eval("GetLuaIndent(" .. lnum .. ")") -- Fallback to Lua indent
    end
  end,
})
vim.api.nvim_create_autocmd("BufReadPost", {
  pattern = "init.lua",
  callback = function()
    vim.opt.foldmethod = "marker"
    vim.opt.foldmarker = "{{{,}}}"
    vim.opt.foldlevel = 0
  end,
})
-- }}}

-- big markdown ideas list {{{
--
--    - https://github.com/iwe-org/iwe
--    - https://github.com/jakewvincent/mkdnflow.nvim
--    - https://github.com/YousefHadder/markdown-plus.nvim
--    - https://github.com/OXY2DEV/markview.nvim?tab=readme-ov-file
--    - previewing:
--      - synced external preview
--    - table of contents: markdown-toc, https://youtu.be/BVyrXsZ_ViA
--      - use TOC to jump/navigate
--    - table input and manipulation
--    - image support
--    - A couple of videos to start ideas:
--      - <https://www.youtube.com/watch?v=DgKI4hZ4EEI>
--      - <https://linkarzu.com/posts/neovim/markdown-setup-2025/>
--    - other ideas:
--      - easier bolding etc. with mini.surround and/or keymaps
--      - better bullet lists: https://github.com/bullets-vim/bullets.vim
--      - https://mambusskruj.github.io/posts/pub-neovim-for-markdown
-- }}}

-- big nvim ideas list from previous config {{{
--
--  ## folding list:
--    toggle with <cr>
--    better navigation (zk, zj, [z, ]z)
--    - relative fold labeling for jumping with e.g. '<num>zj'
--      (this is already kinda there with foldcolumn=1 enabled
--    preserve folds across sessions
--    "focused folded" mode where I navigate to a location (via 'n/N' scrolling through
--      search results, pufo preview, from a picker grep, etc.) and that location is
--      unfolded, but everything else remains folded or is refolded as needed
--    lua block comments
--    what can be done about fold debugging e.g. showing fold locations, etc.?
--    remove need to close+re-open file when folds get messed up from just normal editing
--    e.g. subheadings get messed up when removing list items from top-level heading in markdown files
--
--  ## For writing mode
--
--  - <https://trebaud.github.io/posts/neovim-for-writers/>
--  - <https://miragiancycle.github.io/OVIWrite/>
--  - <https://bhupesh.me/writing-like-a-pro-with-vale-and-neovim/>
--  - <https://www.reddit.com/r/neovim/comments/z26vhz/how_could_i_use_neovim_for_general_writing_and/>
--  - focus/zen modes tuned for writing
--  - comments, sidebar, etc.
--  - can a proportional font be used?
--  - I started a config at .config/nvim.writing - see hash 2c5f0eb for latest
--
--  ## PKM / logseq reproduction
--
--  - markdown is lingua-franca; no need yet to swim upstream on this one
--  - linking, backlinking, tagging (check out markdown-oxide lsp)
--  - autocompletion creates local file links
--  - how much of logseq to bring forward?
--  - comprehensive mouse support
--  - todo workflow with automatic and hidden timestamps
--  - linkarzu's workflow: <https://youtu.be/59hvZl077hM>
--    - fast link navigation
--  - follow local file links with shortcut
--  - use pickers
--  - show all in quick/loc list
--
--  ## Custom theming
--
--  <https://github.com/rktjmp/lush.nvim>
--  <https://github.com/roobert/palette.nvim>
--  <https://vimcolors.org/>
--  <https://nvimcolors.com/>
--
-- }}}

-- Archived info {{{
--
--  Keymap reminders
--    ctrl-w_] --> mostly like :lua vim.lsp.buf.definition() 
--    i_ctrl-u --> useful for unwanted auto-inserted comment
--
--  Minimal setup
--    why I got rid of all my neovim plugins
--      https://yobibyte.github.io/vim.html
--    vanilla neovim setup, no plugins, telescope-like functionality
--      https://www.youtube.com/watch?v=mQ9gmHHe-nI)
--
--  Maintainer dotfiles
--    justinMk
--      https://github.com/justinmk/config/blob/master/.config/nvim/init.lua
--    MariaSolOs
--      https://github.com/MariaSolOs/dotfiles/blob/main/.config/nvim/init.lua
--    echasnovski
--      https://github.com/echasnovski/nvim/blob/master/init.lua
--
--  Improving vimgrep+quickfix workflow
--    https://gist.github.com/romainl/56f0c28ef953ffc157f36cc495947ab3
--
--  TRACK: g-<c-g> to output word/line count in visual mode
--    not an issue with 0.11.4. --clean -u NORC doesn't help
--    WAR: use :1messages to get the text from g-<c-g>
--
--  TRACK: To fix folded code blocks in markdown files completely disappearing,
--  we need to disable the 'conceal_lines' on the fenced_code_block delimiters.
--  According to
--  https://www.reddit.com/r/neovim/comments/1jo6d1n/how_do_i_override_treesitter_conceal_lines/
--  we really only have 2 options at the moment:
--  1. copy share/nvim/runtime/queries/markdown/highlights.scm to
--  .config/nvim/queries/markdown and remove those lines (and without ';; extends')
--  2. remove the lines directly from the runtime highlights.scm file itself
-- }}}
