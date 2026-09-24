# dotfiles 🏠

Config for zsh, vim, tmux, and git. Optimized for jumping between projects and branches, using Claude Code and Vim. Works on macOS and Linux (Ubuntu).

## Conventions

- Cross-platform: keep base.zsh universal, platform-specific code in mac.zsh/linux.zsh
- Git-centric: sessions, branches, and navigation derive from git context
- Short aliases, small composable functions that chain together
- Minimal UI: transparent backgrounds, no chrome
- Local overrides via .local files, never committed
- Self-bootstrapping: new machine setup should just be symlinks — except
  `~/.zshrc`, which is a thin real file so that tools which rewrite a shell
  rc in place cannot write into this repo

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
gitignore_global       # symlinked to ~/.gitignore (core.excludesfile)
bin/
  worktree-cleanup.sh  # clean up merged worktrees, stale sessions, and build caches
  notes-index          # joins notes dirs + session metadata + knowledge base
  notes-preview        # fzf preview pane for the notes picker
  resume-preview       # fzf preview pane for the resume picker
  tmux-sessions        # the session list behind tls and prefix + s
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
mkdir -p ~/Projects ~/workspace
git clone https://github.com/ncherro/dotfiles ~/Projects/dotfiles
```

### macOS

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

### Ubuntu

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
| `jq` | `review-*`, `notes`, `code`, `wip`, `resume`, `notes-gc` | reads and writes the session metadata |
| `fzf` | `notes`, `resume` | the pickers; `notes` falls back to create-without-prompting if absent, `resume` needs it |
| `python3` | `notes`, `wip`, `resume`, `notes-gc`, `recall` | the `bin/notes-*` helpers |
| `rg` | `recall` | searches ~325 MB of transcripts in about a second |
| `claude` | `review-pr`, `code` | [Claude Code](https://claude.ai/code) CLI |

### Configuration

Set these before sourcing to override defaults:

| Variable | Default | Description |
|----------|---------|-------------|
| `WORKSPACE` | `~/workspace` | Primary project checkout directory |
| `WORKTREES_SUBDIR` | `.worktrees` | Directory *inside each repo* where its worktrees are created |
| `NOTES_DIR` | `$WORKSPACE/_notes` | Research notes directory |
| `REVIEWS_DIR` | `$NOTES_DIR/reviews` | PR review artifacts directory |
| `NOTES_KB` | `$WORKSPACE/notes-kb` | Knowledge base `notes` routes against. Unset it to fall back to plain directory-name matching |
| `MONOREPO_DIR` | *(empty)* | Repo whose worktrees go through `spt git:worktree` rather than plain git. Also enables monorepo cleanup in `worktree-cleanup.sh` |
| `MONOREPO_FETCH_CMD` | *(empty)* | How `gfr` fetches `$MONOREPO_DIR` before rebasing (e.g. `spt git:fetch-local`). Unset → plain `git pull --rebase` everywhere |
| `REVIEW_GH_HOST` | `github.com` | Host the PR review workflow calls, passed as `GH_HOST` (e.g. a GitHub Enterprise hostname) |
| `REVIEW_DEFAULT_OWNER` | *(empty)* | Org assumed for review dirs predating `.review-meta.json`. Unset → those dirs report "could not fetch PR status" rather than guessing |
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
| `tls` | List tmux sessions, newest first, highlighting ones with active processes |
| `gwt [branch] [service]` | Create a git worktree, optionally sparse checkout, open in tmux |
| `ws [dir]` | cd into `$WORKSPACE` |
| `wt [branch]` | cd into the current repo's `.worktrees`, or into one worktree of it |
| `ghr` | Open the current repo on GitHub in the browser |
| `ghp` | Open the current branch's PR in the browser |
| `review-pr <url>` | Review a PR in a dedicated tmux session with Claude Code |
| `review-status` | State of every tracked review: new commits, replies, merged |
| `review-cleanup` | Drop review dirs whose PRs are merged or closed |
| `notes <topic>` | Open a research workspace, routed against the knowledge base |
| `code <branch> -p "<task>"` | Start a coding session from a notes dir: worktree, detached tmux session, Claude launched with `--add-dir` back to the notes |
| `recall <terms>` | Which directory was I working on that in |
| `wip [--state]` | Notes, worktrees and reviews currently in flight; `--state` adds dirty/merged at a `git status` per worktree |
| `resume` | Reopen the tmux sessions a reboot took out — pick from what was recently active |
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

### Coming back after a restart

A reboot takes every tmux session with it. `resume` puts them back, but it
does not restore a snapshot — nothing is written down on the way out. It works
out what was in flight from the same three places `wip` reads:

- notes dirs with activity inside the window (`--days`, default 7)
- worktrees that are not merged into `origin/HEAD`
- the review dirs, as a single `pr-reviews` session

You pick from that list; it creates one detached tmux session per pick, named
exactly as `notes`, `code` and `review-pr` would have named it, opened at the
right directory. Nothing is launched inside them.

Two consequences of deriving rather than restoring: a crash loses nothing,
because there was never a snapshot to miss; and work you have since abandoned
never comes back, because the list is what is *currently* recent, not what
happened to be open the last time the machine went down.

Ordering is by last activity. Nothing in that scan runs `git` or `python`:

| Thing | Last activity is the newest of |
|-------|-------------------------------|
| notes dir | the dir, its newest file, the Claude transcript for its path |
| worktree | the checkout, the gitdir's `logs/HEAD`, the Claude transcript |

Deliberately not `git status`: in a sparse monorepo worktree it costs 0.6–20s,
and twenty of those is a thirty-second hang in the one command you run when you
have just sat down. Deliberately not `.git/index` either — `git status` rewrites
it, so it reads as activity when nothing happened. The branch name comes from
reading `.git` and `HEAD` as files. The whole scan is about 0.2s.

The cost of that: `resume` does not know dirty from clean, or merged from
unmerged. Merged worktrees stay in the list until they age out of the window.
The preview pane is where that detail lives — it runs a full `git status` for
one worktree at a time, where the wait is invisible.

`wip` pays for a little more, since it is a report rather than a picker: it
calls `notes-index` for topics and what is undistilled (~0.5s). `wip --state`
adds dirty and merged, at a `git status` per worktree — seconds, and worth
asking for rather than waiting for every time.

Anything already open is filtered out, so `resume` is safe to re-run at any
point in the day, and `resume -n` prints what it would create without creating
it.

### Listing and switching sessions

`tls` and `prefix + s` print the same list, from `bin/tmux-sessions`:

```
* notes workflow-optimization                         2w  00:05
  wt    episode-resolver-cache-dedup                  1w  23:54
  pr    pr-reviews                                    8w  16:25
