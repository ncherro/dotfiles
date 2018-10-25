" *********************************************
" *          Vim Plugins             *
" *********************************************
call plug#begin()

" Navigation
Plug '/usr/local/opt/fzf'
Plug 'junegunn/fzf.vim'
Plug 'scrooloose/nerdtree'
Plug 'vim-scripts/IndexedSearch'
Plug 'vim-scripts/matchit.zip'
Plug 'tpope/vim-unimpaired'
Plug 'jeetsukumaran/vim-buffergator'
Plug 'ludovicchabant/vim-gutentags'

" Syntax
Plug 'pangloss/vim-javascript'
Plug 'slim-template/vim-slim'
Plug 'mtscout6/vim-cjsx'
Plug 'mxw/vim-jsx'
Plug 'fatih/vim-go', { 'do': ':GoUpdateBinaries' }
Plug 'editorconfig/editorconfig-vim'
Plug 'cespare/vim-toml'
Plug 'uarun/vim-protobuf'

" Gist
Plug 'mattn/webapi-vim'
Plug 'mattn/gist-vim'

" Formatting
Plug 'scrooloose/nerdcommenter'
Plug 'godlygeek/tabular'
Plug 'editorconfig/editorconfig-vim'

" Autocomplete
Plug 'Shougo/deoplete.nvim', { 'do': ':UpdateRemotePlugins' }
Plug 'tpope/vim-surround'
Plug 'tpope/vim-endwise'
Plug 'msanders/snipmate.vim'
Plug 'mattn/emmet-vim'
Plug 'Raimondi/delimitMate'
Plug 'ervandew/supertab'

" Bar
Plug 'itchyny/lightline.vim'

" Markdown
Plug 'suan/vim-instant-markdown'

Plug 'rizzatti/funcoo.vim'
Plug 'rizzatti/dash.vim'
Plug 'tpope/vim-dispatch'

" Git
Plug 'sjl/gundo.vim'

" Rails
Plug 'tpope/vim-rails'
Plug 'tpope/vim-rake'
Plug 'tpope/vim-haml'

" Ruby
Plug 'fishbullet/deoplete-ruby'

" Go
Plug 'zchee/deoplete-go', { 'do': 'make'}      " Go auto completion
Plug 'zchee/deoplete-jedi'                     " Go auto completion

" Cucumber
Plug 'tpope/vim-cucumber'

" Elixir
Plug 'elixir-lang/vim-elixir'

" Python
Plug 'nvie/vim-flake8'
Plug 'vim-scripts/indentpython'

" Git
Plug 'tpope/vim-fugitive'

" JS tests
Plug 'janko-m/vim-test'

" Color schemes / colors
Plug 'w0ng/vim-hybrid'
Plug 'ap/vim-css-color'

" Async linting
Plug 'w0rp/ale'

call plug#end()


" *********************************************
" *                 Settings                  *
" *********************************************
syntax enable
filetype plugin indent on         " load file type plugins + indentation

set showcmd                       " Display incomplete commands.
set showmode                      " Display the mode you're in.
set showmatch                     " Show matching brackets/parenthesis

" ctags
set tags=tags

set noswapfile
set nobackup
set nowb

set colorcolumn=80
set cursorline

set list listchars=tab:\ \ ,trail:·

set nowrap                        " don't wrap lines
set tabstop=2 shiftwidth=2        " a tab is two spaces
set expandtab                     " use spaces, not tabs
set backspace=indent,eol,start    " backspace through everything in insert mode
set autoindent                    " match indentation of previous line
set pastetoggle=<F2>

set incsearch                     " Find as you type search
set hlsearch                      " Highlight search terms
set ignorecase                    " Case-insensitive searching.
set smartcase                     " But case-sensitive if expression contains a capital letter.

set foldmethod=indent             "fold based on indent
set foldnestmax=3                 "deepest fold is 3 levels
set nofoldenable                  "dont fold by default

