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
  notes-index          # joins notes dirs + session metadata + knowledge base
  notes-preview        # fzf preview pane for the notes picker
  notes-merge          # consolidate duplicate notes dirs, with undo
  notes-recall         # find the dir you were working in, by searching transcripts
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
| `gh` | `ghp`, `review-*`, `worktree-cleanup.sh` | GitHub CLI |
| `jq` | `review-*`, `notes`, `code`, `wip`, `notes-gc` | reads and writes the session metadata |
| `fzf` | `notes` | the picker; falls back to create-without-prompting if absent |
| `python3` | `notes`, `wip`, `notes-gc`, `recall` | the `bin/notes-*` helpers |
| `rg` | `recall` | searches ~325 MB of transcripts in about a second |
| `claude` | `review-pr`, `code` | [Claude Code](https://claude.ai/code) CLI |

### Configuration

Set these before sourcing to override defaults:

| Variable | Default | Description |
|----------|---------|-------------|
| `WORKSPACE` | `~/workspace` | Primary project checkout directory |
| `WORKTREES_DIR` | `~/worktrees` | Where git worktrees are created |
| `NOTES_DIR` | `$WORKSPACE/_notes` | Research notes directory |
| `REVIEWS_DIR` | `$NOTES_DIR/reviews` | PR review artifacts directory |
| `NOTES_KB` | `$WORKSPACE/notes-kb` | Knowledge base `notes` routes against. Unset it to fall back to plain directory-name matching |
| `MONOREPO_DIR` | *(empty)* | Repo whose worktrees go through `spt git:worktree` rather than plain git. Also enables monorepo cleanup in `worktree-cleanup.sh` |
| `NOTES_BIN` | `$DOTFILES/bin` | Where the `notes-*` helpers live |
| `NOTES_CACHE` | `~/.cache/tmux-workflows/notes-routing.tsv` | Generated routing table |
| `NOTES_REDIRECTS` | *(next to `NOTES_CACHE`)* | Generated old-name → current-dir table |
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
| `review-status` | State of every tracked review: new commits, replies, merged |
| `review-cleanup` | Drop review dirs whose PRs are merged or closed |
| `notes <topic>` | Open a research workspace, routed against the knowledge base |
| `code <branch> -p "<task>"` | Start a coding session from a notes dir: worktree, detached tmux session, Claude launched with `--add-dir` back to the notes |
| `recall <terms>` | Which directory was I working on that in |
| `wip` | Notes, worktrees and reviews currently in flight |
| `notes-gc` | Prune notes dirs that hold nothing; report ones never distilled |

### Notes, code, and the knowledge base

`notes`, `code` and `review-pr` all produce the same shape of thing: a
directory, a tmux session, and a Claude transcript. They are joined by a
metadata file — `.session.json` in a notes dir, `.review-meta.json` in a review
dir, `.notes-link` at a worktree root — which is what lets `wip`, `notes-gc` and
`recall` answer questions across all three without keeping a separate list.

`bin/notes-index` is the only thing that reads all of it. Everything else shells
out to it. Some of what it does is non-obvious:

- **The knowledge base is the routing table.** Topic slugs, frontmatter
  `aliases`, `index.md` hooks and `**Scratch:**` pointers are what `notes`
  matches against, which is why `notes playcount` can find a dir whose name
  shares no words with the query.
- **Dirs that predate `.session.json` still work.** Topics are inferred from the
  KB's own `**Scratch:**` lines, so nothing needed migrating.
- **`**Scratch:**` is parsed as a block, not a file-wide grep.** A topic that
  merely *mentions* another topic's scratch dir must not claim it.
- **A Claude transcript dir is named after the path it was opened at**
  (`-Users-you-workspace--notes-<slug>`, with `/`, `_` and `.` all mapped to
  `-`). It does not follow a dir that moves. That is why `notes-merge` records
  it as provenance, and why `recall` keys on the `cwd` field inside the
  transcript rather than trying to decode the dir name — the encoding is lossy
  and cannot be reversed.

Two gotchas worth not rediscovering:

- **fzf matches the line as transformed by `--with-nth`.** A trailing hidden
  field is invisible to the matcher, so anything searchable has to be in the
  visible columns. That is why aliases are a column in the picker.
- **`local` in zsh prints the variable** when it re-declares one that already
  exists in the same scope. Declare once, above the loop.

The helpers are dry-run or read-only by default. `notes-merge` in particular
refuses to move a dir with a live tmux session, and writes an undo script with
byte-for-byte backups to `$NOTES_DIR/.merge-undo/<timestamp>/`.

The matching slash commands (`/wrap`, `/code`, `/notes-merge`, `/kb-tidy`,
`/review-pr`) live in a separate, work-specific repo and are not part of these
dotfiles. The workflow they add up to is written up in `$NOTES_DIR/README.md`.

### Worktree cleanup

`bin/worktree-cleanup.sh` checks each worktree's PR status and removes ones whose PRs are merged or closed. It also cleans up stale review directories and notes sessions.

```sh
# Symlink into your worktrees directory
ln -s /path/to/dotfiles/bin/worktree-cleanup.sh ~/worktrees/cleanup.sh

# Run it
~/worktrees/cleanup.sh
```

`MONOREPO_DIR` (see Configuration) also enables monorepo-specific cleanup here: sparse query worktree reset and Bazel cache pruning.

## Color schemes

Using [One Dark](https://github.com/joshdick/onedark.vim) via terminal / kitty color preferences.

## Other functions (base.zsh)

| Function / Alias | Description |
|----------|-------------|
| `gco` | Git checkout with auto-prefix for new branches |
| `tks` | Kill all tmux sessions |
| `cd.` | cd to the git repo root |
