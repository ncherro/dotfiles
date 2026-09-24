[← dotfiles](../README.md)

## Worktree layout

Worktrees live inside the repo they belong to, at `<repo>/.worktrees/<branch>`,
with slashes in the branch name flattened to dashes:

```
~/workspace/monorepo/
  .worktrees/
    you-PROJ-913-dalhouse-pool-tuning    # branch you/PROJ-913-…
```

No second directory tree to keep in sync, and a worktree's repo is its
grandparent directory rather than something decoded out of a mangled name.
`gwt` and `code` both create here; `wip`, `worktree-gc` and
`notes-merge` find them by scanning the repos in `$WORKSPACE` (plus
`$MONOREPO_DIR` if it lives elsewhere).

This relies on `.worktrees/` being in your **global** gitignore, which is why
`gitignore_global` is tracked here and symlinked to `~/.gitignore` — without it
the main checkout reads as dirty and `rg`/`grep` descend into every worktree.

## Worktree cleanup

`bin/worktree-gc` checks each worktree's PR status and removes ones whose PRs are merged or closed. It also cleans up stale review directories and notes sessions.

```sh
# Every worktree of every repo in $WORKSPACE
bin/worktree-gc

# Just one, by worktree directory name or by path
bin/worktree-gc you-PROJ-913-dalhouse-pool-tuning
```

`MONOREPO_DIR` (see Configuration) also enables monorepo-specific cleanup here: sparse query worktree reset and Bazel cache pruning.
