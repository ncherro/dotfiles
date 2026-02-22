# dotfiles

Personal config for zsh, vim, tmux, kitty, and git. Targets macOS and Linux (Ubuntu/WSL2).

## Structure

```
zshrc                  # entry point — detects OS, sources platform + base
zsh/
  base.zsh             # cross-platform config (aliases, functions, prompt, tools)
  mac.zsh              # macOS-specific (Homebrew, NVM, etc.)
  linux.zsh            # Linux-specific (antidote, keychain, etc.)
zsh_plugins.txt        # antidote plugin list
tmux.conf
vimrc
kitty.conf
gitconfig
claude/settings.json   # symlinked to ~/.claude/settings.json
```

`~/.zshrc.local` is sourced automatically but never committed — use it for machine-local or sensitive config.

## Reloading configs

- **tmux**: `prefix + r` (bound to `source-file ~/.tmux.conf`)
- **zsh**: `source ~/.zshrc`
- **vim**: `:source ~/.vimrc`

## Symlink setup

```sh
ln -s ~/Projects/dotfiles/zshrc ~/.zshrc
ln -s ~/Projects/dotfiles/tmux.conf ~/.tmux.conf
ln -s ~/Projects/dotfiles/vimrc ~/.vimrc
ln -s ~/Projects/dotfiles/kitty.conf ~/.config/kitty/kitty.conf
ln -s ~/Projects/dotfiles/claude/settings.json ~/.claude/settings.json
```

## Cross-platform notes

- Keep changes compatible with both macOS and Linux unless explicitly platform-specific
- Platform-specific code belongs in `zsh/mac.zsh` or `zsh/linux.zsh`
- Clipboard commands differ: `pbpaste`/`pbcopy` on macOS, `xclip` on Linux — tmux.conf handles this with `if-shell`
