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
docs/                  # the long explanations, linked from below
tmux.conf
vimrc
kitty.conf
gitconfig
claude/settings.json   # symlinked to ~/.claude/settings.json
```

`~/.zshrc.local` is sourced automatically but never committed — use it for machine-local or sensitive config. See `zshrc.local.example` for a template.

Longer explanations live in [`docs/`](docs/) rather than here — this file is
the map.

## Setup

New machine, in short: clone to `~/Projects/dotfiles`, symlink the configs,
let antidote build the zsh plugin cache on first shell. Full steps for macOS
and Ubuntu, including the reason `~/.zshrc` is a real file rather than a
symlink, are in [docs/setup.md](docs/setup.md).

## Workflows

`zsh/tmux-workflows.zsh` is a standalone plugin bundling the tmux, worktree,
PR review and notes workflows. Every one of them produces the same shape of
thing — a directory, a tmux session, and a Claude transcript — joined by a
metadata file, which is what lets any of them answer questions about the
others.

| | |
|---|---|
| `notes <topic>` | Open an investigation, routed against the knowledge base |
| `code <branch> -p "<task>"` | Hand it off to a coding session in a linked worktree |
| `review-pr <url>` | Review a PR in its own session |
| `wip` | What am I in the middle of |
| `recall <terms>` | Which directory was I working in |
| `resume` | Reopen the sessions a reboot took out |
| `tls` / `prefix + s` | The session list, and the picker |

- [tmux-workflows](docs/tmux-workflows.md) — dependencies, configuration, and
  the full function reference
- [Sessions](docs/sessions.md) — how sessions are named, the aligned list, and
  getting back to work after a restart
- [Notes and the knowledge base](docs/notes.md) — how `notes`, `code` and
  `review-pr` join up, and what `bin/notes-index` knows
- [Worktrees](docs/worktrees.md) — layout under `<repo>/.worktrees/`, and cleanup

## Color schemes

Using [One Dark](https://github.com/joshdick/onedark.vim) via terminal / kitty color preferences.

## Other functions (base.zsh)

| Function / Alias | Description |
|----------|-------------|
| `gco` | Git checkout with auto-prefix for new branches |
| `tks` | Kill all tmux sessions |
| `cd.` | cd to the git repo root |
