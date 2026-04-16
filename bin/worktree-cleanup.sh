#!/usr/bin/env bash
set -euo pipefail

WORKTREES_DIR="$(cd "$(dirname "$0")" && pwd)"
: "${MONOREPO_DIR:=""}"
: "${REVIEWS_DIR:="$HOME/workspace/_notes/reviews"}"
: "${NOTES_DIR:="$HOME/workspace/_notes"}"

for dir in "$WORKTREES_DIR"/*/; do
  [ -e "$dir/.git" ] || continue

  branch=$(git -C "$dir" branch --show-current 2>/dev/null)
  [ -n "$branch" ] || continue

  pr_json=$(gh pr list --repo "$(git -C "$dir" remote get-url origin)" \
    --head "$branch" --state all --json number,state,url --limit 1 2>/dev/null)

  pr_count=$(echo "$pr_json" | jq length)
  if [ "$pr_count" -eq 0 ]; then
    echo "SKIP $(basename "$dir"): no PR found for branch $branch"
    read -rp "  Delete this worktree? [y/N] " answer
    if [[ "$answer" =~ ^[Yy]$ ]]; then
      repo_base=$(basename "$(git -C "$dir" remote get-url origin)" .git)
      tmux_session="${repo_base}--${branch}"
      if tmux has-session -t "$tmux_session" 2>/dev/null; then
        echo "  KILL tmux session: $tmux_session"
        tmux kill-session -t "$tmux_session"
      fi
      echo "  REMOVE worktree: $(basename "$dir")"
      git -C "$dir" worktree remove "$dir"
      # prune bazel output dirs for this worktree
      bazel_output="$HOME/.cache/bazel/_bazel_$(whoami)"
      if [ -d "$bazel_output" ]; then
        for bo in "$bazel_output"/*/DO_NOT_BUILD_HERE; do
          if [ -f "$bo" ] && grep -q "$(basename "$dir")" "$bo" 2>/dev/null; then
            bazel_dir=$(dirname "$bo")
            echo "  REMOVE bazel cache: $(basename "$bazel_dir")"
            rm -rf "$bazel_dir"
          fi
        done
      fi
    fi
    continue
  fi

  state=$(echo "$pr_json" | jq -r '.[0].state')
  url=$(echo "$pr_json" | jq -r '.[0].url')

  if [ "$state" = "OPEN" ]; then
    echo "KEEP $(basename "$dir"): PR is still open ($url)"
  else
    echo "REMOVE $(basename "$dir"): PR is $state ($url)"
    repo_base=$(basename "$(git -C "$dir" remote get-url origin)" .git)
    tmux_session="${repo_base}--${branch}"
    if tmux has-session -t "$tmux_session" 2>/dev/null; then
      echo "  KILL tmux session: $tmux_session"
      tmux kill-session -t "$tmux_session"
    fi
    git -C "$dir" worktree remove "$dir"
  fi
done

# reset sparse checkout query worktree
if [ -n "$MONOREPO_DIR" ] && [ -d "$MONOREPO_DIR" ]; then
  query_worktree=$(git -C "$MONOREPO_DIR" worktree list 2>/dev/null \
    | grep query-worktree | awk '{print $1}')
  if [ -n "$query_worktree" ]; then
    echo "RESET sparse query worktree: $query_worktree"
    git -C "$query_worktree" checkout -- . 2>/dev/null || true
    git -C "$query_worktree" clean -fd 2>/dev/null || true
  fi
fi

# clean up stale PR review sessions (open > 24h)
if [ -d "$REVIEWS_DIR" ]; then
  now=$(date +%s)
  for review_dir in "$REVIEWS_DIR"/*/; do
    [ -d "$review_dir" ] || continue
    dir_name=$(basename "$review_dir")
    dir_age=$(( now - $(stat -f %m "$review_dir") ))
    if [ "$dir_age" -gt 86400 ]; then
      tmux_session="review--${dir_name}"
      if tmux has-session -t "$tmux_session" 2>/dev/null; then
        echo "  KILL tmux session: $tmux_session"
        tmux kill-session -t "$tmux_session"
      fi
      echo "REMOVE review dir: $dir_name (age: $(( dir_age / 3600 ))h)"
      rm -rf "$review_dir"
    else
      echo "KEEP review dir: $dir_name (age: $(( dir_age / 3600 ))h)"
    fi
  done
fi

# clean up stale notes tmux sessions (open > 24h), keep dirs
if [ -d "$NOTES_DIR" ]; then
  now=$(date +%s)
  for notes_dir in "$NOTES_DIR"/*/; do
    [ -d "$notes_dir" ] || continue
    dir_name=$(basename "$notes_dir")
    [ "$dir_name" = "reviews" ] && continue
    tmux_session="notes--${dir_name}"
    if tmux has-session -t "$tmux_session" 2>/dev/null; then
      dir_age=$(( now - $(stat -f %m "$notes_dir") ))
      if [ "$dir_age" -gt 86400 ]; then
        echo "STALE notes tmux session: $tmux_session (age: $(( dir_age / 3600 ))h)"
        read -rp "  Kill tmux session? [y/N] " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
          echo "  KILL tmux session: $tmux_session"
          tmux kill-session -t "$tmux_session"
        fi
      fi
    fi
  done
fi

# clear unused bazel cache
if [ -n "$MONOREPO_DIR" ] && [ -d "$MONOREPO_DIR" ] && command -v spt &>/dev/null; then
  cd "$MONOREPO_DIR"
  spt bazel:prune-output-dirs --delete
  cd -
fi
