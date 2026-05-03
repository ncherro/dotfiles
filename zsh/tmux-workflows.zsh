# tmux-workflows.zsh
#
# Tmux-based workflow helpers for dev environments.
# Source this file from your .zshrc:
#   source /path/to/tmux-workflows.zsh
#
# Prerequisites: tmux, git, gh (GitHub CLI), claude (for review-pr)
#
# Optional:
#   GWT_SPARSE_CHECKOUT_CMD — function or command to run after creating a
#   worktree with a second argument, e.g.:
#     GWT_SPARSE_CHECKOUT_CMD='spt git:sparse reset && spt git:sparse add'
#   Called as: eval "$GWT_SPARSE_CHECKOUT_CMD $2"

# --- Config ---
# Override these in your .zshrc before sourcing this file.
: ${WORKSPACE:="$HOME/workspace"}
: ${WORKTREES_DIR:="$HOME/worktrees"}
: ${NOTES_DIR:="$WORKSPACE/_notes"}
: ${REVIEWS_DIR:="$NOTES_DIR/reviews"}
: ${GWT_SPARSE_CHECKOUT_CMD:=""}

# --- Dependency check ---
for _twf_cmd in tmux git gh; do
  if ! command -v "$_twf_cmd" &>/dev/null; then
    echo "tmux-workflows: missing required command: $_twf_cmd" >&2
  fi
done
unset _twf_cmd

# --- Helpers ---

_git_default_branch() {
  local b
  b=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
  echo "${b:-master}"
}

# --- Tmux session management ---

# List tmux sessions, highlighting ones running processes
tls() {
  tmux ls -F '#{session_name}' 2>/dev/null | while read -r session; do
    procs=$(tmux list-windows -t "$session" -F '#{pane_current_command}' \
      | grep -v '^zsh$' | tr '\n' ' ')
    if [[ -n "$procs" ]]; then
      echo "⚡ $session: $procs"
    else
      echo "  $session"
    fi
  done
}

# Attach to a tmux session by fuzzy name match
tatt() {
  local match
  match=$(tmux ls -F '#{session_name}' 2>/dev/null | grep -F "$1" | head -1)
  if [ -n "$match" ]; then
    tmux at -t "$match"
  else
    echo "No session matching '$1'"
    return 1
  fi
}

