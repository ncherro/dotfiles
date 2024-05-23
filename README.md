## Prereqs

1. `brew install fzf` [for fuzzy finding functionality](https://github.com/junegunn/fzf)
1. `brew install ctags` to support gutentags
1. `brew install ripgrep` to support Vim `:Find`

## Zsh

Better than bash

1. `brew install zsh`
1. `brew install antigen`
1. `ln -s /path/to/this/dir/zshrc ~/.zshrc`
1. `source ~/.zshrc` (or open a new shell)

## Vim

1. `ln -s /path/to/this/dir/vimrc ~/.vimrc`
1. launch `vim` (aliased to `v` in .zshrc) and run `:PluginInstall`

## Color schemes

Hybrid - https://github.com/chadmayfield/hybrid-terminal-theme

Rose Pine - https://github.com/rose-pine/terminal.app

## Tmux

1. `brew install tmux`
1. `ln -s /path/to/this/dir/tmux.conf ~/.tmux.conf`

## Git config

1. `cp /path/to/this/dir/gitconfig ~/.gitconfig` and edit the file to override
   your username, etc
