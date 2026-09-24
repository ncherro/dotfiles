[← dotfiles](../README.md)

# Workflows

`zsh/tmux-workflows.zsh` is a standalone plugin that bundles the tmux session management, git worktree, PR review, and notes workflows. It can be sourced independently from the rest of these dotfiles.

## Usage

Add to your `.zshrc`:

```zsh
source /path/to/tmux-workflows.zsh
```

## Dependencies

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

## Configuration

Set these before sourcing to override defaults:

| Variable | Default | Description |
|----------|---------|-------------|
| `WORKSPACE` | `~/workspace` | Primary project checkout directory |
| `WORKTREES_SUBDIR` | `.worktrees` | Directory *inside each repo* where its worktrees are created |
| `NOTES_DIR` | `$WORKSPACE/_notes` | Research notes directory |
| `REVIEWS_DIR` | `$WORKSPACE/_reviews` | PR review artifacts directory |
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

## Functions

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

## Deeper

- [Sessions](sessions.md) — naming, `tls`, the picker, getting back after a restart
- [Notes and the knowledge base](notes.md) — how `notes`, `code` and `review-pr` join up
- [Worktrees](worktrees.md) — layout and cleanup
