# dotfiles 🏠

Config for zsh, vim, tmux, and git. Works on macOS and Linux (Ubuntu).

## Guiding principles

- Cross-platform: keep base.zsh universal, platform-specific code in mac.zsh/linux.zsh
- Git-centric: sessions, branches, and navigation derive from git context
- Short aliases, small composable functions that chain together
- Minimal UI: transparent backgrounds, no chrome
- Local overrides via .local files, never committed
- Self-bootstrapping: new machine setup should just be symlinks

## Structure

```
zshrc                  # entry point — detects OS, sources platform + base
zsh/
  base.zsh             # cross-platform config (aliases, functions, prompt, tools)
  mac.zsh              # macOS-specific (Homebrew, NVM, etc.)
  linux.zsh            # Linux-specific (antidote, keychain, etc.)
zsh_plugins.txt        # antidote plugin list
zshrc.local.example    # template for machine-local overrides
tmux.conf
vimrc
kitty.conf
gitconfig
claude/settings.json   # symlinked to ~/.claude/settings.json
```

`~/.zshrc.local` is sourced automatically but never committed — use it for machine-local or sensitive config. See `zshrc.local.example` for a template.

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
ln -s ~/Projects/dotfiles/vimrc ~/.vimrc
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

### Ubuntu

```sh
# Antidote (zsh plugin manager)
git clone --depth=1 https://github.com/mattmc3/antidote.git ~/.antidote

sudo apt install zsh fzf ripgrep keychain gh tmux vim xclip

# Symlink configs
ln -s ~/Projects/dotfiles/zshrc ~/.zshrc
ln -s ~/Projects/dotfiles/tmux.conf ~/.tmux.conf
ln -s ~/Projects/dotfiles/vimrc ~/.vimrc
mkdir -p ~/.claude
ln -s ~/Projects/dotfiles/claude/settings.json ~/.claude/settings.json

# Vim plugins
curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
  https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

# Git
cp ~/Projects/dotfiles/gitconfig ~/.gitconfig
```

Open a new shell, launch vim and run `:PlugInstall`, then edit `~/.gitconfig` to set your name and email.

**WSL only:** `sudo apt install wslu` — needed for `ghopen`/`ghpr` to open URLs in the Windows browser.

## Color schemes

Using [One Dark](https://github.com/joshdick/onedark.vim) via terminal / kitty color preferences.
