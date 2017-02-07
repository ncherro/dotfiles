" *********************************************
" *          Vundle - Vim Plugins             *
" *********************************************
call plug#begin()

" Let Vundle manage Vundle
Plug 'gmarik/vundle'

" Navigation
Plug 'junegunn/fzf', { 'dir': '~/.fzf', 'do': './install --all' }
Plug 'junegunn/fzf.vim'
Plug 'scrooloose/nerdtree'
Plug 'vim-scripts/IndexedSearch'
Plug 'vim-scripts/matchit.zip'
Plug 'tpope/vim-unimpaired'
Plug 'jeetsukumaran/vim-buffergator'

" Syntax
"Plug 'scrooloose/syntastic'
Plug 'pangloss/vim-javascript'
Plug 'kchmck/vim-coffee-script'
Plug 'groenewege/vim-less'
Plug 'Handlebars'
Plug 'yaymukund/vim-rabl'
Plug 'slim-template/vim-slim'
Plug 'ngmy/vim-rubocop'
Plug 'mtscout6/vim-cjsx'
Plug 'mxw/vim-jsx'
Plug 'fatih/vim-go'
Plug 'editorconfig/editorconfig-vim'
Plug 'cespare/vim-toml'
"Plug 'facebook/vim-flow', { 'autoload' : { 'filetypes' : 'javascript' } }

" Gist
Plug 'mattn/webapi-vim'
Plug 'mattn/gist-vim'

" Formatting
Plug 'scrooloose/nerdcommenter'
Plug 'Align'
Plug 'godlygeek/tabular'
Plug 'editorconfig/editorconfig-vim'

" Autocomplete
Plug 'tpope/vim-surround'
Plug 'tpope/vim-endwise'
Plug 'msanders/snipmate.vim'
Plug 'mattn/emmet-vim'
Plug 'Raimondi/delimitMate'
Plug 'ervandew/supertab'
Plug 'vim-scripts/loremipsum'
"Plug 'Valloric/YouCompleteMe'

Plug 'vim-airline/vim-airline'
Plug 'vim-airline/vim-airline-themes'
Plug 'rizzatti/funcoo.vim'
Plug 'rizzatti/dash.vim'
Plug 'tpope/vim-rvm'
Plug 'tpope/vim-dispatch'

"Plug 'Floobits/floobits-vim'

" Git
Plug 'sjl/gundo.vim'

" Rails
Plug 'tpope/vim-rails'
Plug 'tpope/vim-rake'
Plug 'tpope/vim-haml'

" Cucumber
Plug 'tpope/vim-cucumber'
Plug 'git://gist.github.com/287147.git'

" Ruby
Plug 'skalnik/vim-vroom'

" Elixir
Plug 'elixir-lang/vim-elixir'

" Python
Plug 'nvie/vim-flake8'

" Git
Plug 'tpope/vim-fugitive'

" JS tests
Plug 'janko-m/vim-test'

" Color schemes
Plug 'altercation/vim-colors-solarized'
Plug 'morhetz/gruvbox'
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
set tags=tags;

set noswapfile
set nobackup
set nowb

set colorcolumn=80
set cursorline

set list listchars=tab:\ \ ,trail:·

set nowrap                        " don't wrap lines
set tabstop=2 shiftwidth=2        " a tab is two spaces (or set this to 4)
set expandtab                     " use spaces, not tabs (optional)
set backspace=indent,eol,start    " backspace through everything in insert mode"
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
if has('nvim')
  nmap <BS> <C-W>h
endif
set sidescroll=1

set nobackup                      " Don't make a backup before overwriting a file.
set nowritebackup                 " And again.
set directory=/tmp                " Keep swap files in one location
set timeoutlen=500

set laststatus=2                  " Show the status line all the time
" set statusline=[%n]\ %<%.99f\ %h%w%m%r%y\ %{exists('*CapsLockStatusline')?CapsLockStatusline():''}%=%-16(\ %l,%c-%v\ %)%P
set statusline=%f


set background=dark
" let g:solarized_termcolors=16
colorscheme solarized


autocmd FileType python setlocal tabstop=8 expandtab shiftwidth=4 softtabstop=4

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
nnoremap <Leader>f :bn<CR>
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

" ============================
" Greeper
" ============================
"nmap <silent> <leader>g :G<CR>


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

" AckGrep current word
map <leader>a :call AckGrep()<CR>
" AckVisual current selection
vmap <leader>a :call AckVisual()<CR>

" File tree browser - backslash
map \ :NERDTreeToggle<CR>
" File tree browser showing current file - pipe
map \| :NERDTreeFind<CR>
" Ignore files in nerdtree
let NERDTreeIgnore = ['\.pyc$', '^node_modules', '\.log$', 'public\/system',
      \ 'javascripts\/bundle', '^spec\/dummy', '^bower_components', '^dist',
      \ '^build', '^styleguide-build', '^styleguide-dist']

let g:vroom_map_keys = 0
silent! map <unique> <Leader>t :VroomRunTestFile<CR>
silent! map <unique> <Leader>T :VroomRunNearestTest<CR>
silent! map <unique> <Leader>w :!bundle exec cucumber --profile=wip<CR>

" Remove trailing whitspace on save
autocmd FileType c,cpp,python,ruby,java,javascript autocmd BufWritePre <buffer> :%s/\s\+$//e

" *********************************************
" *           Plugin Customization            *
" *********************************************

" Handlebars
au BufRead,BufNewFile *.handlebars,*.hbs set ft=handlebars

" Override filetype
au BufRead,BufNewFile *.html set ft=htmldjango
au BufNewFile,BufRead *.ejs set ft=html.js
au BufNewFile,BufRead *.slim set ft=slim
au BufNewFile,BufRead Gemfile set ft=ruby
au BufNewFile,BufRead *.cap set ft=ruby

" flake8
let g:flake8_ignore="E403,E128,F403"
autocmd BufWritePost *.py call Flake8()

" syntax alias
autocmd BufNewFile,BufRead *.conf set syntax=config

" *********************************************
" *        Local Vimrc Customization          *
" *********************************************
if filereadable(expand('~/.vimrc.local'))
  so ~/.vimrc.local
endif

function! RSpecFile()
  execute "Dispatch zeus rspec " . expand("%p")
endfunction
map <leader>R :call RSpecFile() <CR>
command! RSpecFile call RSpecFile()

function! RSpecCurrent()
  execute "Dispatch zeus rspec " . expand("%p") . ":" . line(".")
endfunction
map <leader>r :call RSpecCurrent() <CR>
command! RSpecCurrent call RSpecCurrent()

let g:test#strategy = 'dispatch'
let g:test#runner_commands = ['Mocha']
let test#javascript#mocha#options = '--compilers js:babel-core/register --recursive'

" redraw everything
map <leader>d :redraw! <CR>

" vim-airline
let g:airline_left_sep=''
let g:airline_right_sep=''

" vim-jsx
let g:jsx_ext_required = 0

" fzf
nnoremap <Leader>ff :GitFiles<CR>
nnoremap <Leader>fb :Buffers<CR>
nnoremap <Leader>fa :Ag<Space>
nnoremap <C-p> :GitFiles<CR>


" datetime
" TODO: figure out how to get colon into the %z for iso
:nnoremap <F5> "=strftime("%FT%T%z")<CR>P
:inoremap <F5> <C-R>=strftime("%FT%T%z")<CR>

