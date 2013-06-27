set nocompatible                  " Must come first because it changes other options.
filetype off                      " Necessary on some Linux distros for pathogen to properly load bundles

" *********************************************
" *          Vundle - Vim Plugins             *
" *********************************************
set rtp+=~/.vim/bundle/vundle/
call vundle#rc()

" Let Vundle manage Vundle
Bundle 'gmarik/vundle'

" Navigation
Bundle 'kien/ctrlp.vim'
Bundle 'rking/ag.vim'
Bundle 'scrooloose/nerdtree'
Bundle 'vim-scripts/IndexedSearch'
Bundle 'vim-scripts/matchit.zip'
Bundle 'tpope/vim-unimpaired'
Bundle 'jeetsukumaran/vim-buffergator'

" Syntax
Bundle 'Syntastic'
Bundle 'pangloss/vim-javascript'
Bundle 'kchmck/vim-coffee-script'
Bundle 'groenewege/vim-less'
Bundle 'Handlebars'
Bundle 'yaymukund/vim-rabl'
Bundle 'slim-template/vim-slim'

" Gist
Bundle 'mattn/webapi-vim'
Bundle 'mattn/gist-vim'

" Formatting
Bundle 'scrooloose/nerdcommenter'
Bundle 'Align'
Bundle 'godlygeek/tabular'
Bundle 'editorconfig/editorconfig-vim'

" Autocomplete
Bundle 'tpope/vim-surround'
"Bundle 'tpope/vim-endwise'
Bundle 'msanders/snipmate.vim'
Bundle 'mattn/zencoding-vim'
Bundle 'Raimondi/delimitMate'
Bundle 'ervandew/supertab'
Bundle 'vim-scripts/loremipsum'

" Rails
Bundle 'tpope/vim-rails'
Bundle 'tpope/vim-rake'
Bundle 'tpope/vim-haml'

" Cucumber
Bundle 'tpope/vim-cucumber'
Bundle 'git://gist.github.com/287147.git'

" Ruby
Bundle 'skalnik/vim-vroom'

" Python
Bundle 'nvie/vim-flake8'

" Git
Bundle 'tpope/vim-fugitive'

" Color scheme
Bundle 'altercation/vim-colors-solarized'


" *********************************************
" *                 Settings                  *
" *********************************************
set encoding=utf-8
syntax enable
filetype plugin indent on         " load file type plugins + indentation

set showcmd                       " Display incomplete commands.
set showmode                      " Display the mode you're in.
set showmatch                     " Show matching brackets/parenthesis

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
set ttymouse=xterm2
set sidescroll=1

set nobackup                      " Don't make a backup before overwriting a file.
set nowritebackup                 " And again.
set directory=/tmp                " Keep swap files in one location
set timeoutlen=500

set laststatus=2                  " Show the status line all the time
set statusline=[%n]\ %<%.99f\ %h%w%m%r%y\ %{exists('*CapsLockStatusline')?CapsLockStatusline():''}%=%-16(\ %l,%c-%v\ %)%P

set t_Co=256                      " Set terminal to 256 colors
set background=dark
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

" Clear last search highlighting
nnoremap <Space> :noh<cr>

" Easier navigation between split windows
nnoremap <c-j> <c-w>j
nnoremap <c-k> <c-w>k
nnoremap <c-h> <c-w>h
nnoremap <c-l> <c-w>l

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
map <leader>e :edit %%
map <leader>v :view %%

" rename current file
map <leader>n :call RenameFile()<cr>

" AckGrep current word
map <leader>a :call AckGrep()<CR>
" AckVisual current selection
vmap <leader>a :call AckVisual()<CR>

" File tree browser - backslash
map \ :NERDTreeToggle<CR>
" File tree browser showing current file - pipe (shift-backslash)
map \| :NERDTreeFind<CR>
" Ignore files in nerdtree
let NERDTreeIgnore = ['\.pyc$', '^node_modules', '\.log$']

let g:vroom_map_keys = 0
silent! map <unique> <Leader>t :VroomRunTestFile<CR>
silent! map <unique> <Leader>T :VroomRunNearestTest<CR>
silent! map <unique> <Leader>w :!bundle exec cucumber --profile=wip<CR>

" Remove trailing whitspace on save
autocmd FileType c,cpp,python,ruby,java,javascript autocmd BufWritePre <buffer> :%s/\s\+$//e

" *********************************************
" *           Plugin Customization            *
" *********************************************

" ctrlp.vim ignore
set wildignore=*.o,*.obj,*~
set wildignore+=*/.git/*,*/.hg/*,*/.svn/*,*/public/cache/*
set wildignore+=*/tmp/*,*.so,*.swp,*.zip,*.log,*.pyc,node_modules

" Handlebars
au BufRead,BufNewFile *.handlebars,*.hbs set ft=handlebars

" Django html
au BufRead,BufNewFile *.html set ft=htmldjango
au BufNewFile,BufRead *.ejs set ft=html.js

" flake8
let g:flake8_ignore="E403,E128,F403"
autocmd BufWritePost *.py call Flake8()

" *********************************************
" *        Local Vimrc Customization          *
" *********************************************
if filereadable(expand('~/.vimrc.local'))
  so ~/.vimrc.local
endif