set hidden                        " Handle multiple buffers better.
set title                         " Set the terminal's title
set number                        " Show line numbers.
set ruler                         " Show cursor position.
set wildmode=list:longest         " Complete files like a shell.
set wildmenu                      " Enhanced command line completion.
set novisualbell
set noerrorbells
set history=1000                  " Store lots of :cmdline history

set scrolloff=3
set sidescrolloff=7

set mouse-=a
set mousehide
if !has('nvim')
  set ttymouse=xterm2
endif
set sidescroll=1

set nobackup                      " Don't make a backup before overwriting a file.
set nowritebackup                 " And again.
set directory=/tmp                " Keep swap files in one location
set timeoutlen=500

set laststatus=2                  " Show the status line all the time
set statusline=%f

" color scheme
set background=dark
let g:hybrid_custom_term_colors = 1
let g:hybrid_reduced_contrast = 1
colorscheme hybrid

" *********************************************
" *                 Functions                 *
" *********************************************

" Find Cucumber's unused steps
command! CucumberFindUnusedSteps :call CucumberFindUnusedSteps()
function! CucumberFindUnusedSteps()
  let olderrorformat = &l:errorformat
  try
    set errorformat=%m#\ %f:%l
    cexpr system('bundle exec cucumber --no-profile --no-color --format usage --dry-run features \| grep "NOT MATCHED BY ANY STEPS" -B1 \| egrep -v "(--\|NOT MATCHED BY ANY STEPS)"')
    cwindow
  finally
    let &l:errorformat = olderrorformat
  endtry
endfunction

function! RenameFile()
    let old_name = expand('%')
    let new_name = input('New file name: ', expand('%'), 'file')
    if new_name != '' && new_name != old_name
        exec ':saveas ' . new_name
        exec ':silent !rm ' . old_name
        redraw!
    endif
endfunction

" *********************************************
" *               Key Bindings                *
" *********************************************
let mapleader = ","

" ============================
" Rails
" ============================
" Better key maps for switching between controller and view
nnoremap ,vv :Rview<cr>
nnoremap ,cc :Rcontroller<cr>

" Clear last search highlighting
nnoremap <Space> :noh<cr>

" Create window splits easier. The default
" way is Ctrl-w,v and Ctrl-w,s. I remap
" this to vv and ss
nnoremap <silent> vv <C-w>v
nnoremap <silent> ss <C-w>s

" paste
nnoremap <silent> pp :read !pbpaste<CR>

"Clear current search highlight by double tapping //
nmap <silent> // :nohlsearch<CR>

" Flip buffers
nnoremap <Leader>l :ls<CR>
nnoremap <Leader>b :bp<CR>
" nnoremap <Leader>f :bn<CR>
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

" Easier navigation between split windows
nnoremap <C-j> <C-w>j
nnoremap <C-k> <C-w>k
nnoremap <C-h> <C-w>h
nnoremap <C-l> <C-w>l

" Insert blank lines without going into insert mode
nmap go o<esc>
nmap gO O<esc>

" Shortcut for =>
imap <C-l> <Space>=><Space>

" indent/unindent visual mode selection with tab/shift+tab
vmap <tab> >gv
vmap <s-tab> <gv

" F7 reformats the whole file and leaves you where you were (unlike gg)
map <silent> <F7> mzgg=G'z :delmarks z<CR>:echo "Reformatted."<CR>

" open files in directory of current file
cnoremap %% <C-R>=expand('%:h').'/'<cr>
map <leader>v :view %%

" execute current file
map <leader>e :!%:p<cr>

" rename current file
map <leader>n :call RenameFile()<cr>

" File tree browser - backslash
map \ :NERDTreeToggle<CR>
" File tree browser showing current file - pipe
map \| :NERDTreeFind<CR>
" Ignore files in nerdtree
let NERDTreeShowHidden=1
let NERDTreeIgnore = ['\.pyc$', '^node_modules', '\.log$', 'public\/system',
      \ 'javascripts\/bundle', '^spec\/dummy', '^bower_components', '\.git',
      \ '\.DS_Store', '\.vscode', '__pycache__', '^tags', '^tags.lock$',
      \ '^tags.temp$', '^coverage', '^build\/', '__init__.py']

