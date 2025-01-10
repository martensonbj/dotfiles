set nocompatible
runtime! macros/matchit.vim
filetype plugin indent on
syntax enable
set autoindent
set autoread
set clipboard=unnamed
if executable('rg') | set grepprg=rg\ | endif
set history=1000
set hlsearch
set mouse=a
set nobackup
set noswapfile
set nowrap
set nowritebackup
set ruler
set number
set smartindent
set smarttab
set splitright splitbelow
if &t_Co == 8 && $TERM !~# '^linux' | set t_Co=16 | endif
set title
set ttyfast
set undolevels=1000
set wildignore+=*.DS_Store
set wildmenu

let g:markdown_fenced_languages=['css', 'html', 'javascript', 'json', 'graphql', 'sh', 'typescript=javascript', 'yaml']
let g:netrw_liststyle=3

noremap <C-h> <C-w>h
noremap <C-j> <C-w>j
noremap <C-k> <C-w>k
noremap <C-l> <C-w>l
noremap <silent><leader>\ :nohlsearch<CR>
noremap <silent><leader>CW :%s/\s\+$//<CR>

" Auto Commands
" --------------------------------------
if has("autocmd")
  augroup FTOptions
    autocmd!
    autocmd BufRead,BufNewFile *.md set filetype=markdown
    autocmd BufRead,BufNewFile COMMIT_EDITMSG setlocal spell
    autocmd FileType markdown,text,txt setlocal textwidth=80 linebreak nolist wrap spell
  augroup END
endif

colorscheme delek

highlight Tooltip guifg='white' guibg='black'

