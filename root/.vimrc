" -----------------------------------------------------------------------------
"
"   vimrc by graham lopez
"
"   some preliminaries:
"   1) use ':so $MYVIMRC' within vim to reload .vimrc and see effect of changes
"   2) nnoremap <leader>v :so $MYVIMRC
" -----------------------------------------------------------------------------

" -----------------------------------------------------------------------------
" things that are likely necessary at startup                               {{{
" -----------------------------------------------------------------------------

" docs say to put it first (but also redundant since we're in a vimrc)
set nocompatible

" -----------------------------------------------------------------------------
" }}}
" -----------------------------------------------------------------------------



" -----------------------------------------------------------------------------
" miscellaneous key (re)mappings                                            {{{
" -----------------------------------------------------------------------------

set noek " but this means Fn keys cannot be used in insert mode
" clear search highligthing (but not disabled)
nnoremap <esc> :noh<return><esc>

noremap <leader>n :set number!<CR>

" reload the .vimrc in current instance
nnoremap <leader>v :so $MYVIMRC

" enable/disable cursor position highlighting
:nnoremap <Leader>C :set cursorline! cursorcolumn!<CR>

" enable/disable textwidth column highlight
if (exists('+colorcolumn'))
  fun! ToggleCC()
    if &cc == ''
      set colorcolumn=+0
    else
      set colorcolumn=
    endif
  endfun
  nnoremap <Leader>c :call ToggleCC()<CR>
endif

" automatically open help in vertical split
cnoremap vh vert help

" amplify these commands
noremap <c-e> 5
noremap <c-y> 5

" so cursor can navigate within wrapped lines
noremap  <buffer> <silent> k gk
noremap  <buffer> <silent> j gj
noremap  <buffer> <silent> 0 g0
noremap  <buffer> <silent> $ g$
" so it also works with operations
onoremap <silent> j gj
onoremap <silent> k gk

" deal with trailing whitespace
" (from http://www.bestofvim.com/tip/trailing-whitespace/)
nnoremap <Leader>rtw :%s/\s\+$//e<CR>

" use external grep on the word under the cursor, open quickfix window
map <leader>f :execute "grep! -r --exclude-dir=build --exclude-dir=coverage --exclude=compile_commands.json " . expand("<cword>") . " *" <Bar> copen<CR><CR>
" use external grep on an exact string as typed (need to type in the quotes)
map <leader>F :execute "grep! -r --exclude-dir=build --exclude-dir=coverage --exclude=compile_commands.json " . input('grep: ') . " *" <Bar> copen<CR>

" A syntax for placeholders
" Pressing Control-j jumps to the next match.
noremap <c-l> <Esc>/<++><CR><Esc>cf><Esc>:let @/ = ""<CR>a
inoremap <c-l> <Esc>/<++><CR><Esc>cf><Esc>:let @/ = ""<CR>a

" Completions using placeholders
"inoremap () ()<++><Esc>F)i
"inoremap [] []<++><Esc>F]i
"inoremap {} {}<++><Esc>F}i
"inoremap <> <><++><Esc>F>i
"inoremap '' ''<++><Esc>F'i
"inoremap "" ""<++><Esc>F"i
"inoremap `` ``<++><Esc>F`i

" For working with Buffers, Windows, Tabs
nnoremap <c-p> :bNext<cr>
nnoremap <c-n> :bnext<cr>
nnoremap <c-x> :bdelete<cr>
"or use vim-bufkill version instead for added conveniences
" nnoremap <c-x> :BD<cr>
nnoremap <c-b> :ls<cr>:b<Space>

" -----------------------------------------------------------------------------
" }}}
" -----------------------------------------------------------------------------



" -----------------------------------------------------------------------------
" for all things color related in vim                                       {{{
" -----------------------------------------------------------------------------

" http://vim.wikia.com/wiki/Xterm256_color_names_for_console_Vim

" setting terminal stuff must appear before color/syntax settings
set t_Co=256

" turn on syntax highlighting support
syntax enable

" usually using a dark terminal
set background=dark

" because visual mode highlighting disappears for virtual consoles for anything
" except background=light? don't know why
" highlight Visual cterm=reverse ctermbg=NONE
" highlight Visual ctermbg=gray

