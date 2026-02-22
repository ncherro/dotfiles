# dotfiles 🏠

Config for zsh, vim, tmux, and git. Works on macOS and Linux (Ubuntu).

## Structure

```
zshrc                  # entry point — detects OS, sources platform + base
zsh/
  base.zsh             # cross-platform config (~90% of everything)
  mac.zsh              # macOS-specific (Homebrew, NVM, Java, etc.)
  linux.zsh            # Linux-specific (antidote, keychain, etc.)
zsh_plugins.txt        # antidote plugin list (shared)
zshrc.local.example    # template for machine-local overrides
vimrc
tmux.conf
gitconfig
```

Machine-specific or sensitive config (work credentials, internal tools, etc.) goes in `~/.zshrc.local`, which is sourced automatically but never committed. See `zshrc.local.example` for a template.

## Setup

Clone the repo:

```sh
git clone https://github.com/ncherro/dotfiles ~/Projects/dotfiles
```

### macOS

```sh
brew install antidote fzf ripgrep zsh-git-prompt zsh-completions nvm gh tmux

# Symlink configs
ln -s ~/Projects/dotfiles/zshrc ~/.zshrc
ln -s ~/Projects/dotfiles/tmux.conf ~/.tmux.conf

# Vim
curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
  https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
ln -s ~/Projects/dotfiles/vimrc ~/.vimrc

# Git
cp ~/Projects/dotfiles/gitconfig ~/.gitconfig
```

Open a new shell, launch vim and run `:PlugInstall`, then edit `~/.gitconfig` to set your name and email.

### Ubuntu

```sh
# Antidote (zsh plugin manager)
git clone --depth=1 https://github.com/mattmc3/antidote.git ~/.antidote

sudo apt install zsh fzf ripgrep keychain gh tmux vim xclip

# Symlink configs
ln -s ~/Projects/dotfiles/zshrc ~/.zshrc
ln -s ~/Projects/dotfiles/tmux.conf ~/.tmux.conf

# Vim
curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
  https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim
ln -s ~/Projects/dotfiles/vimrc ~/.vimrc

# Git
cp ~/Projects/dotfiles/gitconfig ~/.gitconfig
```

Open a new shell, launch vim and run `:PlugInstall`, then edit `~/.gitconfig` to set your name and email.

**WSL only:** `sudo apt install wslu` — needed for `ghopen`/`ghpr` to open URLs in the Windows browser.

## Color schemes

Using [One Dark](https://github.com/joshdick/onedark.vim) via terminal / kitty color preferences.
