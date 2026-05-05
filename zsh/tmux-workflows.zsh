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
#
# Usage:
#   gwt <branch>                                       create worktree, attach tmux session
#   gwt <branch> -p "<prompt>"                         + open Claude Code with the given prompt
#   gwt <branch> -p path/to/prompt.md                  + read prompt from file
#   gwt <branch> -p "<prompt>" --safer                 + --permission-mode acceptEdits (auto-accept edits, still confirm shell)
#   gwt <branch> -p "<prompt>" --yolo                  + --dangerously-skip-permissions (bypass everything)
#   gwt <branch> -p "<prompt>" --model <name>          + --model <name> (e.g. sonnet, haiku) — cheaper for routine work
#   gwt <branch> <sparse-token> [-p ... [--safer|--yolo] [--model <name>]]
#                                                      + apply $GWT_SPARSE_CHECKOUT_CMD
#   gwt                                                inside a feature branch: switch to its worktree
#
# --safer vs --yolo: --safer is the recommended default for feature work
# (auto-accepts file edits, still pauses on shell commands → fewer wasted
# iteration cycles). --yolo is right for tight scaffolding where you trust
# the agent to run anything.
gwt() {
  if [[ "$PWD" == *"/worktrees/"* ]]; then
    echo "Already in a worktree"
    return 1
  fi
  if [[ -n "$TMUX" ]]; then
    echo "Already in a tmux session — run gwt from outside tmux"
    return 1
  fi
  local source_root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -z "$source_root" ]]; then
    echo "Not in a git repository"
    return 1
  fi
  local original_pwd="$PWD"
  local root=$(basename "$source_root")

  # Parse Claude-launch flags out of the arg list, leaving positional args.
  local prompt="" mode="" model=""
  local -a positional
  positional=()
  while (( $# )); do
    case "$1" in
      -p|--prompt)
        if [[ -z "$2" ]]; then
          echo "gwt: -p|--prompt requires a value (string or file path)"
          return 1
        fi
        prompt="$2"
        shift 2
        ;;
      --yolo)
        mode="bypass"
        shift
        ;;
      --safer)
        mode="safer"
        shift
        ;;
      --model)
        if [[ -z "$2" ]]; then
          echo "gwt: --model requires a value (e.g. sonnet, haiku)"
          return 1
        fi
        model="$2"
        shift 2
        ;;
      *)
        positional+=("$1")
        shift
        ;;
    esac
  done
  set -- "${positional[@]}"

  if [[ ( -n "$mode" || -n "$model" ) && -z "$prompt" ]]; then
    echo "gwt: --yolo, --safer, and --model only apply with -p|--prompt"
    return 1
  fi

  # Resolve prompt source: if it points at an existing file, read it; otherwise treat as literal.
  local prompt_text=""
  if [[ -n "$prompt" ]]; then
    if [[ -f "$prompt" ]]; then
      prompt_text=$(<"$prompt")
    else
      prompt_text="$prompt"
    fi
  fi

  local branch created=0
  if [[ -n "$1" ]]; then
    branch="$1"
    local dest="${WORKTREES_DIR}/${root}--${branch//\//-}"
    git worktree add -b "$branch" "$dest" "$(_git_default_branch)" || return 1
    [[ ! -f "$source_root/.env" ]] || cp "$source_root/.env" "$dest/.env"
    cd "$dest" || return 1
    if [[ -n "$2" && -n "$GWT_SPARSE_CHECKOUT_CMD" ]]; then
      eval "$GWT_SPARSE_CHECKOUT_CMD $2" || return 1
    fi
    created=1
  else
    branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    if [[ "$branch" == "$(_git_default_branch)" ]]; then
      echo "On $branch — pass a branch name to create a new worktree"
      return 1
    fi
    local dest="${WORKTREES_DIR}/${root}--${branch//\//-}"
    if [[ -d "$dest" ]]; then
      cd "$dest" || return 1
    else
      if [[ -n "$(git status --porcelain)" ]]; then
        echo "Working tree is not clean — commit or stash changes first"
        return 1
      fi
      git checkout "$(_git_default_branch)" || return 1
      git worktree add "$dest" "$branch" || return 1
      [[ ! -f "$source_root/.env" ]] || cp "$source_root/.env" "$dest/.env"
      cd "$dest" || return 1
      created=1
    fi
  fi

  # Auto-install pnpm deps if the source has them and this is a fresh worktree.
  # Worktrees don't share node_modules, so a fresh worktree without an install
  # has broken pnpm/typecheck/test commands until install completes. Skip for
  # the existing-worktree path (the user has already worked here).
  if (( created )) && [[ -d "$source_root/node_modules" && -f "$dest/package.json" && ! -d "$dest/node_modules" ]]; then
    echo "→ Installing pnpm deps in $(basename "$dest") (source has node_modules)..."
    (cd "$dest" && pnpm install) || \
      echo "gwt: pnpm install failed — install manually before running pnpm commands in the worktree"
  fi

  # Hand off to tmux.
  #
  # No-prompt mode: defer to `tat` — creates+attaches in one step (you're
  # launching ONE worktree, you want to be in it).
  #
  # Prompt mode: spin up a detached tmux session with Claude already running,
  # then return to where the user was. Lets you fire multiple `gwt -p` calls
  # in parallel without being teleported into each session. Attach later via
  # `tatt <fragment>` or `tmux attach -t <session>`.
  if [[ -z "$prompt_text" ]]; then
    tat
    return
  fi

  # Match tat's session naming convention: dirname--branch with dots → dashes.
  local session_name="${root}--${branch}"
  session_name=${session_name//./-}

  if ! tmux has-session -t "$session_name" 2>/dev/null; then
    tmux new-session -d -s "$session_name" -c "$dest"
  fi

  # Pass the prompt to Claude via a temp file so we don't have to escape it for
  # tmux send-keys. The new shell evaluates "$(cat ...)" cleanly.
  local tmpfile
  tmpfile=$(mktemp -t "gwt-prompt-XXXXXX") || return 1
  print -r -- "$prompt_text" > "$tmpfile"

  local claude_flags=""
  case "$mode" in
    bypass) claude_flags+=" --dangerously-skip-permissions" ;;
    safer)  claude_flags+=" --permission-mode acceptEdits" ;;
  esac
  [[ -n "$model" ]] && claude_flags+=" --model $model"

  tmux send-keys -t "$session_name" "claude${claude_flags} \"\$(cat ${tmpfile})\" && rm -f ${tmpfile}" Enter

  # Return user to their original cwd; don't attach.
  cd "$original_pwd"
  echo "Worktree:    $dest"
  echo "Tmux:        $session_name (detached)"
  echo "Attach with: tatt $session_name   # or: tmux attach -t $session_name"
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