# Attach or create a tmux session named after the repo/branch
tat() {
  if [[ -n "$1" ]]; then
    cd "$1" || return 1
  fi
  local session_name
  if git rev-parse --is-inside-work-tree &>/dev/null; then
    local git_dir=$(cd "$(git rev-parse --git-dir)" && pwd)
    local git_common_dir=$(cd "$(git rev-parse --git-common-dir)" && pwd)
    local dirname=$(basename "$(dirname "$git_common_dir")")
    if [[ "$git_dir" != "$git_common_dir" ]]; then
      local branch=$(git rev-parse --abbrev-ref HEAD)
      session_name="${dirname}--${branch}"
    else
      session_name=$dirname
    fi
  else
    session_name=${PWD##*/}
  fi
  session_name=${session_name//./-}
  if tmux ls 2>/dev/null | grep -q "^${session_name}:"; then
    tmux at -t "$session_name"
    return 0
  fi
  tmux new -s "$session_name"
}

# --- Git worktrees ---

# Create or switch to a git worktree in $WORKTREES_DIR
gwt() {
  if [[ "$PWD" == *"/worktrees/"* ]]; then
    echo "Already in a worktree"
    return 1
  fi
  if [[ -n "$TMUX" ]]; then
    echo "Already in a tmux session — run gwt from outside tmux"
    return 1
  fi
  local root=$(basename "$(git rev-parse --show-toplevel 2>/dev/null)")
  if [[ -z "$root" ]]; then
    echo "Not in a git repository"
    return 1
  fi
  local branch
  if [[ -n "$1" ]]; then
    branch="$1"
    local dest="${WORKTREES_DIR}/${root}--${branch//\//-}"
    git worktree add -b "$branch" "$dest" "$(_git_default_branch)" && cd "$dest" && \
      if [[ -n "$2" && -n "$GWT_SPARSE_CHECKOUT_CMD" ]]; then
        eval "$GWT_SPARSE_CHECKOUT_CMD $2"
      fi && \
      tat
  else
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [[ "$branch" == "$(_git_default_branch)" ]]; then
      echo "On $branch — pass a branch name to create a new worktree"
      return 1
    fi
    local dest="${WORKTREES_DIR}/${root}--${branch//\//-}"
    if [[ -d "$dest" ]]; then
      cd "$dest" && tat
      return
    fi
    if [[ -n "$(git status --porcelain)" ]]; then
      echo "Working tree is not clean — commit or stash changes first"
      return 1
    fi
    git checkout "$(_git_default_branch)" && \
      git worktree add "$dest" "$branch" && cd "$dest" && tat
  fi
}

# --- Navigation ---

# cd into $WORKSPACE
ws() { cd "$WORKSPACE/${1:-.}"; }
# cd into $WORKTREES_DIR
wt() { cd "$WORKTREES_DIR/${1:-.}"; }

# --- GitHub ---

# Open the current repo in the browser
ghr() {
  local url
  url=$(git config --get remote.origin.url \
    | sed 's/:/\//' | sed 's/git@/https:\/\//' | sed 's/\.git//')
  ${OPEN_CMD:-open} "$url"
}

# Open the current branch's PR in the browser
ghp() {
  gh pr view --web 2>/dev/null \
    || echo "No PR found for branch: $(git rev-parse --abbrev-ref HEAD)"
}

# --- Workflow: PR Reviews ---

# Review a PR in a dedicated tmux session with Claude Code
review-pr() {
  local url="$1"
  if [[ -z "$url" ]]; then
    echo "Usage: review-pr <PR-URL>"
    return 1
  fi

  local service pr_number
  service=$(echo "$url" | sed -E 's|.*/([^/]+)/pull/.*|\1|')
  pr_number=$(echo "$url" | sed -E 's|.*/pull/([0-9]+).*|\1|')

  if [[ -z "$service" || -z "$pr_number" ]]; then
    echo "Could not parse service and PR number from URL"
    return 1
  fi

  local dirname="${service}-${pr_number}"
  local dir="${REVIEWS_DIR}/${dirname}"
  mkdir -p "$dir"

  local session="review--${dirname}"

  if ! tmux has-session -t "$session" 2>/dev/null; then
    tmux new-session -d -s "$session" -c "$dir"
  fi

  tmux send-keys -t "$session" \
    "claude --dangerously-skip-permissions '/review-pr $url'" Enter

  if [[ -n "$TMUX" ]]; then
    tmux switch-client -t "$session"
  else
    tmux attach-session -t "$session"
  fi
}

# --- Workflow: Notes ---

# Open a notes directory in a dedicated tmux session
notes() {
  local dirname="$1"
  if [[ -z "$dirname" ]]; then
    echo "Usage: notes <dirname>"
    return 1
  fi

  local dir="${NOTES_DIR}/${dirname}"
  mkdir -p "$dir"

  local session="notes--${dirname}"

  if ! tmux has-session -t "$session" 2>/dev/null; then
    tmux new-session -d -s "$session" -c "$dir"
  fi

  if [[ -n "$TMUX" ]]; then
    tmux switch-client -t "$session"
  else
    tmux attach-session -t "$session"
  fi
}

# --- Tab completion ---

_tmux_workflows_ws() { _path_files -W "$WORKSPACE" -/ }
_tmux_workflows_wt() { _path_files -W "$WORKTREES_DIR" -/ }

_tmux_workflows_init_completions() {
  compdef _tmux_workflows_ws ws
  compdef _tmux_workflows_wt wt
  compdef _tmux_workflows_ws tat
  add-zsh-hook -d precmd _tmux_workflows_init_completions
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd _tmux_workflows_init_completions
