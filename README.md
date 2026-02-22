# dotfiles

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

### Zsh

**macOS:**
```sh
brew install antidote fzf ripgrep zsh-git-prompt zsh-completions
ln -s ~/Projects/dotfiles/zshrc ~/.zshrc
```

**Ubuntu:**
```sh
git clone --depth=1 https://github.com/mattmc3/antidote.git ~/.antidote
sudo apt install fzf ripgrep keychain
ln -s ~/Projects/dotfiles/zshrc ~/.zshrc
```

Then open a new shell (or `source ~/.zshrc`).

### Vim

```sh
# Install vim-plug
curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
  https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

ln -s ~/Projects/dotfiles/vimrc ~/.vimrc
```

Launch vim and run `:PlugInstall`.

### Tmux

**macOS:** `brew install tmux`
**Ubuntu:** `sudo apt install tmux`

```sh
ln -s ~/Projects/dotfiles/tmux.conf ~/.tmux.conf
```

### Git

```sh
cp ~/Projects/dotfiles/gitconfig ~/.gitconfig
```

Edit `~/.gitconfig` to set your name, email, and any local overrides.

## Color schemes

Using [One Dark](https://github.com/joshdick/onedark.vim) via terminal color preferences (no vim plugin needed).
