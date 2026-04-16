# dotfiles 🏠

Config for zsh, vim, tmux, and git. Optimized for jumping between projects and branches, using Claude Code and Vim. Works on macOS and Linux (Ubuntu).

## Conventions

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
  tmux-workflows.zsh   # tmux + worktree workflow helpers (standalone, shareable)
  mac.zsh              # macOS-specific (Homebrew, NVM, etc.)
  linux.zsh            # Linux-specific (antidote, keychain, etc.)
zsh_plugins.txt        # antidote plugin list
zshrc.local.example    # template for machine-local overrides
bin/
  worktree-cleanup.sh  # clean up merged worktrees, stale sessions, and build caches
tmux.conf
vimrc
kitty.conf
gitconfig
claude/settings.json   # symlinked to ~/.claude/settings.json
```

`~/.zshrc.local` is sourced automatically but never committed — use it for machine-local or sensitive config. See `zshrc.local.example` for a template.

## Setup

```sh
mkdir -p ~/Projects ~/workspace ~/worktrees
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

**WSL only:** `sudo apt install wslu` — needed for `ghr`/`ghp` to open URLs in the Windows browser.

## tmux-workflows

`zsh/tmux-workflows.zsh` is a standalone plugin that bundles the tmux session management, git worktree, PR review, and notes workflows. It can be sourced independently from the rest of these dotfiles.

### Usage

Add to your `.zshrc`:

```zsh
source /path/to/tmux-workflows.zsh
```

### Dependencies

| Tool | Required by | Notes |
|------|-------------|-------|
| `tmux` | all | Session management backbone |
| `git` | all | Worktrees, branch detection, repo navigation |
| `gh` | `ghp`, `worktree-cleanup.sh` | GitHub CLI |
| `jq` | `worktree-cleanup.sh` | JSON parsing for PR status |
| `claude` | `review-pr` | [Claude Code](https://claude.ai/code) CLI |

### Configuration

Set these before sourcing to override defaults:

| Variable | Default | Description |
|----------|---------|-------------|
| `WORKSPACE` | `~/workspace` | Primary project checkout directory |
| `WORKTREES_DIR` | `~/worktrees` | Where git worktrees are created |
| `NOTES_DIR` | `$WORKSPACE/_notes` | Research notes directory |
| `REVIEWS_DIR` | `$NOTES_DIR/reviews` | PR review artifacts directory |
| `OPEN_CMD` | `open` | Browser open command (`xdg-open` on Linux) |
| `GWT_SPARSE_CHECKOUT_CMD` | *(empty)* | Sparse checkout command for `gwt`'s second arg (e.g. `spt git:sparse reset && spt git:sparse add`) |

### Functions

| Function | Description |
|----------|-------------|
| `tat [dir]` | Create or attach to a tmux session named after the repo/branch |
| `tatt <name>` | Fuzzy-match and attach to an existing tmux session |
| `tls` | List tmux sessions, highlighting ones with active processes |
| `gwt [branch] [service]` | Create a git worktree, optionally sparse checkout, open in tmux |
| `ws [dir]` | cd into `$WORKSPACE` |
| `wt [dir]` | cd into `$WORKTREES_DIR` |
| `ghr` | Open the current repo on GitHub in the browser |
| `ghp` | Open the current branch's PR in the browser |
| `review-pr <url>` | Review a PR in a dedicated tmux session with Claude Code |
| `notes <dirname>` | Open a research workspace in a dedicated tmux session |

### Worktree cleanup

`bin/worktree-cleanup.sh` checks each worktree's PR status and removes ones whose PRs are merged or closed. It also cleans up stale review directories and notes sessions.

```sh
# Symlink into your worktrees directory
ln -s /path/to/dotfiles/bin/worktree-cleanup.sh ~/worktrees/cleanup.sh

# Run it
~/worktrees/cleanup.sh
```

Set `MONOREPO_DIR` to enable monorepo-specific cleanup (sparse query worktree reset, Bazel cache pruning):

```sh
export MONOREPO_DIR=~/workspace/my-monorepo
```

## Color schemes

Using [One Dark](https://github.com/joshdick/onedark.vim) via terminal / kitty color preferences.

## Other functions (base.zsh)

| Function / Alias | Description |
|----------|-------------|
| `gco` | Git checkout with auto-prefix for new branches |
| `tks` | Kill all tmux sessions |
| `cd.` | cd to the git repo root |