" colorscheme solarized
" colorscheme desert256

" can choose a different scheme when using 'vimdiff'
" if &diff
"     colorscheme inkpot
" endif

" set up statusline (fore/background is reversed) and wildmenu
highlight StatusLine ctermfg=black ctermbg=gray
highlight Wildmenu ctermfg=Yellow ctermbg=black

" change search result color
highlight Search NONE
highlight Search ctermfg=red cterm=undercurl

" change spellbad colors
highlight SpellBad NONE
highlight SpellBad ctermfg=yellow cterm=undercurl

" remove all todo,fixme,etc highlighting - it can be overkill
":hi Todo none
" or change its color
hi Todo ctermfg=Red ctermbg=NONE guifg=Red guibg=NONE
" set color of sign column for using things like vim-signify
" (may have to change these in the plugin itself - gets loaded too late?)
hi SignColumn guibg=NONE ctermbg=NONE guifg=NONE ctermfg=NONE
hi SignifySignAdd ctermbg=NONE guibg=NONE
hi SignifySignDelete ctermbg=NONE guibg=NONE
hi SignifySignChange ctermbg=NONE guibg=NONE

" color the line numbers a certain way
highlight LineNr ctermfg=grey guifg=grey

" highlight the textwidth column
if (exists('+colorcolumn'))
    highlight ColorColumn ctermbg=235 guibg=#121212
endif

" highlight cursor position
hi CursorLine   cterm=NONE ctermbg=237 guibg=#121212
hi CursorColumn ctermbg=237 guibg=#121212
" uncomment below to enable by default
":set cursorline! cursorcolumn!

" folded colors
"highlight Folded cterm=NONE ctermfg=grey guifg=grey
"highlight Folded ctermbg=233 guibg=#121212
highlight Folded cterm=NONE ctermfg=94 guifg=#875f00
highlight Folded ctermbg=NONE guibg=NONE
set fillchars="vert:|,fold:"

" show me trailing whitespace
match ErrorMsg '\s\+$'  " don't need this as vim-airline shows me anyway

" change the colors of the popup menu (e.g. in autocompleteions)
highlight Pmenu ctermfg=15 ctermbg=0 guifg=#ffffff guibg=#000000

" fixup vimdiff colors
highlight DiffAdd    cterm=bold ctermfg=10 ctermbg=17 gui=none guifg=bg guibg=Red
highlight DiffDelete cterm=bold ctermfg=10 ctermbg=17 gui=none guifg=bg guibg=Red
highlight DiffChange cterm=bold ctermfg=10 ctermbg=17 gui=none guifg=bg guibg=Red
highlight DiffText   cterm=bold ctermfg=10 ctermbg=88 gui=none guifg=bg guibg=Red

" vim-indent-guides
let g:indent_guides_indent_levels = 6
let g:indent_guides_auto_colors = 0
let g:indent_guides_start_level = 2
let g:indent_guides_guide_size = 1
hi IndentGuidesOdd  ctermbg=234
hi IndentGuidesEven ctermbg=234

" -----------------------------------------------------------------------------
" }}}
" -----------------------------------------------------------------------------



" -----------------------------------------------------------------------------
" Miscellaneous (small) remaining settings                                  {{{
" -----------------------------------------------------------------------------

" use syntax folding where appropriate

autocmd Syntax c,cpp setlocal foldmethod=syntax

" use indent folding if nothing else, but still allow for manual folding
augroup vimrc
  au BufReadPre * setlocal foldmethod=indent
  au BufWinEnter * if &fdm == 'indent' | setlocal foldmethod=manual | endif
augroup END

" folds opened on file load - probably rather do this on a filetype basis
if has ("autocmd")
  autocmd BufWinEnter * normal zR
endif

" set conceallevel=1
let g:tex_conceal = "" "disable for latex

" try to deal with autocommands properly (per :help autocmd)
" FIXME revisit this - possibly too heavy-handed and/or handle with keybindings
" if !exists("autocommands_loaded")
"   let autocommands_loaded = 1
"   " trying method from http://vim.wikia.com/wiki/All_folds_open_when_opening_a_file
"   autocmd Syntax * setlocal foldmethod=syntax
"   "autocmd BufRead * normal zR
" endif

