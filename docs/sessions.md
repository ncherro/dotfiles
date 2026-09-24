[← dotfiles](../README.md)

# Sessions

## Listing and switching sessions

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

## Coming back after a restart

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