```

Session names are `<repo>--<branch>` or `notes--<slug>`, so the left of every
line is the same text repeated. The kind becomes a tag and the prefix is
stripped — the repo is whatever precedes the first `--`, and the branch prefix
is your own username, both derived rather than configured. `tls` adds a last
column for processes still running, which is what marks a session you were in
the middle of.

Inside tmux it runs in a popup rather than `choose-tree`, whose `-F` format is
only the text *after* a fixed `<session name>: ` label — the name cannot be
shortened and no column can be aligned. `choose-tree` is still on
`prefix + Ctrl-s` as a fallback.

Two things about that popup binding cost an evening, and are commented in
`tmux.conf`: the command must be wrapped in `/bin/sh -c` (a bare path never
starts, and the popup dies before the command does, so there is no error
anywhere), and it must contain no `#{...}` format (they are not expanded in a
key-bound popup, and `sh` then reads the `#` as a comment and exits 0 — which
even `-EE` treats as success).

### Worktree layout

Worktrees live inside the repo they belong to, at `<repo>/.worktrees/<branch>`,
with slashes in the branch name flattened to dashes:

```
~/workspace/monorepo/
  .worktrees/
    you-PROJ-913-dalhouse-pool-tuning    # branch you/PROJ-913-…
```

No second directory tree to keep in sync, and a worktree's repo is its
grandparent directory rather than something decoded out of a mangled name.
`gwt` and `code` both create here; `wip`, `worktree-cleanup.sh` and
`notes-merge` find them by scanning the repos in `$WORKSPACE` (plus
`$MONOREPO_DIR` if it lives elsewhere).

This relies on `.worktrees/` being in your **global** gitignore, which is why
`gitignore_global` is tracked here and symlinked to `~/.gitignore` — without it
the main checkout reads as dirty and `rg`/`grep` descend into every worktree.

### Worktree cleanup

`bin/worktree-cleanup.sh` checks each worktree's PR status and removes ones whose PRs are merged or closed. It also cleans up stale review directories and notes sessions.

```sh
# Every worktree of every repo in $WORKSPACE
bin/worktree-cleanup.sh

# Just one, by worktree directory name or by path
bin/worktree-cleanup.sh you-PROJ-913-dalhouse-pool-tuning
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
