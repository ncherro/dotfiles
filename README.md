## Prereqs

1. install [iTerm2](https://www.iterm2.com/)
1. install [inconsolata](http://levien.com/type/myfonts/inconsolata.html)
1. `brew install fzf` [for fuzzy finding functionality](https://github.com/junegunn/fzf)
1. `brew install ctags` to support gutentags
1. `brew install ripgrep` to support Vim `:Find`

## Zsh

Better than bash

1. `brew install zsh`
1. `brew install antigen`
1. `ln -s /path/to/this/dir/zshrc ~/.zshrc`
1. `source ~/.zshrc` (or open a new shell)

## Neovim

My vimrc file will also work with vim8, but neovim is noticeably faster - not
sure why

1. `brew install neovim`
1. install [plug](https://github.com/junegunn/vim-plug#neovim)
1. `mkdir -p ~/.config/nvim; cd ~/.config/nvim` then symlink this repo's vimrc file to init.vim
1. launch `nvim` (aliased to `v` in .zshrc) and run `:PluginInstall`

## Hybrid color scheme

After years of using solarized dark I switched to the reduced contrast
[hybrid](https://github.com/w0ng/vim-hybrid) color scheme, and my life is much
better

Install the iTerm2 reduced contrast color theme
[like this](https://github.com/w0ng/vim-hybrid#osx-users-iterm)

## Tmux

1. `brew install tmux`
1. `ln -s /path/to/this/dir/tmux.conf ~/.tmux.conf`

## Git config

1. `cp /path/to/this/dir/gitconfig ~/.gitconfig` and edit the file to override
   your username, etc
