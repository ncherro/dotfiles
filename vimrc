" *********************************************
" *                Plugins                   *
" *********************************************
call plug#begin()

" Navigation
Plug 'junegunn/fzf', { 'do': { -> fzf#install() } }
Plug 'junegunn/fzf.vim'
Plug 'preservim/nerdtree'
Plug 'vim-scripts/IndexedSearch'
Plug 'vim-scripts/matchit.zip'
Plug 'tpope/vim-unimpaired'
Plug 'jeetsukumaran/vim-buffergator'

" Syntax and Language Support
Plug 'pangloss/vim-javascript'
Plug 'leafgarland/typescript-vim'
Plug 'slim-template/vim-slim'
Plug 'mtscout6/vim-cjsx'
Plug 'mxw/vim-jsx'
Plug 'hashivim/vim-terraform'
Plug 'jparise/vim-graphql'
Plug 'cespare/vim-toml'
Plug 'uarun/vim-protobuf'
Plug 'HerringtonDarkholme/yats.vim'
Plug 'elixir-lang/vim-elixir'
Plug 'nvie/vim-flake8'
Plug 'vim-scripts/indentpython'

" Formatting
Plug 'scrooloose/nerdcommenter'
Plug 'godlygeek/tabular'
Plug 'editorconfig/editorconfig-vim'
Plug 'prettier/vim-prettier', { 'do': 'yarn install --frozen-lockfile --production' }

" Autocomplete
Plug 'tpope/vim-surround'
Plug 'tpope/vim-endwise'
Plug 'msanders/snipmate.vim'
Plug 'mattn/emmet-vim'
Plug 'Raimondi/delimitMate'
Plug 'ervandew/supertab'

" UI Enhancements
Plug 'itchyny/lightline.vim'
Plug 'suan/vim-instant-markdown'
Plug 'rizzatti/funcoo.vim'
Plug 'rizzatti/dash.vim'
Plug 'tpope/vim-dispatch'

" Git
Plug 'sjl/gundo.vim'
Plug 'tpope/vim-fugitive'

" Testing
Plug 'janko-m/vim-test'

" Async linting
Plug 'w0rp/ale'


" Color
Plug 'joshdick/onedark.vim'

" Debugging
Plug 'puremourning/vimspector'

call plug#end()


" *********************************************
" *                Settings                  *
" *********************************************

" Syntax and filetype
syntax enable
filetype plugin indent on


" Editor UI
set colorcolumn=80
set cursorline
set number
set ruler
set showcmd
set showmode
set showmatch
set title
set wildmenu
set wildmode=list:longest

" Indentation and tabs
set autoindent
set backspace=indent,eol,start
set expandtab
set shiftwidth=2
set tabstop=2

" Search
set hlsearch
set ignorecase
set incsearch
set smartcase

" Folding
set foldmethod=indent
set foldnestmax=3
set nofoldenable

" Scrolling
set scrolloff=3
set sidescroll=1
set sidescrolloff=7

" File handling
set directory=/tmp
set hidden
set nobackup
set noswapfile
set nowb
set nowritebackup

" Miscellaneous
set history=1000
set list listchars=tab:\ \ ,trail:.
set mouse-=a
set mousehide
set novisualbell
set noerrorbells
set pastetoggle=<F2>
set shell=/bin/zsh
set synmaxcol=0
set timeoutlen=500

" Colorscheme
set background=dark
colorscheme onedark
let g:disable_float_bg = 1

" Hide the tildes at the end of the buffer
highlight EndOfBuffer ctermfg=black ctermbg=black

" Terminal mouse support for non-Neovim
if !has('nvim')
  set ttymouse=xterm2
endif

" Status line
set laststatus=2
set statusline=%f


" *********************************************
" *                Functions                 *
" *********************************************

function! RenameFile()
    let old_name = expand('%')
    let new_name = input('New file name: ', expand('%'), 'file')
    if new_name != '' && new_name != old_name
        exec ':saveas ' . new_name
        exec ':silent !rm ' . old_name
        redraw!
    endif
endfunction


function! LightLineFilename()
  return expand('%')
endfunction

function! LightlineLinterWarnings() abort
  let l:counts = ale#statusline#Count(bufnr(''))
  let l:all_errors = l:counts.error + l:counts.style_error
  let l:all_non_errors = l:counts.total - l:all_errors
  return l:counts.total == 0 ? '' : printf('%d ◆', all_non_errors)
endfunction

function! LightlineLinterErrors() abort
  let l:counts = ale#statusline#Count(bufnr(''))
  let l:all_errors = l:counts.error + l:counts.style_error
  let l:all_non_errors = l:counts.total - l:all_errors
  return l:counts.total == 0 ? '' : printf('%d ✗', all_errors)
endfunction

function! LightlineLinterOK() abort
  let l:counts = ale#statusline#Count(bufnr(''))
  let l:all_errors = l:counts.error + l:counts.style_error
  let l:all_non_errors = l:counts.total - l:all_errors
  return l:counts.total == 0 ? '✓ ' : ''
endfunction

function! s:MaybeUpdateLightline()
  if exists('#lightline')
    call lightline#update()
  end
endfunction

autocmd User ALELint call s:MaybeUpdateLightline()


" *********************************************
" *               Key Bindings                *
" *********************************************
let mapleader = ","

" Rails navigation
nnoremap ,vv :Rview<cr>
nnoremap ,cc :Rcontroller<cr>

" Clear last search highlighting
nnoremap <Space> :noh<cr>

" Window splits
nnoremap <silent> vv <C-w>v
nnoremap <silent> ss <C-w>s

" Paste from clipboard
if has('mac')
  nnoremap <silent> pp :read !pbpaste<CR>
else
  nnoremap <silent> pp :read !xclip -o<CR>
endif

" Clear search highlight
nmap <silent> // :nohlsearch<CR>

" Buffer navigation
nnoremap <Leader>l :ls<CR>
nnoremap <Leader>b :bp<CR>
nnoremap <Leader>g :e#<CR>
nnoremap <Leader>1 :1b<CR>
nnoremap <Leader>2 :2b<CR>
nnoremap <Leader>3 :3b<CR>
nnoremap <Leader>4 :4b<CR>
nnoremap <Leader>5 :5b<CR>
nnoremap <Leader>6 :6b<CR>
nnoremap <Leader>7 :7b<CR>
nnoremap <Leader>8 :8b<CR>
nnoremap <Leader>9 :9b<CR>
nnoremap <Leader>0 :10b<CR>

" Split window navigation
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-h> <C-w>h
nnoremap <C-l> <C-w>l

" Vimspector debugging
let g:vimspector_base_dir=expand('~/.vim/plugged/vimspector')
nnoremap <Leader>dd :call vimspector#Launch()<CR>
nnoremap <Leader>de :call vimspector#Reset()<CR>
nnoremap <Leader>dc :call vimspector#Continue()<CR>
nnoremap <Leader>dt :call vimspector#ToggleBreakpoint()<CR>
nnoremap <Leader>dT :call vimspector#ClearBreakpoints()<CR>
nmap <Leader>dk <Plug>VimspectorRestart
nmap <Leader>dh <Plug>VimspectorStepOut
nmap <Leader>dl <Plug>VimspectorStepInto
nmap <Leader>dj <Plug>VimspectorStepOver

" Insert blank lines without insert mode
nmap go o<esc>
nmap gO O<esc>

" Shortcut for =>
imap <C-l> <Space>=><Space>

" Indent/unindent in visual mode
vmap <tab> >gv
vmap <s-tab> <gv

" Reformat whole file
map <silent> <F7> mzgg=G'z :delmarks z<CR>:echo "Reformatted."<CR>

" Instant markdown
let g:instant_markdown_autostart = 0

" Open files in current file's directory
cnoremap %% <C-R>=expand('%:h').'/'<cr>
map <leader>v :view %%

" Execute current file
map <leader>e :!%:p<cr>

" Rename current file
map <leader>n :call RenameFile()<cr>

" NERDTree
map \ :NERDTreeToggle<CR>
map \| :NERDTreeFind<CR>
let NERDTreeShowHidden=1
let NERDTreeIgnore = ['\.pyc$', '^node_modules', '\.log$', 'public\/system',
      \ 'javascripts\/bundle', '^spec\/dummy', '^bower_components', '\.git',
      \ '\.DS_Store', '\.vscode', '__pycache__', '^tags', '^tags.lock$',
      \ '^tags.temp$', '^coverage', '^build\/', '__init__.py']
" Only auto-open NERDTree if the plugin is installed
if exists(':NERDTree')
  au VimEnter * NERDTree
  autocmd VimEnter * wincmd p
  autocmd BufEnter * if winnr('$') == 1 && exists('b:NERDTree') && b:NERDTree.isTabTree() | call feedkeys(":quit\<CR>:\<BS>") | endif
endif

" Remove trailing whitespace on save
autocmd FileType c,cpp,python,ruby,java,javascript autocmd BufWritePre <buffer> :%s/\s\+$//e

" Filetype overrides
au BufRead,BufNewFile *.html      setf htmldjango
au BufNewFile,BufRead *.ejs       setf html.js
au BufNewFile,BufRead *.slim      setf slim
au BufNewFile,BufRead Gemfile     setf ruby
au BufNewFile,BufRead *.rake      setf ruby
au BufNewFile,BufRead *.cap       setf ruby
au BufNewFile,BufRead *.config    setf zsh
au BufNewFile,BufRead *.json      setf javascript
au BufNewFile,BufRead *.proto     setf proto
au BufNewFile,BufRead *.gradle    setf groovy
au BufNewFile,BufRead Jenkinsfile setf groovy
au BufNewFile,BufRead *.py        setf python
au BufNewFile,BufRead *.rb        setf ruby
au BufNewFile,BufRead *.template  setf conf
au BufNewFile,BufRead Dockerfile* setf Dockerfile
au FileType groovy \
    set tabstop=4 | set shiftwidth=4 | set softtabstop=4
au Filetype python \
    set tabstop=4 | set shiftwidth=4 | set softtabstop=4 | set textwidth=79 |

" Flake8
let g:flake8_ignore="E403,E128,F403"

" Syntax alias
autocmd BufNewFile,BufRead *.conf set syntax=config

" Lightline config
let g:lightline = {
\ 'colorscheme': 'onedark',
\ 'active': {
\   'left': [['mode', 'paste'], ['filename', 'modified']],
\   'right': [['lineinfo'], ['percent'], ['readonly', 'linter_warnings', 'linter_errors', 'linter_ok']]
\ },
\ 'component_expand': {
\   'linter_warnings': 'LightlineLinterWarnings',
\   'linter_errors': 'LightlineLinterErrors',
\   'linter_ok': 'LightlineLinterOK'
\ },
\ 'component_type': {
\   'readonly': 'error',
\   'linter_warnings': 'warning',
\   'linter_errors': 'error'
\ },
\ 'component_function': {
\   'filename': 'LightLineFilename'
\ },
\ }

" ALE config
let g:ale_set_highlights = 0

" vim-jsx config
let g:jsx_ext_required = 0

" Ripgrep config
let g:rg_highlight = 1
set grepprg=rg\ --vimgrep\ --smart-case\ --hidden\ --follow
let g:rg_derive_root='true'
nnoremap <C-T> :Files<cr>
nnoremap <Leader>b :Buffers<cr>
nnoremap <Leader>s :BLines<cr>

" FZF mappings
nnoremap <Leader>ff :GitFiles<CR>
nnoremap <Leader>fb :Buffers<CR>
nnoremap <C-p> :GitFiles<CR>
nnoremap <C-t> :Rg<CR>
nnoremap <silent><leader>f :FZF -q <C-R>=expand("<cword>")<CR><CR>

" Datetime mappings
nnoremap <F5> "=strftime("%FT%T%z")<CR>P
inoremap <F5> <C-R>=strftime("%FT%T%z")<CR>

" Local vimrc customization
if filereadable(expand('~/.vimrc.local'))
  so ~/.vimrc.local
endif
