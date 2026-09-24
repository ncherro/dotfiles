[← dotfiles](../README.md)

# Setup

```sh
mkdir -p ~/Projects ~/workspace
git clone https://github.com/ncherro/dotfiles ~/Projects/dotfiles
```

## macOS

```sh
brew install antidote fzf ripgrep zsh-git-prompt zsh-completions nvm gh tmux

# Symlink configs
# ~/.zshrc is a real file, not a symlink: corporate tooling that rewrites a
# shell rc in place would otherwise write straight into this repo.
cat > ~/.zshrc <<'RC'
source ~/Projects/dotfiles/zshrc
RC
ln -s ~/Projects/dotfiles/tmux.conf ~/.tmux.conf
ln -s ~/Projects/dotfiles/vimrc ~/.vimrc
ln -s ~/Projects/dotfiles/gitignore_global ~/.gitignore
mkdir -p ~/.config/kitty
ln -s ~/Projects/dotfiles/kitty.conf ~/.config/kitty/kitty.conf
mkdir -p ~/.claude
ln -s ~/Projects/dotfiles/claude/settings.json ~/.claude/settings.json

# Vim plugins
curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
  https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

# Git
cp ~/Projects/dotfiles/gitconfig ~/.gitconfig
```

Open a new shell, launch vim and run `:PlugInstall`, then edit `~/.gitconfig` to set your name and email.

## Ubuntu

```sh
# Antidote (zsh plugin manager)
git clone --depth=1 https://github.com/mattmc3/antidote.git ~/.antidote

sudo apt install zsh fzf ripgrep keychain gh tmux vim xclip

# Symlink configs
# ~/.zshrc is a real file, not a symlink: corporate tooling that rewrites a
# shell rc in place would otherwise write straight into this repo.
cat > ~/.zshrc <<'RC'
source ~/Projects/dotfiles/zshrc
RC
ln -s ~/Projects/dotfiles/tmux.conf ~/.tmux.conf
ln -s ~/Projects/dotfiles/vimrc ~/.vimrc
ln -s ~/Projects/dotfiles/gitignore_global ~/.gitignore
mkdir -p ~/.claude
ln -s ~/Projects/dotfiles/claude/settings.json ~/.claude/settings.json

# Vim plugins
curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
  https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

# Git
cp ~/Projects/dotfiles/gitconfig ~/.gitconfig
```

Open a new shell, launch vim and run `:PlugInstall`, then edit `~/.gitconfig` to set your name and email.

**WSL only:** `sudo apt install wslu` — needed for `ghr`/`ghp` to open URLs in the Windows browser.
