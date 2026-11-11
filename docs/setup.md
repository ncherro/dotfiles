[← dotfiles](../README.md)

# Setup

```sh
mkdir -p ~/Projects ~/workspace
git clone https://github.com/ncherro/dotfiles ~/Projects/dotfiles
```

## macOS

```sh
brew install antidote fzf ripgrep zsh-git-prompt zsh-completions nvm gh tmux terminal-notifier

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

# Vim plugins
curl -fLo ~/.vim/autoload/plug.vim --create-dirs \
  https://raw.githubusercontent.com/junegunn/vim-plug/master/plug.vim

# Git
cp ~/Projects/dotfiles/gitconfig ~/.gitconfig
```

Open a new shell, launch vim and run `:PlugInstall`, then edit `~/.gitconfig` to set your name and email.

## Claude Code notifications (macOS)

`bin/claude-notify` posts a notification when Claude Code is waiting on you; clicking it focuses kitty and switches tmux to the session, window, and pane running that Claude. Without `terminal-notifier` it falls back to a plain, non-clickable notification; on Linux it does nothing. Add it to the `hooks` in `~/.claude/settings.json` (that file isn't kept in this repo):

```json
"Notification": [
  { "matcher": "idle_prompt",
    "hooks": [{ "type": "command", "command": "~/Projects/dotfiles/bin/claude-notify" }] },
  { "matcher": "permission_prompt",
    "hooks": [{ "type": "command", "command": "~/Projects/dotfiles/bin/claude-notify Submarine" }] }
]
```

macOS can deny `terminal-notifier` silently on first use, so it never shows up under System Settings → Notifications. If running it says notifications are turned off, reset the permission and run it again, then click Allow:

```sh
tccutil reset UserNotification fr.julienxx.oss.terminal-notifier
terminal-notifier -title test -message test
```

**WSL only:** `sudo apt install wslu` — needed for `ghr`/`ghp` to open URLs in the Windows browser.