" relative line numbers relative mode
" and reset to absolute numbering for insert and unfocused buffers/windows
set number
" set relativenumber
" :augroup numbertoggle
" :  autocmd!
" :  autocmd WinEnter,BufEnter,FocusGained,InsertLeave * set relativenumber
" :  autocmd WinLeave,BufLeave,FocusLost,InsertEnter   * set norelativenumber
" :augroup END

" need to figure out better what to set here for fortran
let fortran_free_source=1
let fortran_more_precise=1

"try to fix tmux / xterm key mess as described at (also need a change to ".tmux.conf
"http://superuser.com/questions/401926/how-to-get-shiftarrows-and-ctrlarrows-working-in-vim-in-tmux
if &term =~ '^screen'
    " tmux will send xterm-style keys when its xterm-keys option is on
    execute "set <xUp>=\e[1;*A"
    execute "set <xDown>=\e[1;*B"
    execute "set <xRight>=\e[1;*C"
    execute "set <xLeft>=\e[1;*D"
endif

" set abandoned buffers to hidden
set hidden

set fileformats+=dos

" this is for automatic spell checking which is only useful in
" text documents, not so much in code.  should figure out how to
" do this for only the filetypes we want it for
"setlocal spell spelllang=en

" automatically get and show changes in an open file
set autoread

set backspace=eol,indent,start
set autoindent

" keep this many lines always at bottom/top of screen
set scrolloff=5

"this converts <tab> to spaces.
set expandtab

" this is bad thing to change, use sts instead
"set tabstop=4

" this is how many spaces to use with autoindent
set shiftwidth=2

" auto wrap text at the end of the line
set textwidth=80

" let's allow long lines for things like latex files
set wrap
set linebreak
" set nolist

" make tabs 'feel' like this while editing
set softtabstop=2

" at the beginnig of a line, use shiftwidth, otherwise sts
set smarttab

" show line and column of the cursor position
set ruler

" some searching options
set hlsearch
set incsearch

"Tell you if you are in insert mode (not necessary with vim-airline)
set noshowmode

"match parenthesis, i.e. ) with (  and } with {
set showmatch

"ignore case when doing searches
set ignorecase

"tell you how many lines have been changed
set report=0

" default newly split window to open to the right of current one
set splitright

set completeopt=menuone,preview

" set the size of the completion popup menu
set pumheight=20

" to yank/paste in different vim instances on same X server
" set clipboard=unnamed
" this fixes the problem of macvim+tmux
if $TMUX == ''
    set clipboard+=unnamed
endif

" Search down into subfolders
" Provides tab-completion for all file-related tasks
set path+=**

" Navigation and searching
set wildignore+=build/**,coverage/**
set wildchar=<Tab> wildmenu wildmode=list:longest,full

" OR use these:
" The + forms interact with the clipboard
" ("+y is like Ctrl+C, "+p is like Ctrl+V).
" The * forms interact with the selection buffer
" ("*y is like left click and drag, "*p is like middle click).
" see :help registers, :help x11-selection

" -----------------------------------------------------------------------------
" }}}
" -----------------------------------------------------------------------------



" -----------------------------------------------------------------------------
" filetype specifics                                                        {{{
" -----------------------------------------------------------------------------

" turn on filetype detection and related capabilities
filetype plugin indent on

" enable marker-based folding for the vimscript (.vimrc) files
augroup filetype_vim
    autocmd!
    autocmd FileType vim setlocal foldmethod=marker
augroup END

" change some colors for markdown files
highlight clear markdownItalic
highlight clear markdownBold
highlight clear markdownBoldItalic
highlight markdownItalic ctermfg=red
highlight markdownBold cterm=bold
highlight markdownBoldItalic ctermfg=red cterm=bold

let g:markdown_folding=1

let g:vim_markdown_conceal=1

" tweak vim-mail's behavior in mutt
let g:VimMailStartFlags="to"
let g:VimMailDoNotFold=1

" -----------------------------------------------------------------------------
" }}}
" -----------------------------------------------------------------------------