silent! map <unique> <Leader>w :!bundle exec cucumber --profile=wip<CR>

" Remove trailing whitspace on save
autocmd FileType c,cpp,python,ruby,java,javascript autocmd BufWritePre <buffer> :%s/\s\+$//e

" *********************************************
" *           Plugin Customization            *
" *********************************************

" Override filetype
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
au BufNewFile,BufRead Dockerfile* setf Dockerfile

" Groovy
au FileType groovy 
    \ set tabstop=4 |
    \ set shiftwidth=4 |
    \ set softtabstop=4

" Python
au Filetype python
    \ set tabstop=4 |
    \ set shiftwidth=4 |
    \ set softtabstop=4 |
    \ set textwidth=79 |

" Go
if has('nvim')
    " Enable deoplete on startup
    let g:deoplete#enable_at_startup = 1
endif

" Disable deoplete when in multi cursor mode
function! Multiple_cursors_before()
    let b:deoplete_disable_auto_complete = 1
endfunction

function! Multiple_cursors_after()
    let b:deoplete_disable_auto_complete = 0
endfunction

"" Enable completing of go pointers
"let g:deoplete#sources#go#pointer = 1

" Highlighting
let g:go_highlight_build_constraints = 1
let g:go_highlight_extra_types = 1
let g:go_highlight_fields = 1
let g:go_highlight_functions = 1
let g:go_highlight_methods = 1
let g:go_highlight_operators = 1
let g:go_highlight_structs = 1
let g:go_highlight_types = 1

" Groovy

" flake8
let g:flake8_ignore="E403,E128,F403"

" syntax alias
autocmd BufNewFile,BufRead *.conf set syntax=config

" go
" let g:go_auto_sameids = 1

" *********************************************
" *        Local Vimrc Customization          *
" *********************************************
if filereadable(expand('~/.vimrc.local'))
  so ~/.vimrc.local
endif

function! RSpecFile()
  execute "Dispatch docker-compose exec app rspec " . expand("%p")
endfunction
map <leader>R :call RSpecFile() <CR>
command! RSpecFile call RSpecFile()

function! RSpecCurrent()
  execute "Dispatch docker-compose exec app rspec " . expand("%p") . ":" . line(".")
endfunction
map <leader>r :call RSpecCurrent() <CR>
command! RSpecCurrent call RSpecCurrent()

let g:test#strategy = 'dispatch'
let g:test#runner_commands = ['Mocha']
let test#javascript#mocha#options = '--compilers js:babel-core/register --recursive'

" redraw everything
map <leader>d :redraw! <CR>

" Lightline
let g:lightline = {
\ 'colorscheme': 'wombat',
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

autocmd User ALELint call s:MaybeUpdateLightline()

" Update and show lightline but only if it's visible (e.g., not in Goyo)
function! s:MaybeUpdateLightline()
  if exists('#lightline')
    call lightline#update()
  end
endfunction

" ale
let g:ale_set_highlights = 0

" vim-jsx
let g:jsx_ext_required = 0

" fzf
nnoremap <Leader>ff :GitFiles<CR>
nnoremap <Leader>fb :Buffers<CR>
nnoremap <Leader>fa :Find<Space>
nnoremap <C-p> :GitFiles<CR>

" ripgrep
let g:rg_highlight = 1

" --column: Show column number
" --line-number: Show line number
" --no-heading: Do not show file headings in results
" --fixed-strings: Search term as a literal string
" --ignore-case: Case insensitive search
" --hidden: Search hidden files and folders
" --follow: Follow symlinks
" --glob: Additional conditions for search (in this case ignore everything in the .git/ folder)
" --color: Search color options
command! -bang -nargs=* Find call fzf#vim#grep('rg --column --line-number --no-heading --fixed-strings --ignore-case --hidden --follow --glob "!.git/*" --color "always" '.shellescape(<q-args>), 1, <bang>0)

" datetime
:nnoremap <F5> "=strftime("%FT%T%z")<CR>P
:inoremap <F5> <C-R>=strftime("%FT%T%z")<CR>
